"""Orchestrates one analysis: gate, call, check, store.

The order is the plan's (`service.py`: safety -> context -> provider ->
validate -> log) with the two steps that have nowhere to run yet left out:
there is no RAG, and the religious guard is the only safety stage, because
the analyst is given no religious material to be careful with.

What this class is careful about:

* **The gate comes before the call.** A missing key, or a user who has used
  today's attempts, never reaches the provider.
* **A failure is logged and refunded.** A provider outage records a row in
  `ai_requests` (so the outage is visible) and gives the attempt back (so a
  bad afternoon does not cost the user their day's quota).
* **Nothing is applied.** The only write on success is a `proposed` row.
"""

from __future__ import annotations

from decimal import Decimal

import structlog

from app.ai.agents import analyst
from app.ai.providers.base import AiRefused, AiUnavailable, ProviderAdapter
from app.ai.safety.religious_guard import ReligiousContentError
from app.ai.usage import cost
from app.ai.usage.limiter import DailyQuota
from app.modules.ai.models import AiProposal, ProposalStatus
from app.modules.ai.repository import AiRepository
from app.modules.ai.schemas import AnalystFacts, ProposalStatusUpdate
from app.modules.users.models import User

logger = structlog.get_logger(__name__)


class AiFeatureOff(Exception):
    """No provider is configured. The deploy has no key."""


class AiQuotaExceeded(Exception):
    """This user has used today's attempts (or the quota store is down)."""


class AiNoAnswer(Exception):
    """There is no analysis to store. `reason` is one of the flag names."""

    def __init__(self, reason: str) -> None:
        super().__init__(reason)
        self.reason = reason


class AiService:
    def __init__(
        self,
        repository: AiRepository,
        *,
        provider: ProviderAdapter,
        quota: DailyQuota,
        daily_limit: int,
    ) -> None:
        self._repository = repository
        self._provider = provider
        self._quota = quota
        self._daily_limit = daily_limit

    async def propose_analysis(self, user: User, facts: AnalystFacts) -> AiProposal:
        """Ask the analyst about `facts` and store the answer as a proposal."""
        if not self._provider.available:
            raise AiFeatureOff()

        allowed = await self._quota.reserve(
            agent=analyst.AGENT_NAME, user_id=user.id, limit=self._daily_limit
        )
        if not allowed:
            raise AiQuotaExceeded()

        try:
            outcome = await analyst.analyse(self._provider, facts)
        except AiRefused as exc:
            await self._record_failure(user, "refused", flags=[exc.category or "refused"])
            raise AiNoAnswer("refused") from exc
        except ReligiousContentError as exc:
            # The model said something religious. Logged as a safety event
            # rather than an outage: the flags are the thing worth reading.
            logger.warning(
                "ai_answer_discarded_religious_content",
                agent=analyst.AGENT_NAME,
                flags=list(exc.flags),
            )
            await self._record_failure(user, "discarded", flags=list(exc.flags))
            raise AiNoAnswer("unsafe") from exc
        except AiUnavailable as exc:
            # No tokens were spent and no answer exists: give the attempt
            # back rather than charging the user for our outage.
            await self._quota.refund(agent=analyst.AGENT_NAME, user_id=user.id)
            await self._record_failure(user, "unavailable", flags=["unavailable"])
            raise AiNoAnswer("unavailable") from exc
        except Exception as exc:  # AiMalformed and anything else unexpected
            await self._record_failure(user, "malformed", flags=["malformed"])
            raise AiNoAnswer("malformed") from exc

        await self._repository.record_request(
            user_id=user.id,
            agent=analyst.AGENT_NAME,
            model=outcome.model,
            input_tokens=outcome.input_tokens,
            output_tokens=outcome.output_tokens,
            cache_read_tokens=outcome.cache_read_tokens,
            cache_write_tokens=outcome.cache_write_tokens,
            cost_usd=cost.estimate_usd(
                outcome.model,
                input_tokens=outcome.input_tokens,
                output_tokens=outcome.output_tokens,
                cache_read_tokens=outcome.cache_read_tokens,
                cache_write_tokens=outcome.cache_write_tokens,
            ),
            latency_ms=outcome.latency_ms,
            safety_flags=list(outcome.safety_flags),
        )
        proposal = await self._repository.create_proposal(
            user_id=user.id,
            agent=analyst.AGENT_NAME,
            payload=outcome.analysis.model_dump(mode="json"),
            model=outcome.model,
        )
        await self._repository.commit()
        return proposal

    async def list_proposals(
        self, user: User, *, agent: str | None = None, limit: int = 20
    ) -> list[AiProposal]:
        return await self._repository.list_proposals(user_id=user.id, agent=agent, limit=limit)

    async def update_status(
        self, user: User, proposal_id, payload: ProposalStatusUpdate
    ) -> AiProposal | None:
        """Record what the user did with a proposal. Returns None if it is not theirs.

        This changes a status and nothing else. The widget the user accepted
        is created on their phone; it reaches the server later as an ordinary
        `habits` sync row, like every other widget they ever made.
        """
        proposal = await self._repository.find_proposal(user_id=user.id, proposal_id=proposal_id)
        if proposal is None:
            return None
        updated = await self._repository.set_proposal_status(
            proposal=proposal,
            status=payload.status,
            applied_diff=payload.applied_diff,
        )
        await self._repository.commit()
        return updated

    async def _record_failure(self, user: User, kind: str, *, flags: list[str]) -> None:
        """Log a call that produced nothing, and commit it.

        Committed on its own so the record survives the 503 the caller is
        about to raise -- a failure nobody can count is a failure nobody
        fixes. `model` is what we asked for, not what answered: on an outage
        nothing answered.
        """
        await self._repository.record_request(
            user_id=user.id,
            agent=analyst.AGENT_NAME,
            model=kind,
            cost_usd=Decimal("0"),
            safety_flags=flags,
        )
        await self._repository.commit()


def accepted_statuses() -> tuple[ProposalStatus, ...]:
    """The statuses a client may set.

    `proposed` is the server's to assign; a client re-proposing its own
    proposal is a bug, not a state.
    """
    return (ProposalStatus.accepted, ProposalStatus.modified, ProposalStatus.rejected)

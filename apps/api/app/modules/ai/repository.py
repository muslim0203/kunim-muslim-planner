"""Reads and writes for `ai_proposals` and `ai_requests`.

Every query is filtered by `user_id`. There is no method here that can
return or touch another user's proposal, which is why the router never has
to remember to check.
"""

from __future__ import annotations

import uuid
from decimal import Decimal

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.modules.ai.models import AiProposal, AiRequest, ProposalStatus


class AiRepository:
    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def commit(self) -> None:
        """Commit the unit of work the service assembled.

        Explicit rather than per-write: a successful analysis stores its
        `ai_requests` row and its proposal together, and a half-written pair
        would make the spend report disagree with the proposal list.
        """
        await self._session.commit()

    async def create_proposal(
        self,
        *,
        user_id: uuid.UUID,
        agent: str,
        payload: dict,
        model: str | None = None,
    ) -> AiProposal:
        proposal = AiProposal(
            user_id=user_id,
            agent=agent,
            payload=payload,
            status=ProposalStatus.proposed.value,
            model=model,
        )
        self._session.add(proposal)
        await self._session.flush()
        await self._session.refresh(proposal)
        return proposal

    async def list_proposals(
        self,
        *,
        user_id: uuid.UUID,
        agent: str | None = None,
        limit: int = 20,
    ) -> list[AiProposal]:
        stmt = (
            select(AiProposal)
            .where(AiProposal.user_id == user_id)
            .order_by(AiProposal.created_at.desc())
            .limit(limit)
        )
        if agent is not None:
            stmt = stmt.where(AiProposal.agent == agent)
        result = await self._session.execute(stmt)
        return list(result.scalars().all())

    async def find_proposal(
        self, *, user_id: uuid.UUID, proposal_id: uuid.UUID
    ) -> AiProposal | None:
        stmt = select(AiProposal).where(
            AiProposal.id == proposal_id,
            AiProposal.user_id == user_id,
        )
        result = await self._session.execute(stmt)
        return result.scalar_one_or_none()

    async def set_proposal_status(
        self,
        *,
        proposal: AiProposal,
        status: ProposalStatus,
        applied_diff: dict | None = None,
    ) -> AiProposal:
        proposal.status = status.value
        if applied_diff is not None:
            proposal.applied_diff = applied_diff
        await self._session.flush()
        await self._session.refresh(proposal)
        return proposal

    async def record_request(
        self,
        *,
        user_id: uuid.UUID,
        agent: str,
        model: str,
        input_tokens: int = 0,
        output_tokens: int = 0,
        cache_read_tokens: int = 0,
        cache_write_tokens: int = 0,
        cost_usd: Decimal = Decimal("0"),
        latency_ms: int = 0,
        safety_flags: list[str] | None = None,
    ) -> AiRequest:
        """Log one call. Written for failures too -- a refusal has a cost of
        zero and a story worth keeping."""
        request = AiRequest(
            user_id=user_id,
            agent=agent,
            model=model,
            input_tokens=input_tokens,
            output_tokens=output_tokens,
            cache_read_tokens=cache_read_tokens,
            cache_write_tokens=cache_write_tokens,
            cost_usd=cost_usd,
            latency_ms=latency_ms,
            safety_flags=list(safety_flags or []),
        )
        self._session.add(request)
        await self._session.flush()
        return request

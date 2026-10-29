"""The provider boundary.

Everything above this file speaks `ProviderAdapter`; nothing above it imports
a vendor SDK. That is what makes the second provider (`openai_compat`, plan
section 5) an added file rather than an edit everywhere, and it is what lets
every test above this line run with a fake and no network.

The failure vocabulary is deliberately small, because the caller only ever has
three choices: say the feature is off, say it could not answer, or fall back.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Protocol


class AiError(Exception):
    """Base for every provider failure. Never raised directly."""


class AiUnavailable(AiError):
    """No provider is configured, or the one configured could not be reached.

    The caller answers 503 and the client keeps its own rule-based analysis.
    """


class AiRefused(AiError):
    """The model declined to answer (a safety stop, not an error)."""

    def __init__(self, category: str | None = None) -> None:
        super().__init__(category or "refused")
        self.category = category


class AiMalformed(AiError):
    """The provider answered, but not with the shape that was asked for.

    Covers a truncated answer and anything that fails to parse or validate:
    from the caller's side these are the same event -- there is no usable
    answer, and retrying the same request is unlikely to help.
    """


@dataclass(frozen=True)
class StructuredAnswer:
    """A parsed JSON answer plus what it cost to get.

    `data` has been through the provider's own schema enforcement but no
    domain validation; the agent that asked for it owns that.
    """

    data: dict[str, Any]
    model: str
    input_tokens: int = 0
    output_tokens: int = 0
    cache_read_tokens: int = 0

    # Input tokens written *into* the cache. The first call of a cache
    # window pays a premium for these, so a cost figure that ignores them
    # under-reports every cold call -- which is most of them, since a user
    # asks for one analysis and leaves.
    cache_write_tokens: int = 0

    latency_ms: int = 0


class ProviderAdapter(Protocol):
    """What an agent may ask of a provider.

    `complete_structured` is the only method the first slice needs. `stream`
    and `embed` (plan section 5) join it when chat and RAG arrive; adding them
    here is a change to this Protocol, which is the point of having one.
    """

    name: str

    @property
    def available(self) -> bool:
        """False when the adapter has no credentials; nothing is attempted."""
        ...

    async def complete_structured(
        self,
        *,
        system: str,
        user: str,
        schema: dict[str, Any],
        max_tokens: int,
        effort: str = "low",
    ) -> StructuredAnswer:
        """Answer `user` as JSON matching `schema`.

        `system` is sent as the cacheable prefix, so it must be static for a
        given agent -- a timestamp or a user id in there silently costs full
        price on every request.
        """
        ...

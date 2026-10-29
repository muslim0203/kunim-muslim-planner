"""The Anthropic provider.

Shaped by three things the API asks for and one the project does:

* **The system prompt is the cache breakpoint.** It is static per agent, so
  marking it `ephemeral` makes every request after the first read it back at
  a tenth of the price. The volatile half (the user's numbers) goes in the
  user message, after the breakpoint -- the order matters, a byte of drift in
  the prefix throws the cache away.
* **Structured output, not prose parsing.** `output_config.format` constrains
  the answer to the JSON schema the agent asked for, so there is no
  "sometimes it wraps it in a code fence" branch anywhere above.
* **A refusal is not an error.** `stop_reason == "refusal"` comes back with
  HTTP 200; read before the content, or you read an empty answer as a result.
* **The key only ever comes from the environment.** Never a request, never a
  column, never the repository -- a key in any of those is a key in a backup.
"""

from __future__ import annotations

import json
import time
from typing import Any

import structlog

from app.ai.providers.base import (
    AiMalformed,
    AiRefused,
    AiUnavailable,
    StructuredAnswer,
)
from app.core.config import get_settings

logger = structlog.get_logger(__name__)

# Small answers over a slow mobile connection: the caller is a phone waiting
# on one request, so a long tail is worse than no answer. Seconds (the Python
# SDK's unit), not milliseconds.
REQUEST_TIMEOUT_SECONDS = 45.0


class AnthropicAdapter:
    """`ProviderAdapter` over `anthropic.AsyncAnthropic`."""

    name = "anthropic"

    def __init__(self, *, api_key: str | None = None, model: str | None = None) -> None:
        settings = get_settings()
        self._api_key = api_key if api_key is not None else settings.ANTHROPIC_API_KEY
        self._model = model or settings.AI_MODEL_ANALYST
        self._client: Any = None

    @property
    def available(self) -> bool:
        return bool(self._api_key)

    def _get_client(self) -> Any:
        if self._client is None:
            try:
                import anthropic
            except ImportError as exc:  # pragma: no cover - dependency is declared
                raise AiUnavailable("the anthropic package is not installed") from exc
            self._client = anthropic.AsyncAnthropic(
                api_key=self._api_key,
                timeout=REQUEST_TIMEOUT_SECONDS,
            )
        return self._client

    async def complete_structured(
        self,
        *,
        system: str,
        user: str,
        schema: dict[str, Any],
        max_tokens: int,
        effort: str = "low",
    ) -> StructuredAnswer:
        if not self.available:
            raise AiUnavailable("no ANTHROPIC_API_KEY is configured")

        client = self._get_client()
        started = time.monotonic()
        try:
            response = await client.messages.create(
                model=self._model,
                max_tokens=max_tokens,
                # The cacheable prefix. Static per agent -- see module docstring.
                system=[
                    {
                        "type": "text",
                        "text": system,
                        "cache_control": {"type": "ephemeral"},
                    }
                ],
                messages=[{"role": "user", "content": user}],
                output_config={
                    "effort": effort,
                    "format": {"type": "json_schema", "schema": schema},
                },
            )
        except Exception as exc:  # noqa: BLE001 - mapped to the boundary vocabulary
            raise _as_ai_error(exc) from exc

        latency_ms = int((time.monotonic() - started) * 1000)

        if response.stop_reason == "refusal":
            details = getattr(response, "stop_details", None)
            raise AiRefused(getattr(details, "category", None))
        if response.stop_reason == "max_tokens":
            raise AiMalformed("the answer was cut off by max_tokens")

        text = next(
            (block.text for block in response.content if getattr(block, "type", None) == "text"),
            None,
        )
        if not text:
            raise AiMalformed("the answer carried no text block")
        try:
            data = json.loads(text)
        except ValueError as exc:
            raise AiMalformed("the answer was not valid JSON") from exc
        if not isinstance(data, dict):
            raise AiMalformed("the answer was not a JSON object")

        usage = response.usage
        return StructuredAnswer(
            data=data,
            model=response.model,
            input_tokens=getattr(usage, "input_tokens", 0) or 0,
            output_tokens=getattr(usage, "output_tokens", 0) or 0,
            cache_read_tokens=getattr(usage, "cache_read_input_tokens", 0) or 0,
            cache_write_tokens=getattr(usage, "cache_creation_input_tokens", 0) or 0,
            latency_ms=latency_ms,
        )


def _as_ai_error(exc: Exception) -> Exception:
    """Map an SDK exception onto the boundary's vocabulary.

    Everything the caller can do about a 401, a 429 and a dropped connection
    is the same -- tell the client the feature is unavailable and let it keep
    its own analysis -- so they all become `AiUnavailable`. The distinction is
    kept in the log, where it is actionable, rather than in the type, where it
    would not be. A bad request is the exception: it means *this* code built
    the request wrong, and silently degrading would hide a bug we must fix.
    """
    try:
        import anthropic
    except ImportError:  # pragma: no cover - dependency is declared
        return AiUnavailable(str(exc))

    if isinstance(exc, anthropic.BadRequestError):
        logger.error("ai_provider_bad_request", provider="anthropic", exc_info=True)
        return AiMalformed("the provider rejected the request")
    if isinstance(exc, anthropic.APIError):
        logger.warning(
            "ai_provider_unavailable",
            provider="anthropic",
            kind=type(exc).__name__,
        )
        return AiUnavailable(type(exc).__name__)
    return AiUnavailable(type(exc).__name__)

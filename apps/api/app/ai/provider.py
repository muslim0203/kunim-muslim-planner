"""Which provider the agents talk to.

One adapter per process (it holds an HTTP client with its own connection
pool), swapped in tests for a fake. The same shape as
`app.modules.auth.ratelimit.get_rate_limiter` / `set_rate_limiter`, so there
is one pattern in the codebase for "process-wide thing a test replaces".

`app.modules.ai` asks for the provider and never constructs one, which is
what keeps the vendor SDK import inside `app.ai.providers`.
"""

from __future__ import annotations

from app.ai.providers.anthropic_adapter import AnthropicAdapter
from app.ai.providers.base import ProviderAdapter

_provider: ProviderAdapter | None = None


def get_provider() -> ProviderAdapter:
    """The configured adapter.

    Returns one even with no key: `available` is then False and the caller
    answers 503 without attempting a call. Reporting "off" is a property of
    the adapter, not of whether one exists.
    """
    global _provider
    if _provider is None:
        _provider = AnthropicAdapter()
    return _provider


def set_provider(provider: ProviderAdapter | None) -> None:
    """Swap the adapter (tests inject a fake; `None` resets)."""
    global _provider
    _provider = provider

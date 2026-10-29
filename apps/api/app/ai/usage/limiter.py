"""A per-user daily quota on paid calls.

**Fail-closed, and deliberately the opposite of `app.modules.auth.ratelimit`.**
That limiter fails open because a Redis outage must not stop people logging
in -- the blast radius of failing closed there is "the product is down".
Here it is the reverse: the AI analysis is an addition to a feature that
already works offline on the phone, so refusing it during a Redis outage
costs a user one optional screen. Failing open would instead put an
unmetered, per-call-billed endpoint on the public internet with no ceiling.
Cheap degradation beats an unbounded bill.

The quota is **reserved before the call and refunded when no answer was
produced**, so a provider outage does not burn a user's day of attempts
while a successful answer always counts.
"""

from __future__ import annotations

import uuid
from datetime import UTC, datetime
from typing import Any, Final

import structlog

from app.core.config import get_settings

logger = structlog.get_logger(__name__)

# A day plus an hour: the key is named by UTC date, and the extra hour means
# a clock skew cannot expire the counter before the day it counts is over.
_KEY_TTL_SECONDS: Final[int] = 90_000


class DailyQuota:
    """Counts a user's paid calls per agent per UTC day, in Redis."""

    def __init__(self, *, redis_url: str | None = None, enabled: bool = True) -> None:
        self._redis_url = redis_url
        self._enabled = enabled
        self._client: Any = None

    @property
    def enabled(self) -> bool:
        return self._enabled

    async def _get_client(self) -> Any:
        if self._client is None:
            import redis.asyncio as redis

            url = self._redis_url or get_settings().REDIS_URL
            self._client = redis.from_url(
                url, socket_connect_timeout=1, socket_timeout=1, decode_responses=True
            )
        return self._client

    @staticmethod
    def _key(agent: str, user_id: uuid.UUID) -> str:
        day = datetime.now(UTC).strftime("%Y%m%d")
        return f"ai:quota:{agent}:{user_id}:{day}"

    async def reserve(self, *, agent: str, user_id: uuid.UUID, limit: int) -> bool:
        """Take one of today's attempts. False when there is none left.

        False is also the answer when Redis cannot be reached -- see the
        module docstring.
        """
        if not self._enabled:
            return True
        if limit <= 0:
            return False

        key = self._key(agent, user_id)
        try:
            client = await self._get_client()
            used = int(await client.incr(key))
            if used == 1:
                await client.expire(key, _KEY_TTL_SECONDS)
        except Exception:  # noqa: BLE001 - any Redis failure closes the gate
            logger.warning("ai_quota_unavailable_failing_closed", agent=agent, exc_info=True)
            return False
        return used <= limit

    async def refund(self, *, agent: str, user_id: uuid.UUID) -> None:
        """Give back an attempt that produced no answer. Best effort."""
        if not self._enabled:
            return
        try:
            client = await self._get_client()
            await client.decr(self._key(agent, user_id))
        except Exception:  # noqa: BLE001 - a lost refund costs one attempt
            logger.warning("ai_quota_refund_failed", agent=agent, exc_info=True)

    async def close(self) -> None:
        if self._client is not None:
            await self._client.aclose()
            self._client = None


_quota: DailyQuota | None = None


def get_daily_quota() -> DailyQuota:
    """Process-wide quota. Overridable in tests via `set_daily_quota`."""
    global _quota
    if _quota is None:
        _quota = DailyQuota()
    return _quota


def set_daily_quota(quota: DailyQuota | None) -> None:
    """Swap the quota (tests inject a disabled one; `None` resets)."""
    global _quota
    _quota = quota

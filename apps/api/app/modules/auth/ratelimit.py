"""Redis token-bucket rate limiting for `/auth/*`.

**Fail-open, by deliberate choice.** When Redis is unreachable the limiter logs
a warning and allows the request. The alternative -- fail-closed -- would turn a
Redis outage into a total authentication outage: nobody could log in, existing
sessions could not refresh, and the mobile app would look permanently broken to
every user. The rate limiter is a defence-in-depth control against online
password guessing, not the control that keeps attackers out; argon2id hashing
and the generic, timing-equalised login response are what actually protect
credentials, and those keep working with Redis down. The blast radius of
failing open is "brute-force protection is temporarily absent"; the blast
radius of failing closed is "the product is down". We take the former, and the
degradation is logged so it is visible in monitoring rather than silent.

A short circuit breaker (`_UNAVAILABLE_BACKOFF_SEC`) stops a dead Redis from
adding a connection timeout to every single auth request.

Requests are counted against **two** buckets and rejected if either is empty:

* the client IP -- blunts a single host spraying many accounts;
* the submitted email -- blunts a distributed attack against one account.

The email is keyed by its SHA-256 digest so that no address is written into
Redis in the clear.
"""

from __future__ import annotations

import hashlib
import time
from typing import Any, Final

import structlog
from fastapi import HTTPException, Request, status

from app.core.config import get_settings

logger = structlog.get_logger(__name__)

# Bucket: 10 requests, refilling at 1 every 6s (i.e. 10/minute sustained).
DEFAULT_CAPACITY: Final[int] = 10
DEFAULT_REFILL_PER_SECOND: Final[float] = 10 / 60
BUCKET_TTL_SECONDS: Final[int] = 900
_UNAVAILABLE_BACKOFF_SEC: Final[float] = 30.0

# Atomic token bucket. Returns 1 when the request is allowed, 0 when throttled.
# Running this as a Lua script keeps read-modify-write on the bucket atomic, so
# concurrent requests cannot both consume the same last token.
_TOKEN_BUCKET_LUA: Final[str] = """
local key = KEYS[1]
local capacity = tonumber(ARGV[1])
local refill = tonumber(ARGV[2])
local now = tonumber(ARGV[3])
local ttl = tonumber(ARGV[4])

local bucket = redis.call('HMGET', key, 'tokens', 'updated')
local tokens = tonumber(bucket[1])
local updated = tonumber(bucket[2])

if tokens == nil then
    tokens = capacity
    updated = now
end

local elapsed = now - updated
if elapsed < 0 then elapsed = 0 end
tokens = math.min(capacity, tokens + elapsed * refill)

local allowed = 0
if tokens >= 1 then
    tokens = tokens - 1
    allowed = 1
end

redis.call('HSET', key, 'tokens', tokens, 'updated', now)
redis.call('EXPIRE', key, ttl)
return allowed
"""


class RateLimitExceeded(HTTPException):
    """429, raised when either bucket for a request is empty."""

    def __init__(self) -> None:
        super().__init__(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Too many requests. Please try again shortly.",
        )


class RateLimiter:
    """Token-bucket limiter backed by Redis, safe to use when Redis is down."""

    def __init__(
        self,
        *,
        redis_url: str | None = None,
        capacity: int = DEFAULT_CAPACITY,
        refill_per_second: float = DEFAULT_REFILL_PER_SECOND,
        enabled: bool = True,
    ) -> None:
        self._redis_url = redis_url
        self._capacity = capacity
        self._refill_per_second = refill_per_second
        self._enabled = enabled
        self._client: Any = None
        self._script: Any = None
        self._unavailable_until: float = 0.0

    @property
    def enabled(self) -> bool:
        return self._enabled

    async def _get_script(self) -> Any:
        if self._script is None:
            import redis.asyncio as redis

            url = self._redis_url or get_settings().REDIS_URL
            self._client = redis.from_url(
                url, socket_connect_timeout=1, socket_timeout=1, decode_responses=True
            )
            self._script = self._client.register_script(_TOKEN_BUCKET_LUA)
        return self._script

    async def allow(self, keys: list[str]) -> bool:
        """True when every bucket in `keys` had a token to spend.

        Returns True (fail-open) if Redis cannot be reached; see module docstring.
        """
        if not self._enabled or not keys:
            return True

        now = time.time()
        if now < self._unavailable_until:
            return True

        try:
            script = await self._get_script()
            for key in keys:
                allowed = await script(
                    keys=[key],
                    args=[self._capacity, self._refill_per_second, now, BUCKET_TTL_SECONDS],
                )
                if not int(allowed):
                    return False
            return True
        except Exception:  # noqa: BLE001 - any Redis failure must not break auth
            self._unavailable_until = now + _UNAVAILABLE_BACKOFF_SEC
            logger.warning(
                "rate_limiter_unavailable_failing_open",
                backoff_seconds=_UNAVAILABLE_BACKOFF_SEC,
                exc_info=True,
            )
            return True

    async def close(self) -> None:
        if self._client is not None:
            await self._client.aclose()
            self._client = None
            self._script = None


_limiter: RateLimiter | None = None


def get_rate_limiter() -> RateLimiter:
    """Process-wide limiter. Overridable in tests via `set_rate_limiter`."""
    global _limiter
    if _limiter is None:
        _limiter = RateLimiter()
    return _limiter


def set_rate_limiter(limiter: RateLimiter | None) -> None:
    """Swap the limiter (tests inject a disabled one; `None` resets)."""
    global _limiter
    _limiter = limiter


def _client_ip(request: Request) -> str:
    """Best-effort client IP.

    `X-Forwarded-For` is only consulted because the deployment terminates TLS at
    a trusted reverse proxy; the left-most entry is used. If the app is ever
    exposed directly this header must stop being trusted, since a client can
    forge it and so rotate its way out of the IP bucket.
    """
    forwarded = request.headers.get("x-forwarded-for")
    if forwarded:
        return forwarded.split(",")[0].strip()
    return request.client.host if request.client else "unknown"


async def _submitted_email(request: Request) -> str | None:
    """Peek at the JSON body for an `email`, without consuming it.

    Starlette caches the raw body on the request, so the endpoint still parses
    its own payload normally after this runs.
    """
    if request.method not in {"POST", "PUT", "PATCH"}:
        return None
    if "application/json" not in request.headers.get("content-type", ""):
        return None
    try:
        body = await request.json()
    except Exception:  # noqa: BLE001 - a malformed body is the endpoint's problem
        return None
    if isinstance(body, dict):
        email = body.get("email")
        if isinstance(email, str) and email.strip():
            return email.strip().lower()
    return None


async def auth_rate_limit(request: Request) -> None:
    """FastAPI dependency enforcing the IP + email buckets on `/auth/*`."""
    limiter = get_rate_limiter()
    if not limiter.enabled:
        return

    route = request.url.path
    keys = [f"rl:auth:ip:{_client_ip(request)}:{route}"]

    email = await _submitted_email(request)
    if email is not None:
        digest = hashlib.sha256(email.encode("utf-8")).hexdigest()
        keys.append(f"rl:auth:email:{digest}:{route}")

    if not await limiter.allow(keys):
        raise RateLimitExceeded()

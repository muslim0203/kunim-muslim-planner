"""Cryptographic primitives for authentication.

Scope: password hashing, access-token (JWT) signing/verification, and opaque
refresh-token generation/hashing. No database access and no HTTP concerns live
here, so every function is trivially unit-testable.

Security decisions made here (the product plan is silent on the specifics):

* **Password hashing: argon2id.** Parameters follow the OWASP Password Storage
  Cheat Sheet "m=19456 (19 MiB), t=2, p=1" recommendation, with a 16-byte salt
  and a 32-byte tag. They are spelled out explicitly below rather than relying
  on argon2-cffi's defaults so that changing the library version can never
  silently change the cost of every stored password. `needs_rehash` is checked
  on every successful login so raising the cost later upgrades hashes
  transparently.
* **Refresh tokens are hashed with SHA-256, not argon2.** A refresh token is
  256 bits of output from `secrets.token_urlsafe`, i.e. it has full entropy and
  is not guessable by brute force, so a slow KDF buys nothing. A fast digest is
  what makes an indexed, O(1) `WHERE token_hash = ...` lookup possible. This is
  the same reasoning that applies to API keys and session ids.
* **Hashes and raw tokens are never logged or returned.** No function in this
  module writes to a logger.
"""

from __future__ import annotations

import hashlib
import hmac
import secrets
import uuid
from datetime import UTC, datetime, timedelta
from functools import lru_cache
from typing import Any, Final

import jwt
from argon2 import PasswordHasher, Type
from argon2.exceptions import InvalidHashError, VerificationError, VerifyMismatchError

# --- Password hashing ------------------------------------------------------

ARGON2_TIME_COST: Final[int] = 2
ARGON2_MEMORY_COST_KIB: Final[int] = 19_456  # 19 MiB
ARGON2_PARALLELISM: Final[int] = 1
ARGON2_HASH_LEN: Final[int] = 32
ARGON2_SALT_LEN: Final[int] = 16

_password_hasher: Final[PasswordHasher] = PasswordHasher(
    time_cost=ARGON2_TIME_COST,
    memory_cost=ARGON2_MEMORY_COST_KIB,
    parallelism=ARGON2_PARALLELISM,
    hash_len=ARGON2_HASH_LEN,
    salt_len=ARGON2_SALT_LEN,
    encoding="utf-8",
    type=Type.ID,  # argon2id
)

# A password that can never be produced by the registration flow, used only to
# give the "user does not exist" path the same cost as the "wrong password"
# path. See `dummy_verify_password`.
_DUMMY_PASSWORD: Final[str] = "kunim-enumeration-resistance-dummy-password"


@lru_cache(maxsize=1)
def _dummy_hash() -> str:
    """Return (and memoise) an argon2 hash used purely for timing equalisation.

    Computed lazily on first use so that importing this module stays cheap.
    """
    return _password_hasher.hash(_DUMMY_PASSWORD)


def hash_password(password: str) -> str:
    """Hash a plaintext password with argon2id. The result is never logged."""
    return _password_hasher.hash(password)


def verify_password(password_hash: str | None, password: str) -> bool:
    """Check `password` against `password_hash` in constant-ish time.

    A `None` hash (user exists but has no password set, e.g. a future
    social-login-only account) still burns a dummy verification so that it is
    indistinguishable from a wrong password.
    """
    if password_hash is None:
        dummy_verify_password(password)
        return False
    try:
        return _password_hasher.verify(password_hash, password)
    except (VerifyMismatchError, VerificationError, InvalidHashError):
        return False


def password_needs_rehash(password_hash: str) -> bool:
    """True when `password_hash` was made with weaker parameters than current."""
    try:
        return _password_hasher.check_needs_rehash(password_hash)
    except InvalidHashError:
        return True


def dummy_verify_password(password: str) -> None:
    """Burn one argon2 verification against a throwaway hash.

    Called on the "email not found" branch of login so that an attacker cannot
    distinguish a registered email from an unregistered one by response time.
    Always fails; the result is intentionally discarded.
    """
    try:
        _password_hasher.verify(_dummy_hash(), password)
    except Exception:  # noqa: BLE001 - result is irrelevant, only the cost matters
        pass


# --- Access tokens (JWT) ---------------------------------------------------

JWT_ALGORITHM: Final[str] = "HS256"
ACCESS_TOKEN_TYPE: Final[str] = "access"


class TokenError(Exception):
    """Raised when an access token is missing, malformed, expired or forged."""


def create_access_token(
    *,
    user_id: uuid.UUID,
    role: str,
    secret: str,
    ttl_minutes: int,
    now: datetime | None = None,
) -> tuple[str, str, datetime]:
    """Mint a signed access token.

    Returns `(token, jti, expires_at)`. Claims: `sub`, `role`, `jti`, `iat`,
    `exp`, `typ`.
    """
    issued_at = now or datetime.now(UTC)
    expires_at = issued_at + timedelta(minutes=ttl_minutes)
    jti = str(uuid.uuid4())
    claims: dict[str, Any] = {
        "sub": str(user_id),
        "role": role,
        "jti": jti,
        "iat": int(issued_at.timestamp()),
        "exp": int(expires_at.timestamp()),
        "typ": ACCESS_TOKEN_TYPE,
    }
    token = jwt.encode(claims, secret, algorithm=JWT_ALGORITHM)
    return token, jti, expires_at


def decode_access_token(token: str, *, secret: str) -> dict[str, Any]:
    """Verify and decode an access token, or raise `TokenError`.

    The algorithm is pinned to HS256 so a token carrying `"alg": "none"` (or an
    asymmetric algorithm confusion attack) is rejected outright. `typ` is
    checked so a token minted for another purpose cannot be replayed here.
    """
    try:
        claims = jwt.decode(
            token,
            secret,
            algorithms=[JWT_ALGORITHM],
            options={"require": ["exp", "iat", "sub", "jti"]},
        )
    except jwt.PyJWTError as exc:
        raise TokenError("invalid token") from exc

    if claims.get("typ") != ACCESS_TOKEN_TYPE:
        raise TokenError("unexpected token type")
    return claims


# --- Refresh tokens (opaque) -----------------------------------------------

REFRESH_TOKEN_BYTES: Final[int] = 32  # 256 bits of entropy


def generate_refresh_token() -> str:
    """Return a fresh, opaque, URL-safe refresh token (never a JWT).

    Refresh tokens carry no readable claims on purpose: all of their state
    (owner, device, expiry, revocation, rotation chain) lives server-side in
    the `refresh_tokens` table, so a stolen token can be invalidated instantly.
    """
    return secrets.token_urlsafe(REFRESH_TOKEN_BYTES)


def hash_refresh_token(token: str) -> str:
    """Return the SHA-256 hex digest stored in `refresh_tokens.token_hash`."""
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def constant_time_equals(left: str, right: str) -> bool:
    """Timing-safe string comparison."""
    return hmac.compare_digest(left, right)

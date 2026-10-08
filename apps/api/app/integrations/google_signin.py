"""Verifying Google Sign-In ID tokens.

The mobile app signs the user in with Google on the device and sends the
resulting ID token (a JWT signed by Google) to `/auth/google`. Nothing else
from the client is trusted: the subject and email come only out of a token
whose signature, issuer, audience and expiry all check out.

* **Signature** -- RS256 against Google's published keys
  (`GOOGLE_CERTS_URL`). `PyJWKClient` caches them, so a key is fetched once
  per rotation rather than once per sign-in. The fetch is blocking urllib, so
  it runs in a worker thread.
* **Audience** -- one of `GOOGLE_CLIENT_IDS`. A token minted for some other
  app is a valid Google token too; without this check any app could sign
  users into this one.
* **Email** -- must be present and `email_verified`. The address is what an
  existing account is matched on, so an unverified one is refused outright.

No setting means no Google sign-in: with `GOOGLE_CLIENT_IDS` empty the
endpoint answers 503 instead of accepting tokens for any audience.

Logs never carry the token or the address.
"""

from __future__ import annotations

import asyncio
from dataclasses import dataclass
from functools import lru_cache
from typing import Annotated, Any, Protocol

import jwt
import structlog
from fastapi import Depends

from app.core.config import Settings, get_settings

logger = structlog.get_logger(__name__)

GOOGLE_CERTS_URL = "https://www.googleapis.com/oauth2/v3/certs"
GOOGLE_ISSUERS = ("accounts.google.com", "https://accounts.google.com")
# Google's ID tokens are short-lived; a little slack absorbs clock drift
# between this server and Google without accepting genuinely stale tokens.
CLOCK_SKEW_SECONDS = 60
JWKS_CACHE_SECONDS = 6 * 60 * 60
JWKS_FETCH_TIMEOUT_SECONDS = 10


class InvalidGoogleToken(Exception):
    """The ID token is malformed, forged, expired, for another app or unverified."""


class GoogleSignInDisabled(Exception):
    """No `GOOGLE_CLIENT_IDS` are configured on this deploy."""


@dataclass(frozen=True)
class GoogleIdentity:
    """The verified claims an account is found or created from."""

    subject: str
    email: str


class GoogleTokenVerifier(Protocol):
    async def verify(self, id_token: str) -> GoogleIdentity: ...


class _SigningKeySource(Protocol):
    def get_signing_key_from_jwt(self, token: str) -> Any: ...


class GoogleIdTokenVerifier:
    """Checks an ID token against Google's keys and the configured client ids."""

    def __init__(
        self,
        client_ids: list[str],
        *,
        key_source: _SigningKeySource | None = None,
    ) -> None:
        self._client_ids = [cid for cid in client_ids if cid]
        self._keys = key_source or jwt.PyJWKClient(
            GOOGLE_CERTS_URL,
            cache_keys=True,
            lifespan=JWKS_CACHE_SECONDS,
            timeout=JWKS_FETCH_TIMEOUT_SECONDS,
        )

    async def verify(self, id_token: str) -> GoogleIdentity:
        if not self._client_ids:
            raise GoogleSignInDisabled
        try:
            signing_key = await asyncio.to_thread(self._keys.get_signing_key_from_jwt, id_token)
            claims = jwt.decode(
                id_token,
                signing_key.key,
                algorithms=["RS256"],
                audience=self._client_ids,
                leeway=CLOCK_SKEW_SECONDS,
                options={"require": ["iss", "aud", "sub", "exp", "iat"]},
            )
        except jwt.PyJWKClientConnectionError:
            # Google's key endpoint is unreachable: not the caller's fault,
            # and not a reason to accept the token either.
            logger.warning("google_signin_keys_unavailable")
            raise
        except jwt.PyJWTError as exc:
            logger.info("google_signin_token_rejected", reason=type(exc).__name__)
            raise InvalidGoogleToken from exc

        if claims.get("iss") not in GOOGLE_ISSUERS:
            logger.info("google_signin_token_rejected", reason="issuer")
            raise InvalidGoogleToken
        email = claims.get("email")
        if not isinstance(email, str) or not email.strip():
            logger.info("google_signin_token_rejected", reason="no_email")
            raise InvalidGoogleToken
        # Google sends a boolean; very old tokens sent the string "true".
        if claims.get("email_verified") not in (True, "true"):
            logger.info("google_signin_token_rejected", reason="email_unverified")
            raise InvalidGoogleToken

        return GoogleIdentity(subject=str(claims["sub"]), email=email.strip().lower())


@lru_cache
def _verifier_for(client_ids: tuple[str, ...]) -> GoogleIdTokenVerifier:
    # One verifier per configuration, so the key cache survives across requests.
    return GoogleIdTokenVerifier(list(client_ids))


def get_google_verifier(
    settings: Annotated[Settings, Depends(get_settings)],
) -> GoogleTokenVerifier:
    """FastAPI dependency; tests override it with a fake."""
    return _verifier_for(tuple(settings.GOOGLE_CLIENT_IDS))

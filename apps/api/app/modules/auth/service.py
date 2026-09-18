"""Authentication business rules.

Three behaviours in here carry the weight of the whole module:

1. **Account-enumeration resistance.** `/auth/register` and `/auth/login` must
   not let an unauthenticated caller learn whether an email is registered.
   * Registration always answers with the same neutral `RegisterResponse`, and
     therefore does *not* return tokens -- returning a session for an address
     that is already taken would be an account takeover, and returning an error
     for it would be the enumeration oracle we are trying to remove. The client
     flow is register, then log in.
   * Login answers every failure with one identical error, and burns a dummy
     argon2 verification when the email is unknown so the "no such user" path
     costs the same wall-clock time as the "wrong password" path.

2. **Refresh-token rotation.** Every successful `/auth/refresh` issues a brand
   new refresh token, revokes the presented one and links it forward via
   `replaced_by`. A refresh token is therefore single-use.

3. **Reuse detection.** Because rotation makes tokens single-use, seeing an
   already-rotated (or already-revoked) token is proof that a token was
   captured: either the attacker is replaying the token the legitimate client
   already spent, or the legitimate client is replaying the one the attacker
   spent. There is no way to tell which party is which, so the safe move is to
   distrust both -- the entire token family for that `(user_id, device_id)` is
   revoked and the request is rejected. The legitimate user is forced to log in
   again on that device (and only that device); the attacker's stolen token is
   dead. See `_reject_and_revoke_family`.

Nothing here logs a token, a token hash or a password hash. Log lines carry
user ids and device ids only.
"""

from __future__ import annotations

import secrets
import uuid
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta

import structlog
from fastapi import HTTPException, status
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import Settings
from app.core.security import (
    create_access_token,
    dummy_verify_password,
    generate_refresh_token,
    hash_password,
    hash_refresh_token,
    password_needs_rehash,
    verify_password,
)
from app.integrations.email import get_email_sender
from app.modules.auth.emails import password_reset_email
from app.modules.auth.models import RefreshToken, VerificationPurpose
from app.modules.auth.repository import AuthRepository
from app.modules.auth.schemas import RegisterResponse, TokenPair
from app.modules.users.models import User

logger = structlog.get_logger(__name__)

# How long an email-verification / password-reset token stays valid.
EMAIL_VERIFY_TTL_HOURS = 24
PASSWORD_RESET_TTL_MINUTES = 30


def _invalid_credentials() -> HTTPException:
    """The single, generic authentication failure.

    Unknown email, wrong password, soft-deleted account and deactivated account
    all raise exactly this. Any divergence here reintroduces enumeration.
    """
    return HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Invalid email or password.",
        headers={"WWW-Authenticate": "Bearer"},
    )


def _invalid_refresh_token() -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Invalid or expired refresh token.",
        headers={"WWW-Authenticate": "Bearer"},
    )


@dataclass(frozen=True)
class IssuedTokens:
    """Internal result of minting a token pair."""

    access_token: str
    refresh_token: str
    access_expires_in: int
    refresh_expires_in: int

    def to_schema(self) -> TokenPair:
        return TokenPair(
            access_token=self.access_token,
            refresh_token=self.refresh_token,
            expires_in=self.access_expires_in,
            refresh_expires_in=self.refresh_expires_in,
        )


def _reset_code_hash(user_id: uuid.UUID, code: str) -> str:
    """Digest of the code bound to one account (see `request_password_reset`)."""
    return hash_refresh_token(f"{user_id}:{code.strip()}")


class AuthService:
    """Orchestrates registration, login, rotation and revocation."""

    def __init__(self, session: AsyncSession, settings: Settings) -> None:
        self._session = session
        self._settings = settings
        self._repo = AuthRepository(session)

    # --- helpers -----------------------------------------------------------

    @staticmethod
    def _now() -> datetime:
        return datetime.now(UTC)

    async def _issue_tokens(self, user: User, *, device_id: str, now: datetime) -> IssuedTokens:
        """Mint an access token plus a fresh, persisted refresh token."""
        access_token, _jti, access_expires_at = create_access_token(
            user_id=user.id,
            role=str(user.role),
            secret=self._settings.JWT_SECRET,
            ttl_minutes=self._settings.ACCESS_TOKEN_TTL_MIN,
            now=now,
        )

        raw_refresh = generate_refresh_token()
        refresh_expires_at = now + timedelta(days=self._settings.REFRESH_TOKEN_TTL_DAYS)
        await self._repo.add_refresh_token(
            user_id=user.id,
            device_id=device_id,
            token_hash=hash_refresh_token(raw_refresh),
            expires_at=refresh_expires_at,
            created_at=now,
        )

        return IssuedTokens(
            access_token=access_token,
            refresh_token=raw_refresh,
            access_expires_in=int((access_expires_at - now).total_seconds()),
            refresh_expires_in=int((refresh_expires_at - now).total_seconds()),
        )

    # --- registration ------------------------------------------------------

    async def register(self, *, email: str, password: str, locale: str) -> RegisterResponse:
        """Create an account, or pretend to if the email is already taken.

        Both branches cost one argon2 hash and return the identical response, so
        the endpoint reveals nothing about which emails exist.
        """
        now = self._now()
        existing = await self._repo.get_user_by_email(email)

        if existing is not None:
            # Spend the same work the real path spends, then say nothing.
            # TODO(email): send a "someone tried to register with your address /
            # reset your password instead" notice once a mail provider exists.
            hash_password(password)
            logger.info("auth_register_duplicate_email_suppressed", user_id=str(existing.id))
            return RegisterResponse()

        try:
            user = await self._repo.create_user(
                email=email,
                password_hash=hash_password(password),
                locale=locale,
            )
            await self.create_email_verification_token(user, now=now)
            await self._session.commit()
        except IntegrityError:
            # Lost a race against a concurrent registration for the same email.
            # Indistinguishable from the duplicate branch above, on purpose.
            await self._session.rollback()
            logger.info("auth_register_race_lost")
            return RegisterResponse()

        logger.info("auth_register_succeeded", user_id=str(user.id))
        return RegisterResponse()

    # --- login -------------------------------------------------------------

    async def login(self, *, email: str, password: str, device_id: str) -> TokenPair:
        """Authenticate and issue the first token pair for a device."""
        now = self._now()
        user = await self._repo.get_user_by_email(email)

        if user is None:
            # Equalise timing against the "user exists, wrong password" branch.
            dummy_verify_password(password)
            logger.info("auth_login_failed", reason="unknown_email")
            raise _invalid_credentials()

        if not verify_password(user.password_hash, password):
            logger.info("auth_login_failed", reason="bad_password", user_id=str(user.id))
            raise _invalid_credentials()

        if not user.is_active:
            # Same error as a bad password: a deactivated account must not be
            # distinguishable from a non-existent one.
            logger.info("auth_login_failed", reason="inactive", user_id=str(user.id))
            raise _invalid_credentials()

        # Transparently upgrade hashes that predate a cost increase.
        if user.password_hash is not None and password_needs_rehash(user.password_hash):
            await self._repo.set_password_hash(user, hash_password(password))

        tokens = await self._issue_tokens(user, device_id=device_id, now=now)
        await self._session.commit()
        logger.info("auth_login_succeeded", user_id=str(user.id), device_id=device_id)
        return tokens.to_schema()

    # --- refresh / rotation / reuse detection ------------------------------

    async def _reject_and_revoke_family(self, token: RefreshToken, now: datetime) -> None:
        """Handle a replayed refresh token: kill the family, then reject.

        Scope is `(user_id, device_id)` rather than the whole account. Widening
        it to every device would let anyone holding one stolen token log the
        victim out everywhere on demand -- a denial-of-service handed to the
        attacker. Narrowing it to the single row would be useless, because the
        attacker already holds the successor token. The device family is the
        smallest unit that actually contains the compromise.
        """
        revoked = await self._repo.revoke_family(
            user_id=token.user_id, device_id=token.device_id, when=now
        )
        await self._session.commit()
        logger.warning(
            "auth_refresh_token_reuse_detected",
            user_id=str(token.user_id),
            device_id=token.device_id,
            revoked_tokens=revoked,
        )
        raise _invalid_refresh_token()

    async def refresh(self, *, refresh_token: str, device_id: str) -> TokenPair:
        """Rotate a refresh token, detecting reuse of an already-spent one."""
        now = self._now()
        stored = await self._repo.get_refresh_token_by_hash(hash_refresh_token(refresh_token))

        if stored is None:
            # Never issued, or issued so long ago it was pruned. Nothing to revoke.
            logger.info("auth_refresh_failed", reason="unknown_token")
            raise _invalid_refresh_token()

        # --- reuse detection ---------------------------------------------
        # A token that was already rotated (`replaced_by`) or already revoked
        # is being presented a second time. Treat it as a compromise.
        if stored.replaced_by is not None or stored.revoked_at is not None:
            await self._reject_and_revoke_family(stored, now)

        if stored.expires_at <= now:
            # Simply aged out -- not evidence of theft, so only this row dies.
            await self._repo.revoke_token(stored, when=now)
            await self._session.commit()
            logger.info("auth_refresh_failed", reason="expired", user_id=str(stored.user_id))
            raise _invalid_refresh_token()

        if stored.device_id != device_id:
            # The token is bound to the device it was issued for; presenting it
            # from another device is the same class of signal as a replay.
            await self._reject_and_revoke_family(stored, now)

        user = await self._repo.get_user_by_id(stored.user_id)
        if user is None or not user.is_active:
            await self._repo.revoke_all_for_user(user_id=stored.user_id, when=now)
            await self._session.commit()
            logger.info("auth_refresh_failed", reason="user_unavailable")
            raise _invalid_refresh_token()

        tokens = await self._issue_tokens(user, device_id=device_id, now=now)
        replacement = await self._repo.get_refresh_token_by_hash(
            hash_refresh_token(tokens.refresh_token)
        )
        assert replacement is not None  # noqa: S101 - just flushed in _issue_tokens
        await self._repo.mark_replaced(stored, replacement_id=replacement.id, when=now)
        await self._session.commit()

        logger.info("auth_refresh_rotated", user_id=str(user.id), device_id=device_id)
        return tokens.to_schema()

    # --- logout ------------------------------------------------------------

    async def logout(self, *, refresh_token: str) -> None:
        """Revoke the presented refresh token.

        Always succeeds from the caller's point of view: telling an anonymous
        caller that a token was unknown would leak which tokens are real.
        """
        now = self._now()
        stored = await self._repo.get_refresh_token_by_hash(hash_refresh_token(refresh_token))
        if stored is not None:
            await self._repo.revoke_token(stored, when=now)
            await self._session.commit()
            logger.info(
                "auth_logout",
                user_id=str(stored.user_id),
                device_id=stored.device_id,
            )

    async def logout_all(self, *, user: User) -> int:
        """Revoke every refresh token this user holds, on every device."""
        now = self._now()
        revoked = await self._repo.revoke_all_for_user(user_id=user.id, when=now)
        await self._session.commit()
        logger.info("auth_logout_all", user_id=str(user.id), revoked_tokens=revoked)
        return revoked

    # --- email verification / password reset -------------------------------
    #
    # The token lifecycle is fully implemented; only delivery is missing.
    # Every method below returns the raw token to its caller so that a future
    # mail-sending job can consume it. No endpoint currently exposes them,
    # because a token the user can never receive is not a usable feature.

    async def create_email_verification_token(
        self, user: User, *, now: datetime | None = None
    ) -> str:
        """Issue a single-use email-verification token and return it raw."""
        moment = now or self._now()
        raw = generate_refresh_token()
        await self._repo.add_verification_token(
            user_id=user.id,
            purpose=VerificationPurpose.email_verify,
            token_hash=hash_refresh_token(raw),
            expires_at=moment + timedelta(hours=EMAIL_VERIFY_TTL_HOURS),
            created_at=moment,
        )
        # TODO(email): no mail provider is configured yet. When one exists,
        # enqueue an arq job here to send `raw` to `user.email`. Deliberately
        # not faked: nothing is "sent" and nothing pretends it was.
        logger.info("auth_email_verification_token_created", user_id=str(user.id))
        return raw

    async def create_password_reset_token(self, email: str) -> str | None:
        """Issue a password-reset token, or return None if the email is unknown.

        The caller (a future endpoint) must answer identically in both cases --
        the `None` is for the mail job, never for the HTTP response.
        """
        now = self._now()
        user = await self._repo.get_user_by_email(email)
        if user is None:
            return None

        raw = generate_refresh_token()
        await self._repo.add_verification_token(
            user_id=user.id,
            purpose=VerificationPurpose.password_reset,
            token_hash=hash_refresh_token(raw),
            expires_at=now + timedelta(minutes=PASSWORD_RESET_TTL_MINUTES),
            created_at=now,
        )
        await self._session.commit()
        # TODO(email): enqueue the reset mail carrying `raw` once a provider exists.
        logger.info("auth_password_reset_token_created", user_id=str(user.id))
        return raw

    async def request_password_reset(self, *, email: str, locale: str = "en") -> None:
        """Send a reset code, if the address belongs to an account.

        Always returns quietly: whether an address has an account is not
        something an unauthenticated caller may learn.

        The code is stored as a digest of `user_id:code`, not of the code
        alone: six digits hashed by themselves would be a lookup table of a
        million entries, and would collide across accounts. Redeeming it
        therefore needs the email as well as the code.
        """
        now = self._now()
        user = await self._repo.get_user_by_email(email)
        if user is None:
            logger.info("auth_password_reset_requested", known_email=False)
            return

        await self._repo.invalidate_verification_tokens(
            user_id=user.id,
            purpose=VerificationPurpose.password_reset,
            when=now,
        )
        code = f"{secrets.randbelow(1_000_000):06d}"
        await self._repo.add_verification_token(
            user_id=user.id,
            purpose=VerificationPurpose.password_reset,
            token_hash=_reset_code_hash(user.id, code),
            expires_at=now + timedelta(minutes=PASSWORD_RESET_TTL_MINUTES),
            created_at=now,
        )
        await self._session.commit()

        sent = await get_email_sender().send(
            password_reset_email(
                to=user.email,
                code=code,
                minutes=PASSWORD_RESET_TTL_MINUTES,
                locale=user.locale,
            )
        )
        logger.info("auth_password_reset_requested", known_email=True, sent=sent)

    async def reset_password_with_code(self, *, email: str, code: str, new_password: str) -> None:
        """Set a new password from a code, then end every session.

        Revoking all refresh tokens is the point of a reset: if it was asked
        for because someone else had access, leaving their sessions alive
        would defeat it.
        """
        now = self._now()
        user = await self._repo.get_user_by_email(email)
        # An unknown address answers exactly like a wrong code.
        stored = (
            None
            if user is None
            else await self._repo.get_verification_token_by_hash(_reset_code_hash(user.id, code))
        )
        if (
            user is None
            or stored is None
            or stored.purpose != VerificationPurpose.password_reset
            or stored.consumed_at is not None
            or stored.expires_at <= now
        ):
            logger.info("auth_password_reset_failed")
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Invalid or expired code.",
            )

        await self._repo.consume_verification_token(stored, when=now)
        await self._repo.set_password_hash(user, hash_password(new_password))
        revoked = await self._repo.revoke_all_for_user(user_id=user.id, when=now)
        await self._session.commit()
        logger.info(
            "auth_password_reset_completed",
            user_id=str(user.id),
            revoked_tokens=revoked,
        )

    async def _consume(self, raw_token: str, purpose: VerificationPurpose) -> User:
        """Validate and burn a verification token, returning its owner."""
        now = self._now()
        stored = await self._repo.get_verification_token_by_hash(hash_refresh_token(raw_token))
        if (
            stored is None
            or stored.purpose != purpose
            or stored.consumed_at is not None
            or stored.expires_at <= now
        ):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Invalid or expired token.",
            )
        user = await self._repo.get_user_by_id(stored.user_id)
        if user is None:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Invalid or expired token.",
            )
        await self._repo.consume_verification_token(stored, when=now)
        return user

    async def verify_email(self, raw_token: str) -> User:
        """Consume an email-verification token and stamp `email_verified_at`."""
        user = await self._consume(raw_token, VerificationPurpose.email_verify)
        await self._repo.mark_email_verified(user, self._now())
        await self._session.commit()
        logger.info("auth_email_verified", user_id=str(user.id))
        return user

    async def reset_password(self, raw_token: str, new_password: str) -> User:
        """Consume a reset token, set the new password, kill every session.

        Revoking all refresh tokens is the point of a password reset: if the
        reset was triggered because an attacker had access, leaving their
        sessions alive would defeat it.
        """
        now = self._now()
        user = await self._consume(raw_token, VerificationPurpose.password_reset)
        await self._repo.set_password_hash(user, hash_password(new_password))
        await self._repo.revoke_all_for_user(user_id=user.id, when=now)
        await self._session.commit()
        logger.info("auth_password_reset_completed", user_id=str(user.id))
        return user


def get_user_uuid(raw: str) -> uuid.UUID | None:
    """Parse a `sub` claim into a UUID, or None when it is malformed."""
    try:
        return uuid.UUID(raw)
    except (ValueError, AttributeError, TypeError):
        return None

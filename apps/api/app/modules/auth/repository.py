"""Data access for authentication. No business rules, no HTTP, no logging.

Every method takes an `AsyncSession` and leaves transaction control to the
caller (the service), so a single request can commit rotation and revocation
atomically.
"""

from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.modules.auth.models import RefreshToken, VerificationPurpose, VerificationToken
from app.modules.users.models import User, UserRole


class AuthRepository:
    """Thin persistence layer over `users`, `refresh_tokens`, `verification_tokens`."""

    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    # --- users -------------------------------------------------------------

    async def get_user_by_email(self, email: str) -> User | None:
        """Look up a non-deleted user by normalised email."""
        stmt = select(User).where(User.email == email, User.deleted_at.is_(None))
        return (await self._session.execute(stmt)).scalar_one_or_none()

    async def get_user_by_id(self, user_id: uuid.UUID) -> User | None:
        stmt = select(User).where(User.id == user_id, User.deleted_at.is_(None))
        return (await self._session.execute(stmt)).scalar_one_or_none()

    async def create_user(
        self,
        *,
        email: str,
        password_hash: str,
        locale: str,
        role: UserRole = UserRole.user,
    ) -> User:
        user = User(
            email=email,
            password_hash=password_hash,
            locale=locale,
            role=role,
            is_active=True,
        )
        self._session.add(user)
        await self._session.flush()
        return user

    async def set_password_hash(self, user: User, password_hash: str) -> None:
        user.password_hash = password_hash
        await self._session.flush()

    async def mark_email_verified(self, user: User, when: datetime) -> None:
        user.email_verified_at = when
        await self._session.flush()

    # --- refresh tokens ----------------------------------------------------

    async def get_refresh_token_by_hash(self, token_hash: str) -> RefreshToken | None:
        stmt = select(RefreshToken).where(RefreshToken.token_hash == token_hash)
        return (await self._session.execute(stmt)).scalar_one_or_none()

    async def add_refresh_token(
        self,
        *,
        user_id: uuid.UUID,
        device_id: str,
        token_hash: str,
        expires_at: datetime,
        created_at: datetime,
    ) -> RefreshToken:
        token = RefreshToken(
            user_id=user_id,
            device_id=device_id,
            token_hash=token_hash,
            expires_at=expires_at,
            created_at=created_at,
        )
        self._session.add(token)
        await self._session.flush()
        return token

    async def mark_replaced(
        self, token: RefreshToken, *, replacement_id: uuid.UUID, when: datetime
    ) -> None:
        """Close out a rotated token: revoked, and linked to its successor."""
        token.revoked_at = when
        token.replaced_by = replacement_id
        await self._session.flush()

    async def revoke_token(self, token: RefreshToken, *, when: datetime) -> None:
        if token.revoked_at is None:
            token.revoked_at = when
        await self._session.flush()

    async def revoke_family(self, *, user_id: uuid.UUID, device_id: str, when: datetime) -> int:
        """Revoke every still-live token for one `(user_id, device_id)` family.

        Returns the number of rows revoked.
        """
        stmt = (
            update(RefreshToken)
            .where(
                RefreshToken.user_id == user_id,
                RefreshToken.device_id == device_id,
                RefreshToken.revoked_at.is_(None),
            )
            .values(revoked_at=when)
        )
        result = await self._session.execute(stmt)
        await self._session.flush()
        return int(result.rowcount or 0)

    async def revoke_all_for_user(self, *, user_id: uuid.UUID, when: datetime) -> int:
        """Revoke every still-live token for a user, across all devices."""
        stmt = (
            update(RefreshToken)
            .where(
                RefreshToken.user_id == user_id,
                RefreshToken.revoked_at.is_(None),
            )
            .values(revoked_at=when)
        )
        result = await self._session.execute(stmt)
        await self._session.flush()
        return int(result.rowcount or 0)

    # --- verification / password-reset tokens ------------------------------

    async def add_verification_token(
        self,
        *,
        user_id: uuid.UUID,
        purpose: VerificationPurpose,
        token_hash: str,
        expires_at: datetime,
        created_at: datetime,
    ) -> VerificationToken:
        token = VerificationToken(
            user_id=user_id,
            purpose=purpose,
            token_hash=token_hash,
            expires_at=expires_at,
            created_at=created_at,
        )
        self._session.add(token)
        await self._session.flush()
        return token

    async def invalidate_verification_tokens(
        self, *, user_id: uuid.UUID, purpose: VerificationPurpose, when: datetime
    ) -> int:
        """Consume every still-open token of one purpose for one user.

        Issuing a new code invalidates the previous ones, so a code read from
        an older email cannot be used after a fresh one was asked for.
        """
        stmt = (
            update(VerificationToken)
            .where(
                VerificationToken.user_id == user_id,
                VerificationToken.purpose == purpose,
                VerificationToken.consumed_at.is_(None),
            )
            .values(consumed_at=when)
        )
        result = await self._session.execute(stmt)
        await self._session.flush()
        return int(result.rowcount or 0)

    async def get_verification_token_by_hash(self, token_hash: str) -> VerificationToken | None:
        stmt = select(VerificationToken).where(VerificationToken.token_hash == token_hash)
        return (await self._session.execute(stmt)).scalar_one_or_none()

    async def consume_verification_token(self, token: VerificationToken, *, when: datetime) -> None:
        token.consumed_at = when
        await self._session.flush()

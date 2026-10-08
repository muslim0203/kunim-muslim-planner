"""Account deletion (`docs/privacy/data-map.md`, "O'chirish").

1. `DELETE /users/me` closes the account at once: `users.deleted_at` is set,
   every refresh token is revoked, linked Google sign-ins are removed and the
   email is released (replaced by a placeholder), so the address can be
   registered again. The auth lookups
   ignore deleted users, so the current access token stops working on its
   next request.
2. After the 7-day grace period `purge_deleted_accounts` hard-deletes the row.
   Every user-owned table references `users.id` with `ON DELETE CASCADE`, so
   the user's data goes with it.

Logs carry a SHA-256 digest of the user id, never the id or the email.
"""

from __future__ import annotations

import hashlib
import uuid
from collections.abc import Callable
from datetime import UTC, datetime, timedelta
from typing import Final

import structlog
from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import verify_password
from app.modules.auth.models import IdentityProvider
from app.modules.auth.repository import AuthRepository
from app.modules.users.models import User

logger = structlog.get_logger(__name__)

DELETION_GRACE_PERIOD: Final[timedelta] = timedelta(days=7)


class WrongPasswordError(Exception):
    """The password (or Google account) given to confirm the deletion does not match."""


def user_digest(user_id: uuid.UUID) -> str:
    """What the logs record instead of a user id."""
    return hashlib.sha256(str(user_id).encode("utf-8")).hexdigest()


def released_email(user_id: uuid.UUID) -> str:
    """Placeholder that frees a closed account's address for a new sign-up."""
    return f"deleted-{user_id}@deleted.invalid"


class AccountService:
    def __init__(
        self,
        session: AsyncSession,
        *,
        now: Callable[[], datetime] | None = None,
    ) -> None:
        self._session = session
        self._now = now or (lambda: datetime.now(UTC))

    async def delete_account(self, user: User, *, password: str) -> None:
        """Close [user]'s account; raises `WrongPasswordError` first if needed."""
        if not verify_password(user.password_hash, password):
            logger.info("account_delete_refused", user=user_digest(user.id))
            raise WrongPasswordError
        await self._close(user)

    async def delete_account_with_google(self, user: User, *, google_subject: str) -> None:
        """Close [user]'s account, confirmed by signing in with its linked Google account."""
        identity = await AuthRepository(self._session).get_identity(
            IdentityProvider.google, google_subject
        )
        if identity is None or identity.user_id != user.id:
            logger.info("account_delete_refused", user=user_digest(user.id))
            raise WrongPasswordError
        await self._close(user)

    async def _close(self, user: User) -> None:
        now = self._now()
        user.deleted_at = now
        user.is_active = False
        user.email = released_email(user.id)
        repo = AuthRepository(self._session)
        await repo.revoke_all_for_user(user_id=user.id, when=now)
        # Unlinked at once, so the same Google account can sign up afresh.
        await repo.delete_identities_for_user(user.id)
        await self._session.commit()
        logger.info("account_deleted", user=user_digest(user.id))


async def purge_deleted_accounts(session: AsyncSession, *, now: datetime | None = None) -> int:
    """Hard-delete accounts closed longer ago than the grace period.

    Idempotent: a repeated or missed run only changes when a row goes.
    Returns how many accounts were removed.
    """
    cutoff = (now or datetime.now(UTC)) - DELETION_GRACE_PERIOD
    ids = (
        (
            await session.execute(
                select(User.id).where(User.deleted_at.is_not(None), User.deleted_at <= cutoff)
            )
        )
        .scalars()
        .all()
    )
    if not ids:
        return 0

    await session.execute(delete(User).where(User.id.in_(ids)))
    await session.commit()
    for user_id in ids:
        logger.info("account_purged", user=user_digest(user_id))
    return len(ids)

"""Persistence for `/users/me`.

There is no separate `profiles` table: the profile *is* the `users` row (see
the Phase 1 columns added to `app.modules.users.models.User`). This
repository only exists so the module follows the same
router/service/repository shape as every other module, and so a future
profile-specific table (should one ever be needed) has somewhere to live
without reshaping the service layer.
"""

from __future__ import annotations

import uuid
from typing import Any

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.modules.users.models import User


class ProfileRepository:
    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def nickname_taken(self, nickname: str, *, except_user: uuid.UUID) -> bool:
        """Whether another account already shows that name."""
        stmt = select(User.id).where(User.nickname == nickname, User.id != except_user)
        return (await self._session.execute(stmt)).first() is not None

    async def update(self, user: User, fields: dict[str, Any]) -> User:
        """Apply already-validated field assignments to `user` and persist."""
        for key, value in fields.items():
            setattr(user, key, value)
        await self._session.commit()
        await self._session.refresh(user)
        return user

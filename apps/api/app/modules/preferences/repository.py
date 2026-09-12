"""Data access for `preferences`. One (non-deleted) row per user.

No business rules, no HTTP -- the service owns the deep-merge and validation.
"""

from __future__ import annotations

import uuid
from typing import Any

from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.modules.preferences.models import Preferences
from app.modules.sync.repository import allocate_server_version


class PreferencesRepository:
    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def get_by_user_id(self, user_id: uuid.UUID) -> Preferences | None:
        stmt = select(Preferences).where(
            Preferences.user_id == user_id, Preferences.deleted_at.is_(None)
        )
        return (await self._session.execute(stmt)).scalar_one_or_none()

    async def create(self, *, user_id: uuid.UUID, document: dict[str, Any]) -> Preferences:
        """Insert the initial row for a user. `server_version` starts at 0
        (the `Versioned` mixin's column default)."""
        prefs = Preferences(user_id=user_id, **document)
        self._session.add(prefs)
        await self._session.commit()
        await self._session.refresh(prefs)
        return prefs

    async def update(self, prefs: Preferences, *, document: dict[str, Any]) -> Preferences:
        """Persist `document` with a freshly allocated `server_version`.

        The version comes from the shared per-user counter in
        `app.modules.sync.repository.allocate_server_version` -- the row-locked
        `sync_user_state` allocator the ADR mandates -- so this REST write and
        a `/sync/push` write share one monotonic sequence and a pull cursor can
        never step over either of them. This replaces the earlier
        `server_version = server_version + 1` special case, which was only
        correct because `preferences` has exactly one row per user.
        """
        version = await allocate_server_version(self._session, prefs.user_id)
        stmt = (
            update(Preferences)
            .where(Preferences.id == prefs.id)
            .values(server_version=version, **document)
        )
        await self._session.execute(stmt)
        await self._session.commit()
        await self._session.refresh(prefs)
        return prefs

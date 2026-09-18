"""Persistence for friends, invites and points totals."""

from __future__ import annotations

import uuid
from collections.abc import Sequence
from datetime import date, datetime

from sqlalchemy import and_, delete, func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.modules.scores.models import DailyScore
from app.modules.social.models import FriendInvite, Friendship
from app.modules.users.models import User


class SocialRepository:
    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    # --- invites -----------------------------------------------------------

    async def create_invite(
        self, *, user_id: uuid.UUID, code: str, expires_at: datetime
    ) -> FriendInvite:
        invite = FriendInvite(user_id=user_id, code=code, expires_at=expires_at)
        self._session.add(invite)
        await self._session.flush()
        return invite

    async def get_invite(self, code: str) -> FriendInvite | None:
        stmt = select(FriendInvite).where(FriendInvite.code == code)
        return (await self._session.execute(stmt)).scalar_one_or_none()

    async def mark_invite_used(
        self, invite: FriendInvite, *, user_id: uuid.UUID, when: datetime
    ) -> None:
        invite.used_by = user_id
        invite.used_at = when

    # --- friendships -------------------------------------------------------

    async def friend_ids(self, user_id: uuid.UUID) -> list[uuid.UUID]:
        stmt = select(Friendship.friend_id).where(Friendship.user_id == user_id)
        return list((await self._session.execute(stmt)).scalars().all())

    async def are_friends(self, user_id: uuid.UUID, other_id: uuid.UUID) -> bool:
        stmt = select(Friendship.id).where(
            Friendship.user_id == user_id, Friendship.friend_id == other_id
        )
        return (await self._session.execute(stmt)).first() is not None

    async def add_friendship(self, user_id: uuid.UUID, other_id: uuid.UUID) -> None:
        """Both directions, so either side can read its own friends."""
        self._session.add_all(
            [
                Friendship(user_id=user_id, friend_id=other_id),
                Friendship(user_id=other_id, friend_id=user_id),
            ]
        )
        await self._session.flush()

    async def remove_friendship(self, user_id: uuid.UUID, other_id: uuid.UUID) -> int:
        stmt = delete(Friendship).where(
            or_(
                and_(Friendship.user_id == user_id, Friendship.friend_id == other_id),
                and_(Friendship.user_id == other_id, Friendship.friend_id == user_id),
            )
        )
        result = await self._session.execute(stmt)
        return int(result.rowcount or 0)

    # --- users -------------------------------------------------------------

    async def users_by_ids(self, ids: Sequence[uuid.UUID]) -> list[User]:
        if not ids:
            return []
        stmt = select(User).where(User.id.in_(ids), User.deleted_at.is_(None))
        return list((await self._session.execute(stmt)).scalars().all())

    async def leaderboard_users(self, *, limit: int) -> list[User]:
        """Everyone who opted in and chose a name to show."""
        stmt = (
            select(User)
            .where(
                User.deleted_at.is_(None),
                User.is_active.is_(True),
                User.leaderboard_opt_in.is_(True),
                User.nickname.is_not(None),
            )
            .limit(limit)
        )
        return list((await self._session.execute(stmt)).scalars().all())

    async def nickname_taken(self, nickname: str, *, except_user: uuid.UUID) -> bool:
        stmt = select(User.id).where(User.nickname == nickname, User.id != except_user)
        return (await self._session.execute(stmt)).first() is not None

    # --- points ------------------------------------------------------------

    async def points_by_user(
        self, ids: Sequence[uuid.UUID], *, since: date | None = None
    ) -> dict[uuid.UUID, int]:
        """Summed `daily_scores.points`, zero for a user with no rows.

        Tombstoned rows are excluded, so a day the user deleted does not keep
        paying out.
        """
        if not ids:
            return {}
        stmt = (
            select(DailyScore.user_id, func.coalesce(func.sum(DailyScore.points), 0))
            .where(DailyScore.user_id.in_(ids), DailyScore.deleted_at.is_(None))
            .group_by(DailyScore.user_id)
        )
        if since is not None:
            stmt = stmt.where(DailyScore.date >= since)
        rows = (await self._session.execute(stmt)).all()
        totals = {user_id: int(points) for user_id, points in rows}
        return {user_id: totals.get(user_id, 0) for user_id in ids}

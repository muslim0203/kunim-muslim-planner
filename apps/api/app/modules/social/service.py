"""Friends, invite codes and the two boards.

Points come from `daily_scores`, which every client syncs: the server adds
them up and never recomputes them, so the scoring rules stay in one place
(`apps/mobile/lib/features/stats/domain/daily_score.dart`).

Two boards, both opt-in by construction:

* the friends board shows people who exchanged an invite code, and falls back
  to the display name they already share with friends;
* the global board shows only users who turned it on **and** chose a
  nickname, so nobody is listed under a name they did not pick.

Neither board ever carries an email address.
"""

from __future__ import annotations

import secrets
import uuid
from collections.abc import Callable, Sequence
from datetime import UTC, datetime, timedelta
from typing import Final

from sqlalchemy.ext.asyncio import AsyncSession

from app.modules.social.repository import SocialRepository
from app.modules.social.schemas import Board, BoardEntry, InviteOut
from app.modules.users.models import User

# No look-alike characters: a code is read off one screen and typed into
# another, so O/0 and I/1 would cost more support than the entropy is worth.
CODE_ALPHABET: Final[str] = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
CODE_LENGTH: Final[int] = 8
INVITE_TTL: Final[timedelta] = timedelta(days=7)
BOARD_WINDOW_DAYS: Final[int] = 7
GLOBAL_BOARD_LIMIT: Final[int] = 50

# Tries before giving up on a unique code; with 32^8 codes a single retry is
# already improbable.
_CODE_ATTEMPTS: Final[int] = 5


class InviteNotFoundError(Exception):
    """No invite with that code."""


class InviteExpiredError(Exception):
    """The code is past its expiry."""


class InviteUsedError(Exception):
    """The code was already redeemed."""


class SelfInviteError(Exception):
    """A user redeemed their own code."""


def _as_utc(value: datetime) -> datetime:
    """A stored timestamp as an aware UTC one.

    SQLite hands back a naive datetime for a `DateTime(timezone=True)` column,
    and comparing that to an aware "now" raises. Everything is stored in UTC,
    so a missing tzinfo simply means UTC.
    """
    return value if value.tzinfo is not None else value.replace(tzinfo=UTC)


class SocialService:
    def __init__(
        self,
        session: AsyncSession,
        *,
        now: Callable[[], datetime] | None = None,
    ) -> None:
        self._session = session
        self._repo = SocialRepository(session)
        self._now = now or (lambda: datetime.now(UTC))

    # --- invites -----------------------------------------------------------

    async def create_invite(self, user: User) -> InviteOut:
        now = self._now()
        for _ in range(_CODE_ATTEMPTS):
            code = "".join(secrets.choice(CODE_ALPHABET) for _ in range(CODE_LENGTH))
            if await self._repo.get_invite(code) is not None:
                continue
            invite = await self._repo.create_invite(
                user_id=user.id, code=code, expires_at=now + INVITE_TTL
            )
            await self._session.commit()
            return InviteOut(code=invite.code, expires_at=invite.expires_at)
        raise RuntimeError("could not allocate an unused invite code")

    async def accept_invite(self, user: User, code: str) -> None:
        """Make the caller and the code's owner friends.

        Accepting a code that already made these two friends succeeds
        quietly: the user asked for a state that already holds, and telling
        them otherwise would only be noise.
        """
        invite = await self._repo.get_invite(code.strip().upper())
        if invite is None:
            raise InviteNotFoundError
        if invite.user_id == user.id:
            raise SelfInviteError
        if invite.used_at is not None:
            raise InviteUsedError
        if _as_utc(invite.expires_at) <= self._now():
            raise InviteExpiredError

        if not await self._repo.are_friends(user.id, invite.user_id):
            await self._repo.add_friendship(user.id, invite.user_id)
        await self._repo.mark_invite_used(invite, user_id=user.id, when=self._now())
        await self._session.commit()

    async def remove_friend(self, user: User, friend_id: uuid.UUID) -> None:
        """Unfriend in both directions. A no-op if they were not friends."""
        await self._repo.remove_friendship(user.id, friend_id)
        await self._session.commit()

    # --- boards ------------------------------------------------------------

    async def friends_board(self, user: User) -> Board:
        friends = await self._repo.users_by_ids(await self._repo.friend_ids(user.id))
        return await self._board([*friends, user], me=user)

    async def global_board(self, user: User) -> Board:
        users = await self._repo.leaderboard_users(limit=GLOBAL_BOARD_LIMIT)
        if user.leaderboard_opt_in and user.nickname and all(u.id != user.id for u in users):
            users = [*users, user]
        return await self._board(users, me=user)

    async def _board(self, users: Sequence[User], *, me: User) -> Board:
        if not users:
            return Board(entries=[], my_rank=None)

        ids = [user.id for user in users]
        since = (self._now() - timedelta(days=BOARD_WINDOW_DAYS - 1)).date()
        week = await self._repo.points_by_user(ids, since=since)
        total = await self._repo.points_by_user(ids)

        entries = [
            BoardEntry(
                user_id=user.id,
                name=user.nickname or user.display_name,
                points_week=week.get(user.id, 0),
                points_total=total.get(user.id, 0),
                is_me=user.id == me.id,
            )
            for user in users
        ]
        # Best week first; ties fall back to the all-time total so a board
        # never reorders itself at random between two reads.
        entries.sort(
            key=lambda entry: (-entry.points_week, -entry.points_total, str(entry.user_id))
        )
        my_rank = next(
            (index + 1 for index, entry in enumerate(entries) if entry.is_me),
            None,
        )
        return Board(entries=entries, my_rank=my_rank)

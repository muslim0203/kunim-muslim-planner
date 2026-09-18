"""Business logic for `/users/me`.

There is exactly one profile per authenticated user. `CurrentUser` (from
`app.core.deps`) is the only source of "which user" anywhere in this module --
there is no endpoint, and no code path, that takes another user's id.
"""

from __future__ import annotations

from app.modules.profile.repository import ProfileRepository
from app.modules.profile.schemas import ProfileUpdate
from app.modules.users.models import User


class NicknameTakenError(Exception):
    """Someone else already shows that name on a board."""


class NicknameRequiredError(Exception):
    """The global board needs a name to list the user under."""


class ProfileService:
    def __init__(self, repo: ProfileRepository) -> None:
        self._repo = repo

    async def update_profile(self, user: User, payload: ProfileUpdate) -> User:
        """Apply only the fields the caller actually sent."""
        fields = payload.model_dump(exclude_unset=True)
        if not fields:
            return user

        nickname = fields.get("nickname", user.nickname)
        opted_in = fields.get("leaderboard_opt_in", user.leaderboard_opt_in)
        if fields.get("nickname") is not None and await self._repo.nickname_taken(
            fields["nickname"], except_user=user.id
        ):
            raise NicknameTakenError
        # The global board lists a user by name; joining it without one would
        # either leave a blank row or fall back to a name they never chose.
        if opted_in and not nickname:
            raise NicknameRequiredError

        return await self._repo.update(user, fields)

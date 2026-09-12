"""Business logic for `/users/me`.

There is exactly one profile per authenticated user. `CurrentUser` (from
`app.core.deps`) is the only source of "which user" anywhere in this module --
there is no endpoint, and no code path, that takes another user's id.
"""

from __future__ import annotations

from app.modules.profile.repository import ProfileRepository
from app.modules.profile.schemas import ProfileUpdate
from app.modules.users.models import User


class ProfileService:
    def __init__(self, repo: ProfileRepository) -> None:
        self._repo = repo

    async def update_profile(self, user: User, payload: ProfileUpdate) -> User:
        """Apply only the fields the caller actually sent."""
        fields = payload.model_dump(exclude_unset=True)
        if not fields:
            return user
        return await self._repo.update(user, fields)

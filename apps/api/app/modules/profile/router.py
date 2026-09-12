"""HTTP surface for the authenticated user's own profile.

Route summary::

    GET   /users/me   200  ProfileOut
    PATCH /users/me   200  ProfileOut   (partial update)

A user can only ever read or write their own profile: both routes resolve
"which user" exclusively through `CurrentUser`, and neither takes another
user's id as a path or query parameter.
"""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.deps import CurrentUser
from app.db.session import get_session
from app.modules.profile.repository import ProfileRepository
from app.modules.profile.schemas import ProfileOut, ProfileUpdate
from app.modules.profile.service import ProfileService

router = APIRouter(prefix="/users", tags=["profile"])


async def get_profile_service(
    session: Annotated[AsyncSession, Depends(get_session)],
) -> ProfileService:
    return ProfileService(ProfileRepository(session))


ProfileServiceDep = Annotated[ProfileService, Depends(get_profile_service)]


@router.get("/me", response_model=ProfileOut, summary="The authenticated user's profile")
async def get_profile(user: CurrentUser) -> ProfileOut:
    return ProfileOut.model_validate(user)


@router.patch("/me", response_model=ProfileOut, summary="Partially update the profile")
async def update_profile(
    payload: ProfileUpdate, user: CurrentUser, service: ProfileServiceDep
) -> ProfileOut:
    updated = await service.update_profile(user, payload)
    return ProfileOut.model_validate(updated)

"""HTTP surface for `/preferences`.

Route summary::

    GET   /preferences   200  PreferencesOut   (auto-created with defaults on first read)
    PATCH /preferences   200  PreferencesOut   (deep-merge partial update)

Every route requires an authenticated, active user and only ever reads or
writes that user's own row -- there is no route parameterised by another
user's id.
"""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.deps import CurrentUser
from app.db.session import get_session
from app.modules.preferences.repository import PreferencesRepository
from app.modules.preferences.schemas import PreferencesOut, PreferencesUpdate
from app.modules.preferences.service import PreferencesService

router = APIRouter(prefix="/preferences", tags=["preferences"])


async def get_preferences_service(
    session: Annotated[AsyncSession, Depends(get_session)],
) -> PreferencesService:
    return PreferencesService(PreferencesRepository(session))


PreferencesServiceDep = Annotated[PreferencesService, Depends(get_preferences_service)]


@router.get(
    "",
    response_model=PreferencesOut,
    summary="The authenticated user's preferences",
    description="Created lazily, with defaults, the first time a user reads this.",
)
async def get_preferences(user: CurrentUser, service: PreferencesServiceDep) -> PreferencesOut:
    prefs = await service.get_or_create(user)
    return PreferencesOut.model_validate(prefs)


@router.patch(
    "",
    response_model=PreferencesOut,
    summary="Deep-merge partial update of preferences",
    description="Each top-level key present in the body is merged into its stored "
    "sub-object; sibling keys -- at every nesting level -- are preserved.",
)
async def update_preferences(
    payload: PreferencesUpdate, user: CurrentUser, service: PreferencesServiceDep
) -> PreferencesOut:
    prefs = await service.update(user, payload)
    return PreferencesOut.model_validate(prefs)

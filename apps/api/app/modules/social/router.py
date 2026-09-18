"""HTTP surface for friends and leaderboards.

Route summary::

    POST   /social/invites           201  InviteOut
    POST   /social/invites/accept    204  (body: {"code": ...})
    GET    /social/friends           200  Board
    DELETE /social/friends/{id}      204
    GET    /social/leaderboard       200  Board

Every route resolves "which user" through `CurrentUser` only. Redeeming a
code is rate limited like `/auth/*`: a code is short, and without a limit it
could be guessed.
"""

from __future__ import annotations

import uuid
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Response, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.deps import CurrentUser
from app.db.session import get_session
from app.modules.auth.ratelimit import auth_rate_limit
from app.modules.social.schemas import Board, InviteAccept, InviteOut
from app.modules.social.service import (
    InviteExpiredError,
    InviteNotFoundError,
    InviteUsedError,
    SelfInviteError,
    SocialService,
)

router = APIRouter(prefix="/social", tags=["social"])


async def get_social_service(
    session: Annotated[AsyncSession, Depends(get_session)],
) -> SocialService:
    return SocialService(session)


SocialServiceDep = Annotated[SocialService, Depends(get_social_service)]


@router.post(
    "/invites",
    response_model=InviteOut,
    status_code=status.HTTP_201_CREATED,
    summary="Create an invite code to share with a friend",
)
async def create_invite(user: CurrentUser, service: SocialServiceDep) -> InviteOut:
    return await service.create_invite(user)


@router.post(
    "/invites/accept",
    status_code=status.HTTP_204_NO_CONTENT,
    response_class=Response,
    dependencies=[Depends(auth_rate_limit)],
    summary="Redeem a friend's invite code",
)
async def accept_invite(
    payload: InviteAccept, user: CurrentUser, service: SocialServiceDep
) -> Response:
    try:
        await service.accept_invite(user, payload.code)
    except InviteNotFoundError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="This invite code does not exist.",
        ) from exc
    except SelfInviteError as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="This is your own invite code.",
        ) from exc
    except InviteUsedError as exc:
        raise HTTPException(
            status_code=status.HTTP_410_GONE,
            detail="This invite code has already been used.",
        ) from exc
    except InviteExpiredError as exc:
        raise HTTPException(
            status_code=status.HTTP_410_GONE,
            detail="This invite code has expired.",
        ) from exc
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get("/friends", response_model=Board, summary="The caller's friends board")
async def friends_board(user: CurrentUser, service: SocialServiceDep) -> Board:
    return await service.friends_board(user)


@router.delete(
    "/friends/{friend_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    response_class=Response,
    summary="Remove a friend, in both directions",
)
async def remove_friend(
    friend_id: uuid.UUID, user: CurrentUser, service: SocialServiceDep
) -> Response:
    await service.remove_friend(user, friend_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get(
    "/leaderboard",
    response_model=Board,
    summary="The global board of users who opted in",
)
async def leaderboard(user: CurrentUser, service: SocialServiceDep) -> Board:
    return await service.global_board(user)

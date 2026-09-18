"""HTTP surface for closing the authenticated user's own account.

Route summary::

    DELETE /users/me   204   (body: {"password": ...})

The password is asked again so that a stolen access token alone cannot close
an account. A wrong password answers 403 (the token itself is fine), and the
route shares the `/auth/*` rate limiter so it cannot be used to guess
passwords.
"""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Response, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.deps import CurrentUser
from app.db.session import get_session
from app.modules.account.schemas import AccountDeleteRequest
from app.modules.account.service import AccountService, WrongPasswordError
from app.modules.auth.ratelimit import auth_rate_limit

router = APIRouter(prefix="/users", tags=["account"])


@router.delete(
    "/me",
    status_code=status.HTTP_204_NO_CONTENT,
    response_class=Response,
    dependencies=[Depends(auth_rate_limit)],
    summary="Delete the authenticated user's account",
)
async def delete_account(
    payload: AccountDeleteRequest,
    user: CurrentUser,
    session: Annotated[AsyncSession, Depends(get_session)],
) -> Response:
    try:
        await AccountService(session).delete_account(user, password=payload.password)
    except WrongPasswordError as exc:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Password is incorrect.",
        ) from exc
    return Response(status_code=status.HTTP_204_NO_CONTENT)

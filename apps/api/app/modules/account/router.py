"""HTTP surface for closing the authenticated user's own account.

Route summary::

    DELETE /users/me   204   (body: {"password": ...} or {"google_id_token": ...})

The password (or, for an account signed into with Google, a fresh Google ID
token for the linked Google account) is asked again so that a stolen access
token alone cannot close an account. A wrong password or a Google account
that is not linked answers 403 (the access token itself is fine), and the
route shares the `/auth/*` rate limiter so it cannot be used to guess
passwords.
"""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Response, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.deps import CurrentUser
from app.db.session import get_session
from app.integrations.google_signin import GoogleTokenVerifier, get_google_verifier
from app.modules.account.schemas import AccountDeleteRequest
from app.modules.account.service import AccountService, WrongPasswordError
from app.modules.auth.ratelimit import auth_rate_limit
from app.modules.auth.service import verify_google_token

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
    verifier: Annotated[GoogleTokenVerifier, Depends(get_google_verifier)],
) -> Response:
    service = AccountService(session)
    try:
        if payload.google_id_token is not None:
            google = await verify_google_token(verifier, payload.google_id_token)
            await service.delete_account_with_google(user, google_subject=google.subject)
        else:
            assert payload.password is not None  # guaranteed by the schema
            await service.delete_account(user, password=payload.password)
    except WrongPasswordError as exc:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Password is incorrect.",
        ) from exc
    return Response(status_code=status.HTTP_204_NO_CONTENT)

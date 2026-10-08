"""HTTP surface for authentication.

Every route on this router runs the `auth_rate_limit` dependency (IP + email
token buckets, fail-open when Redis is down -- see `ratelimit.py`).

Route summary::

    POST /auth/register    201  RegisterResponse   (neutral, never reveals existence)
    POST /auth/login       200  TokenPair
    POST /auth/google      200  TokenPair          (sign up or sign in with Google)
    POST /auth/refresh     200  TokenPair          (rotates; detects reuse)
    POST /auth/logout      204  -                  (revokes the presented token)
    POST /auth/logout-all  204  -                  (revokes every token, all devices)
    GET  /auth/me          200  UserOut
"""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, Response, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import Settings, get_settings
from app.core.deps import CurrentUser
from app.db.session import get_session
from app.integrations.google_signin import GoogleTokenVerifier, get_google_verifier
from app.modules.auth.ratelimit import auth_rate_limit
from app.modules.auth.schemas import (
    ForgotPasswordRequest,
    GoogleSignInRequest,
    LoginRequest,
    LogoutRequest,
    RefreshRequest,
    RegisterRequest,
    RegisterResponse,
    ResetPasswordRequest,
    TokenPair,
    UserOut,
)
from app.modules.auth.service import AuthService

router = APIRouter(
    prefix="/auth",
    tags=["auth"],
    dependencies=[Depends(auth_rate_limit)],
)


async def get_auth_service(
    session: Annotated[AsyncSession, Depends(get_session)],
    settings: Annotated[Settings, Depends(get_settings)],
) -> AuthService:
    return AuthService(session, settings)


AuthServiceDep = Annotated[AuthService, Depends(get_auth_service)]


@router.post(
    "/register",
    status_code=status.HTTP_201_CREATED,
    response_model=RegisterResponse,
    summary="Register a new account",
    description=(
        "Always returns the same body whether or not the email is already "
        "registered, so the endpoint cannot be used to enumerate accounts. "
        "No tokens are returned; call /auth/login next."
    ),
)
async def register(payload: RegisterRequest, service: AuthServiceDep) -> RegisterResponse:
    return await service.register(
        email=payload.email,
        password=payload.password,
        locale=payload.locale,
    )


@router.post(
    "/login",
    response_model=TokenPair,
    summary="Exchange credentials for a token pair",
    description="Every failure returns the same generic 401, with matched timing.",
)
async def login(payload: LoginRequest, service: AuthServiceDep) -> TokenPair:
    return await service.login(
        email=payload.email,
        password=payload.password,
        device_id=payload.device_id,
    )


@router.post(
    "/google",
    response_model=TokenPair,
    summary="Sign up or sign in with a Google ID token",
    description=(
        "Verifies the ID token against Google's keys and the configured client "
        "ids, then signs into the linked account, links an account with the "
        "same verified address, or creates one. 401 for a token that does not "
        "verify; 503 when Google sign-in is not configured or Google's keys "
        "cannot be fetched."
    ),
)
async def google_sign_in(
    payload: GoogleSignInRequest,
    service: AuthServiceDep,
    verifier: Annotated[GoogleTokenVerifier, Depends(get_google_verifier)],
) -> TokenPair:
    return await service.google_sign_in(
        id_token=payload.id_token,
        device_id=payload.device_id,
        locale=payload.locale,
        verifier=verifier,
    )


@router.post(
    "/refresh",
    response_model=TokenPair,
    summary="Rotate a refresh token",
    description=(
        "Issues a new token pair and single-uses the presented refresh token. "
        "Presenting an already-rotated or revoked token is treated as theft: "
        "the whole token family for that user+device is revoked."
    ),
)
async def refresh(payload: RefreshRequest, service: AuthServiceDep) -> TokenPair:
    return await service.refresh(
        refresh_token=payload.refresh_token,
        device_id=payload.device_id,
    )


@router.post(
    "/logout",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Revoke the presented refresh token",
)
async def logout(payload: LogoutRequest, service: AuthServiceDep) -> Response:
    await service.logout(refresh_token=payload.refresh_token)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post(
    "/logout-all",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Revoke every refresh token for the current user",
)
async def logout_all(user: CurrentUser, service: AuthServiceDep) -> Response:
    await service.logout_all(user=user)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post(
    "/forgot-password",
    status_code=status.HTTP_202_ACCEPTED,
    response_class=Response,
    summary="Send a password-reset code to an email address",
)
async def forgot_password(payload: ForgotPasswordRequest, service: AuthServiceDep) -> Response:
    """Always 202: whether the address has an account is not disclosed."""
    await service.request_password_reset(email=payload.email, locale=payload.locale)
    return Response(status_code=status.HTTP_202_ACCEPTED)


@router.post(
    "/reset-password",
    status_code=status.HTTP_204_NO_CONTENT,
    response_class=Response,
    summary="Set a new password with a reset code",
)
async def reset_password(payload: ResetPasswordRequest, service: AuthServiceDep) -> Response:
    await service.reset_password_with_code(
        email=payload.email,
        code=payload.code,
        new_password=payload.new_password,
    )
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get(
    "/me",
    response_model=UserOut,
    summary="The authenticated user",
)
async def me(user: CurrentUser) -> UserOut:
    return UserOut.model_validate(user)

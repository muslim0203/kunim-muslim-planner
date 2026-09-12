"""Shared FastAPI dependencies: current user resolution and RBAC.

Other modules should depend on the callables here rather than decoding tokens
themselves, so that authentication semantics live in exactly one place.

Typical use::

    from app.core.deps import CurrentUser, require_role
    from app.modules.users.models import UserRole

    @router.get("/things")
    async def list_things(user: CurrentUser) -> ...: ...

    @router.delete("/things/{id}", dependencies=[Depends(require_role(UserRole.admin))])
    async def delete_thing(...) -> ...: ...

A 401 always means "no usable credentials"; a 403 always means "authenticated,
but not allowed". They are never mixed up, because collapsing them would make
legitimate clients unable to tell a stale token from a missing permission.
"""

from __future__ import annotations

from typing import Annotated

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import Settings, get_settings
from app.core.security import TokenError, decode_access_token
from app.db.session import get_session
from app.modules.users.models import User, UserRole

# auto_error=False so a missing header produces our own JSON error shape
# (via the registered HTTPException handler) rather than Starlette's default.
_bearer_scheme = HTTPBearer(auto_error=False, description="Access token issued by /auth/login")


def _unauthorised(message: str = "Not authenticated.") -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail=message,
        headers={"WWW-Authenticate": "Bearer"},
    )


async def get_current_user(
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(_bearer_scheme)],
    session: Annotated[AsyncSession, Depends(get_session)],
    settings: Annotated[Settings, Depends(get_settings)],
) -> User:
    """Resolve the bearer access token to a `User`, or raise 401.

    The token's signature, expiry and `typ` are all checked (in
    `decode_access_token`), and the user is then loaded from the database on
    every request. Reading the row rather than trusting the token's claims is
    what makes deletion and deactivation take effect within one access-token
    lifetime instead of waiting for the token to expire.
    """
    if credentials is None or not credentials.credentials:
        raise _unauthorised()

    try:
        claims = decode_access_token(credentials.credentials, secret=settings.JWT_SECRET)
    except TokenError as exc:
        raise _unauthorised("Invalid or expired access token.") from exc

    # Imported here to keep `app.core` free of a hard import-time dependency on
    # a feature module (app.modules.auth imports app.core.security).
    from app.modules.auth.repository import AuthRepository
    from app.modules.auth.service import get_user_uuid

    user_id = get_user_uuid(claims.get("sub", ""))
    if user_id is None:
        raise _unauthorised("Invalid or expired access token.")

    user = await AuthRepository(session).get_user_by_id(user_id)
    if user is None:
        raise _unauthorised("Invalid or expired access token.")
    return user


async def get_current_active_user(
    user: Annotated[User, Depends(get_current_user)],
) -> User:
    """`get_current_user`, additionally rejecting deactivated accounts."""
    if not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="This account is disabled.",
        )
    return user


CurrentUser = Annotated[User, Depends(get_current_active_user)]
"""Annotated alias for the common case: an authenticated, active user."""


def require_role(*roles: UserRole):
    """Build a dependency that admits only the listed roles.

    ``admin`` is **not** implicitly granted every other role: the role set is
    flat and explicit, so a route that should also admit admins must say
    ``require_role(UserRole.reviewer, UserRole.admin)``. Implicit superuser
    inheritance is how privileged routes quietly acquire wider access than
    their author intended.
    """
    allowed = frozenset(roles)

    async def _dependency(user: CurrentUser) -> User:
        if user.role not in allowed:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Insufficient permissions for this operation.",
            )
        return user

    return _dependency

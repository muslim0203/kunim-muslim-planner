"""Request/response models for `/auth/*`.

`UserOut` lists its fields explicitly rather than dumping the ORM object, so a
column added to `User` later (`password_hash` above all) can never leak into a
response by accident. There is no schema anywhere in this module with a
`password_hash` field.
"""

from __future__ import annotations

import uuid
from datetime import datetime
from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, EmailStr, Field, field_validator

from app.modules.users.models import UserRole

# 8 is the NIST SP 800-63B minimum; the upper bound stops a megabyte-long
# password from turning argon2 into a denial-of-service vector.
Password = Annotated[str, Field(min_length=8, max_length=128)]
DeviceId = Annotated[str, Field(min_length=1, max_length=128)]
OpaqueToken = Annotated[str, Field(min_length=1, max_length=512)]


class _EmailNormalising(BaseModel):
    """Base class that lower-cases and strips the email before it reaches the DB.

    Normalisation must be identical on register and login, otherwise
    `A@x.com` could register a second account alongside `a@x.com`.
    """

    email: EmailStr

    @field_validator("email", mode="after")
    @classmethod
    def _normalise_email(cls, value: str) -> str:
        return value.strip().lower()


class RegisterRequest(_EmailNormalising):
    password: Password
    locale: Annotated[str, Field(max_length=10)] = "en"


class RegisterResponse(BaseModel):
    """Deliberately neutral: identical whether or not the email already existed.

    See `service.register` for why registration does not return tokens.
    """

    status: Literal["pending_verification"] = "pending_verification"
    message: str = (
        "If this email address can be registered, a verification message will be sent to it."
    )


class LoginRequest(_EmailNormalising):
    password: Password
    device_id: DeviceId = "unknown"


class RefreshRequest(BaseModel):
    refresh_token: OpaqueToken
    device_id: DeviceId = "unknown"


class LogoutRequest(BaseModel):
    refresh_token: OpaqueToken


class TokenPair(BaseModel):
    """The credentials handed back by `/auth/login` and `/auth/refresh`."""

    access_token: str
    refresh_token: str
    token_type: Literal["bearer"] = "bearer"
    expires_in: int = Field(description="Access-token lifetime in seconds.")
    refresh_expires_in: int = Field(description="Refresh-token lifetime in seconds.")


class UserOut(BaseModel):
    """Public view of a user. Never includes `password_hash`."""

    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    email: EmailStr
    role: UserRole
    is_active: bool
    locale: str
    email_verified_at: datetime | None
    created_at: datetime

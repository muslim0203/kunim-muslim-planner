"""Request/response models for `/users/me`.

`ProfileOut` lists its fields explicitly (the same convention as
`app.modules.auth.schemas.UserOut`) so a column added to `User` later can
never leak into a response by accident.
"""

from __future__ import annotations

import uuid
from datetime import datetime
from typing import Annotated, Literal
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from pydantic import BaseModel, ConfigDict, EmailStr, Field, field_validator, model_validator
from pydantic_core import PydanticCustomError

# The app's four supported locales (docs/plan.md; CLAUDE.md).
ALLOWED_LOCALES = ("uz", "uz_Cyrl", "ru", "en")

# The plan does not fix a gender vocabulary; this is this module's own choice
# (decision made where the plan/ADR were silent -- see report to next agent).
Gender = Literal["male", "female", "other", "prefer_not_to_say"]

DisplayName = Annotated[str, Field(max_length=100)]
# Lowercase and plain, so a name on a board cannot be confused with
# another one (no spaces, no mixed scripts, no look-alike padding).
Nickname = Annotated[
    str,
    Field(min_length=3, max_length=24, pattern=r"^[a-z0-9_]+$"),
]
AvatarUrl = Annotated[str, Field(max_length=2048)]
# Plausible birth-year range; loose on purpose (no product requirement pins it).
BirthYear = Annotated[int, Field(ge=1900, le=2100)]


def _validate_locale(value: str) -> str:
    # Raised as `PydanticCustomError`, not a bare `ValueError`: pydantic puts
    # the raw exception object into the error's `ctx` for a plain
    # `ValueError`, which `app.core.errors.validation_exception_handler`
    # (not owned by this module) then fails to JSON-serialise.
    # `PydanticCustomError`'s `ctx` only ever holds the plain values passed
    # in here, so it always serialises.
    if value not in ALLOWED_LOCALES:
        raise PydanticCustomError(
            "invalid_locale",
            "locale must be one of {allowed}, got '{value}'",
            {"allowed": ALLOWED_LOCALES, "value": value},
        )
    return value


def _validate_timezone(value: str) -> str:
    """Reject anything `zoneinfo` cannot resolve to a real IANA zone.

    This matters beyond input hygiene: the backend schedules a user's daily
    review job at their local 21:00, so an unresolvable zone would silently
    break scheduling for that user.
    """
    try:
        ZoneInfo(value)
    except (ZoneInfoNotFoundError, ValueError, KeyError) as exc:
        raise PydanticCustomError(
            "invalid_timezone", "Unknown IANA timezone: '{value}'", {"value": value}
        ) from exc
    return value


class ProfileOut(BaseModel):
    """Public view of a user's profile. Never includes `password_hash`."""

    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    email: EmailStr
    display_name: str | None
    locale: str
    timezone: str
    gender: Gender | None
    birth_year: int | None
    avatar_url: str | None
    nickname: str | None
    leaderboard_opt_in: bool
    created_at: datetime


class ProfileUpdate(BaseModel):
    """Partial update for `/users/me`.

    Only fields actually present in the request body are applied
    (`model_dump(exclude_unset=True)` in `service.py`) -- an omitted field is
    left untouched. `locale` and `timezone` back non-nullable columns, so an
    explicit `null` for either is rejected rather than silently ignored.
    """

    model_config = ConfigDict(extra="forbid")

    display_name: DisplayName | None = None
    locale: str | None = None
    timezone: str | None = None
    gender: Gender | None = None
    birth_year: BirthYear | None = None
    avatar_url: AvatarUrl | None = None
    nickname: Nickname | None = None
    leaderboard_opt_in: bool | None = None
    # TODO(storage): avatar upload (multipart -> object storage) is out of
    # scope for Phase 1 -- no object storage is configured yet. Clients pass
    # a URL they already host; nothing here validates reachability.

    @field_validator("locale")
    @classmethod
    def _check_locale(cls, v: str | None) -> str | None:
        return _validate_locale(v) if v is not None else v

    @field_validator("timezone")
    @classmethod
    def _check_timezone(cls, v: str | None) -> str | None:
        return _validate_timezone(v) if v is not None else v

    @model_validator(mode="before")
    @classmethod
    def _reject_null_for_required_fields(cls, data: object) -> object:
        if isinstance(data, dict):
            for key in ("locale", "timezone"):
                if key in data and data[key] is None:
                    raise PydanticCustomError(
                        "null_not_allowed", "'{key}' cannot be null", {"key": key}
                    )
        return data

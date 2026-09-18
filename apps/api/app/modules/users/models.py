"""User model. Authentication endpoints are out of scope for Phase 0."""

from __future__ import annotations

from datetime import datetime
from enum import StrEnum

from sqlalchemy import Boolean, DateTime, Enum, Integer, String, text
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base
from app.db.mixins import SoftDelete, Timestamps, UUIDPk


class UserRole(StrEnum):
    user = "user"
    reviewer = "reviewer"
    content_editor = "content_editor"
    admin = "admin"


class User(UUIDPk, Timestamps, SoftDelete, Base):
    __tablename__ = "users"

    email: Mapped[str] = mapped_column(String(320), unique=True, nullable=False, index=True)
    password_hash: Mapped[str | None] = mapped_column(String(255), nullable=True)
    role: Mapped[UserRole] = mapped_column(
        Enum(UserRole, name="user_role"),
        default=UserRole.user,
        nullable=False,
    )
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    locale: Mapped[str] = mapped_column(String(10), default="en", nullable=False)

    # --- Added in Phase 1 (auth). Null means "email not verified yet".
    # Phase 1 does not block login on verification; it only records the fact.
    # Plain DateTime(timezone=True) is used here (rather than the auth module's
    # TZDateTime) because this column is only ever written or null-checked,
    # never compared against "now" -- matching the style of the Timestamps mixin.
    email_verified_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True, default=None
    )

    # --- Added in Phase 1 (profile, `app/modules/profile/`). All nullable
    # except `timezone`, which defaults to "UTC" so every existing/newly
    # registered row has a valid IANA zone from the start -- the backend
    # schedules a user's daily review at their local 21:00 and needs one.
    # `gender` is intentionally a plain string, not a DB enum: the allowed
    # values (`male|female|other|prefer_not_to_say`) are validated once, at
    # the API boundary in `app.modules.profile.schemas`, matching how
    # `locale`'s allow-list is validated there rather than as a DB constraint.
    display_name: Mapped[str | None] = mapped_column(String(100), nullable=True, default=None)
    timezone: Mapped[str] = mapped_column(String(64), default="UTC", nullable=False)
    gender: Mapped[str | None] = mapped_column(String(20), nullable=True, default=None)
    birth_year: Mapped[int | None] = mapped_column(Integer, nullable=True, default=None)
    # TODO(storage): avatar upload is out of scope for Phase 1 (no object
    # storage configured). This column only stores a URL the client already
    # hosts elsewhere; nothing here uploads or validates reachability.
    avatar_url: Mapped[str | None] = mapped_column(String(2048), nullable=True, default=None)

    # --- Added with the leaderboard (`app/modules/social/`).
    # `nickname` is the name shown to other users, unique so two people
    # cannot claim the same one; null until the user picks one.
    # `leaderboard_opt_in` is false by default: the global board lists only
    # users who turned it on AND chose a nickname, so nobody is ever listed
    # under a name they did not pick.
    nickname: Mapped[str | None] = mapped_column(
        String(24), nullable=True, unique=True, default=None
    )
    leaderboard_opt_in: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False, server_default=text("false")
    )

    def __repr__(self) -> str:
        return f"<User id={self.id} email={self.email!r}>"

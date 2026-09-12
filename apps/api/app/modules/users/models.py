"""User model. Authentication endpoints are out of scope for Phase 0."""

from __future__ import annotations

from datetime import datetime
from enum import StrEnum

from sqlalchemy import Boolean, DateTime, Enum, String
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

    def __repr__(self) -> str:
        return f"<User id={self.id} email={self.email!r}>"

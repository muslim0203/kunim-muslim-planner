"""ORM models backing authentication.

Two tables live here:

* `refresh_tokens` -- one row per issued refresh token. Rotation is modelled as
  a linked list: refreshing marks the presented row `revoked_at` and points its
  `replaced_by` at the newly issued row. A "token family" is every row sharing
  the same `(user_id, device_id)`; presenting an already-rotated or revoked row
  means the token leaked, so the whole family is killed (see `service.py`).
* `verification_tokens` -- single-use tokens for email verification and
  password reset. The model and the service methods exist; actually delivering
  the token by email is an explicit TODO (no mail provider is configured yet).

Portability note (`TZDateTime`): production runs on PostgreSQL where
`TIMESTAMPTZ` round-trips an aware datetime faithfully, but the test suite runs
on SQLite, whose driver returns *naive* datetimes and would silently make every
`expires_at` comparison raise or, worse, compare wrongly. `TZDateTime` is a
`TypeDecorator` whose `impl` is exactly `DateTime(timezone=True)` -- so the
production DDL is unchanged, `TIMESTAMPTZ` either way -- that normalises values
to UTC on the way in and re-attaches UTC on the way out. The schema is not
weakened to suit the tests; only the Python-side round-trip is made explicit.
"""

from __future__ import annotations

import uuid
from datetime import UTC, datetime
from enum import StrEnum
from typing import Any

from sqlalchemy import DateTime, Enum, ForeignKey, Index, String, func
from sqlalchemy.orm import Mapped, mapped_column
from sqlalchemy.types import TypeDecorator

from app.db.base import Base
from app.db.mixins import UUIDPk

# Imported for its side effect: both tables below carry a ForeignKey to
# "users.id", which SQLAlchemy can only resolve once `User` has been registered
# on the shared `Base.metadata`. Without this, importing the auth models alone
# (Alembic autogenerate, `metadata.create_all` in tests) leaves `user_id` with
# a NullType and DDL generation fails.
from app.modules.users.models import User  # noqa: F401


class TZDateTime(TypeDecorator[datetime]):
    """`TIMESTAMPTZ` that always yields timezone-aware UTC datetimes in Python."""

    impl = DateTime(timezone=True)
    cache_ok = True

    def process_bind_param(self, value: datetime | None, dialect: Any) -> datetime | None:
        if value is None:
            return None
        if value.tzinfo is None:
            raise ValueError("naive datetime passed to a TZDateTime column")
        return value.astimezone(UTC)

    def process_result_value(self, value: datetime | None, dialect: Any) -> datetime | None:
        if value is None:
            return None
        if value.tzinfo is None:
            # SQLite (and any driver that drops the offset) hands back a naive
            # value that we know was stored as UTC.
            return value.replace(tzinfo=UTC)
        return value.astimezone(UTC)


class RefreshToken(UUIDPk, Base):
    """A single issued refresh token.

    The `Timestamps` mixin is deliberately not used: the plan specifies this
    table's columns exactly (`id, user_id, device_id, token_hash, expires_at,
    revoked_at, replaced_by, created_at`) and these rows are never updated in a
    way that an `updated_at` would meaningfully describe.

    Only `token_hash` is stored -- the raw token exists solely in the response
    body that hands it to the client, and is never written to disk or logged.
    """

    __tablename__ = "refresh_tokens"
    __table_args__ = (
        Index("ix_refresh_tokens_user_device", "user_id", "device_id"),
        Index("ix_refresh_tokens_user_id", "user_id"),
    )

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    # Client-supplied opaque device identifier. It scopes the token family, so
    # revoking a leaked token does not log the user out of their other devices.
    device_id: Mapped[str] = mapped_column(String(128), nullable=False)
    token_hash: Mapped[str] = mapped_column(String(64), nullable=False, unique=True, index=True)
    expires_at: Mapped[datetime] = mapped_column(TZDateTime, nullable=False)
    revoked_at: Mapped[datetime | None] = mapped_column(TZDateTime, nullable=True, default=None)
    replaced_by: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("refresh_tokens.id", ondelete="SET NULL"), nullable=True, default=None
    )
    created_at: Mapped[datetime] = mapped_column(
        TZDateTime, server_default=func.now(), nullable=False
    )

    def is_usable(self, now: datetime) -> bool:
        """True only for a token that has never been rotated, revoked or expired."""
        return self.revoked_at is None and self.replaced_by is None and self.expires_at > now

    def __repr__(self) -> str:  # pragma: no cover - debugging aid, no secrets
        return f"<RefreshToken id={self.id} user_id={self.user_id} device_id={self.device_id!r}>"


class VerificationPurpose(StrEnum):
    """What a `VerificationToken` authorises."""

    email_verify = "email_verify"
    password_reset = "password_reset"


class VerificationToken(UUIDPk, Base):
    """Single-use token for email verification / password reset.

    Like refresh tokens these are opaque random strings stored only as a
    SHA-256 digest, and they are consumed (not deleted) so that a replay is
    distinguishable from a token that never existed.
    """

    __tablename__ = "verification_tokens"
    __table_args__ = (Index("ix_verification_tokens_user_purpose", "user_id", "purpose"),)

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    purpose: Mapped[VerificationPurpose] = mapped_column(
        Enum(VerificationPurpose, name="verification_purpose"), nullable=False
    )
    token_hash: Mapped[str] = mapped_column(String(64), nullable=False, unique=True, index=True)
    expires_at: Mapped[datetime] = mapped_column(TZDateTime, nullable=False)
    consumed_at: Mapped[datetime | None] = mapped_column(TZDateTime, nullable=True, default=None)
    created_at: Mapped[datetime] = mapped_column(
        TZDateTime, server_default=func.now(), nullable=False
    )

    def __repr__(self) -> str:  # pragma: no cover - debugging aid, no secrets
        return f"<VerificationToken id={self.id} purpose={self.purpose}>"

"""ORM model for `preferences`: one row per user.

This table is a **synced entity in Phase 2** (`docs/adr/0002-sync.md`,
"Required columns" / rule 3), so it carries every mandatory sync mixin column
exactly as the ADR requires: `UUIDPk`, `Timestamps`, `SoftDelete`,
`Versioned`. It has no `ref_id` (ADR rule 16: each log table documents its own
`ref_id` semantics) because its natural key is simply `(user_id)` -- there is
exactly one row per user, created lazily on first read (see
`service.get_or_create`).
"""

from __future__ import annotations

import uuid

from sqlalchemy import JSON, ForeignKey, Index, text
from sqlalchemy.dialects import postgresql
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base
from app.db.mixins import SoftDelete, Timestamps, UUIDPk, Versioned

# Imported for its side effect: `user_id` below carries a ForeignKey to
# "users.id", which SQLAlchemy can only resolve once `User` is registered on
# the shared `Base.metadata` (same pattern as `app.modules.auth.models`).
from app.modules.users.models import User  # noqa: F401

# Portable JSON: plain JSON on SQLite (what the test suite runs against),
# JSONB on PostgreSQL in production -- same intent as `TZDateTime` in
# `app.modules.auth.models`: the production schema is not weakened for tests.
_JSONType = JSON().with_variant(postgresql.JSONB(), "postgresql")


class Preferences(UUIDPk, Timestamps, SoftDelete, Versioned, Base):
    """Per-user settings: prayer calculation, notifications, privacy, UI.

    `server_version` bump-on-write rule: see `service.py` module docstring
    for the exact mechanism and why a global sequence is not used here.
    """

    __tablename__ = "preferences"
    __table_args__ = (
        # Unique only among *live* rows: a soft-deleted row must not block
        # `service.get_or_create` from inserting a fresh one for the same
        # user (see `test_soft_deleted_row_is_not_returned`). A plain
        # table-wide unique constraint on `user_id` would make the first
        # soft-delete of a user's preferences permanent.
        Index(
            "ix_preferences_user_id_active",
            "user_id",
            unique=True,
            postgresql_where=text("deleted_at IS NULL"),
            sqlite_where=text("deleted_at IS NULL"),
        ),
    )

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )

    prayer_settings: Mapped[dict] = mapped_column(_JSONType, nullable=False)
    notifications: Mapped[dict] = mapped_column(_JSONType, nullable=False)
    privacy_consents: Mapped[dict] = mapped_column(_JSONType, nullable=False)
    ui: Mapped[dict] = mapped_column(_JSONType, nullable=False)

    def __repr__(self) -> str:  # pragma: no cover - debugging aid, no secrets
        return f"<Preferences id={self.id} user_id={self.user_id}>"

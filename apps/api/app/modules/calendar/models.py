"""ORM model for `calendar_events` (`docs/adr/0002-sync.md` rule 20).

Plain LWW + soft delete. `rrule` stores an RFC 5545 `RRULE` subset string
(`docs/plan.md` section 12: "kalendar RRULE subset") -- expansion into
concrete occurrences is a client-side concern, the server only stores and
syncs the string.
"""

from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, Index, String, text
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base
from app.db.mixins import SoftDelete, Timestamps, UUIDPk, Versioned

# Imported for its side effect: `user_id` below carries a ForeignKey to
# "users.id", which SQLAlchemy can only resolve once `User` is registered on
# the shared `Base.metadata`.
from app.modules.users.models import User  # noqa: F401


def _server_version_index(table_name: str) -> Index:
    """ADR rule 3: `(user_id, server_version)` unique for allocated versions."""
    return Index(
        f"uq_{table_name}_user_id_server_version",
        "user_id",
        "server_version",
        unique=True,
        postgresql_where=text("server_version > 0"),
        sqlite_where=text("server_version > 0"),
    )


class CalendarEvent(UUIDPk, Timestamps, SoftDelete, Versioned, Base):
    """A calendar event (ADR rule 20: plain LWW + soft delete)."""

    __tablename__ = "calendar_events"
    __table_args__ = (_server_version_index("calendar_events"),)

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )

    title: Mapped[str] = mapped_column(String(200), nullable=False)
    start_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    end_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    rrule: Mapped[str | None] = mapped_column(String(500), nullable=True, default=None)

    def __repr__(self) -> str:  # pragma: no cover - debugging aid, no secrets
        return f"<CalendarEvent id={self.id} user_id={self.user_id}>"

"""ORM models for `tasks` and `task_categories` (`docs/adr/0002-sync.md` rules 8 & 20).

Both tables are **synced entities in Phase 2**: each carries every mandatory
sync mixin column the ADR requires (`UUIDPk`, `Timestamps`, `SoftDelete`,
`Versioned`) plus its own `user_id` FK. Neither has anything beyond what
`docs/plan.md` section 3 names for these tables.

`Task.category_id` is a **loose reference**, not a SQL `ForeignKey`: the sync
engine applies one client's pushed changes independently of another's, and a
task referencing a category that has not reached the server yet (or that was
deleted on another device in the same window) must still be `applied`, not
crash the whole change with an integrity error. This mirrors how log tables
elsewhere in the codebase (`habit_logs.habit_id`, and the generic `ref_id`
pattern in `docs/sync-conflict-matrix.md` rule 14) already treat a
cross-entity id as an opaque value the server does not enforce referential
integrity on.
"""

from __future__ import annotations

import uuid
from datetime import date, datetime

from sqlalchemy import Date, DateTime, ForeignKey, Index, String, Text, text
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base
from app.db.mixins import SoftDelete, Timestamps, UUIDPk, Versioned

# Imported for its side effect: `user_id` below carries a ForeignKey to
# "users.id", which SQLAlchemy can only resolve once `User` is registered on
# the shared `Base.metadata` (same pattern as `app.modules.preferences.models`).
from app.modules.users.models import User  # noqa: F401


def _server_version_index(table_name: str) -> Index:
    """ADR rule 3: `(user_id, server_version)` unique for allocated versions.

    `server_version = 0` (never allocated) is excluded from the constraint --
    several rows may legitimately sit at 0 at once (e.g. a soft-deleted row
    and a freshly recreated one for the same user).
    """
    return Index(
        f"uq_{table_name}_user_id_server_version",
        "user_id",
        "server_version",
        unique=True,
        postgresql_where=text("server_version > 0"),
        sqlite_where=text("server_version > 0"),
    )


class TaskCategory(UUIDPk, Timestamps, SoftDelete, Versioned, Base):
    """A user-defined task category (ADR rule 20: plain LWW + soft delete)."""

    __tablename__ = "task_categories"
    __table_args__ = (_server_version_index("task_categories"),)

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )

    name: Mapped[str] = mapped_column(String(100), nullable=False)
    color: Mapped[str | None] = mapped_column(String(20), nullable=True, default=None)

    def __repr__(self) -> str:  # pragma: no cover - debugging aid, no secrets
        return f"<TaskCategory id={self.id} user_id={self.user_id}>"


class Task(UUIDPk, Timestamps, SoftDelete, Versioned, Base):
    """A to-do item.

    `completed_at` is `max_wins` (ADR rule 8): sync never reverts a task to
    "not done". The `completed` boolean the mobile UI shows is **not a
    column here** -- it is derived client- and server-side from
    `completed_at IS NOT NULL`, so it can never itself be the subject of a
    conflicting write.
    """

    __tablename__ = "tasks"
    __table_args__ = (_server_version_index("tasks"),)

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )

    title: Mapped[str] = mapped_column(String(200), nullable=False)
    notes: Mapped[str | None] = mapped_column(Text(), nullable=True, default=None)
    priority: Mapped[str] = mapped_column(String(20), nullable=False, server_default="medium")
    due_date: Mapped[date | None] = mapped_column(Date(), nullable=True, default=None)
    # Loose reference to `task_categories.id` -- see module docstring.
    category_id: Mapped[uuid.UUID | None] = mapped_column(nullable=True, default=None)
    completed_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True, default=None
    )

    def __repr__(self) -> str:  # pragma: no cover - debugging aid, no secrets
        return f"<Task id={self.id} user_id={self.user_id}>"

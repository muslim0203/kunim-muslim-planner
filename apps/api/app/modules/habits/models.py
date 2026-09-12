"""ORM models for `habits` and `habit_logs` (`docs/adr/0002-sync.md` rules 9 & 20).

`Habit` is plain LWW + soft delete (rule 20). `HabitLog`'s natural key is
`(user_id, habit_id, date)` (rule 9, verbatim from
`docs/sync-conflict-matrix.md`): `count` and `value` are additive fields
(`max_wins`), `note` is LWW. `habit_id` is a loose reference to `habits.id`,
not a SQL `ForeignKey` -- see `app.modules.tasks.models` module docstring for
why cross-entity ids are not enforced at the database level here.
"""

from __future__ import annotations

import uuid
from datetime import date

from sqlalchemy import JSON, Date, Float, ForeignKey, Index, Integer, String, Text, text
from sqlalchemy.dialects import postgresql
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base
from app.db.mixins import SoftDelete, Timestamps, UUIDPk, Versioned

# Imported for its side effect: `user_id` below carries a ForeignKey to
# "users.id", which SQLAlchemy can only resolve once `User` is registered on
# the shared `Base.metadata`.
from app.modules.users.models import User  # noqa: F401

# Portable JSON: plain JSON on SQLite (the test suite), JSONB on PostgreSQL --
# same pattern as `app.modules.preferences.models._JSONType`.
_JSONType = JSON().with_variant(postgresql.JSONB(), "postgresql")


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


class Habit(UUIDPk, Timestamps, SoftDelete, Versioned, Base):
    """A recurring habit the user tracks (ADR rule 20: plain LWW + soft delete).

    `schedule` is a small JSON document (e.g. `{"days": [1, 2, 3, 4, 5]}` for
    "weekdays" or `{"type": "daily"}`) rather than an RRULE string: unlike
    `calendar_events`, `docs/plan.md` section 3 does not name RRULE for
    habits, only "a schedule and target".
    """

    __tablename__ = "habits"
    __table_args__ = (_server_version_index("habits"),)

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )

    title: Mapped[str] = mapped_column(String(200), nullable=False)
    schedule: Mapped[dict] = mapped_column(_JSONType, nullable=False, default=dict)
    target: Mapped[int] = mapped_column(Integer, nullable=False, server_default="1")

    def __repr__(self) -> str:  # pragma: no cover - debugging aid, no secrets
        return f"<Habit id={self.id} user_id={self.user_id}>"


class HabitLog(UUIDPk, Timestamps, SoftDelete, Versioned, Base):
    """One day's log entry for a habit.

    Natural key `(user_id, habit_id, date)` (ADR rule 9): two devices logging
    the same habit on the same day merge into one row instead of colliding on
    their independently generated UUIDs (ADR rule 14).
    """

    __tablename__ = "habit_logs"
    __table_args__ = (_server_version_index("habit_logs"),)

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )

    # Loose reference to `habits.id` -- see module docstring.
    habit_id: Mapped[uuid.UUID] = mapped_column(nullable=False)
    date: Mapped[date] = mapped_column(Date(), nullable=False)
    count: Mapped[int] = mapped_column(Integer, nullable=False, server_default="0")
    value: Mapped[float] = mapped_column(Float(), nullable=False, server_default="0")
    note: Mapped[str | None] = mapped_column(Text(), nullable=True, default=None)

    def __repr__(self) -> str:  # pragma: no cover - debugging aid, no secrets
        return f"<HabitLog id={self.id} user_id={self.user_id}>"

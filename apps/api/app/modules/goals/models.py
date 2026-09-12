"""ORM models for `goals` and `milestones` (`docs/adr/0002-sync.md` rule 18).

Both are plain LWW, with one deliberate exception named by the ADR itself:
`progress_percent` is **not** `max_wins` -- a goal (or milestone) can
legitimately move backwards, so it is merged like every other field, by
whoever wrote last. `Milestone.goal_id` is a loose reference to `goals.id`,
not a SQL `ForeignKey` -- see `app.modules.tasks.models` module docstring for
why cross-entity ids are not enforced at the database level here.
"""

from __future__ import annotations

import uuid
from datetime import date

from sqlalchemy import Date, ForeignKey, Index, Integer, String, text
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


class Goal(UUIDPk, Timestamps, SoftDelete, Versioned, Base):
    """A user-defined goal (ADR rule 18: LWW, `progress_percent` is not max-wins)."""

    __tablename__ = "goals"
    __table_args__ = (_server_version_index("goals"),)

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )

    title: Mapped[str] = mapped_column(String(200), nullable=False)
    target_date: Mapped[date | None] = mapped_column(Date(), nullable=True, default=None)
    progress_percent: Mapped[int] = mapped_column(Integer, nullable=False, server_default="0")

    def __repr__(self) -> str:  # pragma: no cover - debugging aid, no secrets
        return f"<Goal id={self.id} user_id={self.user_id}>"


class Milestone(UUIDPk, Timestamps, SoftDelete, Versioned, Base):
    """A checkpoint belonging to a `Goal` (ADR rule 18, same merge rules)."""

    __tablename__ = "milestones"
    __table_args__ = (_server_version_index("milestones"),)

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )

    # Loose reference to `goals.id` -- see module docstring.
    goal_id: Mapped[uuid.UUID] = mapped_column(nullable=False)
    title: Mapped[str] = mapped_column(String(200), nullable=False)
    target_date: Mapped[date | None] = mapped_column(Date(), nullable=True, default=None)
    progress_percent: Mapped[int] = mapped_column(Integer, nullable=False, server_default="0")

    def __repr__(self) -> str:  # pragma: no cover - debugging aid, no secrets
        return f"<Milestone id={self.id} user_id={self.user_id}>"

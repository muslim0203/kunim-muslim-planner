"""ORM model for `daily_scores` (`docs/adr/0002-sync.md` rules 26 & 14).

One row per user per local day, holding the points the client computed for
that day and the counts behind them. The client owns the scoring rules
(`apps/mobile/lib/features/stats/domain/daily_score.dart`); the server only
stores and adds them up for the leaderboard, so the formula lives in exactly
one place.

Natural key `(user_id, date)`: unlike the log tables there is no `ref_id`,
because a day has exactly one score.
"""

from __future__ import annotations

import uuid
from datetime import date

from sqlalchemy import Date, ForeignKey, Integer
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base
from app.db.mixins import SoftDelete, Timestamps, UUIDPk, Versioned, sync_version_index

# Imported for its side effect: `user_id` carries a ForeignKey to "users.id".
from app.modules.users.models import User  # noqa: F401


class DailyScore(UUIDPk, Timestamps, SoftDelete, Versioned, Base):
    """One day's points for one user."""

    __tablename__ = "daily_scores"
    __table_args__ = (sync_version_index("daily_scores"),)

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )

    date: Mapped[date] = mapped_column(Date(), nullable=False)
    points: Mapped[int] = mapped_column(Integer, nullable=False, server_default="0")
    # What the points were earned for: how many of the day's widgets were done,
    # out of how many were planned.
    done: Mapped[int] = mapped_column(Integer, nullable=False, server_default="0")
    planned: Mapped[int] = mapped_column(Integer, nullable=False, server_default="0")

    def __repr__(self) -> str:  # pragma: no cover - debugging aid, no secrets
        return f"<DailyScore id={self.id} user_id={self.user_id}>"

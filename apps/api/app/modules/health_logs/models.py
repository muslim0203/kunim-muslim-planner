"""ORM model for `health_logs` (`docs/adr/0002-sync.md` rules 13 & 14).

Natural key `(user_id, coalesce(ref_id, ''), date)`. `ref_id` is reserved:
today's client always sends null ("the day's totals"), and a later client may
use it to keep per-source entries (e.g. one per connected health platform).
Null and '' are one key, hence a nullable `String`.

Every measurement is nullable: null means "not recorded", which `max_wins`
already ranks below any real value. `note` is `EncryptedText`
(`docs/plan.md` section 11); the numbers stay in the clear for aggregation.

The package is `health_logs`, not `health`: `app.modules.health` is the
liveness router.
"""

from __future__ import annotations

import uuid
from datetime import date

from sqlalchemy import Date, Float, ForeignKey, Integer, String
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base
from app.db.mixins import SoftDelete, Timestamps, UUIDPk, Versioned, sync_version_index
from app.db.types import EncryptedText

# Imported for its side effect: `user_id` carries a ForeignKey to "users.id".
from app.modules.users.models import User  # noqa: F401


class HealthLog(UUIDPk, Timestamps, SoftDelete, Versioned, Base):
    """One day's health measurements."""

    __tablename__ = "health_logs"
    __table_args__ = (sync_version_index("health_logs"),)

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )

    ref_id: Mapped[str | None] = mapped_column(String(64), nullable=True, default=None)
    date: Mapped[date] = mapped_column(Date(), nullable=False)
    water_ml: Mapped[int | None] = mapped_column(Integer, nullable=True, default=None)
    steps: Mapped[int | None] = mapped_column(Integer, nullable=True, default=None)
    workout_min: Mapped[int | None] = mapped_column(Integer, nullable=True, default=None)
    calories: Mapped[int | None] = mapped_column(Integer, nullable=True, default=None)
    weight_kg: Mapped[float | None] = mapped_column(Float(), nullable=True, default=None)
    note: Mapped[str | None] = mapped_column(EncryptedText(), nullable=True, default=None)

    def __repr__(self) -> str:  # pragma: no cover - debugging aid, no secrets
        return f"<HealthLog id={self.id} user_id={self.user_id}>"

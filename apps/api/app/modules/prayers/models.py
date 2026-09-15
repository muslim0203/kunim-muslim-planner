"""ORM model for `prayer_logs` (`docs/adr/0002-sync.md` rules 10 & 14).

Natural key `(user_id, ref_id, date)`, where `ref_id` is the prayer key
(`fajr`, `dhuhr`, `asr`, `maghrib`, `isha`; ADR rule 16) and `date` the local
calendar day the prayer belongs to. `status` is an ordered enum merged
max-wins; `note` is `EncryptedText` (`docs/plan.md` section 11).
"""

from __future__ import annotations

import uuid
from datetime import date

from sqlalchemy import Date, ForeignKey, String
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base
from app.db.mixins import SoftDelete, Timestamps, UUIDPk, Versioned, sync_version_index
from app.db.types import EncryptedText

# Imported for its side effect: `user_id` carries a ForeignKey to "users.id".
from app.modules.users.models import User  # noqa: F401


class PrayerLog(UUIDPk, Timestamps, SoftDelete, Versioned, Base):
    """How one of the day's five prayers was marked."""

    __tablename__ = "prayer_logs"
    __table_args__ = (sync_version_index("prayer_logs"),)

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )

    ref_id: Mapped[str] = mapped_column(String(64), nullable=False)
    date: Mapped[date] = mapped_column(Date(), nullable=False)
    status: Mapped[str] = mapped_column(String(16), nullable=False)
    note: Mapped[str | None] = mapped_column(EncryptedText(), nullable=True, default=None)

    def __repr__(self) -> str:  # pragma: no cover - debugging aid, no secrets
        return f"<PrayerLog id={self.id} user_id={self.user_id}>"

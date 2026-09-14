"""ORM model for `sleep_logs` (`docs/adr/0002-sync.md` rules 12 & 14).

Natural key `(user_id, coalesce(ref_id, ''), date)`, where `date` is the
calendar day the user woke up. `ref_id` is reserved: today's client always
sends null ("the day's main sleep"), and a later client may use it to record
naps separately. Null and '' are one key, hence a nullable `String`.

`bed_time` / `wake_time` are full UTC timestamps, not times of day: a night
crosses midnight, and the wire format (`schemas.to_wire`) has no time-only
type. `duration_min` is derived from them and validated at the wire boundary.
`note` is `EncryptedText` (`docs/plan.md` section 11).
"""

from __future__ import annotations

import uuid
from datetime import date, datetime

from sqlalchemy import Date, DateTime, ForeignKey, Integer, String
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base
from app.db.mixins import SoftDelete, Timestamps, UUIDPk, Versioned, sync_version_index
from app.db.types import EncryptedText

# Imported for its side effect: `user_id` carries a ForeignKey to "users.id".
from app.modules.users.models import User  # noqa: F401


class SleepLog(UUIDPk, Timestamps, SoftDelete, Versioned, Base):
    """One sleep window, attributed to the day the user woke up."""

    __tablename__ = "sleep_logs"
    __table_args__ = (sync_version_index("sleep_logs"),)

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )

    ref_id: Mapped[str | None] = mapped_column(String(64), nullable=True, default=None)
    date: Mapped[date] = mapped_column(Date(), nullable=False)
    bed_time: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    wake_time: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    duration_min: Mapped[int] = mapped_column(Integer, nullable=False)
    quality: Mapped[int | None] = mapped_column(Integer, nullable=True, default=None)
    note: Mapped[str | None] = mapped_column(EncryptedText(), nullable=True, default=None)

    def __repr__(self) -> str:  # pragma: no cover - debugging aid, no secrets
        return f"<SleepLog id={self.id} user_id={self.user_id}>"

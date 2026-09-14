"""ORM model for `family_logs` (`docs/adr/0002-sync.md` rules 25 & 14).

Natural key `(user_id, coalesce(ref_id, ''), date)`. `ref_id` is reserved:
today's client always sends null ("the day's family time"), and a later
client may use it to keep several entries per day (e.g. one per family
member). Null and '' are one key, hence a nullable `String`.

`minutes` is additive (max-wins), `activities` a set union, and `note`
(`EncryptedText`) LWW. Family notes are as private as mood notes, so they get
the same column encryption (`docs/privacy/data-map.md`).
"""

from __future__ import annotations

import uuid
from datetime import date

from sqlalchemy import Date, ForeignKey, Integer, String
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base
from app.db.mixins import SoftDelete, Timestamps, UUIDPk, Versioned, sync_version_index
from app.db.types import EncryptedText, JSONType

# Imported for its side effect: `user_id` carries a ForeignKey to "users.id".
from app.modules.users.models import User  # noqa: F401


class FamilyLog(UUIDPk, Timestamps, SoftDelete, Versioned, Base):
    """Time spent with family on one day."""

    __tablename__ = "family_logs"
    __table_args__ = (sync_version_index("family_logs"),)

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )

    ref_id: Mapped[str | None] = mapped_column(String(64), nullable=True, default=None)
    date: Mapped[date] = mapped_column(Date(), nullable=False)
    minutes: Mapped[int | None] = mapped_column(Integer, nullable=True, default=None)
    activities: Mapped[list[str]] = mapped_column(JSONType, nullable=False, default=list)
    note: Mapped[str | None] = mapped_column(EncryptedText(), nullable=True, default=None)

    def __repr__(self) -> str:  # pragma: no cover - debugging aid, no secrets
        return f"<FamilyLog id={self.id} user_id={self.user_id}>"

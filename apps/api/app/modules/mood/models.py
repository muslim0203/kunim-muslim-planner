"""ORM model for `mood_logs` (`docs/adr/0002-sync.md` rules 11 & 14).

Natural key `(user_id, coalesce(ref_id, ''), date)`. `ref_id` is reserved:
today's client always sends null ("the day's mood entry"), and a later client
may use it to keep more than one entry per day. `SyncRepository.
find_by_natural_key` treats null and '' as one key, which is why it is a
nullable `String` and not a `Uuid`.

`note` is `EncryptedText` (`docs/plan.md` section 11); `score` and `tags`
stay in the clear so they can be aggregated.
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


class MoodLog(UUIDPk, Timestamps, SoftDelete, Versioned, Base):
    """A mood score (1-5) for one day, with optional tags and a private note."""

    __tablename__ = "mood_logs"
    __table_args__ = (sync_version_index("mood_logs"),)

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )

    ref_id: Mapped[str | None] = mapped_column(String(64), nullable=True, default=None)
    date: Mapped[date] = mapped_column(Date(), nullable=False)
    score: Mapped[int] = mapped_column(Integer, nullable=False)
    tags: Mapped[list[str]] = mapped_column(JSONType, nullable=False, default=list)
    note: Mapped[str | None] = mapped_column(EncryptedText(), nullable=True, default=None)

    def __repr__(self) -> str:  # pragma: no cover - debugging aid, no secrets
        return f"<MoodLog id={self.id} user_id={self.user_id}>"

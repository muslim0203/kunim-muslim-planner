"""ORM models for friends and invites.

Friendship is stored as two rows, one per direction, so "who are my friends"
is a single indexed lookup on `user_id` and unfriending is symmetric by
construction. A single ordered-pair row would make every read an OR over two
columns for no gain.

An invite is a short code its owner shares out of band (a message, a QR code
later). It is single use and expires, so a leaked code cannot be redeemed for
ever by whoever finds it.
"""

from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, Index, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base
from app.db.mixins import Timestamps, UUIDPk

# Imported for its side effect: the foreign keys below point at "users.id".
from app.modules.users.models import User  # noqa: F401


class Friendship(UUIDPk, Timestamps, Base):
    """One direction of a friendship; the pair is always inserted together."""

    __tablename__ = "friendships"
    __table_args__ = (
        UniqueConstraint("user_id", "friend_id", name="uq_friendships_pair"),
        Index("ix_friendships_user_id", "user_id"),
    )

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    friend_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )

    def __repr__(self) -> str:  # pragma: no cover - debugging aid, no secrets
        return f"<Friendship user_id={self.user_id} friend_id={self.friend_id}>"


class FriendInvite(UUIDPk, Timestamps, Base):
    """A single-use code that makes its redeemer a friend of `user_id`."""

    __tablename__ = "friend_invites"
    __table_args__ = (Index("ix_friend_invites_user_id", "user_id"),)

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    code: Mapped[str] = mapped_column(String(16), nullable=False, unique=True, index=True)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    used_by: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=True, default=None
    )
    used_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True, default=None
    )

    def __repr__(self) -> str:  # pragma: no cover - debugging aid, no secrets
        return f"<FriendInvite id={self.id} user_id={self.user_id}>"

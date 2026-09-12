"""Sync-owned tables (ADR §3 "Idempotentlik", §4 "Saqlash muddatlari").

None of these are syncable entities themselves -- they are server
infrastructure and never appear in a pull response.

* `sync_user_state` -- the per-user monotonic `server_version` counter and the
  tombstone purge watermark.
* `sync_batches`    -- `batch_id` idempotency (7 days).
* `row_history`     -- before/after of every accepted change (30 days,
  support-only restore; no client endpoint reads it).
* `sync_merged_rows` -- which row a natural-key loser was merged into
  (ADR rule 14), kept out of the entity tables so no feature table needs a
  `merged_into` column.
"""

from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import JSON, BigInteger, ForeignKey, Index, String, Uuid, func
from sqlalchemy.dialects import postgresql
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base

# `TZDateTime` is a portability helper (aware UTC in Python, TIMESTAMPTZ in
# the DDL) that happens to live in the auth module; re-implementing it here
# would mean two decorators with the same semantics drifting apart, and moving
# it would mean editing a module this task does not own.
from app.modules.auth.models import TZDateTime

# Imported for its side effect: the FKs below need `users.id` registered on
# the shared metadata (same pattern as `app.modules.preferences.models`).
from app.modules.users.models import User  # noqa: F401

# Plain JSON on SQLite (tests), JSONB on PostgreSQL (production) -- identical
# intent to `app.modules.preferences.models._JSONType`.
_JSONType = JSON().with_variant(postgresql.JSONB(), "postgresql")


class SyncUserState(Base):
    """One row per user: the `server_version` allocator and purge watermark.

    `last_version` is bumped by a row-locked
    `UPDATE ... SET last_version = last_version + 1 ... RETURNING last_version`
    inside the writing transaction (ADR §3 "server_version semantikasi").
    A global `BIGSERIAL` is explicitly rejected by the ADR: it hands out a
    number at statement time while commits may land in a different order, so a
    cursor could step over a row that had not committed yet.
    """

    __tablename__ = "sync_user_state"

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), primary_key=True
    )
    last_version: Mapped[int] = mapped_column(BigInteger, server_default="0", nullable=False)
    purged_up_to_version: Mapped[int] = mapped_column(
        BigInteger,
        server_default="0",
        nullable=False,
        doc="Highest server_version whose tombstones have been physically "
        "deleted. A pull cursor below this cannot be reconciled -> "
        "full_resync_required (ADR §4).",
    )
    updated_at: Mapped[datetime] = mapped_column(
        TZDateTime, server_default=func.now(), onupdate=func.now(), nullable=False
    )


class SyncBatch(Base):
    """A processed push batch, stored so a retry returns the same answer.

    Same `batch_id` + same `request_hash` -> the stored response is replayed
    and **nothing is re-applied**. Same `batch_id` + different hash -> HTTP 409
    `batch_id_reused`. Retained 7 days; an older `batch_id` arriving again is
    simply treated as a new batch, which is safe because every change is an
    upsert by `id` and the merge rules are idempotent.
    """

    __tablename__ = "sync_batches"
    __table_args__ = (Index("ix_sync_batches_created_at", "created_at"),)

    batch_id: Mapped[uuid.UUID] = mapped_column(Uuid(), primary_key=True)
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    device_id: Mapped[str] = mapped_column(String(64), nullable=False)
    request_hash: Mapped[str] = mapped_column(String(64), nullable=False)
    response: Mapped[dict] = mapped_column(_JSONType, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        TZDateTime, server_default=func.now(), nullable=False
    )


class RowHistory(Base):
    """Before/after of every accepted change (ADR §4, 30 days).

    Support-only: there is no client endpoint over this table and no automatic
    rollback in the MVP. Access goes through `/admin` and is audited.
    """

    __tablename__ = "row_history"
    __table_args__ = (
        Index("ix_row_history_entity_row_id", "entity", "row_id"),
        Index("ix_row_history_created_at", "created_at"),
    )

    id: Mapped[uuid.UUID] = mapped_column(Uuid(), primary_key=True, default=uuid.uuid4)
    entity: Mapped[str] = mapped_column(String(64), nullable=False)
    row_id: Mapped[uuid.UUID] = mapped_column(Uuid(), nullable=False)
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    before: Mapped[dict | None] = mapped_column(_JSONType, nullable=True)
    after: Mapped[dict] = mapped_column(_JSONType, nullable=False)
    server_version: Mapped[int] = mapped_column(BigInteger, nullable=False)
    device_id: Mapped[str | None] = mapped_column(String(64), nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        TZDateTime, server_default=func.now(), nullable=False
    )


class SyncMergedRow(Base):
    """ADR rule 14: the loser of a natural-key collision and its survivor.

    Pull decorates the loser's tombstone with `{"merged_into": <survivor id>}`
    so the client can hide it in the UI, without any entity table growing a
    `merged_into` column.
    """

    __tablename__ = "sync_merged_rows"

    entity: Mapped[str] = mapped_column(String(64), primary_key=True)
    row_id: Mapped[uuid.UUID] = mapped_column(Uuid(), primary_key=True)
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    merged_into: Mapped[uuid.UUID] = mapped_column(Uuid(), nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        TZDateTime, server_default=func.now(), nullable=False
    )

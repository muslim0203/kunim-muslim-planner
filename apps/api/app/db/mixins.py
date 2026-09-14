"""Reusable column mixins shared by every syncable model.

These mixins only define columns (plus `sync_version_index`, the one index
every syncable table must carry) — no merge/conflict-resolution logic lives
here (that belongs to the sync engine, Phase 2).
"""

from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import BigInteger, DateTime, Index, func, text
from sqlalchemy.orm import Mapped, mapped_column


def sync_version_index(table_name: str) -> Index:
    """ADR-0002 rule 3: `(user_id, server_version)` unique among allocated versions.

    `0` is the "never allocated" sentinel, hence the partial index. Must match
    the migration's `_create_version_index` for the same table.
    """
    return Index(
        f"uq_{table_name}_user_id_server_version",
        "user_id",
        "server_version",
        unique=True,
        postgresql_where=text("server_version > 0"),
        sqlite_where=text("server_version > 0"),
    )


class UUIDPk:
    """Client-generated UUID primary key (no server default).

    The client (mobile app) is the source of truth for the id so it must be
    able to generate it offline, before the row ever reaches the server.
    """

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)


class Timestamps:
    """Timezone-aware UTC `created_at` / `updated_at` columns."""

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now(),
        nullable=False,
    )


class SoftDelete:
    """Nullable `deleted_at` marker; a non-null value means the row is tombstoned."""

    deleted_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True, default=None
    )


class Versioned:
    """Server-assigned optimistic-concurrency / sync version counter.

    The server owns this value; clients never set it directly.
    """

    server_version: Mapped[int] = mapped_column(BigInteger, server_default="0", nullable=False)

"""sync infrastructure: per-user version counter, batch idempotency, row history

Revision ID: 0004_sync_infrastructure
Revises: 0003_profile_preferences
Create Date: 2026-09-12

Implements the server-side tables of `docs/adr/0002-sync.md`:

* `sync_user_state`   -- §3 "server_version semantikasi": the per-user
  monotonic counter allocated under a row lock, plus §4's
  `purged_up_to_version` watermark that turns a too-old pull cursor into
  `full_resync_required`. A global `BIGSERIAL` is explicitly rejected by the
  ADR, which is why this is a counter row and not a sequence.
* `sync_batches`      -- §3 "Idempotentlik": `batch_id` -> stored response,
  7-day retention.
* `row_history`       -- §4: before/after of every accepted change, 30-day
  retention, support-only restore (no client endpoint reads it).
* `sync_merged_rows`  -- rule 14: which row a natural-key loser was merged
  into. Kept here rather than as a `merged_into` column on every entity table,
  so no feature table has to grow a sync-internal column.

`ref_id` semantics (ADR rule 16): none of these tables carry a `ref_id`. The
log tables that do (`habit_logs.ref_id = habit_id`, `prayer_logs.ref_id =
prayer_key`, ...) arrive with their own Phase-2 migrations and document it
there; the natural keys themselves are declared as data in
`app/modules/sync/merge.py::ADR_ENTITY_POLICIES`.

Applied and verified against PostgreSQL 16 (pgvector/pgvector:pg16) with
`alembic upgrade head`, and exercised on SQLite by the test suite.
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision: str = "0004_sync_infrastructure"
down_revision: str | None = "0003_profile_preferences"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "sync_user_state",
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("last_version", sa.BigInteger(), server_default="0", nullable=False),
        sa.Column(
            "purged_up_to_version",
            sa.BigInteger(),
            server_default="0",
            nullable=False,
            comment="Highest server_version whose tombstones were purged; a pull "
            "cursor below this cannot be reconciled (full_resync_required).",
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.PrimaryKeyConstraint("user_id", name=op.f("pk_sync_user_state")),
        sa.ForeignKeyConstraint(
            ["user_id"],
            ["users.id"],
            name=op.f("fk_sync_user_state_user_id_users"),
            ondelete="CASCADE",
        ),
    )

    op.create_table(
        "sync_batches",
        sa.Column("batch_id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("device_id", sa.String(length=64), nullable=False),
        sa.Column(
            "request_hash",
            sa.String(length=64),
            nullable=False,
            comment="sha256 of the canonical JSON of changes[]; a different hash "
            "under the same batch_id is HTTP 409 batch_id_reused.",
        ),
        sa.Column("response", postgresql.JSONB(), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.PrimaryKeyConstraint("batch_id", name=op.f("pk_sync_batches")),
        sa.ForeignKeyConstraint(
            ["user_id"],
            ["users.id"],
            name=op.f("fk_sync_batches_user_id_users"),
            ondelete="CASCADE",
        ),
    )
    # Retention sweep (7 days) scans by age.
    op.create_index("ix_sync_batches_created_at", "sync_batches", ["created_at"])

    op.create_table(
        "row_history",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("entity", sa.String(length=64), nullable=False),
        sa.Column("row_id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("before", postgresql.JSONB(), nullable=True),
        sa.Column("after", postgresql.JSONB(), nullable=False),
        sa.Column("server_version", sa.BigInteger(), nullable=False),
        sa.Column("device_id", sa.String(length=64), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_row_history")),
        sa.ForeignKeyConstraint(
            ["user_id"],
            ["users.id"],
            name=op.f("fk_row_history_user_id_users"),
            ondelete="CASCADE",
        ),
    )
    op.create_index("ix_row_history_entity_row_id", "row_history", ["entity", "row_id"])
    op.create_index("ix_row_history_created_at", "row_history", ["created_at"])

    op.create_table(
        "sync_merged_rows",
        sa.Column("entity", sa.String(length=64), nullable=False),
        sa.Column("row_id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("merged_into", sa.Uuid(), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.PrimaryKeyConstraint("entity", "row_id", name=op.f("pk_sync_merged_rows")),
        sa.ForeignKeyConstraint(
            ["user_id"],
            ["users.id"],
            name=op.f("fk_sync_merged_rows_user_id_users"),
            ondelete="CASCADE",
        ),
    )

    # ADR rule 3: "(user_id, server_version) unique" so pull can paginate by
    # server_version without ever skipping or repeating a row. The predicate
    # excludes `server_version = 0`, which §1 defines as "new row, never
    # allocated" -- several such rows may legitimately coexist for one user
    # (e.g. a tombstoned preferences row plus a freshly recreated one), and
    # they are invisible to pull precisely because the cursor starts at 0.
    op.create_index(
        "uq_preferences_user_id_server_version",
        "preferences",
        ["user_id", "server_version"],
        unique=True,
        postgresql_where=sa.text("server_version > 0"),
        sqlite_where=sa.text("server_version > 0"),
    )


def downgrade() -> None:
    op.drop_index("uq_preferences_user_id_server_version", table_name="preferences")

    op.drop_table("sync_merged_rows")

    op.drop_index("ix_row_history_created_at", table_name="row_history")
    op.drop_index("ix_row_history_entity_row_id", table_name="row_history")
    op.drop_table("row_history")

    op.drop_index("ix_sync_batches_created_at", table_name="sync_batches")
    op.drop_table("sync_batches")

    op.drop_table("sync_user_state")

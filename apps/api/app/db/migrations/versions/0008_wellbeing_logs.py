"""wellbeing logs: mood_logs, sleep_logs, health_logs, family_logs

Revision ID: 0008_wellbeing_logs
Revises: 0007_align_task_habit_fields
Create Date: 2026-09-14

Adds four daily log tables, registered with the sync engine in
`app.modules.mood.sync_entities`, `app.modules.sleep.sync_entities`,
`app.modules.health_logs.sync_entities` and
`app.modules.family.sync_entities`.

Every table carries the ADR-0002 section 1 mandatory columns (`id`,
`created_at`, `updated_at`, `deleted_at`, `server_version`) plus `user_id`
(FK to `users`, `ON DELETE CASCADE`), and the ADR rule 3 partial unique index
`(user_id, server_version) WHERE server_version > 0` -- the same shape as
`0005_phase2_entities`.

Natural keys and `ref_id` (ADR-0002 rule 16)
-------------------------------------------
All four tables use the natural key `(user_id, coalesce(ref_id, ''), date)`
(rules 11, 12, 13 and 25; collisions resolved by rule 14). `ref_id` is a
nullable `VARCHAR(64)`, never a `UUID`: null and '' are the same key, and a
future discriminator need not be a UUID. It is a loose value, never a foreign
key. What it means per table:

- `mood_logs.ref_id`
      Reserved entry discriminator. Null today = "the mood entry for `date`";
      a later client may set it to keep more than one mood entry per day.
- `sleep_logs.ref_id`
      Reserved sleep-period discriminator. Null today = "the main sleep that
      ended on `date`" (`date` is the day the user woke up); a later client
      may set it to record naps separately.
- `health_logs.ref_id`
      Reserved source discriminator. Null today = "the totals for `date`"; a
      later client may set it to keep per-source entries (e.g. one per
      connected health platform).
- `family_logs.ref_id`
      Reserved entry discriminator. Null today = "family time on `date`"; a
      later client may set it to keep several entries per day (e.g. one per
      family member).

Other column notes
------------------
- `note` on all four tables is `TEXT` holding AES-256-GCM ciphertext
  (`app.db.types.EncryptedText`, format `v<version>:<base64url>`), never
  plaintext.
- `mood_logs.tags` and `family_logs.activities` are JSONB arrays of short
  slugs, `NOT NULL` without a server default: the ORM and the wire schema
  both default them to `[]`, the same convention as `habits.schedule`.
- `sleep_logs.bed_time` / `wake_time` are `TIMESTAMPTZ`, not `TIME`: a night
  crosses midnight. `duration_min` is derived from them (validated at the
  wire boundary).
- Every `health_logs` measurement and `family_logs.minutes` is nullable:
  null means "not recorded", which the rule 13 / 25 max-wins merge ranks
  below any real value.
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision: str = "0008_wellbeing_logs"
down_revision: str | None = "0007_align_task_habit_fields"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def _sync_columns() -> list[sa.Column]:
    """The ADR section 1 mandatory columns, identical on every syncable table."""
    return [
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("server_version", sa.BigInteger(), server_default="0", nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
    ]


def _log_key_columns() -> list[sa.Column]:
    """`ref_id` + `date`: the non-user half of every table's natural key."""
    return [
        sa.Column("ref_id", sa.String(length=64), nullable=True),
        sa.Column("date", sa.Date(), nullable=False),
    ]


def _table_constraints(table_name: str) -> list[sa.Constraint]:
    return [
        sa.PrimaryKeyConstraint("id", name=op.f(f"pk_{table_name}")),
        sa.ForeignKeyConstraint(
            ["user_id"],
            ["users.id"],
            name=op.f(f"fk_{table_name}_user_id_users"),
            ondelete="CASCADE",
        ),
    ]


def _create_version_index(table_name: str) -> None:
    """ADR rule 3: `(user_id, server_version)` unique among allocated versions."""
    op.create_index(
        f"uq_{table_name}_user_id_server_version",
        table_name,
        ["user_id", "server_version"],
        unique=True,
        postgresql_where=sa.text("server_version > 0"),
        sqlite_where=sa.text("server_version > 0"),
    )


def upgrade() -> None:
    # --- mood_logs (ADR rule 11) -----------------------------------------------
    op.create_table(
        "mood_logs",
        *_sync_columns(),
        *_log_key_columns(),
        sa.Column("score", sa.Integer(), nullable=False),
        sa.Column("tags", postgresql.JSONB(), nullable=False),
        sa.Column("note", sa.Text(), nullable=True),
        *_table_constraints("mood_logs"),
    )
    _create_version_index("mood_logs")

    # --- sleep_logs (ADR rule 12) ----------------------------------------------
    op.create_table(
        "sleep_logs",
        *_sync_columns(),
        *_log_key_columns(),
        sa.Column("bed_time", sa.DateTime(timezone=True), nullable=False),
        sa.Column("wake_time", sa.DateTime(timezone=True), nullable=False),
        sa.Column("duration_min", sa.Integer(), nullable=False),
        sa.Column("quality", sa.Integer(), nullable=True),
        sa.Column("note", sa.Text(), nullable=True),
        *_table_constraints("sleep_logs"),
    )
    _create_version_index("sleep_logs")

    # --- health_logs (ADR rule 13) ---------------------------------------------
    op.create_table(
        "health_logs",
        *_sync_columns(),
        *_log_key_columns(),
        sa.Column("water_ml", sa.Integer(), nullable=True),
        sa.Column("steps", sa.Integer(), nullable=True),
        sa.Column("workout_min", sa.Integer(), nullable=True),
        sa.Column("calories", sa.Integer(), nullable=True),
        sa.Column("weight_kg", sa.Float(), nullable=True),
        sa.Column("note", sa.Text(), nullable=True),
        *_table_constraints("health_logs"),
    )
    _create_version_index("health_logs")

    # --- family_logs (ADR rule 25) ---------------------------------------------
    op.create_table(
        "family_logs",
        *_sync_columns(),
        *_log_key_columns(),
        sa.Column("minutes", sa.Integer(), nullable=True),
        sa.Column("activities", postgresql.JSONB(), nullable=False),
        sa.Column("note", sa.Text(), nullable=True),
        *_table_constraints("family_logs"),
    )
    _create_version_index("family_logs")


def downgrade() -> None:
    op.drop_index("uq_family_logs_user_id_server_version", table_name="family_logs")
    op.drop_table("family_logs")

    op.drop_index("uq_health_logs_user_id_server_version", table_name="health_logs")
    op.drop_table("health_logs")

    op.drop_index("uq_sleep_logs_user_id_server_version", table_name="sleep_logs")
    op.drop_table("sleep_logs")

    op.drop_index("uq_mood_logs_user_id_server_version", table_name="mood_logs")
    op.drop_table("mood_logs")

"""prayer logs

Revision ID: 0010_prayer_logs
Revises: 0009_seal_cached_batch_responses
Create Date: 2026-09-15

Adds `prayer_logs`, registered with the sync engine in
`app.modules.prayers.sync_entities` (ADR-0002 rules 10 and 14).

Same shape as the `0008_wellbeing_logs` tables: the ADR section 1 mandatory
columns, `user_id` (FK to `users`, `ON DELETE CASCADE`) and the rule 3 partial
unique index `(user_id, server_version) WHERE server_version > 0`.

Natural key and `ref_id` (ADR-0002 rule 16)
-------------------------------------------
Natural key `(user_id, ref_id, date)`. `prayer_logs.ref_id` is the prayer key,
one of `fajr`, `dhuhr`, `asr`, `maghrib`, `isha` (validated at the wire
boundary), and is never null. `date` is the local calendar day the prayer
belongs to.

Other column notes
------------------
- `status` is `VARCHAR(16)`, one of `none`, `qaza`, `alone`, `jamaah`, merged
  as an ordered enum, max-wins (rule 10).
- `note` is `TEXT` holding AES-256-GCM ciphertext
  (`app.db.types.EncryptedText`, format `v<version>:<base64url>`), never
  plaintext.
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision: str = "0010_prayer_logs"
down_revision: str | None = "0009_seal_cached_batch_responses"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "prayer_logs",
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
        sa.Column("ref_id", sa.String(length=64), nullable=False),
        sa.Column("date", sa.Date(), nullable=False),
        sa.Column("status", sa.String(length=16), nullable=False),
        sa.Column("note", sa.Text(), nullable=True),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_prayer_logs")),
        sa.ForeignKeyConstraint(
            ["user_id"],
            ["users.id"],
            name=op.f("fk_prayer_logs_user_id_users"),
            ondelete="CASCADE",
        ),
    )
    op.create_index(
        "uq_prayer_logs_user_id_server_version",
        "prayer_logs",
        ["user_id", "server_version"],
        unique=True,
        postgresql_where=sa.text("server_version > 0"),
        sqlite_where=sa.text("server_version > 0"),
    )


def downgrade() -> None:
    op.drop_index("uq_prayer_logs_user_id_server_version", table_name="prayer_logs")
    op.drop_table("prayer_logs")

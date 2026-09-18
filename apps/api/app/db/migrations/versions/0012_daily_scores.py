"""daily scores

Revision ID: 0012_daily_scores
Revises: 0011_habit_widgets
Create Date: 2026-09-18

Adds `daily_scores`, registered with the sync engine in
`app.modules.scores.sync_entities` (ADR-0002 rules 26 and 14).

One row per user per local day. The client computes the points
(`apps/mobile/lib/features/stats/domain/daily_score.dart`) and syncs them like
any other row; the server stores them and adds them up for the leaderboard, so
the scoring rules exist in one place only.

Natural key
-----------
`(user_id, date)` -- no `ref_id` column here, unlike the log tables: a day has
exactly one score. `points`, `done` and `planned` all merge max-wins (rule
26), so a device that synced late cannot erase work it never saw.

The table carries the ADR section 1 mandatory columns, `user_id` (FK to
`users`, `ON DELETE CASCADE`) and the rule 3 partial unique index
`(user_id, server_version) WHERE server_version > 0`.
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision: str = "0012_daily_scores"
down_revision: str | None = "0011_habit_widgets"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "daily_scores",
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
        sa.Column("date", sa.Date(), nullable=False),
        sa.Column("points", sa.Integer(), server_default="0", nullable=False),
        sa.Column("done", sa.Integer(), server_default="0", nullable=False),
        sa.Column("planned", sa.Integer(), server_default="0", nullable=False),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_daily_scores")),
        sa.ForeignKeyConstraint(
            ["user_id"],
            ["users.id"],
            name=op.f("fk_daily_scores_user_id_users"),
            ondelete="CASCADE",
        ),
    )
    op.create_index(
        "uq_daily_scores_user_id_server_version",
        "daily_scores",
        ["user_id", "server_version"],
        unique=True,
        postgresql_where=sa.text("server_version > 0"),
        sqlite_where=sa.text("server_version > 0"),
    )
    # The leaderboard reads "this user's rows since a date", and the retention
    # sweep reads them by day; both are served by this index.
    op.create_index(
        "ix_daily_scores_user_id_date",
        "daily_scores",
        ["user_id", "date"],
    )


def downgrade() -> None:
    op.drop_index("ix_daily_scores_user_id_date", table_name="daily_scores")
    op.drop_index("uq_daily_scores_user_id_server_version", table_name="daily_scores")
    op.drop_table("daily_scores")

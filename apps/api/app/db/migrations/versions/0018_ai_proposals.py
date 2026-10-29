"""ai proposals and request accounting

Revision ID: 0018_ai_proposals
Revises: 0017_profile_interests
Create Date: 2026-10-29

The two tables the AI assistant needs, and neither of them is part of the
user's data: `ai_proposals` holds what an agent suggested until the user
accepts or rejects it, and `ai_requests` holds what the call cost in tokens
and dollars. Neither carries `server_version` -- they are server-owned
records read over `/ai/*`, not sync rows.

No content is stored in `ai_requests` on purpose (rule 7 of `CLAUDE.md`):
counts and money, never a prompt or an answer.
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision: str = "0018_ai_proposals"
down_revision: str | None = "0017_profile_interests"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "ai_proposals",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("agent", sa.String(length=32), nullable=False),
        sa.Column(
            "payload",
            sa.JSON().with_variant(sa.dialects.postgresql.JSONB(), "postgresql"),
            nullable=False,
            server_default=sa.text("'{}'"),
        ),
        sa.Column(
            "status",
            sa.String(length=16),
            nullable=False,
            server_default="proposed",
        ),
        sa.Column(
            "applied_diff",
            sa.JSON().with_variant(sa.dialects.postgresql.JSONB(), "postgresql"),
            nullable=True,
        ),
        sa.Column("model", sa.String(length=64), nullable=True),
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
        sa.PrimaryKeyConstraint("id", name=op.f("pk_ai_proposals")),
        sa.ForeignKeyConstraint(
            ["user_id"],
            ["users.id"],
            name=op.f("fk_ai_proposals_user_id_users"),
            ondelete="CASCADE",
        ),
    )
    op.create_index("ix_ai_proposals_user_id_created_at", "ai_proposals", ["user_id", "created_at"])

    op.create_table(
        "ai_requests",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("agent", sa.String(length=32), nullable=False),
        sa.Column("model", sa.String(length=64), nullable=False),
        sa.Column("input_tokens", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("output_tokens", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("cache_read_tokens", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("cache_write_tokens", sa.Integer(), nullable=False, server_default="0"),
        sa.Column(
            "cost_usd",
            sa.Numeric(precision=12, scale=6),
            nullable=False,
            server_default="0",
        ),
        sa.Column("latency_ms", sa.Integer(), nullable=False, server_default="0"),
        sa.Column(
            "safety_flags",
            sa.JSON().with_variant(sa.dialects.postgresql.JSONB(), "postgresql"),
            nullable=False,
            server_default=sa.text("'[]'"),
        ),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_ai_requests")),
        sa.ForeignKeyConstraint(
            ["user_id"],
            ["users.id"],
            name=op.f("fk_ai_requests_user_id_users"),
            ondelete="CASCADE",
        ),
    )
    op.create_index("ix_ai_requests_user_id_created_at", "ai_requests", ["user_id", "created_at"])


def downgrade() -> None:
    op.drop_index("ix_ai_requests_user_id_created_at", table_name="ai_requests")
    op.drop_table("ai_requests")
    op.drop_index("ix_ai_proposals_user_id_created_at", table_name="ai_proposals")
    op.drop_table("ai_proposals")

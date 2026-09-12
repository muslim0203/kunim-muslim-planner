"""profile & preferences: user profile columns, preferences table

Revision ID: 0003_profile_preferences
Revises: 0002_auth
Create Date: 2026-09-12

This migration has NOT been applied -- no PostgreSQL instance is available in
this environment (same situation as 0002_auth). It has been verified by
`ast.parse` and by reading it against the ORM models it is meant to reproduce
(`app.modules.users.models.User`, `app.modules.preferences.models.Preferences`).

`preferences` carries every mandatory sync column from `docs/adr/0002-sync.md`
("Required columns" / rule 3): `id`, `created_at`, `updated_at`, `deleted_at`,
`server_version`, plus this table's own `user_id`. Its natural key is simply
`(user_id)` -- exactly one row per user -- so there is no `ref_id` column here
(ADR rule 16 only applies to log tables keyed by something else).
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision: str = "0003_profile_preferences"
down_revision: str | None = "0002_auth"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    # --- users: Phase-1 profile columns ------------------------------------
    op.add_column("users", sa.Column("display_name", sa.String(length=100), nullable=True))
    op.add_column(
        "users",
        sa.Column("timezone", sa.String(length=64), server_default="UTC", nullable=False),
    )
    op.add_column("users", sa.Column("gender", sa.String(length=20), nullable=True))
    op.add_column("users", sa.Column("birth_year", sa.Integer(), nullable=True))
    op.add_column("users", sa.Column("avatar_url", sa.String(length=2048), nullable=True))

    # --- preferences --------------------------------------------------------
    op.create_table(
        "preferences",
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
        sa.Column("prayer_settings", postgresql.JSONB(), nullable=False),
        sa.Column("notifications", postgresql.JSONB(), nullable=False),
        sa.Column("privacy_consents", postgresql.JSONB(), nullable=False),
        sa.Column("ui", postgresql.JSONB(), nullable=False),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_preferences")),
        sa.ForeignKeyConstraint(
            ["user_id"],
            ["users.id"],
            name=op.f("fk_preferences_user_id_users"),
            ondelete="CASCADE",
        ),
    )
    # Unique: exactly one (non-deleted, and in practice any) row per user;
    # also satisfies the ADR's "(user_id, server_version) unique" rule, since
    # user_id alone being unique is strictly stronger for a one-row table.
    op.create_index(op.f("ix_preferences_user_id"), "preferences", ["user_id"], unique=True)


def downgrade() -> None:
    op.drop_index(op.f("ix_preferences_user_id"), table_name="preferences")
    op.drop_table("preferences")

    op.drop_column("users", "avatar_url")
    op.drop_column("users", "birth_year")
    op.drop_column("users", "gender")
    op.drop_column("users", "timezone")
    op.drop_column("users", "display_name")

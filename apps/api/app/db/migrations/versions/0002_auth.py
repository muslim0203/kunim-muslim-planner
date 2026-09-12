"""auth: refresh tokens, verification tokens, users.email_verified_at

Revision ID: 0002_auth
Revises: 0001
Create Date: 2026-09-12

NOTE ON `down_revision`: the task brief called the baseline "0001_baseline_users",
but that is the *filename*; the `revision` identifier declared inside
`0001_baseline_users.py` is the string "0001". Alembic chains on the identifier,
so `down_revision` must be "0001" or the chain breaks.

This migration has NOT been applied -- no PostgreSQL instance is available in
this environment. It has been verified by `ast.parse` and by reading it against
the ORM models it is meant to reproduce.

"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision: str = "0002_auth"
down_revision: str | None = "0001"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

verification_purpose_enum = sa.Enum("email_verify", "password_reset", name="verification_purpose")


def upgrade() -> None:
    # --- users: record email verification -------------------------------
    op.add_column(
        "users",
        sa.Column("email_verified_at", sa.DateTime(timezone=True), nullable=True),
    )

    # --- refresh_tokens --------------------------------------------------
    op.create_table(
        "refresh_tokens",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("device_id", sa.String(length=128), nullable=False),
        sa.Column("token_hash", sa.String(length=64), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("revoked_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("replaced_by", sa.Uuid(), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_refresh_tokens")),
        sa.ForeignKeyConstraint(
            ["user_id"],
            ["users.id"],
            name=op.f("fk_refresh_tokens_user_id_users"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["replaced_by"],
            ["refresh_tokens.id"],
            name=op.f("fk_refresh_tokens_replaced_by_refresh_tokens"),
            ondelete="SET NULL",
        ),
    )
    # Unique: the hash is the lookup key on every /auth/refresh.
    op.create_index(
        op.f("ix_refresh_tokens_token_hash"), "refresh_tokens", ["token_hash"], unique=True
    )
    op.create_index(op.f("ix_refresh_tokens_user_id"), "refresh_tokens", ["user_id"])
    # Composite: reuse detection revokes a whole (user_id, device_id) family.
    op.create_index("ix_refresh_tokens_user_device", "refresh_tokens", ["user_id", "device_id"])

    # --- verification_tokens ---------------------------------------------
    verification_purpose_enum.create(op.get_bind(), checkfirst=True)
    op.create_table(
        "verification_tokens",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("purpose", verification_purpose_enum, nullable=False),
        sa.Column("token_hash", sa.String(length=64), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("consumed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_verification_tokens")),
        sa.ForeignKeyConstraint(
            ["user_id"],
            ["users.id"],
            name=op.f("fk_verification_tokens_user_id_users"),
            ondelete="CASCADE",
        ),
    )
    op.create_index(
        op.f("ix_verification_tokens_token_hash"),
        "verification_tokens",
        ["token_hash"],
        unique=True,
    )
    op.create_index(
        "ix_verification_tokens_user_purpose",
        "verification_tokens",
        ["user_id", "purpose"],
    )


def downgrade() -> None:
    op.drop_index("ix_verification_tokens_user_purpose", table_name="verification_tokens")
    op.drop_index(op.f("ix_verification_tokens_token_hash"), table_name="verification_tokens")
    op.drop_table("verification_tokens")
    verification_purpose_enum.drop(op.get_bind(), checkfirst=True)

    op.drop_index("ix_refresh_tokens_user_device", table_name="refresh_tokens")
    op.drop_index(op.f("ix_refresh_tokens_user_id"), table_name="refresh_tokens")
    op.drop_index(op.f("ix_refresh_tokens_token_hash"), table_name="refresh_tokens")
    op.drop_table("refresh_tokens")

    op.drop_column("users", "email_verified_at")

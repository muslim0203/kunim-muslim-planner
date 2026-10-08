"""user identities: Google sign-in

Revision ID: 0015_user_identities
Revises: 0014_habit_reminders
Create Date: 2026-10-08

An account can now be signed into with Google. The link is stored as the
provider's stable subject id, not the email, so a changed Google address
still reaches the same account. `(provider, subject)` is unique: one Google
account belongs to one KUNIM account.
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects.postgresql import ENUM

# revision identifiers, used by Alembic.
revision: str = "0015_user_identities"
down_revision: str | None = "0014_habit_reminders"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

identity_provider_enum = ENUM("google", name="identity_provider", create_type=False)


def upgrade() -> None:
    identity_provider_enum.create(op.get_bind(), checkfirst=True)
    op.create_table(
        "user_identities",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("provider", identity_provider_enum, nullable=False),
        sa.Column("subject", sa.String(length=255), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_user_identities")),
        sa.ForeignKeyConstraint(
            ["user_id"],
            ["users.id"],
            name=op.f("fk_user_identities_user_id_users"),
            ondelete="CASCADE",
        ),
        sa.UniqueConstraint("provider", "subject", name="uq_user_identities_provider_subject"),
    )
    op.create_index("ix_user_identities_user_id", "user_identities", ["user_id"])


def downgrade() -> None:
    op.drop_index("ix_user_identities_user_id", table_name="user_identities")
    op.drop_table("user_identities")
    identity_provider_enum.drop(op.get_bind(), checkfirst=True)

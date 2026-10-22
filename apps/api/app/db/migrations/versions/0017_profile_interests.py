"""profile: occupation, interests, focus areas and the time a day holds

Revision ID: 0017_profile_interests
Revises: 0016_profile_height
Create Date: 2026-10-22

Asked once, when the account is created, so the app can suggest which widgets
and tasks the day should hold instead of handing the user an empty grid.

`interests` and `focus_areas` are JSON lists of slugs rather than columns or
database enums: the client ships new options before the server hears of them,
and a vocabulary pinned in the schema would reject a newer app's answer
instead of carrying it. They default to an empty list, so every existing row
is valid without a backfill, and `occupation`/`daily_minutes` stay null for
accounts created before the questions existed.
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision: str = "0017_profile_interests"
down_revision: str | None = "0016_profile_height"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

_JSON = sa.JSON().with_variant(postgresql.JSONB(), "postgresql")


def upgrade() -> None:
    op.add_column("users", sa.Column("occupation", sa.String(length=40), nullable=True))
    op.add_column(
        "users",
        sa.Column("interests", _JSON, nullable=False, server_default=sa.text("'[]'")),
    )
    op.add_column(
        "users",
        sa.Column("focus_areas", _JSON, nullable=False, server_default=sa.text("'[]'")),
    )
    op.add_column("users", sa.Column("daily_minutes", sa.Integer(), nullable=True))


def downgrade() -> None:
    op.drop_column("users", "daily_minutes")
    op.drop_column("users", "focus_areas")
    op.drop_column("users", "interests")
    op.drop_column("users", "occupation")

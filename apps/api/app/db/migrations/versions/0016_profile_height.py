"""profile: height in centimetres

Revision ID: 0016_profile_height
Revises: 0015_user_identities
Create Date: 2026-10-08

The account screen needs a height, and height belongs on the profile: it
barely changes, so one value per user is the whole truth.

Weight deliberately does NOT come with it. Weight is already a dated
measurement in `health_logs` (`weight_kg`, ADR-0002 rule 13), which is what
makes the weight chart possible. A copy on the profile would be a second
source that goes stale the day after it is set and then disagrees with the
chart. The profile screen shows the latest logged weight and writes an edit
back as a log instead.
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision: str = "0016_profile_height"
down_revision: str | None = "0015_user_identities"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("users", sa.Column("height_cm", sa.Integer(), nullable=True))


def downgrade() -> None:
    op.drop_column("users", "height_cm")

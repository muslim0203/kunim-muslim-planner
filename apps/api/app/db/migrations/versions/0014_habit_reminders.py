"""habit reminders: the time of day a widget's task is done

Revision ID: 0014_habit_reminders
Revises: 0013_social
Create Date: 2026-09-28

A habit widget can now carry the time of day its task belongs to, which the
client also uses to raise a local reminder. Stored as minutes from local
midnight (0..1439) rather than a `TIME`: the reminder fires in the user's own
local time on whatever device shows it, so an absolute instant or a timezone
would be the wrong thing to carry across devices.

Nullable, and null means the widget has no fixed time -- which is what every
existing row gets, so older clients keep working untouched.
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision: str = "0014_habit_reminders"
down_revision: str | None = "0013_social"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("habits", sa.Column("reminder_minutes", sa.Integer(), nullable=True))


def downgrade() -> None:
    op.drop_column("habits", "reminder_minutes")

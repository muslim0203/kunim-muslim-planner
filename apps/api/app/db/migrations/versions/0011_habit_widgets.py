"""habit widgets: kind and total target

Revision ID: 0011_habit_widgets
Revises: 0010_prayer_logs
Create Date: 2026-09-18

A habit is now also a home widget: `kind` says what it tracks (a book, Qur'an
memorisation, zikr, sport, ...) and `total_target` the amount that finishes it
(a book's pages, the ayahs to memorise). Both are additive and optional, so
older clients keep working: they simply never send the fields, and the
defaults below apply.

- `kind` is `VARCHAR(32) NOT NULL DEFAULT 'custom'`, a plain slug rather than
  a database enum: clients ship new widget kinds ahead of the server, and a
  kind the server does not recognise must still round-trip (the wire schema
  only bounds its shape). It is merged like every other `habits` field --
  plain last-write-wins, ADR-0002 rule 20.
- `total_target` is nullable: null means an open-ended widget (zikr, sport)
  with no finish line. Progress towards it is the sum of that habit's
  `habit_logs.count`, so nothing new is stored for it.
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision: str = "0011_habit_widgets"
down_revision: str | None = "0010_prayer_logs"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "habits",
        sa.Column("kind", sa.String(length=32), nullable=False, server_default="custom"),
    )
    op.add_column("habits", sa.Column("total_target", sa.Integer(), nullable=True))


def downgrade() -> None:
    op.drop_column("habits", "total_target")
    op.drop_column("habits", "kind")

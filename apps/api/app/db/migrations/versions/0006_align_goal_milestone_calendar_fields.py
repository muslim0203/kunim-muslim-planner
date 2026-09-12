"""align goals, milestones and calendar_events with the client's field sets

Revision ID: 0006_align_client_fields
Revises: 0005_phase2_entities
Create Date: 2026-09-12

`SyncRowBase` is `extra="forbid"`, so any column the Flutter client holds but
the server's wire schema omits makes **every** push of that entity fail with
`schema_invalid` -- permanently, since the outbox entry is re-sent unchanged
on every cycle. Three Phase-2 entities were in exactly that state and could
never sync at all:

- `goals`           -- client has `description`
- `milestones`      -- client has `completed_at`, `sort_order`
- `calendar_events` -- client has `description`, `all_day`, `location`, and
                       models an open-ended event as a row with **no** end,
                       while `end_at` was NOT NULL here

This migration adds the missing columns and relaxes `calendar_events.end_at`
to nullable. Nothing is dropped: the client gains `milestones.progress_percent`
(ADR-0002 rule 18) on its side instead, so after this the two field sets match
exactly in both directions.

`description` and `location` are `Text` rather than `String(n)` because the
client columns are unbounded `text()` -- a narrower type here would re-create
the same class of bug for long values. The 64 KB per-payload cap
(`MAX_PAYLOAD_BYTES`) remains the real bound.
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision: str = "0006_align_client_fields"
down_revision: str | None = "0005_phase2_entities"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    # --- goals ------------------------------------------------------------
    op.add_column("goals", sa.Column("description", sa.Text(), nullable=True))

    # --- milestones -------------------------------------------------------
    op.add_column(
        "milestones",
        sa.Column("completed_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.add_column(
        "milestones",
        sa.Column("sort_order", sa.Integer(), server_default="0", nullable=False),
    )

    # --- calendar_events --------------------------------------------------
    op.add_column("calendar_events", sa.Column("description", sa.Text(), nullable=True))
    op.add_column(
        "calendar_events",
        sa.Column("all_day", sa.Boolean(), server_default=sa.text("false"), nullable=False),
    )
    op.add_column("calendar_events", sa.Column("location", sa.Text(), nullable=True))
    op.alter_column(
        "calendar_events",
        "end_at",
        existing_type=sa.DateTime(timezone=True),
        nullable=True,
    )


def downgrade() -> None:
    # `end_at` is restored to NOT NULL first: rows written while it was
    # nullable may hold NULL, so fall those back to `start_at` (a
    # zero-length event) rather than failing the downgrade.
    op.execute("UPDATE calendar_events SET end_at = start_at WHERE end_at IS NULL")
    op.alter_column(
        "calendar_events",
        "end_at",
        existing_type=sa.DateTime(timezone=True),
        nullable=False,
    )
    op.drop_column("calendar_events", "location")
    op.drop_column("calendar_events", "all_day")
    op.drop_column("calendar_events", "description")

    op.drop_column("milestones", "sort_order")
    op.drop_column("milestones", "completed_at")

    op.drop_column("goals", "description")

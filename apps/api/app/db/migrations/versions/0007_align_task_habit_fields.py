"""align tasks, task_categories, habits and habit_logs with the client's fields

Revision ID: 0007_align_task_habit_fields
Revises: 0006_align_client_fields
Create Date: 2026-09-12

Second half of the wire-contract reconciliation started in `0006`. An audit
that pushed the *exact* payload every Flutter repository builds showed all
seven Phase-2 entities being rejected as `schema_invalid`, i.e. nothing the
app produces could ever reach the server. `0006` fixed goals, milestones and
calendar_events; this one fixes the rest:

- `tasks.notes` -> `tasks.description`
      The client column is `description` (`tasks_table.dart`). The name only
      ever existed as `notes` on this side, so the column is renamed rather
      than duplicated.
- `task_categories.sort_order`  (new)
      The user orders their own categories; the client holds the column.
- `habits.description`, `habits.color`  (new)
      Both are client columns and real product fields.
- `habit_logs.value` -> nullable
      The client column is `real().nullable()` ("not applicable" for a
      count-only habit). `_max_wins` already treats `None` as the smallest
      value, so ADR-0002 rule 9 (additive max-wins) still holds.

Type-level mismatches are fixed on the *client* side instead, because the
server representation is the better one: `tasks.priority` stays a string enum
(not an int whose meaning depends on Dart enum declaration order),
`tasks.due_date` / `habit_logs.date` stay `DATE` (not a timestamp), and
`habits.schedule` stays JSONB (not a JSON string in a TEXT column).
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision: str = "0007_align_task_habit_fields"
down_revision: str | None = "0006_align_client_fields"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    # --- tasks ------------------------------------------------------------
    op.alter_column("tasks", "notes", new_column_name="description")

    # --- task_categories --------------------------------------------------
    op.add_column(
        "task_categories",
        sa.Column("sort_order", sa.Integer(), server_default="0", nullable=False),
    )

    # --- habits -----------------------------------------------------------
    op.add_column("habits", sa.Column("description", sa.Text(), nullable=True))
    op.add_column("habits", sa.Column("color", sa.String(length=20), nullable=True))

    # --- habit_logs -------------------------------------------------------
    op.alter_column(
        "habit_logs",
        "value",
        existing_type=sa.Float(),
        existing_server_default="0",
        server_default=None,
        nullable=True,
    )


def downgrade() -> None:
    # Backfill before tightening the constraint: rows written while the column
    # was nullable may hold NULL, which a NOT NULL alter would reject.
    op.execute("UPDATE habit_logs SET value = 0 WHERE value IS NULL")
    op.alter_column(
        "habit_logs",
        "value",
        existing_type=sa.Float(),
        server_default="0",
        nullable=False,
    )

    op.drop_column("habits", "color")
    op.drop_column("habits", "description")

    op.drop_column("task_categories", "sort_order")

    op.alter_column("tasks", "description", new_column_name="notes")

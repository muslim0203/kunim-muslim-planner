"""phase-2 entities: tasks, task_categories, habits, habit_logs, goals, milestones, calendar_events

Revision ID: 0005_phase2_entities
Revises: 0004_sync_infrastructure
Create Date: 2026-09-12

Adds the seven Phase-2 syncable tables named in `docs/plan.md` section 3's
sync table list and registered with the sync engine in
`app.modules.tasks.sync_entities`, `app.modules.habits.sync_entities`,
`app.modules.goals.sync_entities` and `app.modules.calendar.sync_entities`.

Every table carries the ADR §1 "Required columns" set (`id`, `created_at`,
`updated_at`, `deleted_at`, `server_version`) plus its own `user_id`, and the
ADR rule 3 partial unique index `(user_id, server_version) WHERE
server_version > 0` -- copied verbatim from `0003_profile_preferences` /
`0004_sync_infrastructure`'s `preferences` index, one per table here.

`tasks.category_id`, `habit_logs.habit_id` and `milestones.goal_id` are loose
references (plain `Uuid` columns, no `ForeignKeyConstraint`): the sync engine
applies one device's pushed changes independently of another's and of order
within a batch, so a row referencing a sibling entity that has not reached
the server yet (or was deleted concurrently) must still be applied, never
rejected by a foreign-key violation. This mirrors the ADR's own `ref_id`
convention for log tables (see `0004_sync_infrastructure`'s docstring).

Applied and verified against PostgreSQL 16 with `alembic upgrade head`, and
the downgrade/upgrade round-trip was exercised the same way.
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision: str = "0005_phase2_entities"
down_revision: str | None = "0004_sync_infrastructure"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def _sync_columns() -> list[sa.Column]:
    """The ADR §1 mandatory columns, identical on every syncable table."""
    return [
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
    ]


def _create_version_index(table_name: str) -> None:
    """ADR rule 3: `(user_id, server_version)` unique among allocated versions."""
    op.create_index(
        f"uq_{table_name}_user_id_server_version",
        table_name,
        ["user_id", "server_version"],
        unique=True,
        postgresql_where=sa.text("server_version > 0"),
        sqlite_where=sa.text("server_version > 0"),
    )


def upgrade() -> None:
    # --- task_categories -----------------------------------------------------
    op.create_table(
        "task_categories",
        *_sync_columns(),
        sa.Column("name", sa.String(length=100), nullable=False),
        sa.Column("color", sa.String(length=20), nullable=True),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_task_categories")),
        sa.ForeignKeyConstraint(
            ["user_id"],
            ["users.id"],
            name=op.f("fk_task_categories_user_id_users"),
            ondelete="CASCADE",
        ),
    )
    _create_version_index("task_categories")

    # --- tasks -----------------------------------------------------------------
    op.create_table(
        "tasks",
        *_sync_columns(),
        sa.Column("title", sa.String(length=200), nullable=False),
        sa.Column("notes", sa.Text(), nullable=True),
        sa.Column("priority", sa.String(length=20), server_default="medium", nullable=False),
        sa.Column("due_date", sa.Date(), nullable=True),
        # Loose reference to task_categories.id -- no FK, see module docstring.
        sa.Column("category_id", sa.Uuid(), nullable=True),
        sa.Column("completed_at", sa.DateTime(timezone=True), nullable=True),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_tasks")),
        sa.ForeignKeyConstraint(
            ["user_id"], ["users.id"], name=op.f("fk_tasks_user_id_users"), ondelete="CASCADE"
        ),
    )
    _create_version_index("tasks")

    # --- habits ------------------------------------------------------------------
    op.create_table(
        "habits",
        *_sync_columns(),
        sa.Column("title", sa.String(length=200), nullable=False),
        sa.Column("schedule", postgresql.JSONB(), nullable=False),
        sa.Column("target", sa.Integer(), server_default="1", nullable=False),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_habits")),
        sa.ForeignKeyConstraint(
            ["user_id"], ["users.id"], name=op.f("fk_habits_user_id_users"), ondelete="CASCADE"
        ),
    )
    _create_version_index("habits")

    # --- habit_logs --------------------------------------------------------------
    op.create_table(
        "habit_logs",
        *_sync_columns(),
        # Loose reference to habits.id -- no FK, see module docstring.
        sa.Column("habit_id", sa.Uuid(), nullable=False),
        sa.Column("date", sa.Date(), nullable=False),
        sa.Column("count", sa.Integer(), server_default="0", nullable=False),
        sa.Column("value", sa.Float(), server_default="0", nullable=False),
        sa.Column("note", sa.Text(), nullable=True),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_habit_logs")),
        sa.ForeignKeyConstraint(
            ["user_id"],
            ["users.id"],
            name=op.f("fk_habit_logs_user_id_users"),
            ondelete="CASCADE",
        ),
    )
    _create_version_index("habit_logs")

    # --- goals ---------------------------------------------------------------------
    op.create_table(
        "goals",
        *_sync_columns(),
        sa.Column("title", sa.String(length=200), nullable=False),
        sa.Column("target_date", sa.Date(), nullable=True),
        sa.Column("progress_percent", sa.Integer(), server_default="0", nullable=False),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_goals")),
        sa.ForeignKeyConstraint(
            ["user_id"], ["users.id"], name=op.f("fk_goals_user_id_users"), ondelete="CASCADE"
        ),
    )
    _create_version_index("goals")

    # --- milestones ------------------------------------------------------------------
    op.create_table(
        "milestones",
        *_sync_columns(),
        # Loose reference to goals.id -- no FK, see module docstring.
        sa.Column("goal_id", sa.Uuid(), nullable=False),
        sa.Column("title", sa.String(length=200), nullable=False),
        sa.Column("target_date", sa.Date(), nullable=True),
        sa.Column("progress_percent", sa.Integer(), server_default="0", nullable=False),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_milestones")),
        sa.ForeignKeyConstraint(
            ["user_id"],
            ["users.id"],
            name=op.f("fk_milestones_user_id_users"),
            ondelete="CASCADE",
        ),
    )
    _create_version_index("milestones")

    # --- calendar_events -----------------------------------------------------------
    op.create_table(
        "calendar_events",
        *_sync_columns(),
        sa.Column("title", sa.String(length=200), nullable=False),
        sa.Column("start_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("end_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("rrule", sa.String(length=500), nullable=True),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_calendar_events")),
        sa.ForeignKeyConstraint(
            ["user_id"],
            ["users.id"],
            name=op.f("fk_calendar_events_user_id_users"),
            ondelete="CASCADE",
        ),
    )
    _create_version_index("calendar_events")


def downgrade() -> None:
    op.drop_index("uq_calendar_events_user_id_server_version", table_name="calendar_events")
    op.drop_table("calendar_events")

    op.drop_index("uq_milestones_user_id_server_version", table_name="milestones")
    op.drop_table("milestones")

    op.drop_index("uq_goals_user_id_server_version", table_name="goals")
    op.drop_table("goals")

    op.drop_index("uq_habit_logs_user_id_server_version", table_name="habit_logs")
    op.drop_table("habit_logs")

    op.drop_index("uq_habits_user_id_server_version", table_name="habits")
    op.drop_table("habits")

    op.drop_index("uq_tasks_user_id_server_version", table_name="tasks")
    op.drop_table("tasks")

    op.drop_index("uq_task_categories_user_id_server_version", table_name="task_categories")
    op.drop_table("task_categories")

"""Structural tests for the Phase-2 entities (T-202).

`tests/test_sync_invariants.py::test_registered_entity_satisfies_the_contract`
already runs the generic registry contract against every entity registered
here (schema fields map to columns, the four mandatory sync columns exist,
`dirty` does not, natural-key columns exist). This module adds the
entity-specific checks that generic contract cannot express: which merge
strategy each field actually uses, that `tasks.completed` was never added,
that `habit_logs` really uses `habit_id` (not the generic `ref_id`) for its
natural key, and that the validators added at the wire boundary raise
`PydanticCustomError` rather than a bare `ValueError`.

End-to-end (over `/sync/push` and `/sync/pull`) coverage of the same rules
lives in `tests/test_phase2_sync.py`; this module never starts the FastAPI
app.
"""

from __future__ import annotations

import uuid
from datetime import UTC, date, datetime

import pytest
from pydantic import ValidationError
from sqlalchemy import inspect as sa_inspect

from app.modules.calendar.models import CalendarEvent
from app.modules.calendar.sync_entities import CalendarEventSyncRow
from app.modules.goals.models import Goal, Milestone
from app.modules.goals.sync_entities import GoalSyncRow, MilestoneSyncRow
from app.modules.habits.models import Habit, HabitLog
from app.modules.habits.sync_entities import (
    HABIT_LOG_POLICY,
    HabitLogSyncRow,
    HabitSyncRow,
)
from app.modules.sync import registry
from app.modules.sync.merge import ADR_ENTITY_POLICIES
from app.modules.sync.registry import MergeStrategy
from app.modules.tasks.models import Task, TaskCategory
from app.modules.tasks.sync_entities import TaskPriority, TaskSyncRow

USER = uuid.uuid4()
T0 = datetime(2026, 9, 12, 8, 0, 0, tzinfo=UTC)


def _base_row(**overrides: object) -> dict:
    base = {
        "id": str(uuid.uuid4()),
        "user_id": str(USER),
        "created_at": "2026-09-12T08:00:00.000Z",
        "updated_at": "2026-09-12T08:00:00.000Z",
        "deleted_at": None,
        "server_version": 0,
    }
    base.update(overrides)
    return base


# --- registration -------------------------------------------------------------


@pytest.mark.parametrize(
    "name,model,adr_rules,natural_key",
    [
        ("task_categories", TaskCategory, (20,), ()),
        ("tasks", Task, (8,), ()),
        ("habits", Habit, (20,), ()),
        ("habit_logs", HabitLog, (9, 14), ("user_id", "habit_id", "date")),
        ("goals", Goal, (18,), ()),
        ("milestones", Milestone, (18,), ()),
        ("calendar_events", CalendarEvent, (20,), ()),
    ],
)
def test_phase2_entity_is_registered_with_the_right_model_and_policy(
    name: str, model: type, adr_rules: tuple[int, ...], natural_key: tuple[str, ...]
) -> None:
    entity = registry.get_entity(name)
    assert entity is not None, name
    assert entity.model is model
    assert entity.policy.adr_rules == adr_rules
    assert entity.policy.natural_key == natural_key
    assert entity.direction is registry.SyncDirection.bidirectional


# --- rule 8: tasks.completed_at -----------------------------------------------


def test_rule_08_tasks_completed_at_field_rule_is_max_wins() -> None:
    entity = registry.get_entity("tasks")
    rule = entity.policy.rule_for("completed_at")
    assert rule is not None
    assert rule.strategy is MergeStrategy.max_wins
    assert rule.adr_rule == 8


def test_rule_08_completed_is_not_a_column_and_not_a_synced_field() -> None:
    """The `completed` boolean is derived, never synced (ADR rule 8)."""
    columns = {column.key for column in sa_inspect(Task).columns}
    assert "completed" not in columns
    assert "completed" not in TaskSyncRow.model_fields
    assert "completed" in ADR_ENTITY_POLICIES["tasks"].ignored_fields


def test_pushing_a_completed_boolean_is_schema_invalid() -> None:
    """`SyncRowBase` is `extra=\"forbid\"`: an unknown `completed` key on the
    wire must fail validation rather than silently being accepted."""
    payload = _base_row(title="wash the car", completed=True)
    with pytest.raises(ValidationError):
        TaskSyncRow.model_validate(payload)


def test_task_priority_rejects_an_unknown_value_via_pydantic_not_a_bare_valueerror() -> None:
    payload = _base_row(title="t", priority="urgent")
    with pytest.raises(ValidationError) as excinfo:
        TaskSyncRow.model_validate(payload)
    # A bare `ValueError` inside a validator would surface as `ValueError` in
    # `errors()[0]["type"]` too, so this also pins pydantic's own enum
    # validation is what fires, never a custom validator raising bare
    # `ValueError` (see `app.modules.sync.schemas` module docstring).
    assert excinfo.value.errors()[0]["type"] == "enum"


def test_task_priority_defaults_to_medium() -> None:
    payload = _base_row(title="t")
    row = TaskSyncRow.model_validate(payload)
    assert row.priority is TaskPriority.medium


# --- rule 9: habit_logs --------------------------------------------------------


def test_rule_09_habit_logs_uses_its_own_habit_id_natural_key_not_generic_ref_id() -> None:
    """`ADR_ENTITY_POLICIES["habit_logs"]` (the shared, generically-named
    policy) uses `ref_id`; this table's own column is `habit_id`
    (`docs/sync-conflict-matrix.md` rule 9, verbatim), so the module hand-
    builds its own policy instead of reusing the shared one."""
    assert ADR_ENTITY_POLICIES["habit_logs"].natural_key == ("user_id", "ref_id", "date")
    assert HABIT_LOG_POLICY.natural_key == ("user_id", "habit_id", "date")
    columns = {column.key for column in sa_inspect(HabitLog).columns}
    assert "habit_id" in columns
    assert "ref_id" not in columns


def test_rule_09_count_and_value_are_max_wins_note_is_lww() -> None:
    entity = registry.get_entity("habit_logs")
    assert entity.policy.rule_for("count").strategy is MergeStrategy.max_wins
    assert entity.policy.rule_for("value").strategy is MergeStrategy.max_wins
    assert entity.policy.rule_for("note").strategy is MergeStrategy.lww


def test_habit_log_sync_row_round_trips_date_and_habit_id() -> None:
    habit_id = uuid.uuid4()
    payload = _base_row(habit_id=str(habit_id), date="2026-09-12", count=3, value=1.5)
    row = HabitLogSyncRow.model_validate(payload)
    assert row.habit_id == habit_id
    assert row.date == date(2026, 9, 12)


def test_habit_sync_row_has_schedule_and_target() -> None:
    row = HabitSyncRow.model_validate(_base_row(title="Fajr on time"))
    assert row.schedule == {}
    assert row.target == 1


# --- rule 18: goals / milestones ----------------------------------------------


def test_rule_18_progress_percent_field_rule_is_lww_not_max_wins() -> None:
    for name in ("goals", "milestones"):
        entity = registry.get_entity(name)
        rule = entity.policy.rule_for("progress_percent")
        assert rule is not None, name
        assert rule.strategy is MergeStrategy.lww, name
        assert rule.strategy is not MergeStrategy.max_wins, name


@pytest.mark.parametrize("schema", [GoalSyncRow, MilestoneSyncRow])
def test_rule_18_progress_percent_is_bounded_0_to_100(schema: type) -> None:
    extra = {"goal_id": str(uuid.uuid4())} if schema is MilestoneSyncRow else {}
    schema.model_validate(_base_row(title="t", progress_percent=0, **extra))
    schema.model_validate(_base_row(title="t", progress_percent=100, **extra))
    with pytest.raises(ValidationError):
        schema.model_validate(_base_row(title="t", progress_percent=101, **extra))
    with pytest.raises(ValidationError):
        schema.model_validate(_base_row(title="t", progress_percent=-1, **extra))


def test_milestone_goal_id_is_a_loose_reference_not_a_foreign_key() -> None:
    """No `ForeignKeyConstraint` on `milestones.goal_id` (see module docstring
    of `app.modules.goals.models`): a milestone pushed before its goal has
    reached the server must still be `applied`."""
    fks = {fk.parent.key for fk in Milestone.__table__.foreign_keys}
    assert "goal_id" not in fks
    assert "user_id" in fks


# --- rule 20: plain LWW + soft delete tables -----------------------------------


@pytest.mark.parametrize("name", ["task_categories", "habits", "calendar_events"])
def test_rule_20_tables_declare_no_field_rules_and_no_natural_key(name: str) -> None:
    policy = registry.get_entity(name).policy
    assert policy.field_rules == ()
    assert policy.natural_key == ()


def test_calendar_event_rrule_is_an_optional_plain_string() -> None:
    row = CalendarEventSyncRow.model_validate(
        _base_row(
            title="Friday prayer",
            start_at="2026-09-12T08:00:00.000Z",
            end_at="2026-09-12T09:00:00.000Z",
            rrule="FREQ=WEEKLY;BYDAY=FR",
        )
    )
    assert row.rrule == "FREQ=WEEKLY;BYDAY=FR"


def test_calendar_event_end_before_start_is_rejected_via_pydantic_custom_error() -> None:
    with pytest.raises(ValidationError) as excinfo:
        CalendarEventSyncRow.model_validate(
            _base_row(
                title="broken",
                start_at="2026-09-12T09:00:00.000Z",
                end_at="2026-09-12T08:00:00.000Z",
            )
        )
    assert excinfo.value.errors()[0]["type"] == "invalid_calendar_event"


def test_task_category_id_is_a_loose_reference_not_a_foreign_key() -> None:
    fks = {fk.parent.key for fk in Task.__table__.foreign_keys}
    assert "category_id" not in fks
    assert "user_id" in fks


# --- migration index coverage (ADR rule 3) -------------------------------------


@pytest.mark.parametrize(
    "model,table_name",
    [
        (TaskCategory, "task_categories"),
        (Task, "tasks"),
        (Habit, "habits"),
        (HabitLog, "habit_logs"),
        (Goal, "goals"),
        (Milestone, "milestones"),
        (CalendarEvent, "calendar_events"),
    ],
)
def test_every_phase2_table_declares_the_unique_allocated_version_index(
    model: type, table_name: str
) -> None:
    names = {index.name for index in model.__table__.indexes}
    assert f"uq_{table_name}_user_id_server_version" in names

"""The widget fields on `habits`: `kind` and `total_target`.

A habit doubles as a home widget on the client. The wire schema has to accept
a kind this server has never heard of (clients ship new widget kinds first)
while still bounding its shape, and `total_target` has to stay optional so
older clients keep round-tripping.
"""

from __future__ import annotations

import uuid
from typing import Any

import pytest
from pydantic import ValidationError
from sqlalchemy import Integer, String

from app.modules.habits.models import Habit
from app.modules.habits.sync_entities import HabitSyncRow


def habit_row(**overrides: Any) -> dict[str, Any]:
    row: dict[str, Any] = {
        "id": str(uuid.uuid4()),
        "user_id": str(uuid.uuid4()),
        "created_at": "2026-09-18T08:00:00.000Z",
        "updated_at": "2026-09-18T08:00:00.000Z",
        "deleted_at": None,
        "server_version": 0,
        "title": "Kitob o'qish",
        "description": None,
        "schedule": {"type": "every_day"},
        "target": 10,
        "color": None,
    }
    row.update(overrides)
    return row


def test_a_row_without_the_widget_fields_still_validates() -> None:
    """An older client sends neither field; the defaults stand in."""
    parsed = HabitSyncRow.model_validate(habit_row())
    assert parsed.kind == "custom"
    assert parsed.total_target is None
    assert parsed.reminder_minutes is None


@pytest.mark.parametrize("kind", ["book", "quran", "zikr", "sport", "water", "study"])
def test_known_widget_kinds_are_accepted(kind: str) -> None:
    assert HabitSyncRow.model_validate(habit_row(kind=kind)).kind == kind


def test_an_unknown_kind_from_a_newer_client_is_accepted() -> None:
    """The server must not reject a widget kind it has not shipped yet."""
    assert HabitSyncRow.model_validate(habit_row(kind="fasting")).kind == "fasting"


def test_a_book_carries_the_pages_that_finish_it() -> None:
    parsed = HabitSyncRow.model_validate(habit_row(kind="book", target=10, total_target=300))
    assert parsed.total_target == 300


def test_a_widget_carries_the_time_of_day_its_task_belongs_to() -> None:
    """07:30 is 450 minutes from local midnight."""
    parsed = HabitSyncRow.model_validate(habit_row(reminder_minutes=450))
    assert parsed.reminder_minutes == 450


@pytest.mark.parametrize("minutes", [0, 1439])
def test_midnight_and_the_last_minute_of_the_day_are_inside_the_range(
    minutes: int,
) -> None:
    assert HabitSyncRow.model_validate(habit_row(reminder_minutes=minutes)).reminder_minutes == (
        minutes
    )


@pytest.mark.parametrize(
    "payload",
    [
        habit_row(kind="Not A Slug"),
        habit_row(kind="x" * 33),
        habit_row(kind=None),
        habit_row(total_target=0),
        habit_row(total_target=-5),
        habit_row(reminder_minutes=-1),
        habit_row(reminder_minutes=1440),
    ],
    ids=[
        "not-a-slug",
        "too-long",
        "null-kind",
        "zero-total",
        "negative-total",
        "before-midnight",
        "past-the-last-minute",
    ],
)
def test_invalid_widget_fields_are_rejected(payload: dict[str, Any]) -> None:
    with pytest.raises(ValidationError):
        HabitSyncRow.model_validate(payload)


def test_the_columns_match_the_wire_fields() -> None:
    columns = Habit.__table__.columns
    assert isinstance(columns["kind"].type, String)
    assert columns["kind"].nullable is False
    assert isinstance(columns["total_target"].type, Integer)
    assert columns["total_target"].nullable is True
    assert isinstance(columns["reminder_minutes"].type, Integer)
    assert columns["reminder_minutes"].nullable is True

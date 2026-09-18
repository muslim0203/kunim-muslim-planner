"""Registers `habits` and `habit_logs` as syncable entities.

ADR rule 20 (`habits`): plain LWW + soft delete --
`ADR_ENTITY_POLICIES["habits"]` is reused verbatim.

ADR rule 9 (`habit_logs`): natural key `(user_id, habit_id, date)`, `count`
and `value` are `max_wins`, `note` is LWW. This module hand-builds the
`MergePolicy` rather than reusing `ADR_ENTITY_POLICIES["habit_logs"]`: that
ready-made policy's natural key is generically named `ref_id` (the name every
other log table in the matrix uses), but `docs/sync-conflict-matrix.md` rule
9 and `docs/plan.md` section 3 both name this table's own column `habit_id`,
so the policy here points at `habit_id` directly -- the field rules
(`count`/`value`/`note`) are otherwise identical to the shared policy.
"""

from __future__ import annotations

import uuid
from datetime import date
from typing import Annotated

from pydantic import Field, StringConstraints

from app.modules.habits.models import Habit, HabitLog
from app.modules.sync.merge import ADR_ENTITY_POLICIES
from app.modules.sync.registry import (
    FieldRule,
    MergePolicy,
    MergeStrategy,
    SyncEntity,
    register_entity,
)
from app.modules.sync.schemas import SyncRowBase

WidgetKind = Annotated[
    str,
    StringConstraints(min_length=1, max_length=32, pattern=r"^[a-z][a-z0-9_]*$"),
]
"""What a habit widget tracks (`book`, `quran`, `zikr`, ...).

Deliberately a shape constraint and not an allow-list: the client ships new
widget kinds ahead of the server, and rejecting one it has not heard of
would break sync for that habit entirely.
"""


class HabitSyncRow(SyncRowBase):
    """Wire shape of a `habits` row: title, a JSON schedule, and a target."""

    title: str
    description: str | None = None
    schedule: dict = Field(default_factory=dict)
    target: int = 1
    color: str | None = None
    kind: WidgetKind = "custom"
    # The amount that finishes the widget; null is an open-ended one.
    total_target: int | None = Field(default=None, ge=1)


class HabitLogSyncRow(SyncRowBase):
    """Wire shape of a `habit_logs` row."""

    habit_id: uuid.UUID
    date: date
    count: int = 0
    value: float | None = None
    note: str | None = None


HABIT_LOG_POLICY = MergePolicy(
    adr_rules=(9, 14),
    natural_key=("user_id", "habit_id", "date"),
    field_rules=(
        FieldRule("count", MergeStrategy.max_wins, adr_rule=9),
        FieldRule("value", MergeStrategy.max_wins, adr_rule=9),
        FieldRule("note", MergeStrategy.lww, adr_rule=9),
    ),
)


register_entity(
    SyncEntity(
        name="habits",
        model=Habit,
        schema=HabitSyncRow,
        policy=ADR_ENTITY_POLICIES["habits"],
    )
)

register_entity(
    SyncEntity(
        name="habit_logs",
        model=HabitLog,
        schema=HabitLogSyncRow,
        policy=HABIT_LOG_POLICY,
    )
)

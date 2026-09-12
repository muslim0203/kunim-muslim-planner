"""Registers `goals` and `milestones` as syncable entities (ADR rule 18).

Both are plain LWW, with `progress_percent` explicitly **not** `max_wins` --
a goal (or milestone) can legitimately move backwards, so the field is merged
by whoever wrote last, same as every other field.
`ADR_ENTITY_POLICIES["goals"]` / `["milestones"]` already encode exactly this
and are reused verbatim.
"""

from __future__ import annotations

import uuid
from datetime import date

from pydantic import Field

from app.modules.goals.models import Goal, Milestone
from app.modules.sync.merge import ADR_ENTITY_POLICIES
from app.modules.sync.registry import SyncEntity, register_entity
from app.modules.sync.schemas import SyncRowBase, UtcDatetime


class GoalSyncRow(SyncRowBase):
    """Wire shape of a `goals` row.

    Must stay field-for-field in step with the client's `Goals` Drift table
    (`apps/mobile/lib/core/db/tables/goals_table.dart`): `SyncRowBase` is
    `extra="forbid"`, so a column the client holds but this schema omits makes
    every push of that entity fail with `schema_invalid`.
    """

    title: str
    description: str | None = None
    target_date: date | None = None
    progress_percent: int = Field(default=0, ge=0, le=100)


class MilestoneSyncRow(SyncRowBase):
    """Wire shape of a `milestones` row. `goal_id` is a loose reference to
    `goals.id` -- see `app.modules.goals.models` module docstring.

    Mirrors the client's `Milestones` table; see [GoalSyncRow] on why the two
    field sets have to match exactly.
    """

    goal_id: uuid.UUID
    title: str
    target_date: date | None = None
    progress_percent: int = Field(default=0, ge=0, le=100)
    completed_at: UtcDatetime | None = None
    sort_order: int = 0


register_entity(
    SyncEntity(
        name="goals",
        model=Goal,
        schema=GoalSyncRow,
        policy=ADR_ENTITY_POLICIES["goals"],
    )
)

register_entity(
    SyncEntity(
        name="milestones",
        model=Milestone,
        schema=MilestoneSyncRow,
        policy=ADR_ENTITY_POLICIES["milestones"],
    )
)

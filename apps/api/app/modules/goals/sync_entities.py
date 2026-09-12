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
from app.modules.sync.schemas import SyncRowBase


class GoalSyncRow(SyncRowBase):
    """Wire shape of a `goals` row."""

    title: str
    target_date: date | None = None
    progress_percent: int = Field(default=0, ge=0, le=100)


class MilestoneSyncRow(SyncRowBase):
    """Wire shape of a `milestones` row. `goal_id` is a loose reference to
    `goals.id` -- see `app.modules.goals.models` module docstring."""

    goal_id: uuid.UUID
    title: str
    target_date: date | None = None
    progress_percent: int = Field(default=0, ge=0, le=100)


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

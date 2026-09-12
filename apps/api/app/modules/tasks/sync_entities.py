"""Registers `task_categories` and `tasks` as syncable entities.

ADR rule 20 (`task_categories`): plain LWW + soft delete, no field-level
merge -- `ADR_ENTITY_POLICIES["task_categories"]` is used verbatim.

ADR rule 8 (`tasks`): `completed_at` is `max_wins` (`NULL` is smallest), so
sync can never revert a task to "not done"; every other field is plain LWW.
The `completed` boolean the UI shows is **not synced** -- it is derived from
`completed_at IS NOT NULL`, both on the client and here, which is why it has
no column on `Task` and no field on `TaskSyncRow`.
`ADR_ENTITY_POLICIES["tasks"]` already encodes exactly this (field rule +
`ignored_fields=("completed",)`), so it is reused verbatim too.
"""

from __future__ import annotations

import uuid
from datetime import date
from enum import StrEnum

from app.modules.sync.merge import ADR_ENTITY_POLICIES
from app.modules.sync.registry import SyncEntity, register_entity
from app.modules.sync.schemas import SyncRowBase, UtcDatetime
from app.modules.tasks.models import Task, TaskCategory


class TaskCategorySyncRow(SyncRowBase):
    """Wire shape of a `task_categories` row."""

    name: str
    color: str | None = None
    sort_order: int = 0


class TaskPriority(StrEnum):
    """Allowed `tasks.priority` values (this module's own naming -- `docs/plan.md`
    section 3 names the field but not an enum). Kept as a plain `String`
    column on `Task` (not a DB enum), validated here at the wire boundary --
    an unknown value is `rejected`/`schema_invalid` via pydantic's own enum
    validation rather than silently stored."""

    low = "low"
    medium = "medium"
    high = "high"


class TaskSyncRow(SyncRowBase):
    """Wire shape of a `tasks` row.

    Fields are exactly `docs/plan.md` section 3's minimum for this table:
    title, description, priority, due date, a loose category reference, and
    `completed_at`. No extra product features are added.
    """

    title: str
    description: str | None = None
    priority: TaskPriority = TaskPriority.medium
    due_date: date | None = None
    category_id: uuid.UUID | None = None
    completed_at: UtcDatetime | None = None


register_entity(
    SyncEntity(
        name="task_categories",
        model=TaskCategory,
        schema=TaskCategorySyncRow,
        policy=ADR_ENTITY_POLICIES["task_categories"],
    )
)

register_entity(
    SyncEntity(
        name="tasks",
        model=Task,
        schema=TaskSyncRow,
        policy=ADR_ENTITY_POLICIES["tasks"],
    )
)

"""Registers `calendar_events` as a syncable entity (ADR rule 20).

Plain LWW + soft delete -- `ADR_ENTITY_POLICIES["calendar_events"]` is reused
verbatim. The one piece of validation this schema adds beyond the shared
columns is structural, not a new product feature: `end_at` may not precede
`start_at`, checked with `PydanticCustomError` (never a bare `ValueError`,
per `app.modules.sync.schemas` module docstring) so a malformed push is
`rejected`/`schema_invalid` instead of being stored as a negative-duration
event.
"""

from __future__ import annotations

from pydantic import model_validator
from pydantic_core import PydanticCustomError

from app.modules.calendar.models import CalendarEvent
from app.modules.sync.merge import ADR_ENTITY_POLICIES
from app.modules.sync.registry import SyncEntity, register_entity
from app.modules.sync.schemas import SyncRowBase, UtcDatetime


class CalendarEventSyncRow(SyncRowBase):
    """Wire shape of a `calendar_events` row: title, start/end, RRULE string."""

    title: str
    start_at: UtcDatetime
    end_at: UtcDatetime
    rrule: str | None = None

    @model_validator(mode="after")
    def _check_end_after_start(self) -> CalendarEventSyncRow:
        if self.end_at < self.start_at:
            raise PydanticCustomError(
                "invalid_calendar_event",
                "end_at ('{end_at}') must not precede start_at ('{start_at}')",
                {"end_at": str(self.end_at), "start_at": str(self.start_at)},
            )
        return self


register_entity(
    SyncEntity(
        name="calendar_events",
        model=CalendarEvent,
        schema=CalendarEventSyncRow,
        policy=ADR_ENTITY_POLICIES["calendar_events"],
    )
)

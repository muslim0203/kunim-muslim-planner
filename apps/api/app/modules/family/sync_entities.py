"""Registers `family_logs` as a syncable entity (ADR-0002 rules 25 & 14).

`ADR_ENTITY_POLICIES["family_logs"]` is reused verbatim: `minutes` is
additive (max-wins), `activities` a set union, `note` LWW, natural key
`(user_id, ref_id, date)`.
"""

from __future__ import annotations

from datetime import date

from pydantic import Field

from app.modules.family.models import FamilyLog
from app.modules.sync.merge import ADR_ENTITY_POLICIES
from app.modules.sync.registry import SyncEntity, register_entity
from app.modules.sync.schemas import NoteText, RefId, SlugList, SyncRowBase

FAMILY_MINUTES_MAX = 1_440


class FamilyLogSyncRow(SyncRowBase):
    """Wire shape of a `family_logs` row."""

    ref_id: RefId | None = None
    date: date
    minutes: int | None = Field(default=None, ge=0, le=FAMILY_MINUTES_MAX)
    activities: SlugList = Field(default_factory=list)
    note: NoteText | None = None


register_entity(
    SyncEntity(
        name="family_logs",
        model=FamilyLog,
        schema=FamilyLogSyncRow,
        policy=ADR_ENTITY_POLICIES["family_logs"],
    )
)

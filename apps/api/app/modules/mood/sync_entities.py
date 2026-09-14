"""Registers `mood_logs` as a syncable entity (ADR-0002 rules 11 & 14).

`ADR_ENTITY_POLICIES["mood_logs"]` is reused verbatim: `score` and `note`
are LWW, `tags` is a set union, natural key `(user_id, ref_id, date)`.
"""

from __future__ import annotations

from datetime import date

from pydantic import Field

from app.modules.mood.models import MoodLog
from app.modules.sync.merge import ADR_ENTITY_POLICIES
from app.modules.sync.registry import SyncEntity, register_entity
from app.modules.sync.schemas import NoteText, RefId, SlugList, SyncRowBase

MOOD_SCORE_MIN = 1
MOOD_SCORE_MAX = 5


class MoodLogSyncRow(SyncRowBase):
    """Wire shape of a `mood_logs` row."""

    ref_id: RefId | None = None
    date: date
    score: int = Field(ge=MOOD_SCORE_MIN, le=MOOD_SCORE_MAX)
    tags: SlugList = Field(default_factory=list)
    note: NoteText | None = None


register_entity(
    SyncEntity(
        name="mood_logs",
        model=MoodLog,
        schema=MoodLogSyncRow,
        policy=ADR_ENTITY_POLICIES["mood_logs"],
    )
)

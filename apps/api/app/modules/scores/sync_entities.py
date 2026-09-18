"""Registers `daily_scores` as a syncable entity (ADR-0002 rules 26 & 14).

Natural key `(user_id, date)`. Every number merges **max-wins**: two devices
may each have logged part of the day, and the one that saw more work is the
one that is right. Last-write-wins would let a device that synced late erase
work it never saw.
"""

from __future__ import annotations

from datetime import date

from pydantic import Field

from app.modules.scores.models import DailyScore
from app.modules.sync.merge import ADR_ENTITY_POLICIES
from app.modules.sync.registry import SyncEntity, register_entity
from app.modules.sync.schemas import SyncRowBase


class DailyScoreSyncRow(SyncRowBase):
    """Wire shape of a `daily_scores` row."""

    date: date
    points: int = Field(default=0, ge=0)
    done: int = Field(default=0, ge=0)
    planned: int = Field(default=0, ge=0)


register_entity(
    SyncEntity(
        name="daily_scores",
        model=DailyScore,
        schema=DailyScoreSyncRow,
        policy=ADR_ENTITY_POLICIES["daily_scores"],
    )
)

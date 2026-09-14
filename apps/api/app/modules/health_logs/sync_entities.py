"""Registers `health_logs` as a syncable entity (ADR-0002 rules 13 & 14).

`ADR_ENTITY_POLICIES["health_logs"]` is reused verbatim: `water_ml`, `steps`,
`workout_min` and `calories` are additive (max-wins), `weight_kg` and `note`
are LWW, natural key `(user_id, ref_id, date)`.
"""

from __future__ import annotations

from datetime import date

from pydantic import Field

from app.modules.health_logs.models import HealthLog
from app.modules.sync.merge import ADR_ENTITY_POLICIES
from app.modules.sync.registry import SyncEntity, register_entity
from app.modules.sync.schemas import NoteText, RefId, SyncRowBase

WATER_ML_MAX = 20_000
STEPS_MAX = 200_000
WORKOUT_MIN_MAX = 1_440
CALORIES_MAX = 20_000
WEIGHT_KG_MIN = 20.0
WEIGHT_KG_MAX = 400.0


class HealthLogSyncRow(SyncRowBase):
    """Wire shape of a `health_logs` row."""

    ref_id: RefId | None = None
    date: date
    water_ml: int | None = Field(default=None, ge=0, le=WATER_ML_MAX)
    steps: int | None = Field(default=None, ge=0, le=STEPS_MAX)
    workout_min: int | None = Field(default=None, ge=0, le=WORKOUT_MIN_MAX)
    calories: int | None = Field(default=None, ge=0, le=CALORIES_MAX)
    weight_kg: float | None = Field(default=None, ge=WEIGHT_KG_MIN, le=WEIGHT_KG_MAX)
    note: NoteText | None = None


register_entity(
    SyncEntity(
        name="health_logs",
        model=HealthLog,
        schema=HealthLogSyncRow,
        policy=ADR_ENTITY_POLICIES["health_logs"],
    )
)

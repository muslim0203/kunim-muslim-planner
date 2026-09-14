"""Registers `sleep_logs` as a syncable entity (ADR-0002 rules 12 & 14).

`ADR_ENTITY_POLICIES["sleep_logs"]` is reused verbatim: `bed_time` and
`wake_time` come from one LWW winner as a pair, `duration_min` follows that
pair (derived, never max-wins), `quality` and `note` are LWW.

Because `duration_min` is derived, the wire boundary refuses a row whose
duration disagrees with its own window. Otherwise a merge could not keep the
three fields consistent: they are only guaranteed to agree if every stored
row already did.
"""

from __future__ import annotations

from datetime import date, timedelta

from pydantic import Field, model_validator

from app.modules.sleep.models import SleepLog
from app.modules.sync.merge import ADR_ENTITY_POLICIES
from app.modules.sync.registry import SyncEntity, register_entity
from app.modules.sync.schemas import (
    NoteText,
    RefId,
    SyncRowBase,
    UtcDatetime,
    invalid_payload,
)

SLEEP_MAX_WINDOW = timedelta(hours=24)
SLEEP_DURATION_MIN = 1
SLEEP_DURATION_MAX = 1440
SLEEP_QUALITY_MIN = 1
SLEEP_QUALITY_MAX = 5


class SleepLogSyncRow(SyncRowBase):
    """Wire shape of a `sleep_logs` row."""

    ref_id: RefId | None = None
    date: date
    bed_time: UtcDatetime
    wake_time: UtcDatetime
    duration_min: int = Field(ge=SLEEP_DURATION_MIN, le=SLEEP_DURATION_MAX)
    quality: int | None = Field(default=None, ge=SLEEP_QUALITY_MIN, le=SLEEP_QUALITY_MAX)
    note: NoteText | None = None

    @model_validator(mode="after")
    def _check_sleep_window(self) -> SleepLogSyncRow:
        window = self.wake_time - self.bed_time
        if window <= timedelta(0):
            raise invalid_payload("wake_time must be after bed_time", str(self.wake_time))
        if window > SLEEP_MAX_WINDOW:
            raise invalid_payload(
                "wake_time - bed_time must not exceed 24 hours", str(self.wake_time)
            )
        expected = window // timedelta(minutes=1)
        if self.duration_min != expected:
            raise invalid_payload(
                "duration_min must equal the whole minutes between bed_time and "
                "wake_time ({value})",
                str(expected),
            )
        return self


register_entity(
    SyncEntity(
        name="sleep_logs",
        model=SleepLog,
        schema=SleepLogSyncRow,
        policy=ADR_ENTITY_POLICIES["sleep_logs"],
    )
)

"""Registers `prayer_logs` as a syncable entity (ADR-0002 rules 10 & 14).

`ADR_ENTITY_POLICIES["prayer_logs"]` is reused verbatim: `status` is an
ordered enum merged max-wins (`none < qaza < alone < jamaah`), `note` is LWW,
natural key `(user_id, ref_id, date)` with `ref_id` the prayer key.
"""

from __future__ import annotations

from datetime import date
from typing import Literal

from app.modules.prayers.models import PrayerLog
from app.modules.sync.merge import ADR_ENTITY_POLICIES
from app.modules.sync.registry import SyncEntity, register_entity
from app.modules.sync.schemas import NoteText, SyncRowBase

PrayerKey = Literal["fajr", "dhuhr", "asr", "maghrib", "isha"]
"""The five prayers that can be marked; sunrise is a time, not a prayer."""

PrayerStatus = Literal["none", "qaza", "alone", "jamaah"]
"""Declared in the rule 10 merge order, lowest first."""


class PrayerLogSyncRow(SyncRowBase):
    """Wire shape of a `prayer_logs` row."""

    ref_id: PrayerKey
    date: date
    status: PrayerStatus
    note: NoteText | None = None


register_entity(
    SyncEntity(
        name="prayer_logs",
        model=PrayerLog,
        schema=PrayerLogSyncRow,
        policy=ADR_ENTITY_POLICIES["prayer_logs"],
    )
)

"""Structural tests for `prayer_logs` (ADR-0002 rules 10 and 14).

The generic registry contract in `tests/test_sync_invariants.py` already runs
against every registered entity, and `tests/test_sync_merge_matrix.py` covers
the rule 10 merge itself. This module pins what those cannot express: the wire
schema accepts exactly the merge order's statuses and the five prayer keys,
and the note is stored encrypted.
"""

from __future__ import annotations

import uuid
from typing import Any, get_args

import pytest
from pydantic import ValidationError
from sqlalchemy import String

from app.db.types import EncryptedText
from app.modules.prayers.models import PrayerLog
from app.modules.prayers.sync_entities import PrayerKey, PrayerLogSyncRow, PrayerStatus
from app.modules.sync import registry
from app.modules.sync.merge import ADR_ENTITY_POLICIES
from app.modules.sync.registry import MergeStrategy
from app.modules.sync.schemas import NOTE_MAX_LENGTH


def prayer_row(**overrides: Any) -> dict[str, Any]:
    row: dict[str, Any] = {
        "id": str(uuid.uuid4()),
        "user_id": str(uuid.uuid4()),
        "created_at": "2026-09-12T08:00:00.000Z",
        "updated_at": "2026-09-12T08:00:00.000Z",
        "deleted_at": None,
        "server_version": 0,
        "ref_id": "fajr",
        "date": "2026-09-12",
        "status": "jamaah",
        "note": None,
    }
    row.update(overrides)
    return row


def test_prayer_logs_is_registered_with_its_adr_policy() -> None:
    entity = registry.get_entity("prayer_logs")
    assert entity is not None
    assert entity.model is PrayerLog
    assert entity.schema is PrayerLogSyncRow
    assert entity.policy is ADR_ENTITY_POLICIES["prayer_logs"]
    assert entity.policy.adr_rules == (10, 14)
    assert entity.policy.natural_key == ("user_id", "ref_id", "date")


def test_wire_statuses_are_exactly_the_rule_10_merge_order() -> None:
    rule = ADR_ENTITY_POLICIES["prayer_logs"].rules_for_adr(10)[0]
    assert rule.strategy is MergeStrategy.enum_max_wins
    assert get_args(PrayerStatus) == rule.enum_order


@pytest.mark.parametrize("key", get_args(PrayerKey))
def test_every_prayer_key_is_accepted(key: str) -> None:
    parsed = PrayerLogSyncRow.model_validate(prayer_row(ref_id=key))
    assert parsed.ref_id == key


@pytest.mark.parametrize(
    "payload",
    [
        prayer_row(ref_id="sunrise"),
        prayer_row(ref_id=None),
        prayer_row(ref_id=""),
        prayer_row(status="missed"),
        prayer_row(status=None),
        prayer_row(note="x" * (NOTE_MAX_LENGTH + 1)),
        prayer_row(dirty=True),
    ],
    ids=["sunrise", "null-key", "empty-key", "unknown-status", "null-status", "long-note", "dirty"],
)
def test_invalid_rows_are_rejected(payload: dict[str, Any]) -> None:
    with pytest.raises(ValidationError):
        PrayerLogSyncRow.model_validate(payload)


def test_note_is_encrypted_and_ref_id_is_a_required_string() -> None:
    columns = PrayerLog.__table__.columns
    assert isinstance(columns["note"].type, EncryptedText)
    assert isinstance(columns["ref_id"].type, String)
    assert columns["ref_id"].nullable is False

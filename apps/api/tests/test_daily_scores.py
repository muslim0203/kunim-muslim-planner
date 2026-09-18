"""Structural tests for `daily_scores` (ADR-0002 rules 26 and 14).

The client computes the points and syncs them; the server stores them and
adds them up for the leaderboard. What matters here is that a day has exactly
one row per user, that every number merges max-wins (a device that synced
late must not erase work it never saw), and that the wire schema refuses
negative numbers.
"""

from __future__ import annotations

import uuid
from typing import Any

import pytest
from pydantic import ValidationError
from sqlalchemy import Integer

from app.modules.scores.models import DailyScore
from app.modules.scores.sync_entities import DailyScoreSyncRow
from app.modules.sync import registry
from app.modules.sync.merge import ADR_ENTITY_POLICIES
from app.modules.sync.registry import MergeStrategy


def score_row(**overrides: Any) -> dict[str, Any]:
    row: dict[str, Any] = {
        "id": str(uuid.uuid4()),
        "user_id": str(uuid.uuid4()),
        "created_at": "2026-09-18T20:30:00.000Z",
        "updated_at": "2026-09-18T20:30:00.000Z",
        "deleted_at": None,
        "server_version": 0,
        "date": "2026-09-18",
        "points": 35,
        "done": 1,
        "planned": 1,
    }
    row.update(overrides)
    return row


def test_daily_scores_is_registered_with_its_adr_policy() -> None:
    entity = registry.get_entity("daily_scores")
    assert entity is not None
    assert entity.model is DailyScore
    assert entity.schema is DailyScoreSyncRow
    assert entity.policy is ADR_ENTITY_POLICIES["daily_scores"]
    assert entity.policy.adr_rules == (26, 14)
    # A day has exactly one score, so there is no `ref_id` in the key.
    assert entity.policy.natural_key == ("user_id", "date")


@pytest.mark.parametrize("field", ["points", "done", "planned"])
def test_every_number_is_max_wins(field: str) -> None:
    rule = next(
        candidate
        for candidate in ADR_ENTITY_POLICIES["daily_scores"].field_rules
        if candidate.field == field
    )
    assert rule.strategy is MergeStrategy.max_wins


def test_a_full_row_validates() -> None:
    parsed = DailyScoreSyncRow.model_validate(score_row())
    assert parsed.points == 35
    assert parsed.done == 1
    assert parsed.planned == 1


def test_the_numbers_default_to_zero() -> None:
    row = score_row()
    for field in ("points", "done", "planned"):
        row.pop(field)
    parsed = DailyScoreSyncRow.model_validate(row)
    assert (parsed.points, parsed.done, parsed.planned) == (0, 0, 0)


@pytest.mark.parametrize(
    "payload",
    [
        score_row(points=-1),
        score_row(done=-1),
        score_row(planned=-1),
        score_row(date=None),
        score_row(dirty=True),
    ],
    ids=["negative-points", "negative-done", "negative-planned", "null-date", "dirty"],
)
def test_invalid_rows_are_rejected(payload: dict[str, Any]) -> None:
    with pytest.raises(ValidationError):
        DailyScoreSyncRow.model_validate(payload)


def test_the_columns_are_plain_integers() -> None:
    columns = DailyScore.__table__.columns
    for field in ("points", "done", "planned"):
        assert isinstance(columns[field].type, Integer)
        assert columns[field].nullable is False

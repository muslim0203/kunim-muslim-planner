"""Structural tests for the wellbeing log entities: mood, sleep, health, family.

`tests/test_sync_invariants.py::test_registered_entity_satisfies_the_contract`
already runs the generic registry contract against these entities. This
module adds what that contract cannot express: which merge strategy each
field uses (ADR-0002 rules 11, 12, 13 and 25), every bound the wire schemas
enforce, and the columns the ADR and the privacy data map care about (a
nullable string `ref_id`, an encrypted `note`, the rule 3 version index).

End-to-end `/sync` coverage of the same entities is in
`tests/test_wellbeing_sync.py`.
"""

from __future__ import annotations

import uuid
from datetime import date
from typing import Any

import pytest
from pydantic import BaseModel, ValidationError
from sqlalchemy import String

from app.db.types import EncryptedText
from app.modules.family.models import FamilyLog
from app.modules.family.sync_entities import FamilyLogSyncRow
from app.modules.health_logs.models import HealthLog
from app.modules.health_logs.sync_entities import HealthLogSyncRow
from app.modules.mood.models import MoodLog
from app.modules.mood.sync_entities import MoodLogSyncRow
from app.modules.sleep.models import SleepLog
from app.modules.sleep.sync_entities import SleepLogSyncRow
from app.modules.sync import registry
from app.modules.sync.merge import ADR_ENTITY_POLICIES
from app.modules.sync.registry import MergeStrategy
from app.modules.sync.schemas import SyncRowBase

USER = uuid.uuid4()
NATURAL_KEY = ("user_id", "ref_id", "date")
MODELS = [MoodLog, SleepLog, HealthLog, FamilyLog]
ENTITY_NAMES = ["mood_logs", "sleep_logs", "health_logs", "family_logs"]


def _base_row(**overrides: Any) -> dict[str, Any]:
    base: dict[str, Any] = {
        "id": str(uuid.uuid4()),
        "user_id": str(USER),
        "created_at": "2026-09-12T08:00:00.000Z",
        "updated_at": "2026-09-12T08:00:00.000Z",
        "deleted_at": None,
        "server_version": 0,
        "date": "2026-09-12",
    }
    base.update(overrides)
    return base


def mood_row(**overrides: Any) -> dict[str, Any]:
    return _base_row(ref_id=None, score=3, tags=[], note=None) | overrides


def sleep_row(**overrides: Any) -> dict[str, Any]:
    # 22:30:00.000 -> 06:15:30.500 is 7h45m30.5s, i.e. 465 whole minutes.
    return (
        _base_row(
            ref_id=None,
            bed_time="2026-09-11T22:30:00.000Z",
            wake_time="2026-09-12T06:15:30.500Z",
            duration_min=465,
            quality=None,
            note=None,
        )
        | overrides
    )


def health_row(**overrides: Any) -> dict[str, Any]:
    return _base_row(ref_id=None, note=None) | overrides


def family_row(**overrides: Any) -> dict[str, Any]:
    return _base_row(ref_id=None, minutes=None, activities=[], note=None) | overrides


ROW_BUILDERS: dict[type[BaseModel], Any] = {
    MoodLogSyncRow: mood_row,
    SleepLogSyncRow: sleep_row,
    HealthLogSyncRow: health_row,
    FamilyLogSyncRow: family_row,
}


def _assert_invalid(schema: type[BaseModel], payload: dict[str, Any]) -> ValidationError:
    with pytest.raises(ValidationError) as excinfo:
        schema.model_validate(payload)
    return excinfo.value


# --- registration ---------------------------------------------------------------


@pytest.mark.parametrize(
    "name,model,schema,adr_rules",
    [
        ("mood_logs", MoodLog, MoodLogSyncRow, (11, 14)),
        ("sleep_logs", SleepLog, SleepLogSyncRow, (12, 14)),
        ("health_logs", HealthLog, HealthLogSyncRow, (13, 14)),
        ("family_logs", FamilyLog, FamilyLogSyncRow, (25, 14)),
    ],
)
def test_wellbeing_entity_is_registered_with_its_adr_policy(
    name: str, model: type, schema: type, adr_rules: tuple[int, ...]
) -> None:
    entity = registry.get_entity(name)
    assert entity is not None, name
    assert entity.model is model
    assert entity.schema is schema
    assert entity.policy is ADR_ENTITY_POLICIES[name]
    assert entity.policy.adr_rules == adr_rules
    assert entity.policy.natural_key == NATURAL_KEY
    assert entity.direction is registry.SyncDirection.bidirectional


@pytest.mark.parametrize(
    "name,field,strategy",
    [
        ("mood_logs", "score", MergeStrategy.lww),
        ("mood_logs", "note", MergeStrategy.lww),
        ("mood_logs", "tags", MergeStrategy.set_union),
        ("sleep_logs", "bed_time", MergeStrategy.grouped_lww),
        ("sleep_logs", "wake_time", MergeStrategy.grouped_lww),
        ("sleep_logs", "duration_min", MergeStrategy.derived),
        ("sleep_logs", "quality", MergeStrategy.lww),
        ("sleep_logs", "note", MergeStrategy.lww),
        ("health_logs", "water_ml", MergeStrategy.max_wins),
        ("health_logs", "steps", MergeStrategy.max_wins),
        ("health_logs", "workout_min", MergeStrategy.max_wins),
        ("health_logs", "calories", MergeStrategy.max_wins),
        ("health_logs", "weight_kg", MergeStrategy.lww),
        ("health_logs", "note", MergeStrategy.lww),
        ("family_logs", "minutes", MergeStrategy.max_wins),
        ("family_logs", "activities", MergeStrategy.set_union),
        ("family_logs", "note", MergeStrategy.lww),
    ],
)
def test_field_uses_the_adr_merge_strategy(name: str, field: str, strategy: MergeStrategy) -> None:
    rule = registry.get_entity(name).policy.rule_for(field)
    assert rule is not None, f"{name}.{field} has no merge rule"
    assert rule.strategy is strategy


@pytest.mark.parametrize("name", ENTITY_NAMES)
def test_every_data_field_has_an_explicit_merge_rule(name: str) -> None:
    """A data field without a rule would silently fall back to row-level LWW.

    This is what caught `sleep_logs.quality` / `note` missing from rule 12.
    """
    entity = registry.get_entity(name)
    data_fields = set(entity.schema.model_fields) - set(SyncRowBase.model_fields)
    data_fields -= {"ref_id", "date"}  # natural-key columns, never merged
    assert data_fields == {rule.field for rule in entity.policy.field_rules}


# --- columns --------------------------------------------------------------------


@pytest.mark.parametrize("model", MODELS, ids=lambda m: m.__tablename__)
def test_ref_id_is_a_nullable_string_and_not_a_foreign_key(model: type) -> None:
    """`find_by_natural_key` treats null and '' as one key -- impossible on a UUID."""
    column = model.__table__.c.ref_id
    assert isinstance(column.type, String)
    assert not isinstance(column.type, EncryptedText)
    assert column.nullable is True
    assert {fk.parent.key for fk in model.__table__.foreign_keys} == {"user_id"}


@pytest.mark.parametrize("model", MODELS, ids=lambda m: m.__tablename__)
def test_note_column_is_encrypted_text(model: type) -> None:
    assert isinstance(model.__table__.c.note.type, EncryptedText)


@pytest.mark.parametrize("model", MODELS, ids=lambda m: m.__tablename__)
def test_table_declares_the_unique_allocated_version_index(model: type) -> None:
    names = {index.name for index in model.__table__.indexes}
    assert f"uq_{model.__tablename__}_user_id_server_version" in names


# --- shared fields: ref_id, date, note --------------------------------------------


@pytest.mark.parametrize("schema", list(ROW_BUILDERS), ids=lambda s: s.__name__)
def test_the_baseline_row_is_valid(schema: type[BaseModel]) -> None:
    row = schema.model_validate(ROW_BUILDERS[schema]())
    assert row.date == date(2026, 9, 12)
    assert row.ref_id is None


@pytest.mark.parametrize("schema", list(ROW_BUILDERS), ids=lambda s: s.__name__)
def test_ref_id_accepts_null_empty_and_short_strings(schema: type[BaseModel]) -> None:
    build = ROW_BUILDERS[schema]
    for value in (None, "", "nap", "x" * 64):
        schema.model_validate(build(ref_id=value))
    _assert_invalid(schema, build(ref_id="x" * 65))


@pytest.mark.parametrize("schema", list(ROW_BUILDERS), ids=lambda s: s.__name__)
def test_date_is_required_and_must_be_a_calendar_date(schema: type[BaseModel]) -> None:
    build = ROW_BUILDERS[schema]
    payload = build()
    payload.pop("date")
    _assert_invalid(schema, payload)
    _assert_invalid(schema, build(date="2026-02-30"))


@pytest.mark.parametrize("schema", list(ROW_BUILDERS), ids=lambda s: s.__name__)
def test_note_is_optional_and_at_most_2000_characters(schema: type[BaseModel]) -> None:
    build = ROW_BUILDERS[schema]
    payload = build()
    payload.pop("note")
    assert schema.model_validate(payload).note is None
    assert schema.model_validate(build(note="ё" * 2000)).note == "ё" * 2000
    _assert_invalid(schema, build(note="x" * 2001))


@pytest.mark.parametrize("schema", list(ROW_BUILDERS), ids=lambda s: s.__name__)
def test_unknown_keys_are_schema_invalid(schema: type[BaseModel]) -> None:
    _assert_invalid(schema, ROW_BUILDERS[schema](dirty=True))


# --- slug lists: mood_logs.tags, family_logs.activities --------------------------

SLUG_LIST_FIELDS = [(MoodLogSyncRow, "tags"), (FamilyLogSyncRow, "activities")]


@pytest.mark.parametrize("schema,field", SLUG_LIST_FIELDS, ids=lambda v: getattr(v, "__name__", v))
def test_slug_list_defaults_to_empty(schema: type[BaseModel], field: str) -> None:
    payload = ROW_BUILDERS[schema]()
    payload.pop(field)
    assert getattr(schema.model_validate(payload), field) == []


@pytest.mark.parametrize("schema,field", SLUG_LIST_FIELDS, ids=lambda v: getattr(v, "__name__", v))
@pytest.mark.parametrize(
    "values",
    [
        ["calm"],
        ["grateful_2", "a"],
        ["a" * 32],
        [f"tag_{index}" for index in range(32)],
    ],
)
def test_slug_list_accepts_valid_values(
    schema: type[BaseModel], field: str, values: list[str]
) -> None:
    row = schema.model_validate(ROW_BUILDERS[schema](**{field: values}))
    assert getattr(row, field) == values


@pytest.mark.parametrize(
    "name,field,schema",
    [("mood_logs", "tags", MoodLogSyncRow), ("family_logs", "activities", FamilyLogSyncRow)],
)
def test_the_merge_cap_equals_the_wire_list_limit(
    name: str, field: str, schema: type[BaseModel]
) -> None:
    """A merged list can never be longer than the schema accepts on re-validation."""
    from app.modules.sync.schemas import SLUG_LIST_MAX_ITEMS

    rule = registry.get_entity(name).policy.rule_for(field)
    assert SLUG_LIST_MAX_ITEMS == 32
    assert rule.max_items == SLUG_LIST_MAX_ITEMS
    build = ROW_BUILDERS[schema]
    schema.model_validate(build(**{field: [f"item_{i}" for i in range(rule.max_items)]}))
    _assert_invalid(schema, build(**{field: [f"item_{i}" for i in range(rule.max_items + 1)]}))


def test_max_items_is_only_valid_on_set_union_and_must_be_positive() -> None:
    from app.modules.sync.registry import FieldRule

    FieldRule("tags", MergeStrategy.set_union, adr_rule=11, max_items=1)
    with pytest.raises(ValueError):
        FieldRule("note", MergeStrategy.lww, adr_rule=11, max_items=5)
    with pytest.raises(ValueError):
        FieldRule("tags", MergeStrategy.set_union, adr_rule=11, max_items=0)


@pytest.mark.parametrize("schema,field", SLUG_LIST_FIELDS, ids=lambda v: getattr(v, "__name__", v))
@pytest.mark.parametrize(
    "values",
    [
        [f"tag_{index}" for index in range(33)],  # more than 32
        [""],  # empty
        ["a" * 33],  # longer than 32
        ["Calm"],  # upper case
        ["1calm"],  # must start with a letter
        ["_calm"],
        ["calm-down"],  # hyphen
        ["calm down"],  # space
        ["calm\n"],  # trailing newline must not slip past `$`
        ["қувонч"],  # non-ASCII
        "calm",  # not a list
        [1],  # not a string
    ],
)
def test_slug_list_rejects_invalid_values(schema: type[BaseModel], field: str, values: Any) -> None:
    _assert_invalid(schema, ROW_BUILDERS[schema](**{field: values}))


@pytest.mark.parametrize("schema,field", SLUG_LIST_FIELDS, ids=lambda v: getattr(v, "__name__", v))
def test_slug_list_drops_duplicates_keeping_first_occurrence(
    schema: type[BaseModel], field: str
) -> None:
    row = schema.model_validate(ROW_BUILDERS[schema](**{field: ["tired", "calm", "tired"]}))
    assert getattr(row, field) == ["tired", "calm"]


# --- mood_logs ------------------------------------------------------------------


@pytest.mark.parametrize("score", [1, 2, 5])
def test_mood_score_accepts_1_to_5(score: int) -> None:
    assert MoodLogSyncRow.model_validate(mood_row(score=score)).score == score


@pytest.mark.parametrize("score", [0, 6, -1, None, 2.5])
def test_mood_score_rejects_out_of_range(score: Any) -> None:
    _assert_invalid(MoodLogSyncRow, mood_row(score=score))


def test_mood_score_is_required() -> None:
    payload = mood_row()
    payload.pop("score")
    _assert_invalid(MoodLogSyncRow, payload)


# --- sleep_logs -----------------------------------------------------------------


def test_sleep_duration_is_floored_whole_minutes_between_bed_and_wake() -> None:
    row = SleepLogSyncRow.model_validate(sleep_row())
    assert row.duration_min == 465
    assert row.bed_time.tzinfo is not None


def test_sleep_times_with_an_offset_are_normalised_before_the_duration_check() -> None:
    row = SleepLogSyncRow.model_validate(
        sleep_row(
            bed_time="2026-09-12T03:30:00+05:00",  # 22:30Z the previous day
            wake_time="2026-09-12T06:15:30.500Z",
        )
    )
    assert row.duration_min == 465


@pytest.mark.parametrize("duration", [464, 466])
def test_sleep_duration_that_disagrees_with_the_window_is_rejected(duration: int) -> None:
    error = _assert_invalid(SleepLogSyncRow, sleep_row(duration_min=duration))
    # A `PydanticCustomError`, never a bare `ValueError` (see sync.schemas).
    assert error.errors()[0]["type"] == "sync_invalid_payload"


def test_sleep_wake_time_must_be_after_bed_time() -> None:
    same = "2026-09-12T06:00:00.000Z"
    error = _assert_invalid(
        SleepLogSyncRow, sleep_row(bed_time=same, wake_time=same, duration_min=1)
    )
    assert error.errors()[0]["type"] == "sync_invalid_payload"

    error = _assert_invalid(
        SleepLogSyncRow,
        sleep_row(
            bed_time="2026-09-12T06:00:00.000Z",
            wake_time="2026-09-12T05:00:00.000Z",
            duration_min=60,
        ),
    )
    assert error.errors()[0]["type"] == "sync_invalid_payload"


def test_sleep_window_of_exactly_24_hours_is_accepted() -> None:
    row = SleepLogSyncRow.model_validate(
        sleep_row(
            bed_time="2026-09-11T06:00:00.000Z",
            wake_time="2026-09-12T06:00:00.000Z",
            duration_min=1440,
        )
    )
    assert row.duration_min == 1440


def test_sleep_window_longer_than_24_hours_is_rejected() -> None:
    # 24h00m30s floors to 1440 minutes, so only the window check can catch it.
    error = _assert_invalid(
        SleepLogSyncRow,
        sleep_row(
            bed_time="2026-09-11T06:00:00.000Z",
            wake_time="2026-09-12T06:00:30.000Z",
            duration_min=1440,
        ),
    )
    assert error.errors()[0]["type"] == "sync_invalid_payload"


@pytest.mark.parametrize("duration", [0, 1441])
def test_sleep_duration_outside_1_to_1440_is_rejected(duration: int) -> None:
    _assert_invalid(SleepLogSyncRow, sleep_row(duration_min=duration))


def test_sleep_window_under_a_minute_is_rejected() -> None:
    _assert_invalid(
        SleepLogSyncRow,
        sleep_row(
            bed_time="2026-09-12T06:00:00.000Z",
            wake_time="2026-09-12T06:00:59.999Z",
            duration_min=0,
        ),
    )


@pytest.mark.parametrize("field", ["bed_time", "wake_time", "duration_min"])
def test_sleep_window_fields_are_required(field: str) -> None:
    payload = sleep_row()
    payload.pop(field)
    _assert_invalid(SleepLogSyncRow, payload)


@pytest.mark.parametrize("quality", [None, 1, 5])
def test_sleep_quality_is_optional_1_to_5(quality: int | None) -> None:
    assert SleepLogSyncRow.model_validate(sleep_row(quality=quality)).quality == quality


@pytest.mark.parametrize("quality", [0, 6])
def test_sleep_quality_outside_1_to_5_is_rejected(quality: int) -> None:
    _assert_invalid(SleepLogSyncRow, sleep_row(quality=quality))


# --- health_logs ----------------------------------------------------------------


def test_health_measurements_are_all_optional() -> None:
    row = HealthLogSyncRow.model_validate(health_row())
    assert (row.water_ml, row.steps, row.workout_min, row.calories, row.weight_kg) == (
        None,
        None,
        None,
        None,
        None,
    )


@pytest.mark.parametrize(
    "field,valid,invalid",
    [
        ("water_ml", [0, 20_000], [-1, 20_001]),
        ("steps", [0, 200_000], [-1, 200_001]),
        ("workout_min", [0, 1_440], [-1, 1_441]),
        ("calories", [0, 20_000], [-1, 20_001]),
        ("weight_kg", [20, 72.5, 400], [19.9, 400.1, 0]),
    ],
)
def test_health_measurement_bounds(field: str, valid: list[Any], invalid: list[Any]) -> None:
    for value in valid:
        assert (
            getattr(HealthLogSyncRow.model_validate(health_row(**{field: value})), field) == value
        )
    for value in invalid:
        _assert_invalid(HealthLogSyncRow, health_row(**{field: value}))


# --- family_logs ----------------------------------------------------------------


@pytest.mark.parametrize("minutes", [None, 0, 1_440])
def test_family_minutes_is_optional_0_to_1440(minutes: int | None) -> None:
    assert FamilyLogSyncRow.model_validate(family_row(minutes=minutes)).minutes == minutes


@pytest.mark.parametrize("minutes", [-1, 1_441])
def test_family_minutes_outside_0_to_1440_is_rejected(minutes: int) -> None:
    _assert_invalid(FamilyLogSyncRow, family_row(minutes=minutes))

"""End-to-end `/sync/push` + `/sync/pull` coverage for the wellbeing logs.

Same two-simulated-device harness as `tests/test_phase2_sync.py`: `SimClient`
only applies what the server answers, so every assertion here is about the
server's merge over HTTP (ADR-0002 rules 11-14 and 25), never a client-side
re-implementation of it.

Structural and schema-bound checks for the same entities are in
`tests/test_wellbeing_entities.py`; column encryption at rest is in
`tests/test_field_encryption.py`.
"""

from __future__ import annotations

import uuid
from datetime import datetime, timedelta
from typing import Any

import pytest

from tests import test_sync_harness as harness

BASE_TIME = harness.BASE_TIME
wire_time = harness.wire_time

# Fixtures are re-exported by assignment, not imported: pytest discovers them
# either way, but a test whose parameter shares a name with an import trips
# ruff's F811.
client = harness.client
session_factory = harness.session_factory
two_clients = harness.two_clients

DAY = "2026-09-12"


# --- payload builders -------------------------------------------------------------


def _base(
    row_id: str, *, updated_at: datetime, created_at: datetime | None = None
) -> dict[str, Any]:
    return {
        "id": row_id,
        "created_at": wire_time(created_at or updated_at),
        "updated_at": wire_time(updated_at),
        "deleted_at": None,
        "server_version": 0,
        "ref_id": None,
        "date": DAY,
    }


def mood_payload(
    row_id: str,
    *,
    updated_at: datetime,
    created_at: datetime | None = None,
    score: int = 3,
    tags: list[str] | None = None,
    note: str | None = None,
) -> dict[str, Any]:
    return _base(row_id, updated_at=updated_at, created_at=created_at) | {
        "score": score,
        "tags": tags or [],
        "note": note,
    }


def sleep_payload(
    row_id: str,
    *,
    updated_at: datetime,
    bed_time: datetime,
    wake_time: datetime,
    quality: int | None = None,
    note: str | None = None,
) -> dict[str, Any]:
    return _base(row_id, updated_at=updated_at) | {
        "bed_time": wire_time(bed_time),
        "wake_time": wire_time(wake_time),
        "duration_min": (wake_time - bed_time) // timedelta(minutes=1),
        "quality": quality,
        "note": note,
    }


def health_payload(
    row_id: str,
    *,
    updated_at: datetime,
    water_ml: int | None = None,
    steps: int | None = None,
    workout_min: int | None = None,
    calories: int | None = None,
    weight_kg: float | None = None,
    note: str | None = None,
) -> dict[str, Any]:
    return _base(row_id, updated_at=updated_at) | {
        "water_ml": water_ml,
        "steps": steps,
        "workout_min": workout_min,
        "calories": calories,
        "weight_kg": weight_kg,
        "note": note,
    }


def family_payload(
    row_id: str,
    *,
    updated_at: datetime,
    minutes: int | None = None,
    activities: list[str] | None = None,
    note: str | None = None,
) -> dict[str, Any]:
    return _base(row_id, updated_at=updated_at) | {
        "minutes": minutes,
        "activities": activities or [],
        "note": note,
    }


BED = BASE_TIME - timedelta(hours=9)  # 23:00Z the previous evening
WAKE = BASE_TIME - timedelta(hours=1, minutes=30)  # 06:30Z

BUILDERS = {
    "mood_logs": lambda row_id: mood_payload(
        row_id,
        updated_at=BASE_TIME,
        score=4,
        tags=["calm", "grateful"],
        note="Alhamdulillah, a calm day",
    ),
    "sleep_logs": lambda row_id: sleep_payload(
        row_id,
        updated_at=BASE_TIME,
        bed_time=BED,
        wake_time=WAKE,
        quality=4,
        note="woke up for fajr",
    ),
    "health_logs": lambda row_id: health_payload(
        row_id,
        updated_at=BASE_TIME,
        water_ml=1500,
        steps=8000,
        workout_min=30,
        calories=2100,
        weight_kg=72.5,
        note="knee felt better",
    ),
    "family_logs": lambda row_id: family_payload(
        row_id,
        updated_at=BASE_TIME,
        minutes=90,
        activities=["meal", "walk"],
        note="dinner with my parents",
    ),
}


def _change(entity: str, payload: dict[str, Any]) -> dict[str, Any]:
    return {
        "client_seq": 1,
        "entity": entity,
        "row_id": payload["id"],
        "op": "upsert",
        "base_version": 0,
        "payload": payload,
    }


# --- registration / round trip ----------------------------------------------------


async def test_all_wellbeing_entities_appear_in_limits(two_clients) -> None:
    alice, _ = two_clients
    body = (await alice.http.get("/sync/limits", headers=alice.headers)).json()
    by_name = {entry["name"]: entry for entry in body["entities"]}
    for name in BUILDERS:
        assert by_name[name]["natural_key"] == ["user_id", "ref_id", "date"]
    assert by_name["family_logs"]["adr_rules"] == [25, 14]


@pytest.mark.parametrize("entity_name", sorted(BUILDERS))
async def test_a_wellbeing_row_round_trips_to_a_second_device_unchanged(
    two_clients, entity_name: str
) -> None:
    alice, bob = two_clients
    row_id = str(uuid.uuid4())
    payload = BUILDERS[entity_name](row_id)
    alice.stage(entity_name, payload)
    result = (await alice.push()).json()["results"][0]
    assert result["status"] == "applied", result

    await bob.pull_all()
    pulled = bob.rows[(entity_name, row_id)]
    for key, value in payload.items():
        if key == "server_version":
            continue
        assert pulled[key] == value, key  # the note comes back as plaintext
    assert pulled["server_version"] == result["server_version"]


async def test_a_sleep_row_whose_duration_disagrees_with_its_window_is_schema_invalid(
    two_clients,
) -> None:
    alice, _ = two_clients
    payload = BUILDERS["sleep_logs"](str(uuid.uuid4()))
    payload["duration_min"] += 1
    result = (await alice.push(changes=[_change("sleep_logs", payload)])).json()["results"][0]
    assert (result["status"], result["reason"]) == ("rejected", "schema_invalid")


@pytest.mark.parametrize(
    "entity_name,field", [("mood_logs", "tags"), ("family_logs", "activities")]
)
async def test_33_slugs_are_schema_invalid_and_32_are_applied(
    two_clients, entity_name: str, field: str
) -> None:
    alice, _ = two_clients
    too_many = BUILDERS[entity_name](str(uuid.uuid4())) | {
        field: [f"item_{i:02d}" for i in range(33)]
    }
    result = (await alice.push(changes=[_change(entity_name, too_many)])).json()["results"][0]
    assert (result["status"], result["reason"]) == ("rejected", "schema_invalid")

    at_limit = BUILDERS[entity_name](str(uuid.uuid4())) | {
        field: [f"item_{i:02d}" for i in range(32)]
    }
    result = (await alice.push(changes=[_change(entity_name, at_limit)])).json()["results"][0]
    assert result["status"] == "applied", result


async def test_rule_11_a_tag_union_over_the_limit_is_capped_and_still_valid(two_clients) -> None:
    from app.modules.mood.sync_entities import MoodLogSyncRow

    alice, bob = two_clients
    row_id = str(uuid.uuid4())
    alice.stage("mood_logs", mood_payload(row_id, updated_at=BASE_TIME, tags=["start"]))
    await alice.sync()
    await bob.pull_all()

    # Alice fills the list at T+5 ("start" is cut: her 32 tags win the cap).
    alice_tags = [f"alice_{i:02d}" for i in range(32)]
    full = dict(alice.rows[("mood_logs", row_id)])
    full.update(tags=alice_tags, updated_at=wire_time(BASE_TIME + timedelta(minutes=5)))
    alice.stage("mood_logs", full)
    await alice.sync()
    assert alice.rows[("mood_logs", row_id)]["tags"] == alice_tags

    # Bob, still on ["start"], writes 20 different tags at T+10: a 52-item union.
    bob_tags = [f"bob_{i:02d}" for i in range(19, -1, -1)]
    edit = dict(bob.rows[("mood_logs", row_id)])
    edit.update(tags=bob_tags, updated_at=wire_time(BASE_TIME + timedelta(minutes=10)))
    bob.stage("mood_logs", edit)
    result = (await bob.push()).json()["results"][0]

    # Uncapped, this merge could not re-validate and the change was rejected.
    assert result["status"] == "conflict", result
    # Survivors: all of Bob's (the winner), then Alice's first 12 in sorted
    # order; returned sorted like any union.
    assert result["server_row"]["tags"] == sorted(bob_tags + alice_tags[:12])
    MoodLogSyncRow.model_validate(result["server_row"])

    await alice.pull_all()
    await bob.pull_all()
    assert alice.snapshot() == bob.snapshot()

    # The capped row can be pushed back unchanged by either device.
    again = dict(alice.rows[("mood_logs", row_id)])
    again.update(score=5, updated_at=wire_time(BASE_TIME + timedelta(minutes=15)))
    alice.stage("mood_logs", again)
    assert (await alice.push()).json()["results"][0]["status"] == "applied"


# --- rule 12: sleep_logs ------------------------------------------------------------


async def test_rule_12_sleep_quality_note_and_window_follow_the_last_writer(two_clients) -> None:
    alice, bob = two_clients
    row_id = str(uuid.uuid4())
    alice.stage(
        "sleep_logs",
        sleep_payload(
            row_id, updated_at=BASE_TIME, bed_time=BED, wake_time=WAKE, quality=3, note="ok"
        ),
    )
    await alice.sync()
    await bob.pull_all()

    # Bob corrects the window and rates the night at T+5.
    new_bed = BED - timedelta(minutes=45)  # 22:15Z
    new_wake = WAKE - timedelta(minutes=45)  # 05:45Z
    corrected = dict(bob.rows[("sleep_logs", row_id)])
    corrected.update(
        bed_time=wire_time(new_bed),
        wake_time=wire_time(new_wake),
        duration_min=450,
        quality=5,
        note="slept early",
        updated_at=wire_time(BASE_TIME + timedelta(minutes=5)),
    )
    bob.stage("sleep_logs", corrected)
    await bob.sync()

    # Alice's older (T+2) edit arrives afterwards and loses on every LWW field.
    stale = dict(alice.rows[("sleep_logs", row_id)])
    stale.update(quality=1, note="restless", updated_at=wire_time(BASE_TIME + timedelta(minutes=2)))
    alice.stage("sleep_logs", stale)
    result = (await alice.push()).json()["results"][0]

    assert result["status"] == "conflict"
    server_row = result["server_row"]
    assert (server_row["quality"], server_row["note"]) == (5, "slept early")
    assert (server_row["bed_time"], server_row["wake_time"], server_row["duration_min"]) == (
        wire_time(new_bed),
        wire_time(new_wake),
        450,
    )

    await alice.pull_all()
    await bob.pull_all()
    assert alice.snapshot() == bob.snapshot()


# --- rule 13: health_logs -----------------------------------------------------------


async def test_rule_13_health_additive_fields_survive_a_stale_device(two_clients) -> None:
    alice, bob = two_clients
    row_id = str(uuid.uuid4())
    alice.stage(
        "health_logs",
        health_payload(
            row_id, updated_at=BASE_TIME, water_ml=250, steps=1000, weight_kg=80.0, note="morning"
        ),
    )
    await alice.sync()
    await bob.pull_all()

    # Alice logs more water and a workout at T+5.
    more = dict(alice.rows[("health_logs", row_id)])
    more.update(
        water_ml=1500, workout_min=45, updated_at=wire_time(BASE_TIME + timedelta(minutes=5))
    )
    alice.stage("health_logs", more)
    await alice.sync()

    # Bob never saw that: at T+10 he adds steps and a weight to his stale copy,
    # which still says 250 ml and no workout.
    stale = dict(bob.rows[("health_logs", row_id)])
    stale.update(
        steps=9000,
        weight_kg=78.5,
        note="evening",
        updated_at=wire_time(BASE_TIME + timedelta(minutes=10)),
    )
    bob.stage("health_logs", stale)
    result = (await bob.push()).json()["results"][0]

    assert result["status"] == "conflict"
    server_row = result["server_row"]
    assert server_row["water_ml"] == 1500  # max-wins: never shrinks back to 250
    assert server_row["workout_min"] == 45  # max-wins: null never erases a value
    assert server_row["steps"] == 9000
    assert server_row["weight_kg"] == 78.5  # LWW, not max (80.0 lost)
    assert server_row["note"] == "evening"  # LWW

    await alice.pull_all()
    await bob.pull_all()
    assert alice.snapshot() == bob.snapshot()


# --- rule 14: natural-key collision ------------------------------------------------


async def test_rule_14_mood_logs_same_day_on_two_devices_merge_into_the_older_row(
    two_clients,
) -> None:
    alice, bob = two_clients
    older_id = str(uuid.uuid4())
    newer_id = str(uuid.uuid4())

    alice.stage(
        "mood_logs",
        mood_payload(
            older_id,
            updated_at=BASE_TIME,
            created_at=BASE_TIME,
            score=2,
            tags=["tired"],
            note="long day",
        ),
    )
    await alice.sync()

    # Bob was offline and never saw Alice's entry: he minted his own id for
    # the same (user, ref_id=null, date).
    later = BASE_TIME + timedelta(minutes=10)
    bob.stage(
        "mood_logs",
        mood_payload(
            newer_id,
            updated_at=later,
            created_at=later,
            score=4,
            tags=["grateful", "calm"],
            note="better after isha",
        ),
    )
    result = (await bob.push()).json()["results"][0]

    assert result["status"] == "conflict"
    server_row = result["server_row"]
    assert server_row["id"] == older_id  # smaller created_at survives
    assert server_row["created_at"] == wire_time(BASE_TIME)
    assert server_row["score"] == 4  # LWW: Bob wrote last
    assert server_row["tags"] == ["calm", "grateful", "tired"]  # set union
    assert server_row["note"] == "better after isha"

    await alice.pull_all()
    await bob.pull_all()
    tombstone = alice.rows[("mood_logs", newer_id)]
    assert tombstone["deleted_at"] is not None
    assert tombstone["merged_into"] == older_id
    assert [row["id"] for row in alice.live("mood_logs")] == [older_id]
    assert alice.live("mood_logs") == bob.live("mood_logs")


async def test_rule_14_a_null_and_an_empty_ref_id_are_the_same_natural_key(two_clients) -> None:
    alice, bob = two_clients
    first_id = str(uuid.uuid4())
    alice.stage(
        "family_logs",
        family_payload(first_id, updated_at=BASE_TIME, minutes=20, activities=["meal"]),
    )
    await alice.sync()

    second = family_payload(
        str(uuid.uuid4()),
        updated_at=BASE_TIME + timedelta(minutes=1),
        minutes=50,
        activities=["walk"],
    )
    second["ref_id"] = ""
    bob.stage("family_logs", second)
    result = (await bob.push()).json()["results"][0]

    assert result["status"] == "conflict"
    assert result["server_row"]["id"] == first_id
    assert result["server_row"]["minutes"] == 50
    assert result["server_row"]["activities"] == ["meal", "walk"]


# --- rule 25: family_logs -----------------------------------------------------------


async def test_rule_25_family_minutes_max_wins_and_activities_union_across_devices(
    two_clients,
) -> None:
    alice, bob = two_clients
    row_id = str(uuid.uuid4())
    alice.stage(
        "family_logs", family_payload(row_id, updated_at=BASE_TIME, minutes=30, activities=["meal"])
    )
    await alice.sync()
    await bob.pull_all()

    # Alice records a longer evening at T+5.
    evening = dict(alice.rows[("family_logs", row_id)])
    evening.update(
        minutes=120,
        activities=["meal", "quran"],
        note="read together",
        updated_at=wire_time(BASE_TIME + timedelta(minutes=5)),
    )
    alice.stage("family_logs", evening)
    await alice.sync()

    # Bob, still on the 30-minute copy, adds a walk at T+10.
    walk = dict(bob.rows[("family_logs", row_id)])
    walk.update(
        minutes=60,
        activities=["meal", "walk"],
        note="walk after asr",
        updated_at=wire_time(BASE_TIME + timedelta(minutes=10)),
    )
    bob.stage("family_logs", walk)
    result = (await bob.push()).json()["results"][0]

    assert result["status"] == "conflict"
    server_row = result["server_row"]
    assert server_row["minutes"] == 120  # additive: max-wins
    assert server_row["activities"] == ["meal", "quran", "walk"]  # set union
    assert server_row["note"] == "walk after asr"  # LWW: Bob wrote last

    await alice.pull_all()
    await bob.pull_all()
    assert alice.snapshot() == bob.snapshot()

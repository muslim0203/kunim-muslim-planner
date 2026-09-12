"""End-to-end `/sync/push` + `/sync/pull` coverage for the Phase-2 entities.

Uses the same two-simulated-device harness as `tests/test_sync_harness.py`
and `tests/test_sync_entity_contract.py`: `SimClient` applies only what the
server answers, with no merge logic of its own, so a round trip here proves
the server's merge -- not a client-side reimplementation of it -- actually
produces the ADR's answer over HTTP.

`tests/test_phase2_entities.py` covers the same rules at the unit level
(schema/model/policy shape); this module never calls `merge.py` directly.
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


# --- payload builders, one per Phase-2 entity ---------------------------------


def category_payload(
    row_id: str, *, updated_at: datetime, name: str = "Work", color: str | None = "#3366FF"
) -> dict[str, Any]:
    return {
        "id": row_id,
        "created_at": wire_time(updated_at),
        "updated_at": wire_time(updated_at),
        "deleted_at": None,
        "server_version": 0,
        "name": name,
        "color": color,
    }


def task_payload(
    row_id: str,
    *,
    updated_at: datetime,
    title: str = "Buy groceries",
    priority: str = "medium",
    completed_at: datetime | None = None,
    category_id: str | None = None,
    server_version: int = 0,
) -> dict[str, Any]:
    return {
        "id": row_id,
        "created_at": wire_time(updated_at),
        "updated_at": wire_time(updated_at),
        "deleted_at": None,
        "server_version": server_version,
        "title": title,
        "notes": None,
        "priority": priority,
        "due_date": None,
        "category_id": category_id,
        "completed_at": wire_time(completed_at) if completed_at else None,
    }


def habit_payload(
    row_id: str, *, updated_at: datetime, title: str = "Read Qur'an", target: int = 1
) -> dict[str, Any]:
    return {
        "id": row_id,
        "created_at": wire_time(updated_at),
        "updated_at": wire_time(updated_at),
        "deleted_at": None,
        "server_version": 0,
        "title": title,
        "schedule": {"type": "daily"},
        "target": target,
    }


def habit_log_payload(
    row_id: str,
    *,
    habit_id: str,
    updated_at: datetime,
    date_str: str = "2026-09-12",
    count: int = 1,
    value: float = 0.0,
    note: str | None = None,
    server_version: int = 0,
) -> dict[str, Any]:
    return {
        "id": row_id,
        "created_at": wire_time(updated_at),
        "updated_at": wire_time(updated_at),
        "deleted_at": None,
        "server_version": server_version,
        "habit_id": habit_id,
        "date": date_str,
        "count": count,
        "value": value,
        "note": note,
    }


def goal_payload(
    row_id: str,
    *,
    updated_at: datetime,
    title: str = "Memorize Juz Amma",
    progress_percent: int = 10,
) -> dict[str, Any]:
    return {
        "id": row_id,
        "created_at": wire_time(updated_at),
        "updated_at": wire_time(updated_at),
        "deleted_at": None,
        "server_version": 0,
        "title": title,
        "target_date": "2026-12-31",
        "progress_percent": progress_percent,
    }


def milestone_payload(
    row_id: str,
    *,
    goal_id: str,
    updated_at: datetime,
    title: str = "First 5 surahs",
    progress_percent: int = 0,
) -> dict[str, Any]:
    return {
        "id": row_id,
        "created_at": wire_time(updated_at),
        "updated_at": wire_time(updated_at),
        "deleted_at": None,
        "server_version": 0,
        "goal_id": goal_id,
        "title": title,
        "target_date": None,
        "progress_percent": progress_percent,
    }


def calendar_event_payload(
    row_id: str,
    *,
    updated_at: datetime,
    title: str = "Jumu'ah",
    start_at: datetime = BASE_TIME,
    end_at: datetime | None = None,
    rrule: str | None = "FREQ=WEEKLY;BYDAY=FR",
) -> dict[str, Any]:
    return {
        "id": row_id,
        "created_at": wire_time(updated_at),
        "updated_at": wire_time(updated_at),
        "deleted_at": None,
        "server_version": 0,
        "title": title,
        "start_at": wire_time(start_at),
        "end_at": wire_time(end_at or (start_at + timedelta(hours=1))),
        "rrule": rrule,
    }


PAYLOAD_BUILDERS = {
    "task_categories": lambda row_id: category_payload(row_id, updated_at=BASE_TIME),
    "tasks": lambda row_id: task_payload(row_id, updated_at=BASE_TIME),
    "habits": lambda row_id: habit_payload(row_id, updated_at=BASE_TIME),
    "goals": lambda row_id: goal_payload(row_id, updated_at=BASE_TIME),
    "calendar_events": lambda row_id: calendar_event_payload(row_id, updated_at=BASE_TIME),
}


# --- registration / limits -----------------------------------------------------


async def test_all_phase2_entities_appear_in_limits(two_clients) -> None:
    alice, _ = two_clients
    body = (await alice.http.get("/sync/limits", headers=alice.headers)).json()
    names = {entry["name"] for entry in body["entities"]}
    assert {
        "tasks",
        "task_categories",
        "habits",
        "habit_logs",
        "goals",
        "milestones",
        "calendar_events",
    } <= names


@pytest.mark.parametrize("entity_name", sorted(PAYLOAD_BUILDERS))
async def test_a_pushed_row_of_every_phase2_entity_round_trips_to_a_second_device(
    two_clients, entity_name: str
) -> None:
    alice, bob = two_clients
    row_id = str(uuid.uuid4())
    alice.stage(entity_name, PAYLOAD_BUILDERS[entity_name](row_id))
    result = (await alice.push()).json()["results"][0]
    assert result["status"] == "applied", result

    await bob.pull_all()
    assert (entity_name, row_id) in bob.rows
    assert bob.rows[(entity_name, row_id)]["id"] == row_id


async def test_habit_log_round_trips_with_its_habit_id_natural_key(two_clients) -> None:
    alice, bob = two_clients
    habit_id = str(uuid.uuid4())
    alice.stage("habits", habit_payload(habit_id, updated_at=BASE_TIME))
    await alice.sync()

    log_id = str(uuid.uuid4())
    alice.stage(
        "habit_logs",
        habit_log_payload(log_id, habit_id=habit_id, updated_at=BASE_TIME, count=2),
    )
    result = (await alice.push()).json()["results"][0]
    assert result["status"] == "applied"

    await bob.pull_all()
    assert bob.rows[("habit_logs", log_id)]["habit_id"] == habit_id
    assert bob.rows[("habit_logs", log_id)]["count"] == 2


# --- rule 8: tasks.completed_at is max_wins ------------------------------------


async def test_rule_08_tasks_completed_at_survives_a_later_title_only_edit(two_clients) -> None:
    """Two devices, one completes a task and the other edits its title later:
    completion must survive and never be reverted, even though the second
    write is chronologically the winner for every other field."""
    alice, bob = two_clients
    row_id = str(uuid.uuid4())
    alice.stage("tasks", task_payload(row_id, updated_at=BASE_TIME, title="Buy milk"))
    await alice.sync()
    await bob.pull_all()

    # Alice completes the task at T+10.
    done = dict(alice.rows[("tasks", row_id)])
    done["completed_at"] = wire_time(BASE_TIME + timedelta(minutes=10))
    done["updated_at"] = wire_time(BASE_TIME + timedelta(minutes=10))
    alice.stage("tasks", done)
    await alice.sync()

    # Bob, later still and without having seen the completion, renames the
    # task and (as a stale client would) pushes `completed_at: null`.
    stale = dict(bob.rows[("tasks", row_id)])
    stale["title"] = "Buy milk and eggs"
    stale["completed_at"] = None
    stale["updated_at"] = wire_time(BASE_TIME + timedelta(minutes=20))
    bob.stage("tasks", stale)
    result = (await bob.push()).json()["results"][0]

    assert result["status"] == "conflict"
    assert result["server_row"]["title"] == "Buy milk and eggs"  # LWW field followed Bob
    assert result["server_row"]["completed_at"] is not None  # max-wins held: never reverted
    assert result["server_row"]["completed_at"] == wire_time(BASE_TIME + timedelta(minutes=10))

    await alice.pull_all()
    await bob.pull_all()
    assert alice.snapshot() == bob.snapshot()


async def test_rule_08_a_push_that_would_clear_completed_at_does_not_clear_it(two_clients) -> None:
    """Even a same-second, single-device push cannot un-complete a task by
    sending `completed_at: null` for an already-completed row: `max_wins`
    treats `None` as the smallest value, so the completed timestamp wins
    regardless of `updated_at` ordering between the two pushes."""
    alice, _ = two_clients
    row_id = str(uuid.uuid4())
    alice.stage("tasks", task_payload(row_id, updated_at=BASE_TIME))
    await alice.sync()

    completed_at = BASE_TIME + timedelta(minutes=5)
    done = dict(alice.rows[("tasks", row_id)])
    done["completed_at"] = wire_time(completed_at)
    done["updated_at"] = wire_time(completed_at)
    alice.stage("tasks", done)
    await alice.sync()

    later_but_clears = dict(alice.rows[("tasks", row_id)])
    later_but_clears["completed_at"] = None
    later_but_clears["updated_at"] = wire_time(completed_at + timedelta(minutes=1))
    alice.stage("tasks", later_but_clears)
    result = (await alice.push()).json()["results"][0]

    # Every other field followed the later write (rule 1: client wins), but
    # `completed_at` itself is max-wins and `None` never beats a real value,
    # so the merge disagrees with what was pushed -- a `conflict`, not a
    # silent `applied`, with the surviving value in `server_row`.
    assert result["status"] == "conflict"
    assert result["server_row"]["completed_at"] == wire_time(completed_at)


async def test_pushing_the_completed_boolean_key_is_rejected_schema_invalid(two_clients) -> None:
    alice, _ = two_clients
    row_id = str(uuid.uuid4())
    payload = task_payload(row_id, updated_at=BASE_TIME)
    payload["completed"] = True  # not a real column; must not be accepted
    change = {
        "client_seq": 1,
        "entity": "tasks",
        "row_id": row_id,
        "op": "upsert",
        "base_version": 0,
        "payload": payload,
    }
    result = (await alice.push(changes=[change])).json()["results"][0]
    assert (result["status"], result["reason"]) == ("rejected", "schema_invalid")


# --- rule 9: habit_logs additive fields, natural key ---------------------------


async def test_rule_09_habit_logs_same_day_different_counts_merge_to_one_row(
    two_clients,
) -> None:
    """Two devices log the same habit on the same date with different
    counts: one row survives, `count` is the max, `note` is the last
    writer's (LWW)."""
    alice, bob = two_clients
    habit_id = str(uuid.uuid4())
    alice.stage("habits", habit_payload(habit_id, updated_at=BASE_TIME))
    await alice.sync()
    await bob.pull_all()

    alice_log_id = str(uuid.uuid4())
    alice.stage(
        "habit_logs",
        habit_log_payload(
            alice_log_id,
            habit_id=habit_id,
            updated_at=BASE_TIME + timedelta(minutes=1),
            count=1,
            note="morning",
        ),
    )
    await alice.sync()

    # Bob independently minted a *different* id for the same
    # (user_id, habit_id, date) natural key -- exactly the offline scenario
    # ADR rule 14 exists for.
    bob_log_id = str(uuid.uuid4())
    bob.stage(
        "habit_logs",
        habit_log_payload(
            bob_log_id,
            habit_id=habit_id,
            updated_at=BASE_TIME + timedelta(minutes=5),
            count=3,
            note="evening",
        ),
    )
    result = (await bob.push()).json()["results"][0]

    assert result["status"] == "conflict"
    assert result["server_row"]["count"] == 3  # max(1, 3)
    assert result["server_row"]["note"] == "evening"  # last writer (LWW)

    await alice.pull_all()
    await bob.pull_all()
    live_logs = [row for row in alice.live("habit_logs") if row["habit_id"] == habit_id]
    assert len(live_logs) == 1  # the two ids merged into one surviving row
    assert alice.snapshot() == bob.snapshot()


async def test_rule_09_a_lower_count_pushed_later_never_shrinks_the_stored_total(
    two_clients,
) -> None:
    alice, bob = two_clients
    habit_id = str(uuid.uuid4())
    alice.stage("habits", habit_payload(habit_id, updated_at=BASE_TIME))
    await alice.sync()
    await bob.pull_all()

    log_id = str(uuid.uuid4())
    alice.stage(
        "habit_logs",
        habit_log_payload(log_id, habit_id=habit_id, updated_at=BASE_TIME, count=5),
    )
    await alice.sync()
    await bob.pull_all()

    lower = dict(bob.rows[("habit_logs", log_id)])
    lower["count"] = 1
    lower["updated_at"] = wire_time(BASE_TIME + timedelta(minutes=5))
    bob.stage("habit_logs", lower)
    result = (await bob.push()).json()["results"][0]

    assert result["status"] == "conflict"
    assert result["server_row"]["count"] == 5


# --- rule 14: natural-key collision on a real, registered entity --------------


async def test_rule_14_habit_logs_natural_key_collision_older_created_at_survives(
    two_clients,
) -> None:
    alice, bob = two_clients
    habit_id = str(uuid.uuid4())
    alice.stage("habits", habit_payload(habit_id, updated_at=BASE_TIME))
    await alice.sync()
    await bob.pull_all()

    older_id = str(uuid.uuid4())
    newer_id = str(uuid.uuid4())
    alice.stage(
        "habit_logs",
        {
            **habit_log_payload(older_id, habit_id=habit_id, updated_at=BASE_TIME, count=1),
            "created_at": wire_time(BASE_TIME),
        },
    )
    await alice.sync()

    bob.stage(
        "habit_logs",
        {
            **habit_log_payload(
                newer_id,
                habit_id=habit_id,
                updated_at=BASE_TIME + timedelta(minutes=2),
                count=9,
            ),
            "created_at": wire_time(BASE_TIME + timedelta(minutes=2)),
        },
    )
    result = (await bob.push()).json()["results"][0]

    assert result["status"] == "conflict"
    assert result["server_row"]["id"] == older_id
    assert result["server_row"]["count"] == 9

    await alice.pull_all()
    tombstone = alice.rows[("habit_logs", newer_id)]
    assert tombstone["deleted_at"] is not None
    assert tombstone["merged_into"] == older_id


# --- rule 18: goals / milestones progress can go backwards ---------------------


async def test_rule_18_goal_progress_percent_genuinely_decreases(two_clients) -> None:
    alice, bob = two_clients
    row_id = str(uuid.uuid4())
    alice.stage("goals", goal_payload(row_id, updated_at=BASE_TIME, progress_percent=80))
    await alice.sync()
    await bob.pull_all()
    assert bob.rows[("goals", row_id)]["progress_percent"] == 80

    lowered = dict(bob.rows[("goals", row_id)])
    lowered["progress_percent"] = 30
    lowered["updated_at"] = wire_time(BASE_TIME + timedelta(minutes=5))
    bob.stage("goals", lowered)
    result = (await bob.push()).json()["results"][0]
    assert result["status"] == "applied"

    await alice.pull_all()
    assert alice.rows[("goals", row_id)]["progress_percent"] == 30


async def test_rule_18_milestone_progress_percent_genuinely_decreases(two_clients) -> None:
    alice, _ = two_clients
    goal_id = str(uuid.uuid4())
    alice.stage("goals", goal_payload(goal_id, updated_at=BASE_TIME))
    await alice.sync()

    milestone_id = str(uuid.uuid4())
    alice.stage(
        "milestones",
        milestone_payload(
            milestone_id, goal_id=goal_id, updated_at=BASE_TIME, progress_percent=100
        ),
    )
    await alice.sync()

    lowered = dict(alice.rows[("milestones", milestone_id)])
    lowered["progress_percent"] = 40
    lowered["updated_at"] = wire_time(BASE_TIME + timedelta(minutes=5))
    alice.stage("milestones", lowered)
    result = (await alice.push()).json()["results"][0]

    assert result["status"] == "applied"
    assert alice.rows[("milestones", milestone_id)]["progress_percent"] == 40


# --- rule 20: plain LWW + soft delete on the remaining tables -------------------


@pytest.mark.parametrize("entity_name", ["task_categories", "habits", "calendar_events"])
async def test_rule_20_a_stale_edit_conflicts_and_the_newer_write_wins(
    two_clients, entity_name: str
) -> None:
    alice, bob = two_clients
    row_id = str(uuid.uuid4())
    alice.stage(entity_name, PAYLOAD_BUILDERS[entity_name](row_id))
    await alice.sync()
    await bob.pull_all()

    # Bob writes at T+10 first...
    newer = dict(bob.rows[(entity_name, row_id)])
    field, value = _renameable_field(entity_name)
    newer[field] = value
    newer["updated_at"] = wire_time(BASE_TIME + timedelta(minutes=10))
    bob.stage(entity_name, newer)
    await bob.sync()

    # ...then Alice's older (T+5), stale write arrives and must lose.
    stale = dict(alice.rows[(entity_name, row_id)])
    stale[field] = "stale-value"
    stale["updated_at"] = wire_time(BASE_TIME + timedelta(minutes=5))
    alice.stage(entity_name, stale)
    result = (await alice.push()).json()["results"][0]

    assert result["status"] == "conflict"
    assert result["server_row"][field] == value


def _renameable_field(entity_name: str) -> tuple[str, str]:
    return {
        "task_categories": ("name", "Deep work"),
        "habits": ("title", "Night prayer"),
        "calendar_events": ("title", "Eid gathering"),
    }[entity_name]


# --- foreign_user (ADR rule 23) for a Phase-2 entity ---------------------------


async def test_foreign_user_in_a_phase2_payload_is_rejected(two_clients) -> None:
    alice, _ = two_clients
    row_id = str(uuid.uuid4())
    payload = task_payload(row_id, updated_at=BASE_TIME)
    payload["user_id"] = str(uuid.uuid4())  # somebody else's id
    change = {
        "client_seq": 1,
        "entity": "tasks",
        "row_id": row_id,
        "op": "upsert",
        "base_version": 0,
        "payload": payload,
    }
    result = (await alice.push(changes=[change])).json()["results"][0]
    assert (result["status"], result["reason"]) == ("rejected", "foreign_user")


async def test_foreign_user_in_a_habit_log_payload_is_rejected(two_clients) -> None:
    alice, _ = two_clients
    row_id = str(uuid.uuid4())
    payload = habit_log_payload(row_id, habit_id=str(uuid.uuid4()), updated_at=BASE_TIME)
    payload["user_id"] = str(uuid.uuid4())
    change = {
        "client_seq": 1,
        "entity": "habit_logs",
        "row_id": row_id,
        "op": "upsert",
        "base_version": 0,
        "payload": payload,
    }
    result = (await alice.push(changes=[change])).json()["results"][0]
    assert (result["status"], result["reason"]) == ("rejected", "foreign_user")


# --- loose references survive out-of-order / dangling pushes -------------------


async def test_a_task_can_reference_a_category_that_never_reaches_the_server(
    two_clients,
) -> None:
    """`category_id` is a loose reference (no FK): a dangling reference must
    still be `applied`, not crash the change."""
    alice, _ = two_clients
    dangling_category_id = str(uuid.uuid4())
    row_id = str(uuid.uuid4())
    alice.stage(
        "tasks",
        task_payload(row_id, updated_at=BASE_TIME, category_id=dangling_category_id),
    )
    result = (await alice.push()).json()["results"][0]
    assert result["status"] == "applied"

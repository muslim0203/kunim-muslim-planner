"""Wire-protocol behaviour of `/sync/*` -- ADR-0002 section 3 and section 4.

Limits, `batch_id` idempotency, SAVEPOINT isolation, the closed `rejected`
reason list, cursor semantics and `full_resync_required`.
"""

from __future__ import annotations

import uuid
from datetime import UTC, datetime, timedelta

import pytest
from sqlalchemy import select

from app.modules.sync import registry
from app.modules.sync.models import RowHistory, SyncBatch, SyncUserState
from app.modules.sync.registry import SyncDirection, SyncEntity
from app.modules.sync.schemas import MAX_CHANGES_PER_BATCH, MAX_PULL_LIMIT
from app.modules.sync.service import SyncService
from tests import test_sync_harness as harness

BASE_TIME = harness.BASE_TIME
preferences_payload = harness.preferences_payload


# Fixtures are re-exported by assignment, not imported: pytest discovers them
# either way, but a test whose parameter shares a name with an import trips
# ruff's F811.
client = harness.client
session_factory = harness.session_factory
two_clients = harness.two_clients


@pytest.fixture
def readonly_entity():
    """A pull-only entity, so ADR rule 24 can be exercised.

    `content` / Qur'an text / prayer presets are Phase-3 tables; a pull-only
    push is rejected before the model is ever touched, so reusing the
    preferences model here is harmless and keeps this test free of a fake
    table.
    """
    from app.modules.preferences.models import Preferences
    from app.modules.preferences.sync_entities import PreferencesSyncRow

    entity = SyncEntity(
        name="content",
        model=Preferences,
        schema=PreferencesSyncRow,
        direction=SyncDirection.pull_only,
    )
    registry.register_entity(entity)
    try:
        yield entity
    finally:
        registry.unregister_entity("content")


# --- authentication ----------------------------------------------------------


async def test_push_requires_authentication(client) -> None:
    response = await client.post(
        "/sync/push", json={"device_id": "d", "batch_id": str(uuid.uuid4()), "changes": []}
    )
    assert response.status_code == 401


async def test_pull_requires_authentication(client) -> None:
    assert (await client.get("/sync/pull?cursor=0")).status_code == 401


async def test_limits_requires_authentication(client) -> None:
    assert (await client.get("/sync/limits")).status_code == 401


# --- GET /sync/limits --------------------------------------------------------


async def test_limits_publishes_the_adr_caps_and_entity_list(two_clients) -> None:
    alice, _ = two_clients
    body = (await alice.http.get("/sync/limits", headers=alice.headers)).json()

    assert body["max_changes_per_batch"] == MAX_CHANGES_PER_BATCH == 200
    assert body["max_pull_limit"] == MAX_PULL_LIMIT == 500
    assert body["max_payload_bytes"] == 64 * 1024
    assert body["max_body_bytes"] == 4 * 1024 * 1024
    assert body["tombstone_retention_days"] == 90
    assert body["row_history_retention_days"] == 30
    assert body["batch_retention_days"] == 7
    # The closed `rejected` reason list, so clients can assert on it too.
    assert set(body["rejected_reasons"]) == {
        "updated_at_in_future",
        "schema_invalid",
        "unknown_entity",
        "readonly_entity",
        "foreign_user",
        "payload_too_large",
    }
    names = {entity["name"] for entity in body["entities"]}
    assert "preferences" in names


# --- batch limits ------------------------------------------------------------


async def test_batch_of_201_changes_is_rejected_with_400_batch_too_large(two_clients) -> None:
    alice, _ = two_clients
    changes = [
        {
            "client_seq": index,
            "entity": "preferences",
            "row_id": str(uuid.uuid4()),
            "op": "upsert",
            "base_version": 0,
            "payload": preferences_payload(str(uuid.uuid4()), updated_at=BASE_TIME),
        }
        for index in range(MAX_CHANGES_PER_BATCH + 1)
    ]
    response = await alice.push(changes=changes)
    assert response.status_code == 400
    assert response.json()["error"]["message"] == "batch_too_large"


async def test_batch_of_exactly_200_changes_is_accepted(two_clients) -> None:
    alice, _ = two_clients
    changes = [
        {
            "client_seq": index,
            "entity": "not_a_real_entity",
            "row_id": str(uuid.uuid4()),
            "op": "upsert",
            "base_version": 0,
            "payload": {"id": str(uuid.uuid4())},
        }
        for index in range(MAX_CHANGES_PER_BATCH)
    ]
    response = await alice.push(changes=changes)
    assert response.status_code == 200
    assert len(response.json()["results"]) == MAX_CHANGES_PER_BATCH


async def test_payload_over_64kb_is_rejected_payload_too_large(two_clients) -> None:
    alice, _ = two_clients
    payload = preferences_payload(str(uuid.uuid4()), updated_at=BASE_TIME)
    payload["prayer_settings"]["location"]["city"] = "x" * 70_000
    change = {
        "client_seq": 1,
        "entity": "preferences",
        "row_id": payload["id"],
        "op": "upsert",
        "base_version": 0,
        "payload": payload,
    }
    result = (await alice.push(changes=[change])).json()["results"][0]
    assert result["status"] == "rejected"
    assert result["reason"] == "payload_too_large"


# --- idempotency (ADR section 3) --------------------------------------------


async def test_replaying_a_batch_id_returns_the_stored_response_without_reapplying(
    two_clients, session_factory
) -> None:
    alice, _ = two_clients
    batch_id = str(uuid.uuid4())
    row_id = str(uuid.uuid4())
    alice.stage("preferences", preferences_payload(row_id, updated_at=BASE_TIME))

    first = await alice.push(batch_id=batch_id, changes=alice.outbox)
    assert first.status_code == 200

    second = await alice.push(batch_id=batch_id, changes=alice.outbox)
    assert second.status_code == 200
    assert second.json() == first.json()

    # Nothing was applied a second time: one history entry, one version burnt.
    async with session_factory() as session:
        history = (await session.execute(select(RowHistory))).scalars().all()
        assert len(history) == 1
        state = (await session.execute(select(SyncUserState))).scalar_one()
        assert state.last_version == 1
        batches = (await session.execute(select(SyncBatch))).scalars().all()
        assert len(batches) == 1


async def test_same_batch_id_with_a_different_payload_is_409_batch_id_reused(
    two_clients,
) -> None:
    alice, _ = two_clients
    batch_id = str(uuid.uuid4())
    first_change = {
        "client_seq": 1,
        "entity": "preferences",
        "row_id": str(uuid.uuid4()),
        "op": "upsert",
        "base_version": 0,
        "payload": preferences_payload(str(uuid.uuid4()), updated_at=BASE_TIME),
    }
    first_change["payload"]["id"] = first_change["row_id"]
    assert (await alice.push(batch_id=batch_id, changes=[first_change])).status_code == 200

    other = dict(first_change)
    other["payload"] = dict(first_change["payload"])
    other["payload"]["ui"] = {"theme": "dark", "first_day_of_week": 1}
    response = await alice.push(batch_id=batch_id, changes=[other])
    assert response.status_code == 409
    assert response.json()["error"]["message"] == "batch_id_reused"


# --- SAVEPOINT isolation (ADR section 3 "Tranzaksiya chegarasi") ------------


async def test_one_rejected_change_does_not_roll_back_its_siblings(
    two_clients, session_factory
) -> None:
    alice, _ = two_clients
    good_before = str(uuid.uuid4())
    good_after = str(uuid.uuid4())
    changes = [
        {
            "client_seq": 1,
            "entity": "preferences",
            "row_id": good_before,
            "op": "upsert",
            "base_version": 0,
            "payload": preferences_payload(good_before, updated_at=BASE_TIME),
        },
        {
            "client_seq": 2,
            "entity": "preferences",
            "row_id": str(uuid.uuid4()),
            "op": "upsert",
            "base_version": 0,
            # Invalid: `ui.theme` is not a member of the Theme enum.
            "payload": {
                **preferences_payload(str(uuid.uuid4()), updated_at=BASE_TIME),
                "ui": {"theme": "neon", "first_day_of_week": 1},
            },
        },
        {
            "client_seq": 3,
            "entity": "preferences",
            "row_id": good_after,
            "op": "upsert",
            "base_version": 0,
            "payload": preferences_payload(good_after, updated_at=BASE_TIME + timedelta(minutes=1)),
        },
    ]
    changes[1]["payload"]["id"] = changes[1]["row_id"]

    body = (await alice.push(changes=changes)).json()
    statuses = [result["status"] for result in body["results"]]
    # The middle change is rejected; its siblings on both sides survive.
    assert statuses[0] == "applied"
    assert statuses[1] == "rejected"
    assert body["results"][1]["reason"] == "schema_invalid"
    # The third is a natural-key collision with the first (one preferences row
    # per user), which is a `conflict` -- but it was still applied, which is
    # what proves the savepoint of change 2 did not take it down.
    assert statuses[2] in ("applied", "conflict")

    async with session_factory() as session:
        history = (await session.execute(select(RowHistory))).scalars().all()
        assert {str(entry.row_id) for entry in history} >= {good_before, good_after}


# --- the closed `rejected` reason list --------------------------------------


async def test_unknown_entity_is_rejected(two_clients) -> None:
    alice, _ = two_clients
    change = {
        "client_seq": 1,
        "entity": "definitely_not_registered",
        "row_id": str(uuid.uuid4()),
        "op": "upsert",
        "base_version": 0,
        "payload": {"id": str(uuid.uuid4())},
    }
    result = (await alice.push(changes=[change])).json()["results"][0]
    assert (result["status"], result["reason"]) == ("rejected", "unknown_entity")


async def test_pull_only_entity_push_is_rejected_readonly_entity(
    two_clients, readonly_entity
) -> None:
    alice, _ = two_clients
    row_id = str(uuid.uuid4())
    change = {
        "client_seq": 1,
        "entity": "content",
        "row_id": row_id,
        "op": "upsert",
        "base_version": 0,
        "payload": preferences_payload(row_id, updated_at=BASE_TIME),
    }
    result = (await alice.push(changes=[change])).json()["results"][0]
    assert (result["status"], result["reason"]) == ("rejected", "readonly_entity")


async def test_pull_never_returns_a_non_bidirectional_entity(two_clients, readonly_entity) -> None:
    alice, _ = two_clients
    alice.stage("preferences", preferences_payload(str(uuid.uuid4()), updated_at=BASE_TIME))
    await alice.sync()
    body = (await alice.http.get("/sync/pull?cursor=0", headers=alice.headers)).json()
    assert {row["entity"] for row in body["rows"]} <= {"preferences"}


async def test_payload_for_another_user_is_rejected_foreign_user(two_clients) -> None:
    alice, _ = two_clients
    row_id = str(uuid.uuid4())
    payload = preferences_payload(row_id, updated_at=BASE_TIME)
    payload["user_id"] = str(uuid.uuid4())  # somebody else's id
    change = {
        "client_seq": 1,
        "entity": "preferences",
        "row_id": row_id,
        "op": "upsert",
        "base_version": 0,
        "payload": payload,
    }
    result = (await alice.push(changes=[change])).json()["results"][0]
    assert (result["status"], result["reason"]) == ("rejected", "foreign_user")


async def test_row_id_not_matching_payload_id_is_schema_invalid(two_clients) -> None:
    alice, _ = two_clients
    change = {
        "client_seq": 1,
        "entity": "preferences",
        "row_id": str(uuid.uuid4()),
        "op": "upsert",
        "base_version": 0,
        "payload": preferences_payload(str(uuid.uuid4()), updated_at=BASE_TIME),
    }
    result = (await alice.push(changes=[change])).json()["results"][0]
    assert (result["status"], result["reason"]) == ("rejected", "schema_invalid")


async def test_client_only_dirty_column_is_rejected(two_clients) -> None:
    """ADR section 1: `dirty` must never cross the wire."""
    alice, _ = two_clients
    row_id = str(uuid.uuid4())
    payload = preferences_payload(row_id, updated_at=BASE_TIME) | {"dirty": True}
    change = {
        "client_seq": 1,
        "entity": "preferences",
        "row_id": row_id,
        "op": "upsert",
        "base_version": 0,
        "payload": payload,
    }
    result = (await alice.push(changes=[change])).json()["results"][0]
    assert (result["status"], result["reason"]) == ("rejected", "schema_invalid")


async def test_updated_at_more_than_24h_in_the_future_is_rejected_and_restamped(
    two_clients,
) -> None:
    """ADR rule 6 plus the client action the ADR prescribes for it."""
    alice, _ = two_clients
    row_id = str(uuid.uuid4())
    far_future = datetime.now(UTC) + timedelta(hours=30)
    alice.stage("preferences", preferences_payload(row_id, updated_at=far_future))

    body = (await alice.push()).json()
    result = body["results"][0]
    assert (result["status"], result["reason"]) == ("rejected", "updated_at_in_future")
    # The harness re-stamped it and put it back in the outbox, per the ADR.
    assert len(alice.outbox) == 1

    retry = (await alice.push()).json()
    assert retry["results"][0]["status"] == "applied"


async def test_updated_at_just_inside_the_24h_window_is_accepted(two_clients) -> None:
    alice, _ = two_clients
    row_id = str(uuid.uuid4())
    near_future = datetime.now(UTC) + timedelta(hours=23, minutes=30)
    alice.stage("preferences", preferences_payload(row_id, updated_at=near_future))
    result = (await alice.push()).json()["results"][0]
    assert result["status"] == "applied"


# --- cursor semantics --------------------------------------------------------


async def test_pull_limit_larger_than_500_is_clamped_not_rejected(two_clients) -> None:
    alice, _ = two_clients
    response = await alice.http.get("/sync/pull?cursor=0&limit=5000", headers=alice.headers)
    assert response.status_code == 200


async def test_negative_cursor_is_400_invalid_cursor(two_clients) -> None:
    alice, _ = two_clients
    response = await alice.http.get("/sync/pull?cursor=-1", headers=alice.headers)
    assert response.status_code == 400
    assert response.json()["error"]["message"] == "invalid_cursor"


async def test_pull_paginates_by_server_version_without_gaps(two_clients) -> None:
    alice, bob = two_clients
    for index in range(5):
        alice.stage(
            "preferences",
            preferences_payload(
                str(uuid.uuid4()),
                created_at=BASE_TIME + timedelta(minutes=index),
                updated_at=BASE_TIME + timedelta(minutes=index),
            ),
        )
        await alice.push()

    seen: list[int] = []
    cursor = 0
    while True:
        body = (
            await bob.http.get(f"/sync/pull?cursor={cursor}&limit=2", headers=bob.headers)
        ).json()
        seen.extend(row["server_version"] for row in body["rows"])
        cursor = body["next_cursor"]
        if not body["has_more"]:
            break
    assert seen == sorted(seen)
    assert len(seen) == len(set(seen))


async def test_entities_filter_restricts_the_page(two_clients) -> None:
    alice, _ = two_clients
    alice.stage("preferences", preferences_payload(str(uuid.uuid4()), updated_at=BASE_TIME))
    await alice.push()
    body = (
        await alice.http.get("/sync/pull?cursor=0&entities=tasks", headers=alice.headers)
    ).json()
    assert body["rows"] == []


async def test_cursor_older_than_the_tombstone_window_forces_a_full_resync(
    two_clients, session_factory
) -> None:
    """ADR section 4: `cursor < purged_up_to_version` -> `full_resync_required`."""
    alice, bob = two_clients
    row_id = str(uuid.uuid4())
    alice.stage("preferences", preferences_payload(row_id, updated_at=BASE_TIME))
    await alice.sync()
    assert alice.cursor > 0

    async with session_factory() as session:
        state = (await session.execute(select(SyncUserState))).scalar_one()
        state.purged_up_to_version = alice.cursor + 10
        await session.commit()

    body = (await alice.pull()).json()
    assert body["full_resync_required"] is True
    assert body["rows"] == []
    # The client dropped its clean rows, kept the outbox, and reset the cursor.
    assert alice.cursor == 0

    # `cursor = 0` is a full load already and must never trigger a resync.
    fresh = (await bob.pull()).json()
    assert fresh["full_resync_required"] is False


async def test_full_resync_keeps_unpushed_dirty_rows(two_clients, session_factory) -> None:
    alice, _ = two_clients
    synced_id = str(uuid.uuid4())
    alice.stage("preferences", preferences_payload(synced_id, updated_at=BASE_TIME))
    await alice.sync()

    offline_id = str(uuid.uuid4())
    alice.stage("preferences", preferences_payload(offline_id, updated_at=BASE_TIME))

    async with session_factory() as session:
        state = (await session.execute(select(SyncUserState))).scalar_one()
        state.purged_up_to_version = alice.cursor + 10
        await session.commit()

    await alice.pull()
    assert ("preferences", offline_id) in alice.rows  # dirty row survived
    assert ("preferences", synced_id) not in alice.rows  # clean row dropped
    assert len(alice.outbox) == 1


# --- retention ---------------------------------------------------------------


async def test_retention_purges_old_tombstones_and_raises_the_watermark(
    two_clients, session_factory
) -> None:
    alice, _ = two_clients
    row_id = str(uuid.uuid4())
    alice.stage("preferences", preferences_payload(row_id, updated_at=BASE_TIME))
    await alice.sync()
    alice.stage_delete("preferences", row_id, deleted_at=BASE_TIME + timedelta(minutes=1))
    await alice.sync()

    async with session_factory() as session:
        stats = await SyncService(session).run_retention(now=BASE_TIME + timedelta(days=200))
        assert stats["tombstones"] == 1
        assert stats["batches"] == 2
        state = (await session.execute(select(SyncUserState))).scalar_one()
        assert state.purged_up_to_version > 0

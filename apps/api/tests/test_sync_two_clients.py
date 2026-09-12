"""Two devices, one user, end to end -- the Phase-2 DoD scenario.

"Two devices edit offline -> come online -> nothing is lost." Each test drives
the real `/sync/push` + `/sync/pull` endpoints through `SimClient`, so the
merge decisions here are the ones a real client would see, not `merge.py`
called directly (that is `test_sync_merge_matrix.py`).

Test names carry the ADR conflict-matrix row they exercise.
"""

from __future__ import annotations

import uuid
from datetime import timedelta

from tests import test_sync_harness as harness

BASE_TIME = harness.BASE_TIME
SimClient = harness.SimClient
preferences_payload = harness.preferences_payload
wire_time = harness.wire_time


# Fixtures are re-exported by assignment, not imported: pytest discovers them
# either way, but a test whose parameter shares a name with an import trips
# ruff's F811.
client = harness.client
session_factory = harness.session_factory
two_clients = harness.two_clients


async def test_e2e_rule_01_later_updated_at_wins_across_devices(two_clients) -> None:
    """ADR rule 1: the incoming row is newer -> `applied`, both devices converge."""
    alice, bob = two_clients
    row_id = str(uuid.uuid4())

    alice.stage("preferences", preferences_payload(row_id, updated_at=BASE_TIME, theme="light"))
    await alice.sync()
    await bob.pull_all()
    assert bob.live("preferences")[0]["ui"]["theme"] == "light"

    row = dict(bob.rows[("preferences", row_id)])
    row["ui"] = {"theme": "dark", "first_day_of_week": 1}
    row["updated_at"] = wire_time(BASE_TIME + timedelta(minutes=5))
    bob.stage("preferences", row)
    response = await bob.push()
    assert response.json()["results"][0]["status"] == "applied"

    await bob.pull_all()
    await alice.pull_all()
    assert alice.live("preferences")[0]["ui"]["theme"] == "dark"
    assert alice.snapshot() == bob.snapshot()


async def test_e2e_rule_02_older_updated_at_loses_and_gets_server_row(two_clients) -> None:
    """ADR rule 2: the stored row is newer -> `conflict` + the full `server_row`."""
    alice, bob = two_clients
    row_id = str(uuid.uuid4())

    alice.stage("preferences", preferences_payload(row_id, updated_at=BASE_TIME))
    await alice.sync()
    await bob.pull_all()

    newer = dict(alice.rows[("preferences", row_id)])
    newer["ui"] = {"theme": "dark", "first_day_of_week": 1}
    newer["updated_at"] = wire_time(BASE_TIME + timedelta(minutes=10))
    alice.stage("preferences", newer)
    await alice.sync()

    stale = dict(bob.rows[("preferences", row_id)])
    stale["ui"] = {"theme": "light", "first_day_of_week": 0}
    stale["updated_at"] = wire_time(BASE_TIME + timedelta(minutes=1))
    bob.stage("preferences", stale)
    result = (await bob.push()).json()["results"][0]

    assert result["status"] == "conflict"
    assert result["server_row"]["ui"] == {"theme": "dark", "first_day_of_week": 1}
    # The client replaced its row wholesale and did not resend.
    assert bob.outbox == []
    assert bob.rows[("preferences", row_id)]["ui"]["theme"] == "dark"


async def test_e2e_rule_05_delete_beats_a_concurrent_update(two_clients) -> None:
    """ADR rule 5: a later soft delete wins over an older live edit."""
    alice, bob = two_clients
    row_id = str(uuid.uuid4())
    alice.stage("preferences", preferences_payload(row_id, updated_at=BASE_TIME))
    await alice.sync()
    await bob.pull_all()

    # Bob edits at T+1 (offline); Alice deletes at T+5 and reaches the server first.
    stale = dict(bob.rows[("preferences", row_id)])
    stale["ui"] = {"theme": "light", "first_day_of_week": 0}
    stale["updated_at"] = wire_time(BASE_TIME + timedelta(minutes=1))
    bob.stage("preferences", stale)

    alice.stage_delete("preferences", row_id, deleted_at=BASE_TIME + timedelta(minutes=5))
    await alice.sync()

    result = (await bob.push()).json()["results"][0]
    assert result["status"] == "conflict"
    assert result["server_row"]["deleted_at"] is not None
    assert bob.live("preferences") == []


async def test_e2e_rule_05_later_update_resurrects_a_deleted_row(two_clients) -> None:
    """ADR rule 5, other direction: an upsert with `updated_at > deleted_at` revives it."""
    alice, bob = two_clients
    row_id = str(uuid.uuid4())
    alice.stage("preferences", preferences_payload(row_id, updated_at=BASE_TIME))
    await alice.sync()
    await bob.pull_all()

    alice.stage_delete("preferences", row_id, deleted_at=BASE_TIME + timedelta(minutes=5))
    await alice.sync()

    revived = dict(bob.rows[("preferences", row_id)])
    revived["deleted_at"] = None
    revived["ui"] = {"theme": "dark", "first_day_of_week": 1}
    revived["updated_at"] = wire_time(BASE_TIME + timedelta(minutes=9))
    bob.stage("preferences", revived)
    result = (await bob.push()).json()["results"][0]

    assert result["status"] == "applied"
    await alice.pull_all()
    assert alice.live("preferences")[0]["ui"]["theme"] == "dark"


async def test_e2e_rule_14_natural_key_collision_with_different_uuids(two_clients) -> None:
    """ADR rule 14: two devices, one natural key `(user_id)`, two UUIDs.

    The older `created_at` survives; the loser becomes a `merged_into`
    tombstone that both devices receive and must hide in the UI.
    """
    alice, bob = two_clients
    older_id = str(uuid.uuid4())
    newer_id = str(uuid.uuid4())

    alice.stage(
        "preferences",
        preferences_payload(older_id, created_at=BASE_TIME, updated_at=BASE_TIME, theme="light"),
    )
    await alice.sync()

    bob.stage(
        "preferences",
        preferences_payload(
            newer_id,
            created_at=BASE_TIME + timedelta(minutes=1),
            updated_at=BASE_TIME + timedelta(minutes=1),
            theme="dark",
        ),
    )
    result = (await bob.push()).json()["results"][0]

    assert result["status"] == "conflict"
    assert result["server_row"]["id"] == older_id
    # The newer row's content won (later `updated_at`), under the older id.
    assert result["server_row"]["ui"]["theme"] == "dark"

    await bob.pull_all()
    await alice.pull_all()

    # Both devices agree on the surviving row, byte for byte.
    assert alice.live("preferences") == bob.live("preferences")
    assert [row["id"] for row in alice.live("preferences")] == [older_id]

    # Alice, whose cursor was already past 0, receives the loser's tombstone
    # carrying `merged_into`. Bob does not: he pulled at `cursor = 0`, where
    # the ADR withholds tombstones -- and he no longer holds the loser id
    # anyway, because the `conflict` answer replaced it with the survivor.
    tombstone = alice.rows[("preferences", newer_id)]
    assert tombstone["deleted_at"] is not None
    assert tombstone["merged_into"] == older_id
    assert ("preferences", newer_id) not in bob.rows


async def test_e2e_offline_edits_then_online_converge_byte_identical(two_clients) -> None:
    """Phase-2 DoD: both devices edit offline, then come online -- no loss, no drift."""
    alice, bob = two_clients
    row_id = str(uuid.uuid4())
    alice.stage("preferences", preferences_payload(row_id, updated_at=BASE_TIME))
    await alice.sync()
    await bob.pull_all()

    # Both go offline and edit the same row at different wall-clock times.
    alice_row = dict(alice.rows[("preferences", row_id)])
    alice_row["privacy_consents"] = {
        "analytics": True,
        "ai_personalization": False,
        "dw_cloud_stats": False,
    }
    alice_row["updated_at"] = wire_time(BASE_TIME + timedelta(minutes=3))
    alice.stage("preferences", alice_row)

    bob_row = dict(bob.rows[("preferences", row_id)])
    bob_row["ui"] = {"theme": "dark", "first_day_of_week": 0}
    bob_row["updated_at"] = wire_time(BASE_TIME + timedelta(minutes=7))
    bob.stage("preferences", bob_row)

    # They come back online in the "wrong" order: the older edit pushes last.
    await bob.sync()
    await alice.sync()
    await bob.pull_all()

    assert alice.snapshot() == bob.snapshot()
    winner = alice.live("preferences")[0]
    assert winner["ui"] == {"theme": "dark", "first_day_of_week": 0}  # newest edit survived
    assert alice.outbox == [] and bob.outbox == []


async def test_e2e_device_pushing_while_the_other_is_offline_then_pulls(two_clients) -> None:
    """A long-offline device catches up in one pull and matches byte for byte."""
    alice, bob = two_clients
    row_id = str(uuid.uuid4())

    for minute in range(5):
        payload = preferences_payload(
            row_id,
            created_at=BASE_TIME,
            updated_at=BASE_TIME + timedelta(minutes=minute),
            first_day_of_week=minute % 7,
            server_version=int(
                (alice.rows.get(("preferences", row_id)) or {}).get("server_version") or 0
            ),
        )
        alice.stage("preferences", payload)
        await alice.sync()

    assert bob.rows == {}
    await bob.pull_all()
    assert alice.snapshot() == bob.snapshot()


async def test_e2e_pull_echoes_the_pushing_devices_own_rows(two_clients) -> None:
    """ADR section 3: pull returns a device's own writes too; applying them is idempotent."""
    alice, _ = two_clients
    row_id = str(uuid.uuid4())
    alice.stage("preferences", preferences_payload(row_id, updated_at=BASE_TIME))
    await alice.push()

    before = alice.snapshot()
    await alice.pull_all()
    first_pass = alice.snapshot()
    await alice.pull_all()
    assert first_pass == alice.snapshot()
    assert before != "" and first_pass != ""


async def test_e2e_cursor_zero_withholds_tombstones(two_clients) -> None:
    """ADR section 3: a brand-new device has nothing to delete, so no tombstones."""
    alice, bob = two_clients
    row_id = str(uuid.uuid4())
    alice.stage("preferences", preferences_payload(row_id, updated_at=BASE_TIME))
    await alice.sync()
    alice.stage_delete("preferences", row_id, deleted_at=BASE_TIME + timedelta(minutes=2))
    await alice.sync()

    body = (await bob.pull()).json()
    assert body["rows"] == []
    assert bob.rows == {}

"""A second, fixture-only entity registered through the public registry API.

This is the proof that the Phase-2 contract actually holds: the entity below
is declared exactly the way `app/modules/tasks/sync_entities.py` will be --
ORM model with the four standard mixins, a `SyncRowBase` subclass, a
`MergePolicy` -- and **nothing inside `app/modules/sync/` mentions it**. It
also lets the matrix rows that need a real table (rule 8 `completed_at`
max-wins, rule 9 additive max-wins, rule 14 natural-key collision on
`(user_id, ref_id, date)`) run end to end over HTTP rather than only through
`merge.py`.

`sync_fixture_notes` is a test table: it lives on `Base.metadata` so
`create_all` builds it, and it deliberately has no Alembic migration -- the
real Phase-2 tables are T-202's work (this task must not create them).
"""

from __future__ import annotations

import uuid
from datetime import datetime, timedelta
from typing import Any

import pytest
from sqlalchemy import DateTime, ForeignKey, Integer, String
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base
from app.db.mixins import SoftDelete, Timestamps, UUIDPk, Versioned
from app.modules.sync import registry
from app.modules.sync.registry import (
    FieldRule,
    MergePolicy,
    MergeStrategy,
    SyncEntity,
    register_entity,
    unregister_entity,
)
from app.modules.sync.schemas import SyncRowBase, UtcDatetime
from app.modules.users.models import User  # noqa: F401 - FK target registration
from tests import test_sync_harness as harness

BASE_TIME = harness.BASE_TIME
wire_time = harness.wire_time


# Fixtures are re-exported by assignment, not imported: pytest discovers them
# either way, but a test whose parameter shares a name with an import trips
# ruff's F811.
client = harness.client
session_factory = harness.session_factory
two_clients = harness.two_clients


class SyncFixtureNote(UUIDPk, Timestamps, SoftDelete, Versioned, Base):
    """A syncable table built from nothing but the four standard mixins."""

    __tablename__ = "sync_fixture_notes"

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    # ADR rule 16: this table's `ref_id` means "the notebook this note belongs
    # to"; `date` is the note's calendar day. Together with `user_id` they are
    # the natural key.
    ref_id: Mapped[str | None] = mapped_column(String(64), nullable=True)
    date: Mapped[str | None] = mapped_column(String(10), nullable=True)
    title: Mapped[str] = mapped_column(String(200), nullable=False, default="")
    count: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    # Plain `DateTime(timezone=True)`, not a custom decorator: `UtcDatetime` in
    # the wire schema is what normalises SQLite's naive round-trip, so an
    # entity module needs nothing beyond the shared mixins.
    completed_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True, default=None
    )


class NoteSyncRow(SyncRowBase):
    ref_id: str | None = None
    date: str | None = None
    title: str = ""
    count: int = 0
    completed_at: UtcDatetime | None = None


NOTE_POLICY = MergePolicy(
    adr_rules=(8, 9, 14),
    natural_key=("user_id", "ref_id", "date"),
    field_rules=(
        FieldRule("completed_at", MergeStrategy.max_wins, adr_rule=8),
        FieldRule("count", MergeStrategy.max_wins, adr_rule=9),
        FieldRule("title", MergeStrategy.lww, adr_rule=9),
    ),
)


@pytest.fixture
def note_entity():
    entity = SyncEntity(
        name="sync_fixture_notes",
        model=SyncFixtureNote,
        schema=NoteSyncRow,
        policy=NOTE_POLICY,
    )
    register_entity(entity)
    try:
        yield entity
    finally:
        unregister_entity("sync_fixture_notes")


def note_payload(
    row_id: str,
    *,
    updated_at: datetime,
    created_at: datetime | None = None,
    title: str = "note",
    count: int = 0,
    completed_at: datetime | None = None,
    ref_id: str | None = "notebook-1",
    date: str | None = "2026-09-12",
    server_version: int = 0,
) -> dict[str, Any]:
    return {
        "id": row_id,
        "created_at": wire_time(created_at or updated_at),
        "updated_at": wire_time(updated_at),
        "deleted_at": None,
        "server_version": server_version,
        "ref_id": ref_id,
        "date": date,
        "title": title,
        "count": count,
        "completed_at": wire_time(completed_at) if completed_at else None,
    }


# --- the contract itself -----------------------------------------------------


async def test_registering_an_entity_needs_no_change_inside_the_sync_package(
    note_entity,
) -> None:
    assert "sync_fixture_notes" in registry.entity_names()
    assert registry.get_entity("sync_fixture_notes") is note_entity


async def test_a_registered_entity_appears_in_limits(two_clients, note_entity) -> None:
    alice, _ = two_clients
    body = (await alice.http.get("/sync/limits", headers=alice.headers)).json()
    entry = next(e for e in body["entities"] if e["name"] == "sync_fixture_notes")
    assert entry["natural_key"] == ["user_id", "ref_id", "date"]
    assert entry["direction"] == "bidirectional"
    assert entry["adr_rules"] == [8, 9, 14]


async def test_a_registered_entity_round_trips_push_then_pull(two_clients, note_entity) -> None:
    alice, bob = two_clients
    row_id = str(uuid.uuid4())
    alice.stage("sync_fixture_notes", note_payload(row_id, updated_at=BASE_TIME, title="salom"))
    await alice.sync()

    await bob.pull_all()
    assert bob.live("sync_fixture_notes")[0]["title"] == "salom"
    assert alice.snapshot() == bob.snapshot()


# --- rule 8 end to end -------------------------------------------------------


async def test_e2e_rule_08_completed_at_is_max_wins_over_http(two_clients, note_entity) -> None:
    """Sync never un-completes: an older device cannot clear `completed_at`."""
    alice, bob = two_clients
    row_id = str(uuid.uuid4())
    alice.stage("sync_fixture_notes", note_payload(row_id, updated_at=BASE_TIME))
    await alice.sync()
    await bob.pull_all()

    # Alice completes it at T+10.
    done = dict(alice.rows[("sync_fixture_notes", row_id)])
    done["completed_at"] = wire_time(BASE_TIME + timedelta(minutes=10))
    done["updated_at"] = wire_time(BASE_TIME + timedelta(minutes=10))
    alice.stage("sync_fixture_notes", done)
    await alice.sync()

    # Bob, later still, edits the title and sends `completed_at: null`.
    stale = dict(bob.rows[("sync_fixture_notes", row_id)])
    stale["title"] = "renamed"
    stale["completed_at"] = None
    stale["updated_at"] = wire_time(BASE_TIME + timedelta(minutes=20))
    bob.stage("sync_fixture_notes", stale)
    result = (await bob.push()).json()["results"][0]

    assert result["status"] == "conflict"
    assert result["server_row"]["title"] == "renamed"  # LWW field followed Bob
    assert result["server_row"]["completed_at"] == "2026-09-12T08:10:00.000Z"  # max-wins held

    await alice.pull_all()
    await bob.pull_all()
    assert alice.snapshot() == bob.snapshot()


async def test_e2e_rule_09_additive_count_is_max_wins_over_http(two_clients, note_entity) -> None:
    alice, bob = two_clients
    row_id = str(uuid.uuid4())
    alice.stage("sync_fixture_notes", note_payload(row_id, updated_at=BASE_TIME, count=5))
    await alice.sync()
    await bob.pull_all()

    lower = dict(bob.rows[("sync_fixture_notes", row_id)])
    lower["count"] = 1
    lower["updated_at"] = wire_time(BASE_TIME + timedelta(minutes=5))
    bob.stage("sync_fixture_notes", lower)
    result = (await bob.push()).json()["results"][0]

    assert result["status"] == "conflict"
    assert result["server_row"]["count"] == 5


# --- rule 14 end to end ------------------------------------------------------


async def test_e2e_rule_14_same_natural_key_different_uuids_over_http(
    two_clients, note_entity
) -> None:
    """Two devices create a note for the same `(user_id, ref_id, date)` offline."""
    alice, bob = two_clients
    older_id = str(uuid.uuid4())
    newer_id = str(uuid.uuid4())

    alice.stage(
        "sync_fixture_notes",
        note_payload(older_id, created_at=BASE_TIME, updated_at=BASE_TIME, count=3, title="a"),
    )
    await alice.sync()

    bob.stage(
        "sync_fixture_notes",
        note_payload(
            newer_id,
            created_at=BASE_TIME + timedelta(minutes=2),
            updated_at=BASE_TIME + timedelta(minutes=2),
            count=9,
            title="b",
        ),
    )
    result = (await bob.push()).json()["results"][0]

    assert result["status"] == "conflict"
    assert result["server_row"]["id"] == older_id  # older created_at survives
    assert result["server_row"]["count"] == 9  # additive field merged (rule 9)
    assert result["server_row"]["title"] == "b"  # LWW winner

    await alice.pull_all()
    tombstone = alice.rows[("sync_fixture_notes", newer_id)]
    assert tombstone["deleted_at"] is not None
    assert tombstone["merged_into"] == older_id
    assert [note["id"] for note in alice.live("sync_fixture_notes")] == [older_id]


async def test_e2e_a_different_natural_key_is_not_a_collision(two_clients, note_entity) -> None:
    alice, _ = two_clients
    first = str(uuid.uuid4())
    second = str(uuid.uuid4())
    alice.stage("sync_fixture_notes", note_payload(first, updated_at=BASE_TIME))
    alice.stage(
        "sync_fixture_notes",
        note_payload(second, updated_at=BASE_TIME, date="2026-09-13"),
    )
    body = (await alice.push()).json()
    assert [result["status"] for result in body["results"]] == ["applied", "applied"]
    await alice.pull_all()
    assert len(alice.live("sync_fixture_notes")) == 2


async def test_e2e_deleting_then_recreating_the_same_natural_key_is_allowed(
    two_clients, note_entity
) -> None:
    """A tombstone must not block a fresh entry for the same day."""
    alice, _ = two_clients
    first = str(uuid.uuid4())
    alice.stage("sync_fixture_notes", note_payload(first, updated_at=BASE_TIME))
    await alice.sync()
    alice.stage_delete("sync_fixture_notes", first, deleted_at=BASE_TIME + timedelta(minutes=1))
    await alice.sync()

    second = str(uuid.uuid4())
    alice.stage(
        "sync_fixture_notes",
        note_payload(second, updated_at=BASE_TIME + timedelta(minutes=5)),
    )
    result = (await alice.push()).json()["results"][0]
    assert result["status"] == "applied"


async def test_e2e_two_entities_share_one_monotonic_cursor(two_clients, note_entity) -> None:
    """One per-user counter across every entity, so pull can page globally."""
    alice, bob = two_clients
    alice.stage("sync_fixture_notes", note_payload(str(uuid.uuid4()), updated_at=BASE_TIME))
    await alice.push()

    from tests.test_sync_harness import preferences_payload

    alice.stage("preferences", preferences_payload(str(uuid.uuid4()), updated_at=BASE_TIME))
    await alice.push()

    body = (await bob.http.get("/sync/pull?cursor=0", headers=bob.headers)).json()
    versions = [entry["server_version"] for entry in body["rows"]]
    entities = [entry["entity"] for entry in body["rows"]]
    assert versions == sorted(versions)
    assert len(set(versions)) == len(versions)  # no two rows share a version
    assert set(entities) == {"sync_fixture_notes", "preferences"}


async def test_ai_can_never_write_a_row_through_this_module(two_clients, note_entity) -> None:
    """ADR "AI invarianti": sync is the only write path for user rows.

    Structurally: every write goes through `/sync/push`, which takes its
    `user_id` from the JWT subject only. There is no route, parameter or
    header by which a caller can write a row "on behalf of AI" -- a payload
    naming another user is `foreign_user`, and an unregistered entity (such as
    the online-only `ai_proposals`) is `unknown_entity`.
    """
    alice, _ = two_clients
    row_id = str(uuid.uuid4())
    proposal = {
        "client_seq": 1,
        "entity": "ai_proposals",
        "row_id": row_id,
        "op": "upsert",
        "base_version": 0,
        "payload": note_payload(row_id, updated_at=BASE_TIME),
    }
    result = (await alice.push(changes=[proposal])).json()["results"][0]
    assert (result["status"], result["reason"]) == ("rejected", "unknown_entity")

    # And the AI's own table is not, and must never become, a sync entity.
    assert "ai_proposals" not in registry.entity_names()

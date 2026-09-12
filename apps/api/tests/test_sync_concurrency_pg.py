"""Concurrency behaviour of the sync engine, against real PostgreSQL.

Everything else in this suite runs on in-memory SQLite over a single
connection, where two pushes can never actually overlap. That is exactly why
the two defects covered here survived a green build: they only exist when two
transactions run at the same time on a database with real row locks.

Skipped unless a reachable PostgreSQL is configured. CI already provides one
(`.github/workflows/api.yml` starts `pgvector/pgvector:pg16`, exports
`DATABASE_URL` and runs `alembic upgrade head` before pytest), so these run
there automatically. Locally, point `TEST_DATABASE_URL` at the development
container:

    TEST_DATABASE_URL=postgresql+asyncpg://kunim:<pw>@localhost:5432/kunim

The tests only ever touch users they create themselves, so they are safe to
run against the development database.
"""

from __future__ import annotations

import asyncio
import os
import uuid
from collections.abc import AsyncGenerator
from datetime import UTC, datetime, timedelta
from typing import Any

import pytest
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.db.models_discovery import import_all_models
from app.modules.sync import repository as sync_repository
from app.modules.sync.registry import get_entity
from app.modules.sync.schemas import ChangeStatus, PushRequest, SyncChange, SyncOp, to_wire
from app.modules.sync.service import SyncService

import_all_models()

from app.modules.users.models import User  # noqa: E402  (needs metadata registered)

BASE_TIME = datetime(2026, 9, 12, 8, 0, 0, tzinfo=UTC)


def _database_url() -> str | None:
    url = os.environ.get("TEST_DATABASE_URL") or os.environ.get("DATABASE_URL")
    if not url or "postgresql" not in url:
        return None
    return url


pytestmark = pytest.mark.skipif(
    _database_url() is None,
    reason="no PostgreSQL configured (set TEST_DATABASE_URL or DATABASE_URL)",
)


@pytest.fixture
async def engine() -> AsyncGenerator[Any, None]:
    url = _database_url()
    assert url is not None
    eng = create_async_engine(url, pool_size=5, max_overflow=5)
    try:
        # Fail the test loudly rather than silently passing if the database
        # is configured but unreachable.
        async with eng.connect():
            pass
    except Exception as exc:  # pragma: no cover - environment problem
        await eng.dispose()
        pytest.skip(f"PostgreSQL not reachable: {exc}")
    try:
        yield eng
    finally:
        await eng.dispose()


@pytest.fixture
async def sessions(engine: Any) -> AsyncGenerator[async_sessionmaker[AsyncSession], None]:
    yield async_sessionmaker(bind=engine, expire_on_commit=False)


@pytest.fixture
async def user_id(sessions: async_sessionmaker[AsyncSession]) -> AsyncGenerator[uuid.UUID, None]:
    """A throwaway user; every row these tests touch belongs to it."""
    uid = uuid.uuid4()
    async with sessions() as session:
        session.add(
            User(
                id=uid,
                email=f"pg-concurrency-{uid.hex[:12]}@example.com",
                password_hash="not-a-real-hash",
                locale="uz",
            )
        )
        await session.commit()
    yield uid
    # `ON DELETE CASCADE` on every user_id FK clears the rows this test wrote.
    async with sessions() as session:
        user = await session.get(User, uid)
        if user is not None:
            await session.delete(user)
            await session.commit()


def _task_change(
    *,
    row_id: uuid.UUID,
    user_id: uuid.UUID,
    title: str,
    updated_at: datetime,
    seq: int = 1,
) -> SyncChange:
    return SyncChange(
        client_seq=seq,
        entity="tasks",
        row_id=row_id,
        op=SyncOp.upsert,
        base_version=0,
        payload={
            "id": str(row_id),
            "user_id": str(user_id),
            "created_at": to_wire(BASE_TIME),
            "updated_at": to_wire(updated_at),
            "deleted_at": None,
            "server_version": 0,
            "title": title,
            "description": None,
            "priority": "medium",
            "due_date": None,
            "category_id": None,
            "completed_at": None,
        },
    )


async def _push(
    sessions: async_sessionmaker[AsyncSession],
    user_id: uuid.UUID,
    change: SyncChange,
    *,
    device_id: str,
) -> Any:
    async with sessions() as session:
        user = await session.get(User, user_id)
        assert user is not None
        service = SyncService(session)
        return await service.push(
            user,
            PushRequest(device_id=device_id, batch_id=uuid.uuid4(), changes=[change]),
            now=BASE_TIME + timedelta(minutes=5),
        )


async def _stored_title(
    sessions: async_sessionmaker[AsyncSession], user_id: uuid.UUID, row_id: uuid.UUID
) -> tuple[str, int]:
    entity = get_entity("tasks")
    assert entity is not None
    async with sessions() as session:
        row = await session.get(entity.model, row_id)
        assert row is not None
        assert row.user_id == user_id
        return row.title, int(row.server_version)


async def test_a_push_merges_against_state_no_one_else_can_still_change(
    sessions: async_sessionmaker[AsyncSession],
    user_id: uuid.UUID,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Rules 1-2 must survive a concurrent writer (the lost-update race).

    `allocate_server_version` takes the per-user row lock, but it used to run
    *after* the merge decision. Two pushes for the same row could both read the
    pre-push state, both decide "incoming wins", and both answer `applied` --
    so whichever committed last won, even when it carried the OLDER
    `updated_at`. The device whose newer edit lost had already been told
    `applied`, so it cleared `dirty` and dropped its outbox entry: that edit
    was gone for good.

    Deterministic setup, no sleeps deciding the outcome:

    * writer A takes the lock and writes the NEWER edit, uncommitted;
    * push B arrives with an OLDER edit while A is still open.

    With the lock taken first, B cannot read anything until A commits, so it
    merges against "newer edit" and correctly loses (`conflict`). Without it, B
    reads the pre-A seed, decides `applied`, blocks only at allocation, and
    then overwrites A's newer row -- which is the data loss this pins down.
    """
    entity = get_entity("tasks")
    assert entity is not None
    row_id = uuid.uuid4()

    # Fires as soon as B has read the row it will merge against. Post-fix B is
    # blocked on the lock and never gets here, which is the point -- so every
    # wait on it is bounded.
    b_has_read = asyncio.Event()
    original_get_row = sync_repository.SyncRepository.get_row

    async def signalling_get_row(self: Any, *args: Any, **kwargs: Any) -> Any:
        row = await original_get_row(self, *args, **kwargs)
        b_has_read.set()
        return row

    seed = await _push(
        sessions,
        user_id,
        _task_change(row_id=row_id, user_id=user_id, title="seed", updated_at=BASE_TIME, seq=1),
        device_id="seed",
    )
    assert seed.results[0].status is ChangeStatus.applied

    async with sessions() as writer:
        # A: hold the per-user lock and stage the newer edit, uncommitted.
        await sync_repository.acquire_user_lock(writer, user_id)
        newer_version = await sync_repository.allocate_server_version(writer, user_id)
        await writer.execute(
            entity.model.__table__.update()
            .where(entity.model.id == row_id)
            .values(
                title="newer edit",
                updated_at=BASE_TIME + timedelta(minutes=2),
                server_version=newer_version,
            )
        )
        await writer.flush()

        # B: an older edit, pushed while A is still in flight. Its session is
        # opened and warmed FIRST, so connection setup cannot eat the window
        # in which it is supposed to read.
        older = _task_change(
            row_id=row_id,
            user_id=user_id,
            title="older edit",
            updated_at=BASE_TIME + timedelta(minutes=1),
            seq=2,
        )

        async with sessions() as b_session:
            b_user = await b_session.get(User, user_id)
            assert b_user is not None  # also warms the connection

            b_has_read.clear()
            monkeypatch.setattr(sync_repository.SyncRepository, "get_row", signalling_get_row)

            push_b = asyncio.create_task(
                SyncService(b_session).push(
                    b_user,
                    PushRequest(device_id="device-b", batch_id=uuid.uuid4(), changes=[older]),
                    now=BASE_TIME + timedelta(minutes=5),
                )
            )

            # Let B get as far as it can. Either it reads (the bug: it read
            # state A is still changing) or it blocks on the lock and this
            # times out (the fix). Both paths continue.
            try:
                await asyncio.wait_for(b_has_read.wait(), timeout=2.0)
            except TimeoutError:
                pass

            await writer.commit()
            response_b = await asyncio.wait_for(push_b, timeout=15)
    status_b = response_b.results[0].status

    title, _version = await _stored_title(sessions, user_id, row_id)
    assert title == "newer edit", (
        f"the newer edit was overwritten by an older one (B answered "
        f"{status_b.value}): B merged against a snapshot that a concurrent "
        "push was still changing"
    )
    assert status_b is ChangeStatus.conflict, (
        f"B carried the older updated_at, so rule 2 requires `conflict`, got {status_b.value}"
    )
    assert response_b.results[0].server_row is not None
    assert response_b.results[0].server_row["title"] == "newer edit"


async def test_a_pull_never_steps_over_an_uncommitted_row(
    sessions: async_sessionmaker[AsyncSession],
    user_id: uuid.UUID,
) -> None:
    """A pull must not advance its cursor past a row that is still in flight.

    `pull` issues one SELECT per entity with no isolation level set, so every
    statement gets its own READ COMMITTED snapshot. The concern was that a
    transaction committing mid-loop could let the cursor skip a lower version
    that had not landed yet.

    It cannot, and this pins down why: `allocate_server_version` bumps
    `sync_user_state.last_version` with an UPDATE, which holds that row's
    exclusive lock until commit. Versions are therefore handed out in commit
    order, so a committed version N+1 can never coexist with an uncommitted N.
    Every version below anything a pull can see is already committed.

    The test holds a push open (allocated, not committed), pulls concurrently,
    then commits and pulls again from the cursor it was given -- and asserts
    the in-flight row is delivered rather than skipped.
    """
    entity = get_entity("tasks")
    assert entity is not None
    in_flight_id = uuid.uuid4()

    async with sessions() as writer, sessions() as reader:
        writer_user = await writer.get(User, user_id)
        reader_user = await reader.get(User, user_id)
        assert writer_user is not None and reader_user is not None

        # Apply a change but DO NOT commit: the row and its version exist only
        # inside this transaction.
        writer_service = SyncService(writer)
        await writer_service._repo.acquire_user_lock(user_id)
        version = await writer_service._repo.allocate_server_version(user_id)
        assert version >= 1
        await writer.execute(
            entity.model.__table__.insert().values(
                id=in_flight_id,
                user_id=user_id,
                created_at=BASE_TIME,
                updated_at=BASE_TIME,
                deleted_at=None,
                server_version=version,
                title="in flight",
                description=None,
                priority="medium",
                due_date=None,
                category_id=None,
                completed_at=None,
            )
        )
        await writer.flush()

        # A concurrent pull must not see it, and must not claim a cursor at or
        # above its version.
        reader_service = SyncService(reader)
        during = await reader_service.pull(reader_user, cursor=0, limit=100)
        delivered_ids = {row.row["id"] for row in during.rows}
        assert str(in_flight_id) not in delivered_ids
        assert during.next_cursor < version, (
            "the cursor moved to or past an uncommitted version, so that row "
            "would never be delivered again"
        )
        await reader.rollback()

        await writer.commit()

    # Now that it is committed, a pull from the cursor the reader was given
    # must deliver it.
    async with sessions() as reader:
        reader_user = await reader.get(User, user_id)
        assert reader_user is not None
        after = await SyncService(reader).pull(reader_user, cursor=during.next_cursor, limit=100)
        assert str(in_flight_id) in {row.row["id"] for row in after.rows}


async def test_concurrent_first_ever_pushes_do_not_collide_on_the_state_row(
    sessions: async_sessionmaker[AsyncSession],
    user_id: uuid.UUID,
) -> None:
    """Two first-ever pushes must not race on creating `sync_user_state`.

    The row is created lazily. `allocate_server_version` used `add` + `flush`
    with no conflict handling, so two concurrent first writers collided on the
    primary key -- and the blanket handler in `push` reported that as
    `schema_invalid`, a reason whose client action is "never resend". A
    genuine local change could be stranded for ever by a pure infrastructure
    race. `acquire_user_lock` now inserts with `ON CONFLICT DO NOTHING`.
    """
    results = await asyncio.gather(
        _push(
            sessions,
            user_id,
            _task_change(
                row_id=uuid.uuid4(), user_id=user_id, title="a", updated_at=BASE_TIME, seq=1
            ),
            device_id="device-a",
        ),
        _push(
            sessions,
            user_id,
            _task_change(
                row_id=uuid.uuid4(), user_id=user_id, title="b", updated_at=BASE_TIME, seq=1
            ),
            device_id="device-b",
        ),
    )

    for response in results:
        assert response.results[0].status is ChangeStatus.applied, (
            f"a first-ever push was rejected as {response.results[0].reason}"
        )

    versions = sorted(r.results[0].server_version for r in results)
    assert versions[0] != versions[1], "both pushes were handed the same server_version"


async def test_a_pull_sees_a_multi_entity_batch_all_or_nothing(
    sessions: async_sessionmaker[AsyncSession],
    user_id: uuid.UUID,
) -> None:
    """The exact scenario raised against `pull`: one batch, two entities.

    `pull` runs one SELECT per entity inside a single READ COMMITTED
    transaction, so each statement gets its own snapshot. The worry was that a
    batch committing mid-loop could be seen *partially* -- the habits row at
    version N+1 delivered while the tasks row at version N was still invisible
    -- after which the cursor would sit above N and that row would never be
    sent again.

    It cannot happen, and this test is the evidence. Versions come from
    `allocate_server_version`, whose UPDATE holds the `sync_user_state` row
    lock until commit, so they are handed out in commit order: a committed
    version can never sit above an uncommitted one. A batch therefore becomes
    visible all at once.
    """
    tasks_entity = get_entity("tasks")
    habits_entity = get_entity("habits")
    assert tasks_entity is not None and habits_entity is not None

    task_id = uuid.uuid4()
    habit_id = uuid.uuid4()

    async with sessions() as writer, sessions() as reader:
        reader_user = await reader.get(User, user_id)
        assert reader_user is not None  # warms the reader's connection

        await sync_repository.acquire_user_lock(writer, user_id)
        task_version = await sync_repository.allocate_server_version(writer, user_id)
        habit_version = await sync_repository.allocate_server_version(writer, user_id)
        assert habit_version > task_version

        await writer.execute(
            tasks_entity.model.__table__.insert().values(
                id=task_id,
                user_id=user_id,
                created_at=BASE_TIME,
                updated_at=BASE_TIME,
                deleted_at=None,
                server_version=task_version,
                title="lower version",
                description=None,
                priority="medium",
                due_date=None,
                category_id=None,
                completed_at=None,
            )
        )
        await writer.execute(
            habits_entity.model.__table__.insert().values(
                id=habit_id,
                user_id=user_id,
                created_at=BASE_TIME,
                updated_at=BASE_TIME,
                deleted_at=None,
                server_version=habit_version,
                title="higher version",
                description=None,
                schedule={},
                target=1,
                color=None,
            )
        )
        await writer.flush()

        during = await SyncService(reader).pull(reader_user, cursor=0, limit=100)
        seen = {row.row["id"] for row in during.rows}
        assert str(task_id) not in seen
        assert str(habit_id) not in seen, (
            "the higher-versioned row of an uncommitted batch was delivered "
            "while its sibling was not: the cursor would skip the sibling"
        )
        assert during.next_cursor < task_version
        await reader.rollback()

        await writer.commit()

    async with sessions() as reader:
        reader_user = await reader.get(User, user_id)
        assert reader_user is not None
        after = await SyncService(reader).pull(reader_user, cursor=during.next_cursor, limit=100)
        delivered = {row.row["id"] for row in after.rows}
        assert {str(task_id), str(habit_id)} <= delivered, (
            "both rows of the batch must arrive once it is committed"
        )


async def test_concurrent_natural_key_writes_leave_one_live_row(
    sessions: async_sessionmaker[AsyncSession],
    user_id: uuid.UUID,
) -> None:
    """Rule 14 under concurrency: two devices, same natural key, two ids.

    The merge path looks for an existing row on the natural key and tombstones
    the loser. Before the per-user lock covered the whole push, two concurrent
    pushes could both look, both find nothing, and both insert -- leaving two
    live `habit_logs` rows for the same `(habit_id, date)` for ever, which the
    client then shows as a doubled count. There is no database-level unique
    index on the natural key to catch it.
    """
    entity = get_entity("habit_logs")
    assert entity is not None
    habit_id = uuid.uuid4()
    day = "2026-09-12"

    def log_change(row_id: uuid.UUID, count: int, seq: int) -> SyncChange:
        return SyncChange(
            client_seq=seq,
            entity="habit_logs",
            row_id=row_id,
            op=SyncOp.upsert,
            base_version=0,
            payload={
                "id": str(row_id),
                "user_id": str(user_id),
                "created_at": to_wire(BASE_TIME),
                "updated_at": to_wire(BASE_TIME + timedelta(minutes=count)),
                "deleted_at": None,
                "server_version": 0,
                "habit_id": str(habit_id),
                "date": day,
                "count": count,
                "value": None,
                "note": None,
            },
        )

    id_a, id_b = uuid.uuid4(), uuid.uuid4()
    await asyncio.gather(
        _push(sessions, user_id, log_change(id_a, 1, 1), device_id="device-a"),
        _push(sessions, user_id, log_change(id_b, 2, 1), device_id="device-b"),
    )

    async with sessions() as session:
        rows = (
            (
                await session.execute(
                    entity.model.__table__.select().where(
                        entity.model.user_id == user_id,
                        entity.model.habit_id == habit_id,
                        entity.model.deleted_at.is_(None),
                    )
                )
            )
            .mappings()
            .all()
        )

    assert len(rows) == 1, (
        f"{len(rows)} live habit_logs rows share one natural key: both pushes "
        "missed the collision because they read before taking the lock"
    )
    # Rule 9: the additive `count` is max-wins across the merge.
    assert rows[0]["count"] == 2

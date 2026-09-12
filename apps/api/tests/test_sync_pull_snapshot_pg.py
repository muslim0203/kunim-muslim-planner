"""Does a pull ever step over a row it has not delivered? (real PostgreSQL)

`tests/test_sync_concurrency_pg.py` already checks the single-version case and
concludes a pull cannot skip a row, because `allocate_server_version` holds an
exclusive lock on `sync_user_state` until commit, so versions are handed out in
commit order.

That argument only holds when each version belongs to a *different*
transaction. A push batch that touches several entities allocates several
versions inside ONE transaction and commits them atomically -- and `pull`
issues one SELECT per entity with no isolation level set, so each statement
gets its own READ COMMITTED snapshot. A commit landing between two of those
statements is visible to the later ones and invisible to the earlier ones.

This module pins that case down: the entity queried first gets the LOWER
version, the entity queried last gets the HIGHER one, and the writer commits
in between.

Skipped unless a reachable PostgreSQL is configured (TEST_DATABASE_URL or
DATABASE_URL), exactly like the sibling module.
"""

from __future__ import annotations

import os
import uuid
from collections.abc import AsyncGenerator
from datetime import UTC, datetime
from typing import Any

import pytest
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.db.models_discovery import import_all_models
from app.modules.sync import registry
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
    uid = uuid.uuid4()
    async with sessions() as session:
        session.add(
            User(
                id=uid,
                email=f"pg-pullsnap-{uid.hex[:12]}@example.com",
                password_hash="not-a-real-hash",
                locale="uz",
            )
        )
        await session.commit()
    yield uid
    async with sessions() as session:
        user = await session.get(User, uid)
        if user is not None:
            await session.delete(user)
            await session.commit()


def _pullable_names() -> list[str]:
    return [e.name for e in registry.all_entities() if e.pullable]


async def test_a_multi_entity_commit_is_never_half_delivered(
    sessions: async_sessionmaker[AsyncSession],
    user_id: uuid.UUID,
) -> None:
    """One transaction, two entities, two versions, committed mid-pull.

    `habits` is queried before `tasks`, so the habits row gets the lower
    version. The writer commits after the reader's habits SELECT and before
    its tasks SELECT. The reader then sees only the tasks row (higher
    version). If it reports that version as `next_cursor`, the habits row
    below it is never delivered again -- a silent, permanent loss.

    The invariant asserted here is the one that actually matters and does not
    depend on entity ordering: *every committed row at or below `next_cursor`
    must have been delivered in this page*.
    """
    names = _pullable_names()
    assert names.index("habits") < names.index("tasks"), (
        f"this test relies on habits being queried before tasks; current order is {names}"
    )

    habits_entity = registry.get_entity("habits")
    tasks_entity = registry.get_entity("tasks")
    assert habits_entity is not None and tasks_entity is not None

    habit_id = uuid.uuid4()
    task_id = uuid.uuid4()

    async with sessions() as writer, sessions() as reader:
        reader_user = await reader.get(User, user_id)
        assert reader_user is not None

        writer_service = SyncService(writer)
        await writer_service._repo.acquire_user_lock(user_id)

        # Both versions come from ONE transaction, committed atomically.
        habit_version = await writer_service._repo.allocate_server_version(user_id)
        task_version = await writer_service._repo.allocate_server_version(user_id)
        assert task_version == habit_version + 1

        await writer.execute(
            habits_entity.model.__table__.insert().values(
                id=habit_id,
                user_id=user_id,
                created_at=BASE_TIME,
                updated_at=BASE_TIME,
                deleted_at=None,
                server_version=habit_version,
                title="early entity, lower version",
                description=None,
                schedule={},
                target=1,
                color=None,
            )
        )
        await writer.execute(
            tasks_entity.model.__table__.insert().values(
                id=task_id,
                user_id=user_id,
                created_at=BASE_TIME,
                updated_at=BASE_TIME,
                deleted_at=None,
                server_version=task_version,
                title="late entity, higher version",
                description=None,
                priority="medium",
                due_date=None,
                category_id=None,
                completed_at=None,
            )
        )
        await writer.flush()

        # Commit exactly once, between the reader's habits and tasks queries,
        # by wrapping the per-entity read `pull` performs.
        reader_service = SyncService(reader)
        original_rows_after = reader_service._repo.rows_after
        committed = False

        async def rows_after_then_commit(entity: Any, *args: Any, **kwargs: Any) -> Any:
            nonlocal committed
            rows = await original_rows_after(entity, *args, **kwargs)
            if entity.name == "habits" and not committed:
                committed = True
                await writer.commit()
            return rows

        reader_service._repo.rows_after = rows_after_then_commit  # type: ignore[method-assign]

        page = await reader_service.pull(reader_user, cursor=0, limit=100)
        assert committed, "the writer never committed; the interleaving did not happen"

        delivered = {row.row["id"] for row in page.rows}
        await reader.rollback()

    # What is actually committed at or below the cursor the client will store?
    async with sessions() as checker:
        missed: list[str] = []
        for name in names:
            entity = registry.get_entity(name)
            assert entity is not None
            model = entity.model
            result = await checker.execute(
                select(model.id, model.server_version).where(
                    model.user_id == user_id,
                    model.server_version > 0,
                    model.server_version <= page.next_cursor,
                )
            )
            for row_id, version in result.all():
                if str(row_id) not in delivered:
                    missed.append(f"{name}@{version} ({row_id})")

    assert not missed, (
        "pull advanced next_cursor to "
        f"{page.next_cursor} but never delivered {missed}; a client storing "
        "that cursor loses those rows permanently. `pull` reads each entity in "
        "its own READ COMMITTED snapshot, so a multi-entity commit landing "
        "mid-loop is seen by the later queries and missed by the earlier ones."
    )

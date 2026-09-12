"""Entity-agnostic data access for sync.

Nothing here knows what a task or a habit is: every query is built from the
`SyncEntity` descriptor handed in by the caller, which is what lets Phase-2
modules register new tables without editing this package.

No method commits. `service.push` owns the transaction boundary (ADR §3
"Tranzaksiya chegarasi": the whole batch is one transaction, each change its
own SAVEPOINT), so a commit hidden in here would break the savepoint contract.
"""

from __future__ import annotations

import uuid
from datetime import datetime, timedelta
from typing import Any

from sqlalchemy import delete, or_, select, update
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.dialects.sqlite import insert as sqlite_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.modules.sync.models import RowHistory, SyncBatch, SyncMergedRow, SyncUserState
from app.modules.sync.registry import SyncEntity
from app.modules.sync.schemas import normalise_stored


async def acquire_user_lock(session: AsyncSession, user_id: uuid.UUID) -> None:
    """Serialize this user's pushes by locking their `sync_user_state` row.

    ADR-0002 ("Oqibatlar") claims the `sync_user_state` row lock serializes
    writes per user, but `allocate_server_version` only takes it *after* the
    merge decision has already been made from a pre-lock snapshot. Two pushes
    for the same row could therefore both read the old state, both decide
    "incoming wins", and both answer `applied` -- leaving whichever committed
    last on the server, even when it carried the OLDER `updated_at`. The
    losing device clears `dirty`, drops its outbox entry, and the newer edit
    is gone (rules 1-2 violated). The same race let two devices both miss a
    natural-key collision and insert duplicate rows, defeating rule 14.

    Taking the lock as the FIRST statement of a push closes the window: every
    read in the batch then sees state no concurrent push can still change.

    `INSERT ... ON CONFLICT DO NOTHING` first, because the row is created
    lazily and two first-ever writers would otherwise collide on the primary
    key (surfacing as a bogus `schema_invalid`).
    """
    dialect = session.bind.dialect.name if session.bind is not None else "postgresql"
    insert_stmt = pg_insert if dialect == "postgresql" else sqlite_insert
    await session.execute(
        insert_stmt(SyncUserState)
        .values(user_id=user_id, last_version=0, purged_up_to_version=0)
        .on_conflict_do_nothing(index_elements=["user_id"])
    )

    stmt = select(SyncUserState.user_id).where(SyncUserState.user_id == user_id)
    if dialect == "postgresql":
        # Held until this transaction commits or rolls back. SQLite has no
        # row locks (and no concurrency inside a single connection), so the
        # plain SELECT is the whole story there.
        stmt = stmt.with_for_update()
    await session.execute(stmt)


async def allocate_server_version(session: AsyncSession, user_id: uuid.UUID) -> int:
    """Allocate the next per-user `server_version` (ADR §3).

    A single `UPDATE ... SET last_version = last_version + 1 ... RETURNING`
    takes the row lock and hands back a gap-free number in commit order. This
    is the *only* place in the codebase allowed to produce a `server_version`:
    a global sequence is explicitly rejected by the ADR because it allocates
    at statement time while commits may land out of order, which would let a
    pull cursor step over an uncommitted row.
    """
    stmt = (
        update(SyncUserState)
        .where(SyncUserState.user_id == user_id)
        .values(last_version=SyncUserState.last_version + 1)
        .returning(SyncUserState.last_version)
        .execution_options(synchronize_session=False)
    )
    version = (await session.execute(stmt)).scalar_one_or_none()
    if version is not None:
        return int(version)

    # First write ever for this user: create the counter, then re-run the
    # bump so the lock semantics are identical on every subsequent call.
    session.add(SyncUserState(user_id=user_id, last_version=0, purged_up_to_version=0))
    await session.flush()
    version = (await session.execute(stmt)).scalar_one()
    return int(version)


class SyncRepository:
    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    @property
    def session(self) -> AsyncSession:
        return self._session

    # --- per-user state -----------------------------------------------------

    async def acquire_user_lock(self, user_id: uuid.UUID) -> None:
        return await acquire_user_lock(self._session, user_id)

    async def allocate_server_version(self, user_id: uuid.UUID) -> int:
        return await allocate_server_version(self._session, user_id)

    async def get_state(self, user_id: uuid.UUID) -> SyncUserState | None:
        stmt = select(SyncUserState).where(SyncUserState.user_id == user_id)
        return (await self._session.execute(stmt)).scalar_one_or_none()

    async def max_server_version(self, user_id: uuid.UUID) -> int:
        state = await self.get_state(user_id)
        return int(state.last_version) if state is not None else 0

    async def purged_up_to(self, user_id: uuid.UUID) -> int:
        state = await self.get_state(user_id)
        return int(state.purged_up_to_version) if state is not None else 0

    async def set_purged_up_to(self, user_id: uuid.UUID, version: int) -> None:
        state = await self.get_state(user_id)
        if state is None:
            self._session.add(
                SyncUserState(user_id=user_id, last_version=0, purged_up_to_version=version)
            )
        elif version > state.purged_up_to_version:
            state.purged_up_to_version = version
        await self._session.flush()

    # --- batch idempotency --------------------------------------------------

    async def get_batch(self, batch_id: uuid.UUID, user_id: uuid.UUID) -> SyncBatch | None:
        stmt = select(SyncBatch).where(SyncBatch.batch_id == batch_id, SyncBatch.user_id == user_id)
        return (await self._session.execute(stmt)).scalar_one_or_none()

    def save_batch(
        self,
        *,
        batch_id: uuid.UUID,
        user_id: uuid.UUID,
        device_id: str,
        request_hash: str,
        response: dict[str, Any],
    ) -> SyncBatch:
        batch = SyncBatch(
            batch_id=batch_id,
            user_id=user_id,
            device_id=device_id,
            request_hash=request_hash,
            response=response,
        )
        self._session.add(batch)
        return batch

    # --- entity rows --------------------------------------------------------

    async def get_row(
        self, entity: SyncEntity, user_id: uuid.UUID, row_id: uuid.UUID
    ) -> Any | None:
        model = entity.model
        stmt = select(model).where(model.id == row_id, model.user_id == user_id)
        return (await self._session.execute(stmt)).scalar_one_or_none()

    async def find_by_natural_key(
        self,
        entity: SyncEntity,
        user_id: uuid.UUID,
        key_values: dict[str, Any],
        *,
        exclude_id: uuid.UUID | None = None,
    ) -> Any | None:
        """Live row matching the entity's natural key, if any (ADR rule 14).

        Tombstones are excluded: a deleted row must not pull a new one into a
        merge, otherwise a delete could never be followed by a fresh entry for
        the same day.
        """
        model = entity.model
        stmt = select(model).where(model.user_id == user_id, model.deleted_at.is_(None))
        for column_name in entity.policy.natural_key:
            if column_name == "user_id":
                continue
            column = getattr(model, column_name)
            value = key_values.get(column_name)
            if value is None or value == "":
                # ADR: `coalesce(ref_id, '')` -- NULL and '' are one key.
                stmt = stmt.where(or_(column.is_(None), column == ""))
            else:
                stmt = stmt.where(column == value)
        if exclude_id is not None:
            stmt = stmt.where(model.id != exclude_id)
        stmt = stmt.order_by(model.created_at.asc(), model.id.asc()).limit(1)
        return (await self._session.execute(stmt)).scalars().first()

    async def write_row(
        self,
        entity: SyncEntity,
        *,
        user_id: uuid.UUID,
        row: dict[str, Any],
        server_version: int,
        existing: Any | None,
    ) -> Any:
        """Insert or update one entity row from a merged dict.

        Only the fields declared on the entity's wire schema are written, plus
        `user_id` (always the JWT subject) and the freshly allocated
        `server_version` -- so a payload can never reach a column the entity
        did not publish.
        """
        model = entity.model
        fields = [name for name in entity.schema.model_fields if name not in ("user_id",)]

        target = existing
        if target is None:
            target = model(id=row["id"], user_id=user_id)
            self._session.add(target)

        for name in fields:
            if name == "server_version" or name not in row:
                continue
            setattr(target, name, normalise_stored(row[name]))
        target.user_id = user_id
        target.server_version = server_version
        await self._session.flush()
        return target

    async def rows_after(
        self,
        entity: SyncEntity,
        user_id: uuid.UUID,
        *,
        cursor: int,
        limit: int,
        include_tombstones: bool,
        upper_bound: int | None = None,
    ) -> list[Any]:
        """Rows in `(cursor, upper_bound]`, oldest version first.

        `upper_bound` is what keeps a multi-entity commit from being seen
        half-delivered. `pull` runs one of these per entity, each in its own
        READ COMMITTED snapshot, so a batch committing mid-loop is invisible to
        the statements already issued and visible to the ones that follow. With
        entities queried in a fixed order, the row that lands in an
        earlier-queried entity is missed while its higher-versioned sibling in
        a later one is delivered -- and the cursor then sits above the row that
        was never sent. Bounding every statement by a watermark read *before*
        the loop makes the whole page come from one consistent version range.
        """
        model = entity.model
        stmt = (
            select(model)
            .where(model.user_id == user_id, model.server_version > cursor)
            .order_by(model.server_version.asc())
            .limit(limit)
        )
        if upper_bound is not None:
            stmt = stmt.where(model.server_version <= upper_bound)
        if not include_tombstones:
            stmt = stmt.where(model.deleted_at.is_(None))
        return list((await self._session.execute(stmt)).scalars().all())

    # --- rule 14 bookkeeping ------------------------------------------------

    def record_merge(
        self, *, entity: str, row_id: uuid.UUID, user_id: uuid.UUID, merged_into: uuid.UUID
    ) -> None:
        self._session.add(
            SyncMergedRow(entity=entity, row_id=row_id, user_id=user_id, merged_into=merged_into)
        )

    async def merged_into_map(
        self, user_id: uuid.UUID, pairs: list[tuple[str, uuid.UUID]]
    ) -> dict[tuple[str, uuid.UUID], uuid.UUID]:
        if not pairs:
            return {}
        stmt = select(SyncMergedRow).where(
            SyncMergedRow.user_id == user_id,
            SyncMergedRow.row_id.in_([row_id for _, row_id in pairs]),
        )
        rows = (await self._session.execute(stmt)).scalars().all()
        return {(row.entity, row.row_id): row.merged_into for row in rows}

    # --- history ------------------------------------------------------------

    def add_history(
        self,
        *,
        entity: str,
        row_id: uuid.UUID,
        user_id: uuid.UUID,
        before: dict[str, Any] | None,
        after: dict[str, Any],
        server_version: int,
        device_id: str | None,
    ) -> None:
        self._session.add(
            RowHistory(
                entity=entity,
                row_id=row_id,
                user_id=user_id,
                before=before,
                after=after,
                server_version=server_version,
                device_id=device_id,
            )
        )

    # --- retention (ADR §4; a daily job calls these) ------------------------

    async def delete_expired_batches(self, *, now: datetime, days: int) -> int:
        cutoff = now - timedelta(days=days)
        result = await self._session.execute(delete(SyncBatch).where(SyncBatch.created_at < cutoff))
        return int(result.rowcount or 0)

    async def delete_expired_history(self, *, now: datetime, days: int) -> int:
        cutoff = now - timedelta(days=days)
        result = await self._session.execute(
            delete(RowHistory).where(RowHistory.created_at < cutoff)
        )
        return int(result.rowcount or 0)

    async def purge_tombstones(
        self, entity: SyncEntity, *, now: datetime, days: int
    ) -> dict[uuid.UUID, int]:
        """Physically delete tombstones older than `days`.

        Returns the highest purged `server_version` per user so the caller can
        raise `sync_user_state.purged_up_to_version` -- the watermark that
        turns a too-old cursor into `full_resync_required`.
        """
        model = entity.model
        cutoff = now - timedelta(days=days)
        stmt = select(model).where(model.deleted_at.is_not(None), model.deleted_at < cutoff)
        doomed = list((await self._session.execute(stmt)).scalars().all())
        watermarks: dict[uuid.UUID, int] = {}
        for row in doomed:
            watermarks[row.user_id] = max(watermarks.get(row.user_id, 0), int(row.server_version))
            await self._session.delete(row)
        await self._session.flush()
        return watermarks

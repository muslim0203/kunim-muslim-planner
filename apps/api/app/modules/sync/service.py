"""Push/pull orchestration.

Transaction shape (ADR §3 "Tranzaksiya chegarasi"): the whole batch runs in
one transaction, but every change is applied inside its **own SAVEPOINT**, so
one `rejected` change cannot roll back its siblings. The `sync_batches` row is
written in that same transaction, which is what makes the stored response
always agree with the state that was actually committed.

Logging discipline: this module logs entity names, counts and statuses only --
never a payload, a row id's contents, a token, or anything a user typed.
"""

from __future__ import annotations

import hashlib
import json
from datetime import UTC, datetime
from typing import Any

import structlog
from fastapi import HTTPException
from fastapi import status as http_status
from pydantic import ValidationError
from sqlalchemy.ext.asyncio import AsyncSession

from app.modules.sync import registry
from app.modules.sync.merge import (
    ChangeStatus,
    merge_natural_key_collision,
    merge_row,
    precheck,
)
from app.modules.sync.repository import SyncRepository
from app.modules.sync.schemas import (
    BATCH_RETENTION_DAYS,
    DEFAULT_PULL_LIMIT,
    MAX_CHANGES_PER_BATCH,
    MAX_PAYLOAD_BYTES,
    MAX_PULL_LIMIT,
    ROW_HISTORY_RETENTION_DAYS,
    TOMBSTONE_RETENTION_DAYS,
    ChangeResult,
    EntityLimits,
    LimitsResponse,
    PullResponse,
    PullRow,
    PushRequest,
    PushResponse,
    RejectReason,
    SyncChange,
    SyncOp,
    to_wire,
)
from app.modules.users.models import User

logger = structlog.get_logger(__name__)


def canonical_request_hash(changes: list[SyncChange]) -> str:
    """sha256 over the canonical JSON of `changes[]` (ADR §3 "Idempotentlik")."""
    payload = [change.model_dump(mode="json") for change in changes]
    canonical = json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def _payload_bytes(payload: dict[str, Any]) -> int:
    return len(json.dumps(payload, separators=(",", ":"), ensure_ascii=False).encode("utf-8"))


class SyncService:
    def __init__(self, session: AsyncSession) -> None:
        self._session = session
        self._repo = SyncRepository(session)

    # --- limits -------------------------------------------------------------

    def limits(self, *, now: datetime | None = None) -> LimitsResponse:
        server_time = now or datetime.now(UTC)
        return LimitsResponse(
            entities=[
                EntityLimits(
                    name=entity.name,
                    direction=entity.direction.value,
                    natural_key=list(entity.policy.natural_key),
                    adr_rules=list(entity.policy.adr_rules),
                )
                for entity in registry.all_entities()
            ],
            server_time=to_wire(server_time),
        )

    # --- push ---------------------------------------------------------------

    async def push(
        self, user: User, request: PushRequest, *, now: datetime | None = None
    ) -> PushResponse:
        server_time = now or datetime.now(UTC)

        if len(request.changes) > MAX_CHANGES_PER_BATCH:
            raise HTTPException(
                status_code=http_status.HTTP_400_BAD_REQUEST, detail="batch_too_large"
            )

        request_hash = canonical_request_hash(request.changes)
        stored = await self._repo.get_batch(request.batch_id, user.id)
        if stored is not None:
            if stored.request_hash == request_hash:
                # Replay: return the stored response, apply nothing.
                logger.info("sync_push_replayed", changes=len(request.changes))
                return PushResponse.model_validate(stored.response)
            raise HTTPException(status_code=http_status.HTTP_409_CONFLICT, detail="batch_id_reused")

        results: list[ChangeResult] = []
        for change in request.changes:
            savepoint = await self._session.begin_nested()
            try:
                result = await self._apply_change(
                    user=user,
                    change=change,
                    device_id=request.device_id,
                    server_time=server_time,
                )
            except Exception:
                await savepoint.rollback()
                # An unexpected failure is confined to this one change; the
                # closed reason list has no "server error", and `schema_invalid`
                # is the reason whose client action (leave in the outbox,
                # surface in diagnostics, do not resend) is correct here.
                logger.exception("sync_change_failed", entity=change.entity)
                result = ChangeResult(
                    client_seq=change.client_seq,
                    row_id=change.row_id,
                    entity=change.entity,
                    status=ChangeStatus.rejected,
                    reason=RejectReason.schema_invalid,
                )
            else:
                if result.status is ChangeStatus.rejected:
                    await savepoint.rollback()
                else:
                    await savepoint.commit()
            results.append(result)

        response = PushResponse(
            batch_id=request.batch_id,
            server_time=to_wire(server_time),
            max_server_version=await self._repo.max_server_version(user.id),
            results=results,
        )
        self._repo.save_batch(
            batch_id=request.batch_id,
            user_id=user.id,
            device_id=request.device_id,
            request_hash=request_hash,
            response=response.model_dump(mode="json"),
        )
        await self._session.commit()
        logger.info(
            "sync_push",
            changes=len(results),
            applied=sum(1 for r in results if r.status is ChangeStatus.applied),
            conflicts=sum(1 for r in results if r.status is ChangeStatus.conflict),
            rejected=sum(1 for r in results if r.status is ChangeStatus.rejected),
        )
        return response

    async def _apply_change(
        self,
        *,
        user: User,
        change: SyncChange,
        device_id: str,
        server_time: datetime,
    ) -> ChangeResult:
        def result(
            status_value: ChangeStatus,
            *,
            server_version: int | None = None,
            server_row: dict[str, Any] | None = None,
            reason: RejectReason | None = None,
        ) -> ChangeResult:
            return ChangeResult(
                client_seq=change.client_seq,
                row_id=change.row_id,
                entity=change.entity,
                status=status_value,
                server_version=server_version,
                server_row=server_row,
                reason=reason,
            )

        entity = registry.get_entity(change.entity)
        # Rules 23/24: unknown or pull-only entity.
        reason = precheck(entity=entity, payload_user_id=None, jwt_user_id=user.id)
        if reason is not None:
            return result(ChangeStatus.rejected, reason=reason)
        assert entity is not None  # narrowed by precheck

        if _payload_bytes(change.payload) > MAX_PAYLOAD_BYTES:
            return result(ChangeStatus.rejected, reason=RejectReason.payload_too_large)

        try:
            validated = entity.schema.model_validate(change.payload)
        except ValidationError:
            return result(ChangeStatus.rejected, reason=RejectReason.schema_invalid)

        incoming: dict[str, Any] = validated.model_dump()
        if incoming.get("id") != change.row_id:
            # ADR §3: `row_id` is `payload.id`; disagreement is a client bug.
            return result(ChangeStatus.rejected, reason=RejectReason.schema_invalid)

        # Rule 23 / §1: the payload may not claim another user's rows.
        reason = precheck(
            entity=entity, payload_user_id=incoming.get("user_id"), jwt_user_id=user.id
        )
        if reason is not None:
            return result(ChangeStatus.rejected, reason=reason)
        incoming["user_id"] = user.id

        existing_orm = await self._repo.get_row(entity, user.id, change.row_id)
        existing = self._row_dict(entity, existing_orm) if existing_orm is not None else None

        collision_orm = None
        if entity.policy.natural_key and change.op is SyncOp.upsert:
            if incoming.get("deleted_at") is None and (
                existing is None or existing.get("deleted_at") is not None
            ):
                collision_orm = await self._repo.find_by_natural_key(
                    entity, user.id, incoming, exclude_id=change.row_id
                )

        if collision_orm is not None:
            return await self._apply_natural_key_collision(
                entity=entity,
                user=user,
                change=change,
                incoming=incoming,
                existing_orm=existing_orm,
                collision_orm=collision_orm,
                device_id=device_id,
                server_time=server_time,
                result=result,
            )

        outcome = merge_row(
            policy=entity.policy,
            incoming=incoming,
            existing=existing,
            op=change.op,
            server_time=server_time,
        )
        if outcome.rejected or outcome.row is None:
            return result(ChangeStatus.rejected, reason=outcome.reason)

        merged = outcome.row
        if existing is not None and _rows_equal(merged, existing):
            # Nothing changed (rule 2 server-wins, rule 3 no-op): do not burn a
            # server_version, or every other device would re-pull an identical row.
            server_row = to_wire(existing) if outcome.status is ChangeStatus.conflict else None
            return result(
                outcome.status,
                server_version=int(existing["server_version"]),
                server_row=server_row,
            )

        version = await self._repo.allocate_server_version(user.id)
        merged["server_version"] = version
        row_orm = await self._repo.write_row(
            entity,
            user_id=user.id,
            row=merged,
            server_version=version,
            existing=existing_orm,
        )
        after = self._row_dict(entity, row_orm)
        self._repo.add_history(
            entity=entity.name,
            row_id=change.row_id,
            user_id=user.id,
            before=to_wire(existing) if existing is not None else None,
            after=to_wire(after),
            server_version=version,
            device_id=device_id,
        )
        server_row = to_wire(after) if outcome.status is ChangeStatus.conflict else None
        return result(outcome.status, server_version=version, server_row=server_row)

    async def _apply_natural_key_collision(
        self,
        *,
        entity: registry.SyncEntity,
        user: User,
        change: SyncChange,
        incoming: dict[str, Any],
        existing_orm: Any | None,
        collision_orm: Any,
        device_id: str,
        server_time: datetime,
        result: Any,
    ) -> ChangeResult:
        """ADR rule 14: two devices minted different ids for one natural key."""
        other = self._row_dict(entity, collision_orm)
        outcome = merge_natural_key_collision(
            policy=entity.policy,
            incoming=incoming,
            other=other,
            op=change.op,
            server_time=server_time,
        )
        if outcome.rejected or outcome.row is None:
            return result(ChangeStatus.rejected, reason=outcome.reason)

        merged = outcome.row
        survivor_id = merged["id"]
        incoming_survives = survivor_id == incoming["id"]
        loser_id = incoming["id"] if not incoming_survives else other["id"]
        loser_orm = existing_orm if not incoming_survives else collision_orm
        loser_before = (
            self._row_dict(entity, loser_orm) if loser_orm is not None else dict(incoming)
        )

        # Tombstone the loser *first*: a live-row unique index on the natural
        # key would otherwise reject the survivor's write.
        loser_version = await self._repo.allocate_server_version(user.id)
        loser_row = dict(loser_before)
        loser_row["deleted_at"] = server_time
        loser_row["updated_at"] = max(loser_before["updated_at"], server_time)
        loser_row["server_version"] = loser_version
        loser_orm = await self._repo.write_row(
            entity,
            user_id=user.id,
            row=loser_row,
            server_version=loser_version,
            existing=loser_orm,
        )
        self._repo.record_merge(
            entity=entity.name, row_id=loser_id, user_id=user.id, merged_into=survivor_id
        )
        self._repo.add_history(
            entity=entity.name,
            row_id=loser_id,
            user_id=user.id,
            before=to_wire(loser_before),
            after=to_wire(self._row_dict(entity, loser_orm)),
            server_version=loser_version,
            device_id=device_id,
        )

        survivor_orm = collision_orm if not incoming_survives else existing_orm
        survivor_before = self._row_dict(entity, survivor_orm) if survivor_orm else None
        survivor_version = await self._repo.allocate_server_version(user.id)
        merged["server_version"] = survivor_version
        survivor_orm = await self._repo.write_row(
            entity,
            user_id=user.id,
            row=merged,
            server_version=survivor_version,
            existing=survivor_orm,
        )
        after = self._row_dict(entity, survivor_orm)
        self._repo.add_history(
            entity=entity.name,
            row_id=survivor_id,
            user_id=user.id,
            before=to_wire(survivor_before) if survivor_before else None,
            after=to_wire(after),
            server_version=survivor_version,
            device_id=device_id,
        )
        # Always `conflict`: whatever the pushing device believed about at
        # least one of the two ids is no longer true.
        return result(
            ChangeStatus.conflict, server_version=survivor_version, server_row=to_wire(after)
        )

    # --- pull ---------------------------------------------------------------

    async def pull(
        self,
        user: User,
        *,
        cursor: int = 0,
        limit: int | None = None,
        entities: str | None = None,
        now: datetime | None = None,
    ) -> PullResponse:
        server_time = now or datetime.now(UTC)
        if cursor < 0:
            raise HTTPException(
                status_code=http_status.HTTP_400_BAD_REQUEST, detail="invalid_cursor"
            )
        page = DEFAULT_PULL_LIMIT if limit is None else limit
        page = max(1, min(page, MAX_PULL_LIMIT))  # ADR: larger requests are clamped, not rejected

        wanted = (
            {name.strip() for name in entities.split(",") if name.strip()} if entities else None
        )

        purged_up_to = await self._repo.purged_up_to(user.id)
        # `cursor == 0` is already a full load, so it never triggers a resync.
        if cursor > 0 and cursor < purged_up_to:
            return PullResponse(
                rows=[],
                next_cursor=cursor,
                has_more=False,
                full_resync_required=True,
                server_time=to_wire(server_time),
            )

        # ADR §3: tombstones are withheld at cursor == 0 -- a brand-new device
        # has nothing to delete, and this keeps the first load small.
        include_tombstones = cursor > 0

        collected: list[tuple[int, str, Any]] = []
        for entity in registry.all_entities():
            if not entity.pullable:
                continue  # upload-only never appears in a pull (rules 21-22)
            if wanted is not None and entity.name not in wanted:
                continue
            rows = await self._repo.rows_after(
                entity,
                user.id,
                cursor=cursor,
                limit=page + 1,
                include_tombstones=include_tombstones,
            )
            for row in rows:
                collected.append((int(row.server_version), entity.name, row))

        collected.sort(key=lambda item: (item[0], item[1]))
        has_more = len(collected) > page
        window = collected[:page]

        merged_map = await self._repo.merged_into_map(
            user.id, [(name, row.id) for _, name, row in window]
        )

        out_rows: list[PullRow] = []
        for version, name, row in window:
            entity = registry.get_entity(name)
            assert entity is not None
            wire_row = to_wire(self._row_dict(entity, row))
            merged_into = merged_map.get((name, row.id))
            if merged_into is not None:
                # ADR rule 14: the client keeps this tombstone but hides it.
                wire_row["merged_into"] = str(merged_into)
            out_rows.append(PullRow(entity=name, server_version=version, row=wire_row))

        next_cursor = window[-1][0] if window else cursor
        return PullResponse(
            rows=out_rows,
            next_cursor=next_cursor,
            has_more=has_more,
            full_resync_required=False,
            server_time=to_wire(server_time),
        )

    # --- retention (ADR §4; called by the daily cleanup job) ----------------

    async def run_retention(self, *, now: datetime | None = None) -> dict[str, int]:
        """Purge tombstones (90d), `row_history` (30d) and `sync_batches` (7d)."""
        moment = now or datetime.now(UTC)
        batches = await self._repo.delete_expired_batches(now=moment, days=BATCH_RETENTION_DAYS)
        history = await self._repo.delete_expired_history(
            now=moment, days=ROW_HISTORY_RETENTION_DAYS
        )
        tombstones = 0
        for entity in registry.all_entities():
            watermarks = await self._repo.purge_tombstones(
                entity, now=moment, days=TOMBSTONE_RETENTION_DAYS
            )
            for user_id, version in watermarks.items():
                tombstones += 1
                await self._repo.set_purged_up_to(user_id, version)
        await self._session.commit()
        return {"batches": batches, "row_history": history, "tombstones": tombstones}

    # --- helpers ------------------------------------------------------------

    @staticmethod
    def _row_dict(entity: registry.SyncEntity, row: Any) -> dict[str, Any]:
        """ORM row -> merge dict, through the entity's own wire schema."""
        return entity.schema.model_validate(row).model_dump()


def _rows_equal(left: dict[str, Any], right: dict[str, Any]) -> bool:
    keys = set(left) | set(right)
    return all(left.get(key) == right.get(key) for key in keys if key != "server_version")

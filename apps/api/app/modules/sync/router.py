"""HTTP surface for `/sync` -- ADR-0002 §3.

    POST /sync/push    200 PushResponse   | 400 batch_too_large
                                          | 409 batch_id_reused
                                          | 413 body_too_large
    GET  /sync/pull     200 PullResponse   | 400 invalid_cursor
    GET  /sync/limits   200 LimitsResponse

Every route requires an authenticated, active user and works only on that
user's rows: `user_id` comes from the JWT subject and is never read from the
request (ADR rule 4). There is no route parameterised by another user's id,
and no route that writes anything other than a syncable entity row -- which is
the ADR's AI invariant in structural form: sync is the only write path for
user data.

Error codes: the ADR writes `{"code": "batch_id_reused"}`, while this API's
shared handler (`app/core/errors.py`, not owned here) renders
`{"error": {"code": "http_409", "message": ..., "request_id": ...}}`. The
machine-readable token is therefore carried in `message`; the HTTP status is
the one the ADR specifies.
"""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, Request, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.deps import CurrentUser
from app.db.session import get_session
from app.modules.sync.schemas import (
    MAX_BODY_BYTES,
    MAX_PULL_LIMIT,
    LimitsResponse,
    PullResponse,
    PushRequest,
    PushResponse,
)
from app.modules.sync.service import SyncService

router = APIRouter(prefix="/sync", tags=["sync"])


async def get_sync_service(
    session: Annotated[AsyncSession, Depends(get_session)],
) -> SyncService:
    return SyncService(session)


SyncServiceDep = Annotated[SyncService, Depends(get_sync_service)]


@router.get(
    "/limits",
    response_model=LimitsResponse,
    summary="Batch/payload caps and the registered entity list",
    description="Clients read their caps from here instead of hardcoding them "
    "(ADR rule 5); 200/500 remain the local defaults.",
)
async def get_limits(user: CurrentUser, service: SyncServiceDep) -> LimitsResponse:
    return service.limits()


@router.post(
    "/push",
    response_model=PushResponse,
    summary="Apply a batch of client changes",
    description="Idempotent on `batch_id`: the same batch replayed returns the "
    "stored response without re-applying anything; a different payload under "
    "the same `batch_id` is a 409.",
)
async def push(
    request: Request,
    payload: PushRequest,
    user: CurrentUser,
    service: SyncServiceDep,
) -> PushResponse:
    content_length = request.headers.get("content-length")
    if content_length is not None and content_length.isdigit():
        if int(content_length) > MAX_BODY_BYTES:
            raise HTTPException(
                status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
                detail="body_too_large",
            )
    return await service.push(user, payload)


@router.get(
    "/pull",
    response_model=PullResponse,
    summary="Rows with `server_version > cursor`, oldest first",
    description="Tombstones are returned for `cursor > 0` only. A cursor older "
    "than the tombstone purge watermark answers `full_resync_required: true` "
    "with an empty `rows`.",
)
async def pull(
    user: CurrentUser,
    service: SyncServiceDep,
    cursor: Annotated[int, Query(description="Last applied server_version.")] = 0,
    # Deliberately unconstrained: the ADR says a larger `limit` is *clamped* to
    # 500, not rejected, so the clamp lives in the service and a client asking
    # for 5000 gets a 500-row page instead of a 422.
    limit: Annotated[int, Query(description="Page size; clamped to 500.")] = MAX_PULL_LIMIT,
    entities: Annotated[
        str | None, Query(description="Optional comma-separated entity filter.")
    ] = None,
) -> PullResponse:
    return await service.pull(user, cursor=cursor, limit=limit, entities=entities)

"""Wire contract for `/sync/*` -- exactly the shapes in `docs/adr/0002-sync.md` §3.

Timestamp discipline (ADR rule 13): every timestamp on the wire is UTC,
RFC 3339, **millisecond** precision, `Z` suffix -- `2026-09-12T08:15:30.123Z`.
Pydantic's own datetime serialisation emits `+00:00` and microseconds, so
outgoing rows go through `to_wire()` instead of `model_dump(mode="json")`.

Incoming timestamps are normalised to aware UTC by `UtcDatetime`: SQLite (the
test database) hands back naive datetimes for `DateTime(timezone=True)`
columns, and merging a naive against an aware datetime raises. Normalising in
one annotated type means neither `merge.py` nor any entity schema has to
remember.

Validators here raise `PydanticCustomError`, never a bare `ValueError`: the
shared handler in `app/core/errors.py` cannot JSON-serialise the latter.
"""

from __future__ import annotations

import uuid
from datetime import UTC, date, datetime
from enum import StrEnum
from typing import Annotated, Any, Literal

from pydantic import AfterValidator, BaseModel, ConfigDict, Field
from pydantic_core import PydanticCustomError

# --- limits (ADR §3 "Chegaralar" and rule 5) --------------------------------

MAX_CHANGES_PER_BATCH = 200
MAX_PAYLOAD_BYTES = 64 * 1024
MAX_BODY_BYTES = 4 * 1024 * 1024
MAX_PULL_LIMIT = 500
DEFAULT_PULL_LIMIT = 500

# --- retention (ADR §4) -----------------------------------------------------

TOMBSTONE_RETENTION_DAYS = 90
ROW_HISTORY_RETENTION_DAYS = 30
BATCH_RETENTION_DAYS = 7

# Rule 6: a client clock may run ahead by at most this much.
FUTURE_TOLERANCE_HOURS = 24


def _to_utc(value: datetime) -> datetime:
    """Attach UTC to a naive datetime, convert an aware one to UTC."""
    if value.tzinfo is None:
        return value.replace(tzinfo=UTC)
    return value.astimezone(UTC)


UtcDatetime = Annotated[datetime, AfterValidator(_to_utc)]
"""Timestamp type every syncable entity schema must use."""


def to_wire(value: Any) -> Any:
    """Recursively convert a merged row into JSON-safe wire values."""
    if isinstance(value, datetime):
        stamped = _to_utc(value)
        return stamped.strftime("%Y-%m-%dT%H:%M:%S.") + f"{stamped.microsecond // 1000:03d}Z"
    if isinstance(value, date):
        return value.isoformat()
    if isinstance(value, uuid.UUID):
        return str(value)
    if isinstance(value, StrEnum):
        return value.value
    if isinstance(value, dict):
        return {key: to_wire(item) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [to_wire(item) for item in value]
    return value


def normalise_stored(value: Any) -> Any:
    """Strip enums out of a nested structure bound for a JSON column.

    Datetimes and UUIDs are kept as objects (the column types handle them);
    enums are reduced to their string values so a round-trip through the
    database compares equal to what merge produced.
    """
    if isinstance(value, StrEnum):
        return value.value
    if isinstance(value, dict):
        return {key: normalise_stored(item) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [normalise_stored(item) for item in value]
    return value


# --- enums (ADR §3 tables) --------------------------------------------------


class SyncOp(StrEnum):
    upsert = "upsert"
    delete = "delete"


class ChangeStatus(StrEnum):
    applied = "applied"
    conflict = "conflict"
    rejected = "rejected"


class RejectReason(StrEnum):
    """Closed list -- ADR §3 "`rejected` sabablari". Nothing may be added
    without amending the ADR, because the client switches on these values."""

    updated_at_in_future = "updated_at_in_future"
    schema_invalid = "schema_invalid"
    unknown_entity = "unknown_entity"
    readonly_entity = "readonly_entity"
    foreign_user = "foreign_user"
    payload_too_large = "payload_too_large"


# --- row base ---------------------------------------------------------------


class SyncRowBase(BaseModel):
    """The seven mandatory sync columns (ADR §1), minus client-only `dirty`.

    `dirty` is deliberately absent: the ADR forbids it from ever crossing the
    wire, and `extra="forbid"` turns an attempt into `schema_invalid`.
    """

    model_config = ConfigDict(extra="forbid", from_attributes=True)

    id: uuid.UUID
    user_id: uuid.UUID | None = None
    """Advisory: the server always overwrites it with the JWT subject, and
    rejects a mismatch with `foreign_user` (ADR §1 / rule 23)."""
    created_at: UtcDatetime
    updated_at: UtcDatetime
    deleted_at: UtcDatetime | None = None
    server_version: int = 0


# --- push -------------------------------------------------------------------


class SyncChange(BaseModel):
    model_config = ConfigDict(extra="forbid")

    client_seq: int = Field(description="`sync_outbox.seq`; echoed back to match results.")
    entity: str = Field(min_length=1, max_length=64)
    row_id: uuid.UUID
    op: SyncOp
    base_version: int = Field(
        default=0,
        description="Last server_version the client knew. Advisory only -- the "
        "decision rests on the merge rules (ADR 'base_version ning roli').",
    )
    payload: dict[str, Any]


class PushRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    device_id: str = Field(min_length=1, max_length=64)
    batch_id: uuid.UUID = Field(description="Client-generated idempotency key.")
    # Not `max_length=200`: the ADR mandates HTTP 400 `batch_too_large`, and a
    # pydantic length constraint would produce a 422 instead.
    changes: list[SyncChange]


class ChangeResult(BaseModel):
    model_config = ConfigDict(extra="forbid")

    client_seq: int
    row_id: uuid.UUID
    entity: str
    status: ChangeStatus
    server_version: int | None = None
    server_row: dict[str, Any] | None = None
    """Present exactly when `status == conflict` (ADR: otherwise the client
    would be forced into an immediate pull)."""
    reason: RejectReason | None = None
    """Mandatory exactly when `status == rejected`."""


class PushResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    batch_id: uuid.UUID
    server_time: str
    max_server_version: int
    results: list[ChangeResult]


# --- pull -------------------------------------------------------------------


class PullRow(BaseModel):
    model_config = ConfigDict(extra="forbid")

    entity: str
    server_version: int
    row: dict[str, Any]


class PullResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    rows: list[PullRow]
    next_cursor: int
    has_more: bool
    full_resync_required: bool
    server_time: str


# --- limits -----------------------------------------------------------------


class EntityLimits(BaseModel):
    model_config = ConfigDict(extra="forbid")

    name: str
    direction: str
    natural_key: list[str]
    adr_rules: list[int]


class LimitsResponse(BaseModel):
    """`GET /sync/limits` (ADR rule 5: clients read the caps, never hardcode)."""

    model_config = ConfigDict(extra="forbid")

    max_changes_per_batch: int = MAX_CHANGES_PER_BATCH
    max_payload_bytes: int = MAX_PAYLOAD_BYTES
    max_body_bytes: int = MAX_BODY_BYTES
    max_pull_limit: int = MAX_PULL_LIMIT
    default_pull_limit: int = DEFAULT_PULL_LIMIT
    tombstone_retention_days: int = TOMBSTONE_RETENTION_DAYS
    row_history_retention_days: int = ROW_HISTORY_RETENTION_DAYS
    batch_retention_days: int = BATCH_RETENTION_DAYS
    future_tolerance_hours: int = FUTURE_TOLERANCE_HOURS
    rejected_reasons: list[str] = Field(default_factory=lambda: [r.value for r in RejectReason])
    entities: list[EntityLimits]
    server_time: str


# --- error codes (ADR §3 "Chegaralar" / "Idempotentlik") --------------------

ErrorCode = Literal["batch_too_large", "batch_id_reused", "body_too_large", "invalid_cursor"]


def invalid_payload(message: str, value: str) -> PydanticCustomError:
    """Build the error type field validators in entity schemas should raise."""
    return PydanticCustomError("sync_invalid_payload", message, {"value": value})

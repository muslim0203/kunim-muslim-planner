"""Two-simulated-client harness for `/sync` (Phase-2 DoD).

`SimClient` is a deliberately dumb stand-in for `apps/mobile/lib/core/sync/`:
it owns a local row store, an append-only outbox and a pull cursor, and it
applies whatever the server answers **without any merge logic of its own**
(ADR rule 8: "Klientda merge mantiqi yo'q"). Two of them against one test app
is what lets the conflict matrix be driven end to end instead of only through
`merge.py`.

Fixtures mirror `tests/test_auth.py` / `tests/test_preferences.py` (see those
modules for why they live in the test modules rather than in `conftest.py`),
with one addition: SQLite needs the documented pysqlite workaround before
SAVEPOINTs behave, and every push depends on SAVEPOINT isolation
(ADR section 3 "Tranzaksiya chegarasi").
"""

from __future__ import annotations

import json
import uuid
from collections.abc import AsyncGenerator
from datetime import UTC, datetime, timedelta
from typing import Any

import pytest
from httpx import ASGITransport, AsyncClient
from sqlalchemy import event
from sqlalchemy.ext.asyncio import (
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)
from sqlalchemy.pool import StaticPool

from app.core.config import Settings
from app.db.base import Base
from app.main import app
from app.modules.auth.ratelimit import RateLimiter, auth_rate_limit, set_rate_limiter

# Importing the sync models registers the sync tables on Base.metadata, which
# `create_all` below relies on.
from app.modules.sync import models as sync_models  # noqa: F401

PASSWORD = "correct-horse-battery"
TEST_JWT_SECRET = "test-secret-key-that-is-comfortably-longer-than-32-bytes-ok!!"


def _test_settings() -> Settings:
    return Settings(_env_file=None, JWT_SECRET=TEST_JWT_SECRET)


@pytest.fixture
async def session_factory() -> AsyncGenerator[async_sessionmaker[AsyncSession], None]:
    engine = create_async_engine(
        "sqlite+aiosqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )

    # pysqlite opens transactions implicitly and at the wrong moment, which
    # makes SAVEPOINT unreliable. The documented fix: turn the driver's
    # implicit BEGIN off and emit it ourselves. Without this, "one rejected
    # change must not roll back its siblings" cannot be tested honestly.
    @event.listens_for(engine.sync_engine, "connect")
    def _disable_implicit_begin(dbapi_connection: Any, _record: Any) -> None:
        dbapi_connection.isolation_level = None

    @event.listens_for(engine.sync_engine, "begin")
    def _emit_begin(connection: Any) -> None:
        connection.exec_driver_sql("BEGIN")

    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

    factory = async_sessionmaker(bind=engine, expire_on_commit=False)
    try:
        yield factory
    finally:
        await engine.dispose()


@pytest.fixture
async def client(
    session_factory: async_sessionmaker[AsyncSession],
) -> AsyncGenerator[AsyncClient, None]:
    from app.core.config import get_settings
    from app.db.session import get_session

    async def _override_session() -> AsyncGenerator[AsyncSession, None]:
        async with session_factory() as session:
            yield session

    app.dependency_overrides[get_session] = _override_session
    app.dependency_overrides[get_settings] = _test_settings
    app.dependency_overrides[auth_rate_limit] = lambda: None
    set_rate_limiter(RateLimiter(enabled=False))

    transport = ASGITransport(app=app)
    try:
        async with AsyncClient(transport=transport, base_url="http://test") as ac:
            yield ac
    finally:
        app.dependency_overrides.clear()
        set_rate_limiter(None)


async def register_and_login(
    http: AsyncClient, email: str, device_id: str = "device-a", password: str = PASSWORD
) -> dict:
    await http.post("/auth/register", json={"email": email, "password": password, "locale": "en"})
    response = await http.post(
        "/auth/login", json={"email": email, "password": password, "device_id": device_id}
    )
    assert response.status_code == 200, response.text
    return response.json()


def auth_header(tokens: dict) -> dict[str, str]:
    return {"Authorization": f"Bearer {tokens['access_token']}"}


# --- wire helpers ------------------------------------------------------------

WIRE_FORMAT = "%Y-%m-%dT%H:%M:%S.%f"


def wire_time(moment: datetime) -> str:
    """RFC 3339, UTC, millisecond precision, `Z` (ADR rule 13)."""
    moment = moment.astimezone(UTC)
    return moment.strftime("%Y-%m-%dT%H:%M:%S.") + f"{moment.microsecond // 1000:03d}Z"


BASE_TIME = datetime(2026, 9, 12, 8, 0, 0, tzinfo=UTC)


def preferences_payload(
    row_id: uuid.UUID | str,
    *,
    updated_at: datetime,
    created_at: datetime | None = None,
    deleted_at: datetime | None = None,
    theme: str = "system",
    first_day_of_week: int = 1,
    analytics: bool = False,
    server_version: int = 0,
) -> dict[str, Any]:
    """A complete, valid `preferences` wire row."""
    return {
        "id": str(row_id),
        "created_at": wire_time(created_at or updated_at),
        "updated_at": wire_time(updated_at),
        "deleted_at": wire_time(deleted_at) if deleted_at else None,
        "server_version": server_version,
        "prayer_settings": {
            "method": "muslim_world_league",
            "madhab": "shafi",
            "high_latitude_rule": "middle_of_the_night",
            "adjustments": {"fajr": 0, "dhuhr": 0, "asr": 0, "maghrib": 0, "isha": 0},
            "location": {"lat": None, "lon": None, "city": None, "timezone": None},
        },
        "notifications": {
            "prayer": True,
            "habits": True,
            "tasks": True,
            "quran": True,
            "wellbeing": True,
            "ai_recommendations": True,
            "reviews": True,
            "system": True,
            "quiet_hours": {"enabled": False, "start": "22:00", "end": "06:00"},
        },
        "privacy_consents": {
            "analytics": analytics,
            "ai_personalization": False,
            "dw_cloud_stats": False,
        },
        "ui": {"theme": theme, "first_day_of_week": first_day_of_week},
    }


# --- the simulated client ----------------------------------------------------


class SimClient:
    """One simulated device: local rows + outbox + cursor, no merge logic."""

    def __init__(self, http: AsyncClient, tokens: dict, device_id: str) -> None:
        self.http = http
        self.tokens = tokens
        self.device_id = device_id
        self.cursor = 0
        self.rows: dict[tuple[str, str], dict[str, Any]] = {}
        self.dirty: set[tuple[str, str]] = set()
        self.outbox: list[dict[str, Any]] = []
        self.rejections: list[dict[str, Any]] = []
        self._seq = 0

    # -- local write ---------------------------------------------------------

    def stage(self, entity: str, payload: dict[str, Any], op: str = "upsert") -> dict[str, Any]:
        """Local row write + outbox insert -- one indivisible step (ADR rule 1)."""
        self._seq += 1
        key = (entity, payload["id"])
        self.rows[key] = dict(payload)
        self.dirty.add(key)
        change = {
            "client_seq": self._seq,
            "entity": entity,
            "row_id": payload["id"],
            "op": op,
            "base_version": int(payload.get("server_version") or 0),
            "payload": dict(payload),
        }
        self.outbox.append(change)
        return change

    def stage_delete(self, entity: str, row_id: str, *, deleted_at: datetime) -> dict[str, Any]:
        row = dict(self.rows[(entity, row_id)])
        row["deleted_at"] = wire_time(deleted_at)
        row["updated_at"] = wire_time(deleted_at)
        return self.stage(entity, row, op="delete")

    # -- push ----------------------------------------------------------------

    async def push(self, *, batch_id: str | None = None, changes: list | None = None):
        body = {
            "device_id": self.device_id,
            "batch_id": batch_id or str(uuid.uuid4()),
            "changes": changes if changes is not None else self.outbox,
        }
        response = await self.http.post("/sync/push", json=body, headers=self.headers)
        if response.status_code == 200 and changes is None:
            self.apply_push_response(response.json())
        return response

    @property
    def headers(self) -> dict[str, str]:
        return auth_header(self.tokens)

    def apply_push_response(self, body: dict[str, Any]) -> None:
        """Exactly the client actions in the ADR's status table."""
        keep: list[dict[str, Any]] = []
        by_seq = {change["client_seq"]: change for change in self.outbox}
        for result in body["results"]:
            key = (result["entity"], result["row_id"])
            if result["status"] == "applied":
                if key in self.rows:
                    self.rows[key]["server_version"] = result["server_version"]
                self.dirty.discard(key)
            elif result["status"] == "conflict":
                # Replace the local row wholesale; never resend.
                server_row = result["server_row"]
                self.dirty.discard(key)
                if server_row["id"] != result["row_id"]:
                    # ADR rule 14: the natural key was merged into another id.
                    # The client keeps both rows -- the survivor now, and the
                    # `merged_into` tombstone for this id on the next pull.
                    self.rows.pop(key, None)
                self.rows[(result["entity"], server_row["id"])] = server_row
            else:
                self.rejections.append(result)
                if result["reason"] == "updated_at_in_future":
                    # Re-stamp with "now" and put it back in the outbox.
                    change = dict(by_seq[result["client_seq"]])
                    payload = dict(change["payload"])
                    payload["updated_at"] = wire_time(datetime.now(UTC))
                    change["payload"] = payload
                    self.rows[key] = payload
                    keep.append(change)
                # Every other reason: drop it from the outbox (unknown_entity,
                # readonly_entity, foreign_user) or leave it to diagnostics.
        self.outbox = keep

    # -- pull ----------------------------------------------------------------

    async def pull(self, *, entities: str | None = None, limit: int | None = None):
        url = f"/sync/pull?cursor={self.cursor}"
        if limit is not None:
            url += f"&limit={limit}"
        if entities is not None:
            url += f"&entities={entities}"
        response = await self.http.get(url, headers=self.headers)
        if response.status_code == 200:
            self.apply_pull_response(response.json())
        return response

    def apply_pull_response(self, body: dict[str, Any]) -> None:
        if body["full_resync_required"]:
            # ADR section 4: keep the outbox and every dirty row, drop the rest,
            # reset the cursor. Partial recovery is forbidden.
            self.rows = {key: row for key, row in self.rows.items() if key in self.dirty}
            self.cursor = 0
            return
        for entry in body["rows"]:
            self.rows[(entry["entity"], entry["row"]["id"])] = entry["row"]
        self.cursor = body["next_cursor"]

    async def pull_all(self, *, entities: str | None = None, limit: int | None = None) -> int:
        """Pull pages until the server says there are none left."""
        pages = 0
        while True:
            response = await self.pull(entities=entities, limit=limit)
            assert response.status_code == 200, response.text
            pages += 1
            body = response.json()
            if body["full_resync_required"]:
                continue
            if not body["has_more"]:
                return pages

    async def sync(self) -> None:
        """Push, then the mandatory pull (ADR section 3, last bullet)."""
        if self.outbox:
            response = await self.push()
            assert response.status_code == 200, response.text
        await self.pull_all()

    # -- assertions ----------------------------------------------------------

    def snapshot(self) -> str:
        """Canonical JSON of the local store -- for byte-identical comparisons."""
        return json.dumps(
            {f"{entity}:{row_id}": row for (entity, row_id), row in sorted(self.rows.items())},
            sort_keys=True,
            separators=(",", ":"),
        )

    def live(self, entity: str) -> list[dict[str, Any]]:
        return [
            row
            for (name, _), row in sorted(self.rows.items())
            if name == entity and not row.get("deleted_at")
        ]


@pytest.fixture
async def two_clients(client: AsyncClient):
    """Two devices of the same user, both starting empty."""
    tokens = await register_and_login(client, "sync-two@example.com", device_id="device-a")
    return (
        SimClient(client, tokens, "device-a"),
        SimClient(client, tokens, "device-b"),
    )


# --- harness self-tests ------------------------------------------------------


async def test_harness_two_clients_share_one_user(two_clients) -> None:
    alice, bob = two_clients
    assert alice.tokens["access_token"] == bob.tokens["access_token"]
    assert alice.device_id != bob.device_id


async def test_harness_stage_writes_row_and_outbox_together(two_clients) -> None:
    """The outbox invariant the ADR puts first: never a row without an entry."""
    alice, _ = two_clients
    row_id = str(uuid.uuid4())
    alice.stage("preferences", preferences_payload(row_id, updated_at=BASE_TIME))
    assert ("preferences", row_id) in alice.rows
    assert len(alice.outbox) == 1
    assert alice.outbox[0]["row_id"] == row_id


async def test_harness_wire_time_is_rfc3339_millis_utc(two_clients) -> None:
    """ADR rule 13: UTC, RFC 3339, millisecond precision, `Z`."""
    stamp = wire_time(BASE_TIME + timedelta(microseconds=123456))
    assert stamp == "2026-09-12T08:00:00.123Z"

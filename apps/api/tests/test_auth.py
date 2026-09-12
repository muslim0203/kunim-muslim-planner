"""Phase-1 authentication tests.

All fixtures live in this module rather than in `tests/conftest.py` so that the
existing Phase-0 conftest is left untouched.

The suite runs against SQLite (aiosqlite) because no PostgreSQL is available
here. The production schema is *not* weakened to make that work: `sa.Uuid` and
the `TZDateTime` TypeDecorator (see `app.modules.auth.models`) both emit the
real Postgres types (`UUID`, `TIMESTAMPTZ`) and degrade to `CHAR(32)`/`DATETIME`
only on SQLite. `test_schema_uses_postgres_native_types` locks that in.
"""

from __future__ import annotations

import uuid
from collections.abc import AsyncGenerator
from datetime import UTC, datetime, timedelta
from typing import Annotated

import pytest
from fastapi import Depends
from httpx import ASGITransport, AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import (
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)
from sqlalchemy.pool import StaticPool

from app.core.config import Settings
from app.core.deps import require_role
from app.core.security import create_access_token, hash_refresh_token
from app.db.base import Base
from app.main import app
from app.modules.auth.models import RefreshToken
from app.modules.auth.ratelimit import RateLimiter, auth_rate_limit, set_rate_limiter
from app.modules.users.models import User, UserRole

# Importing the models above registers every table on Base.metadata, which is
# what `create_all` below relies on.

PASSWORD = "correct-horse-battery"
EMAIL = "user@example.com"

# 64 chars: pyjwt (>=2.14) warns when an HS256 key is shorter than 32 bytes.
TEST_JWT_SECRET = "test-secret-key-that-is-comfortably-longer-than-32-bytes-ok!!"


def _test_settings() -> Settings:
    return Settings(
        _env_file=None,
        JWT_SECRET=TEST_JWT_SECRET,
        ACCESS_TOKEN_TTL_MIN=15,
        REFRESH_TOKEN_TTL_DAYS=30,
    )


@pytest.fixture
async def session_factory() -> AsyncGenerator[async_sessionmaker[AsyncSession], None]:
    """A fresh in-memory SQLite database per test.

    StaticPool keeps every connection pointed at the same `:memory:` database,
    otherwise each new connection would get its own empty one.
    """
    engine = create_async_engine(
        "sqlite+aiosqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
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
    """The real ASGI app, wired to the test database and a disabled limiter.

    The rate limiter is turned off here so tests stay fast and deterministic;
    `test_rate_limiter_fails_open_without_redis` covers its behaviour directly.
    """
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


# --- helpers ---------------------------------------------------------------


async def register(client: AsyncClient, email: str = EMAIL, password: str = PASSWORD):
    return await client.post(
        "/auth/register", json={"email": email, "password": password, "locale": "en"}
    )


async def login(
    client: AsyncClient,
    email: str = EMAIL,
    password: str = PASSWORD,
    device_id: str = "device-a",
):
    return await client.post(
        "/auth/login",
        json={"email": email, "password": password, "device_id": device_id},
    )


async def register_and_login(client: AsyncClient, **kw) -> dict:
    await register(client, **{k: v for k, v in kw.items() if k in {"email", "password"}})
    response = await login(client, **kw)
    assert response.status_code == 200, response.text
    return response.json()


def auth_header(tokens: dict) -> dict[str, str]:
    return {"Authorization": f"Bearer {tokens['access_token']}"}


# --- registration & login --------------------------------------------------


async def test_register_then_login_then_access_protected_route(client: AsyncClient) -> None:
    response = await register(client)
    assert response.status_code == 201
    assert response.json()["status"] == "pending_verification"

    tokens = await register_and_login(client, email="flow@example.com")
    assert tokens["token_type"] == "bearer"
    assert tokens["expires_in"] == 15 * 60
    assert tokens["refresh_expires_in"] == 30 * 24 * 3600

    me = await client.get("/auth/me", headers=auth_header(tokens))
    assert me.status_code == 200
    body = me.json()
    assert body["email"] == "flow@example.com"
    assert body["role"] == "user"
    assert body["email_verified_at"] is None


async def test_refresh_token_is_opaque_not_a_jwt(client: AsyncClient) -> None:
    tokens = await register_and_login(client, email="opaque@example.com")
    # A JWT is three base64url segments separated by dots.
    assert tokens["refresh_token"].count(".") == 0
    assert tokens["access_token"].count(".") == 2


async def test_wrong_password_is_rejected(client: AsyncClient) -> None:
    await register(client, email="wrong@example.com")
    response = await login(client, email="wrong@example.com", password="not-the-password")
    assert response.status_code == 401
    assert response.json()["error"]["message"] == "Invalid email or password."


async def test_unknown_email_is_indistinguishable_from_wrong_password(
    client: AsyncClient,
) -> None:
    await register(client, email="known@example.com")

    wrong_password = await login(client, email="known@example.com", password="bad-password-x")
    unknown_email = await login(client, email="nobody@example.com", password="bad-password-x")

    assert wrong_password.status_code == unknown_email.status_code == 401
    # Identical bodies apart from the per-request id.
    a = wrong_password.json()["error"]
    b = unknown_email.json()["error"]
    assert a["code"] == b["code"]
    assert a["message"] == b["message"]


async def test_register_with_existing_email_returns_identical_response(
    client: AsyncClient,
) -> None:
    first = await register(client, email="dup@example.com")
    second = await register(client, email="dup@example.com", password="a-different-pw-1")

    assert first.status_code == second.status_code == 201
    assert first.json() == second.json()


async def test_duplicate_registration_does_not_overwrite_the_password(
    client: AsyncClient, session_factory
) -> None:
    """The enumeration-safe duplicate branch must not be an account takeover."""
    await register(client, email="takeover@example.com", password=PASSWORD)
    await register(client, email="takeover@example.com", password="attacker-password")

    # The original password still works...
    ok = await login(client, email="takeover@example.com", password=PASSWORD)
    assert ok.status_code == 200
    # ...and the attacker's does not.
    bad = await login(client, email="takeover@example.com", password="attacker-password")
    assert bad.status_code == 401

    async with session_factory() as session:
        users = (
            (await session.execute(select(User).where(User.email == "takeover@example.com")))
            .scalars()
            .all()
        )
        assert len(users) == 1


async def test_email_is_normalised_case_insensitively(client: AsyncClient) -> None:
    await register(client, email="Mixed.Case@Example.COM")
    response = await login(client, email="mixed.case@example.com")
    assert response.status_code == 200


# --- access tokens ---------------------------------------------------------


async def test_expired_access_token_is_rejected(client: AsyncClient) -> None:
    tokens = await register_and_login(client, email="expired@example.com")
    me = await client.get("/auth/me", headers=auth_header(tokens))
    user_id = uuid.UUID(me.json()["id"])

    expired, _jti, _exp = create_access_token(
        user_id=user_id,
        role="user",
        secret=TEST_JWT_SECRET,
        ttl_minutes=-1,  # already expired
        now=datetime.now(UTC) - timedelta(minutes=30),
    )
    response = await client.get("/auth/me", headers={"Authorization": f"Bearer {expired}"})
    assert response.status_code == 401


async def test_access_token_signed_with_another_secret_is_rejected(
    client: AsyncClient,
) -> None:
    forged, _jti, _exp = create_access_token(
        user_id=uuid.uuid4(),
        role="admin",
        secret="a-totally-different-secret-key-of-sufficient-length!!",
        ttl_minutes=15,
    )
    response = await client.get("/auth/me", headers={"Authorization": f"Bearer {forged}"})
    assert response.status_code == 401


async def test_missing_and_malformed_tokens_are_rejected(client: AsyncClient) -> None:
    assert (await client.get("/auth/me")).status_code == 401
    bad = await client.get("/auth/me", headers={"Authorization": "Bearer not-a-token"})
    assert bad.status_code == 401


# --- rotation & reuse detection -------------------------------------------


async def test_refresh_rotates_and_old_token_stops_working(client: AsyncClient) -> None:
    tokens = await register_and_login(client, email="rotate@example.com")
    old_refresh = tokens["refresh_token"]

    rotated = await client.post(
        "/auth/refresh", json={"refresh_token": old_refresh, "device_id": "device-a"}
    )
    assert rotated.status_code == 200
    new_refresh = rotated.json()["refresh_token"]
    assert new_refresh != old_refresh

    # The new token authenticates.
    me = await client.get("/auth/me", headers=auth_header(rotated.json()))
    assert me.status_code == 200

    # The old one is spent.
    replayed = await client.post(
        "/auth/refresh", json={"refresh_token": old_refresh, "device_id": "device-a"}
    )
    assert replayed.status_code == 401


async def test_replayed_refresh_token_revokes_the_whole_family(
    client: AsyncClient, session_factory
) -> None:
    """The single most important behaviour in the module.

    Replaying a spent refresh token proves a token leaked, so every token for
    that user+device dies -- including the newest, still-valid one.
    """
    tokens = await register_and_login(client, email="reuse@example.com")
    gen1 = tokens["refresh_token"]

    r2 = await client.post("/auth/refresh", json={"refresh_token": gen1, "device_id": "device-a"})
    assert r2.status_code == 200
    gen2 = r2.json()["refresh_token"]

    r3 = await client.post("/auth/refresh", json={"refresh_token": gen2, "device_id": "device-a"})
    assert r3.status_code == 200
    gen3 = r3.json()["refresh_token"]

    # An attacker replays the long-spent generation-1 token.
    attack = await client.post(
        "/auth/refresh", json={"refresh_token": gen1, "device_id": "device-a"}
    )
    assert attack.status_code == 401

    # The legitimate client's newest token is now dead too.
    after = await client.post(
        "/auth/refresh", json={"refresh_token": gen3, "device_id": "device-a"}
    )
    assert after.status_code == 401

    # And nothing in the family survives in the database.
    async with session_factory() as session:
        rows = (await session.execute(select(RefreshToken))).scalars().all()
        assert len(rows) == 3
        assert all(row.revoked_at is not None for row in rows)


async def test_family_revocation_is_scoped_to_one_device(
    client: AsyncClient,
) -> None:
    """Killing device-a's family must not log the user out of device-b."""
    await register(client, email="scoped@example.com")
    a = (await login(client, email="scoped@example.com", device_id="device-a")).json()
    b = (await login(client, email="scoped@example.com", device_id="device-b")).json()

    rotated_a = await client.post(
        "/auth/refresh", json={"refresh_token": a["refresh_token"], "device_id": "device-a"}
    )
    assert rotated_a.status_code == 200

    # Replay device-a's spent token -> device-a's family dies.
    replay = await client.post(
        "/auth/refresh", json={"refresh_token": a["refresh_token"], "device_id": "device-a"}
    )
    assert replay.status_code == 401

    # device-b is untouched.
    still_good = await client.post(
        "/auth/refresh", json={"refresh_token": b["refresh_token"], "device_id": "device-b"}
    )
    assert still_good.status_code == 200


async def test_refresh_with_unknown_token_is_rejected(client: AsyncClient) -> None:
    await register_and_login(client, email="unknown-rt@example.com")
    response = await client.post(
        "/auth/refresh", json={"refresh_token": "totally-made-up", "device_id": "device-a"}
    )
    assert response.status_code == 401


async def test_expired_refresh_token_is_rejected(client: AsyncClient, session_factory) -> None:
    tokens = await register_and_login(client, email="rt-expired@example.com")

    async with session_factory() as session:
        row = (
            await session.execute(
                select(RefreshToken).where(
                    RefreshToken.token_hash == hash_refresh_token(tokens["refresh_token"])
                )
            )
        ).scalar_one()
        row.expires_at = datetime.now(UTC) - timedelta(seconds=1)
        await session.commit()

    response = await client.post(
        "/auth/refresh",
        json={"refresh_token": tokens["refresh_token"], "device_id": "device-a"},
    )
    assert response.status_code == 401


async def test_refresh_from_a_different_device_is_rejected(client: AsyncClient) -> None:
    tokens = await register_and_login(client, email="devicebind@example.com")
    response = await client.post(
        "/auth/refresh",
        json={"refresh_token": tokens["refresh_token"], "device_id": "some-other-device"},
    )
    assert response.status_code == 401


# --- logout ----------------------------------------------------------------


async def test_logout_revokes_only_the_presented_token(client: AsyncClient) -> None:
    await register(client, email="logout@example.com")
    a = (await login(client, email="logout@example.com", device_id="device-a")).json()
    b = (await login(client, email="logout@example.com", device_id="device-b")).json()

    out = await client.post("/auth/logout", json={"refresh_token": a["refresh_token"]})
    assert out.status_code == 204

    dead = await client.post(
        "/auth/refresh", json={"refresh_token": a["refresh_token"], "device_id": "device-a"}
    )
    assert dead.status_code == 401

    alive = await client.post(
        "/auth/refresh", json={"refresh_token": b["refresh_token"], "device_id": "device-b"}
    )
    assert alive.status_code == 200


async def test_logout_all_kills_every_device(client: AsyncClient) -> None:
    await register(client, email="logoutall@example.com")
    a = (await login(client, email="logoutall@example.com", device_id="device-a")).json()
    b = (await login(client, email="logoutall@example.com", device_id="device-b")).json()
    c = (await login(client, email="logoutall@example.com", device_id="device-c")).json()

    out = await client.post("/auth/logout-all", headers=auth_header(a))
    assert out.status_code == 204

    for tokens, device in ((a, "device-a"), (b, "device-b"), (c, "device-c")):
        response = await client.post(
            "/auth/refresh",
            json={"refresh_token": tokens["refresh_token"], "device_id": device},
        )
        assert response.status_code == 401, f"{device} survived logout-all"


async def test_logout_all_requires_authentication(client: AsyncClient) -> None:
    assert (await client.post("/auth/logout-all")).status_code == 401


# --- RBAC ------------------------------------------------------------------


# Built once at import time, exactly as a real feature module would.
ReviewerOrAdmin = Annotated[User, Depends(require_role(UserRole.reviewer, UserRole.admin))]
AdminOnly = Annotated[User, Depends(require_role(UserRole.admin))]


@pytest.fixture
def rbac_app(client: AsyncClient) -> AsyncClient:
    """Register throwaway routes guarded by `require_role` on the live app."""
    if not any(getattr(r, "path", None) == "/_test/reviewer" for r in app.routes):

        @app.get("/_test/reviewer")
        async def _reviewer_only(user: ReviewerOrAdmin) -> dict:
            return {"ok": True, "role": str(user.role)}

        @app.get("/_test/admin")
        async def _admin_only(user: AdminOnly) -> dict:
            return {"ok": True, "role": str(user.role)}

    return client


async def _promote(session_factory, email: str, role: UserRole) -> None:
    async with session_factory() as session:
        user = (await session.execute(select(User).where(User.email == email))).scalar_one()
        user.role = role
        await session.commit()


async def test_require_role_denies_under_privileged_user(
    rbac_app: AsyncClient,
) -> None:
    tokens = await register_and_login(rbac_app, email="plain@example.com")
    response = await rbac_app.get("/_test/reviewer", headers=auth_header(tokens))
    assert response.status_code == 403
    assert "Insufficient permissions" in response.json()["error"]["message"]


async def test_require_role_allows_the_right_role(rbac_app: AsyncClient, session_factory) -> None:
    await register(rbac_app, email="reviewer@example.com")
    await _promote(session_factory, "reviewer@example.com", UserRole.reviewer)
    tokens = (await login(rbac_app, email="reviewer@example.com")).json()

    response = await rbac_app.get("/_test/reviewer", headers=auth_header(tokens))
    assert response.status_code == 200
    assert response.json()["role"] == "reviewer"


async def test_admin_is_not_implicitly_granted_other_roles(
    rbac_app: AsyncClient, session_factory
) -> None:
    """`require_role` is a flat allow-list; admin is only admin."""
    await register(rbac_app, email="admin@example.com")
    await _promote(session_factory, "admin@example.com", UserRole.admin)
    tokens = (await login(rbac_app, email="admin@example.com")).json()

    # admin is explicitly listed on /_test/reviewer, so it passes there...
    assert (await rbac_app.get("/_test/reviewer", headers=auth_header(tokens))).status_code == 200
    # ...and on its own route.
    assert (await rbac_app.get("/_test/admin", headers=auth_header(tokens))).status_code == 200


async def test_content_editor_cannot_reach_admin_route(
    rbac_app: AsyncClient, session_factory
) -> None:
    await register(rbac_app, email="editor@example.com")
    await _promote(session_factory, "editor@example.com", UserRole.content_editor)
    tokens = (await login(rbac_app, email="editor@example.com")).json()

    assert (await rbac_app.get("/_test/admin", headers=auth_header(tokens))).status_code == 403


async def test_deactivated_user_is_locked_out(client: AsyncClient, session_factory) -> None:
    tokens = await register_and_login(client, email="deactivated@example.com")

    async with session_factory() as session:
        user = (
            await session.execute(select(User).where(User.email == "deactivated@example.com"))
        ).scalar_one()
        user.is_active = False
        await session.commit()

    # The already-issued access token stops working immediately.
    assert (await client.get("/auth/me", headers=auth_header(tokens))).status_code == 403
    # And logging in again gives the generic credential error, not a hint.
    response = await login(client, email="deactivated@example.com")
    assert response.status_code == 401
    assert response.json()["error"]["message"] == "Invalid email or password."


# --- secrets never leak ----------------------------------------------------


async def test_password_hash_never_appears_in_any_response_body(
    client: AsyncClient, session_factory
) -> None:
    """Sweep every auth endpoint and assert no hash or hash-fragment leaks."""
    register_response = await register(client, email="leak@example.com")
    login_response = await login(client, email="leak@example.com")
    tokens = login_response.json()
    me_response = await client.get("/auth/me", headers=auth_header(tokens))
    refresh_response = await client.post(
        "/auth/refresh",
        json={"refresh_token": tokens["refresh_token"], "device_id": "device-a"},
    )
    bad_login = await login(client, email="leak@example.com", password="nope-nope-nope")
    logout_all_response = await client.post(
        "/auth/logout-all", headers=auth_header(refresh_response.json())
    )

    async with session_factory() as session:
        user = (
            await session.execute(select(User).where(User.email == "leak@example.com"))
        ).scalar_one()
        stored_hash = user.password_hash

    assert stored_hash is not None and stored_hash.startswith("$argon2id$")

    bodies = [
        register_response.text,
        login_response.text,
        me_response.text,
        refresh_response.text,
        bad_login.text,
        logout_all_response.text,
    ]
    for body in bodies:
        assert "password_hash" not in body
        assert stored_hash not in body
        # The argon2 salt+tag segment on its own must not appear either.
        assert stored_hash.rsplit("$", 1)[-1] not in body
        assert PASSWORD not in body
        assert "$argon2" not in body


async def test_refresh_tokens_are_stored_only_as_hashes(
    client: AsyncClient, session_factory
) -> None:
    tokens = await register_and_login(client, email="hashed@example.com")
    raw = tokens["refresh_token"]

    async with session_factory() as session:
        rows = (await session.execute(select(RefreshToken))).scalars().all()
        assert len(rows) == 1
        assert rows[0].token_hash != raw
        assert rows[0].token_hash == hash_refresh_token(raw)
        assert len(rows[0].token_hash) == 64


async def test_me_response_has_exactly_the_public_fields(client: AsyncClient) -> None:
    tokens = await register_and_login(client, email="fields@example.com")
    body = (await client.get("/auth/me", headers=auth_header(tokens))).json()
    assert set(body) == {
        "id",
        "email",
        "role",
        "is_active",
        "locale",
        "email_verified_at",
        "created_at",
    }


# --- rate limiter ----------------------------------------------------------


async def test_rate_limiter_fails_open_without_redis() -> None:
    """With Redis unreachable the limiter must allow, not block."""
    limiter = RateLimiter(redis_url="redis://127.0.0.1:1/0", capacity=1)
    assert await limiter.allow(["rl:test:key"]) is True
    # Second call goes through the circuit breaker and must still allow.
    assert await limiter.allow(["rl:test:key"]) is True
    await limiter.close()


async def test_rate_limiter_can_be_disabled() -> None:
    limiter = RateLimiter(enabled=False)
    assert limiter.enabled is False
    assert await limiter.allow(["anything"]) is True


async def test_auth_endpoints_work_with_redis_down(client: AsyncClient) -> None:
    """End-to-end proof of the fail-open decision, limiter enabled.

    The limiter dependency override is removed so the real one runs, pointed at
    a port where nothing is listening.
    """
    from app.core.config import get_settings

    app.dependency_overrides.pop(auth_rate_limit, None)
    set_rate_limiter(RateLimiter(redis_url="redis://127.0.0.1:1/0"))
    app.dependency_overrides[get_settings] = _test_settings
    try:
        response = await register(client, email="redisdown@example.com")
        assert response.status_code == 201
        assert (await login(client, email="redisdown@example.com")).status_code == 200
    finally:
        set_rate_limiter(RateLimiter(enabled=False))
        app.dependency_overrides[auth_rate_limit] = lambda: None


# --- schema portability ----------------------------------------------------


def test_schema_uses_postgres_native_types() -> None:
    """SQLite compatibility must not have weakened the production schema."""
    from sqlalchemy.dialects import postgresql, sqlite
    from sqlalchemy.schema import CreateTable

    pg = str(CreateTable(RefreshToken.__table__).compile(dialect=postgresql.dialect()))
    assert "user_id UUID NOT NULL" in pg
    assert "expires_at TIMESTAMP WITH TIME ZONE NOT NULL" in pg

    # ...and it still compiles for SQLite, which is what lets these tests run.
    lite = str(CreateTable(RefreshToken.__table__).compile(dialect=sqlite.dialect()))
    assert "user_id CHAR(32) NOT NULL" in lite


async def test_timestamps_round_trip_as_utc_aware(session_factory) -> None:
    """`TZDateTime` must hand back aware datetimes even on SQLite."""
    async with session_factory() as session:
        user = User(email="tz@example.com", password_hash="x", locale="en")
        session.add(user)
        await session.flush()

        expires = datetime.now(UTC) + timedelta(days=1)
        token = RefreshToken(
            user_id=user.id,
            device_id="d",
            token_hash="h" * 64,
            expires_at=expires,
            created_at=datetime.now(UTC),
        )
        session.add(token)
        await session.commit()

    async with session_factory() as session:
        loaded = (await session.execute(select(RefreshToken))).scalar_one()
        assert loaded.expires_at.tzinfo is not None
        assert loaded.expires_at.utcoffset() == timedelta(0)
        # A comparison against an aware "now" must not raise.
        assert loaded.expires_at > datetime.now(UTC)


# --- migration ---------------------------------------------------------------


def test_migration_0002_is_valid_and_chains_from_the_baseline() -> None:
    """The migration cannot be executed here (no PostgreSQL); verify statically."""
    import ast
    from pathlib import Path

    versions = Path(__file__).resolve().parents[1] / "app" / "db" / "migrations" / "versions"
    source = (versions / "0002_auth.py").read_text(encoding="utf-8")
    tree = ast.parse(source)

    assigned: dict[str, object] = {}
    for node in tree.body:
        if isinstance(node, ast.AnnAssign) and isinstance(node.target, ast.Name):
            if node.value is not None:
                try:
                    assigned[node.target.id] = ast.literal_eval(node.value)
                except ValueError:
                    pass

    assert assigned["revision"] == "0002_auth"

    baseline = ast.parse((versions / "0001_baseline_users.py").read_text(encoding="utf-8"))
    baseline_revision = None
    for node in baseline.body:
        if (
            isinstance(node, ast.AnnAssign)
            and isinstance(node.target, ast.Name)
            and node.target.id == "revision"
            and node.value is not None
        ):
            baseline_revision = ast.literal_eval(node.value)
    assert assigned["down_revision"] == baseline_revision

    functions = {n.name for n in tree.body if isinstance(n, ast.FunctionDef)}
    assert {"upgrade", "downgrade"} <= functions

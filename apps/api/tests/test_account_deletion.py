"""Account deletion (`DELETE /users/me`) and the grace-period purge.

Fixtures mirror `tests/test_profile.py`: in-memory SQLite per test, the real
ASGI app, rate limiter disabled.
"""

from __future__ import annotations

import uuid
from collections.abc import AsyncGenerator
from datetime import UTC, datetime, timedelta

import pytest
from httpx import ASGITransport, AsyncClient
from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.pool import StaticPool

from app.core.config import Settings
from app.db.base import Base
from app.jobs import cleanup
from app.jobs.worker import WorkerSettings
from app.main import app
from app.modules.account.service import purge_deleted_accounts
from app.modules.auth.ratelimit import RateLimiter, auth_rate_limit, set_rate_limiter
from app.modules.users.models import User

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


async def register_and_login(client: AsyncClient, email: str) -> dict:
    await client.post("/auth/register", json={"email": email, "password": PASSWORD, "locale": "en"})
    response = await client.post(
        "/auth/login", json={"email": email, "password": PASSWORD, "device_id": "device-a"}
    )
    assert response.status_code == 200, response.text
    return response.json()


def auth_header(tokens: dict) -> dict[str, str]:
    return {"Authorization": f"Bearer {tokens['access_token']}"}


async def delete_account(client: AsyncClient, tokens: dict | None, password: str = PASSWORD):
    headers = auth_header(tokens) if tokens else {}
    return await client.request("DELETE", "/users/me", json={"password": password}, headers=headers)


async def user_id_of(client: AsyncClient, tokens: dict) -> uuid.UUID:
    response = await client.get("/auth/me", headers=auth_header(tokens))
    assert response.status_code == 200, response.text
    return uuid.UUID(response.json()["id"])


async def test_deleting_requires_authentication(client: AsyncClient) -> None:
    response = await delete_account(client, None)
    assert response.status_code == 401


async def test_a_wrong_password_is_refused_and_the_account_stays(client: AsyncClient) -> None:
    tokens = await register_and_login(client, "keep@example.com")

    response = await delete_account(client, tokens, password="not-the-password")

    assert response.status_code == 403
    assert (await client.get("/users/me", headers=auth_header(tokens))).status_code == 200


async def test_deleting_closes_the_account_at_once(client: AsyncClient) -> None:
    tokens = await register_and_login(client, "gone@example.com")

    response = await delete_account(client, tokens)

    assert response.status_code == 204
    assert (await client.get("/users/me", headers=auth_header(tokens))).status_code == 401
    refresh = await client.post(
        "/auth/refresh",
        json={"refresh_token": tokens["refresh_token"], "device_id": "device-a"},
    )
    assert refresh.status_code == 401
    login = await client.post(
        "/auth/login",
        json={"email": "gone@example.com", "password": PASSWORD, "device_id": "device-a"},
    )
    assert login.status_code == 401


async def test_the_address_can_sign_up_again(client: AsyncClient) -> None:
    first = await register_and_login(client, "again@example.com")
    first_id = await user_id_of(client, first)
    assert (await delete_account(client, first)).status_code == 204

    second = await register_and_login(client, "again@example.com")

    assert await user_id_of(client, second) != first_id


async def test_the_purge_waits_for_the_grace_period(
    client: AsyncClient, session_factory: async_sessionmaker[AsyncSession]
) -> None:
    old = await register_and_login(client, "old@example.com")
    recent = await register_and_login(client, "recent@example.com")
    kept = await register_and_login(client, "kept@example.com")
    old_id = await user_id_of(client, old)
    recent_id = await user_id_of(client, recent)
    kept_id = await user_id_of(client, kept)
    assert (await delete_account(client, old)).status_code == 204
    assert (await delete_account(client, recent)).status_code == 204

    now = datetime.now(UTC)
    async with session_factory() as session:
        await session.execute(
            update(User).where(User.id == old_id).values(deleted_at=now - timedelta(days=8))
        )
        await session.commit()

        purged = await purge_deleted_accounts(session, now=now)
        remaining = set((await session.execute(select(User.id))).scalars().all())

    assert purged == 1
    assert old_id not in remaining
    assert {recent_id, kept_id} <= remaining


def test_the_purge_job_is_registered_and_scheduled() -> None:
    assert cleanup.account_purge in WorkerSettings.functions
    names = {getattr(job.coroutine, "__name__", None) for job in WorkerSettings.cron_jobs}
    assert "account_purge" in names

"""Phase-1 profile tests (`/users/me`).

Fixtures mirror `tests/test_auth.py` (in-memory SQLite per test, real ASGI
app, rate limiter disabled) rather than living in `tests/conftest.py` -- same
reasoning as that module: the Phase-0 conftest stays untouched, and each
Phase-1 test module is self-contained.
"""

from __future__ import annotations

from collections.abc import AsyncGenerator

import pytest
from httpx import ASGITransport, AsyncClient
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

# Importing these registers every table on Base.metadata for `create_all`.
from app.modules.preferences import models as preferences_models  # noqa: F401

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


async def register_and_login(client: AsyncClient, email: str, password: str = PASSWORD) -> dict:
    await client.post("/auth/register", json={"email": email, "password": password, "locale": "en"})
    response = await client.post(
        "/auth/login", json={"email": email, "password": password, "device_id": "device-a"}
    )
    assert response.status_code == 200, response.text
    return response.json()


def auth_header(tokens: dict) -> dict[str, str]:
    return {"Authorization": f"Bearer {tokens['access_token']}"}


# --- authentication ----------------------------------------------------------


async def test_get_profile_requires_authentication(client: AsyncClient) -> None:
    response = await client.get("/users/me")
    assert response.status_code == 401


async def test_patch_profile_requires_authentication(client: AsyncClient) -> None:
    response = await client.patch("/users/me", json={"display_name": "X"})
    assert response.status_code == 401


# --- reading the profile ------------------------------------------------------


async def test_get_profile_returns_defaults(client: AsyncClient) -> None:
    tokens = await register_and_login(client, "profile-defaults@example.com")
    response = await client.get("/users/me", headers=auth_header(tokens))
    assert response.status_code == 200
    body = response.json()
    assert body["email"] == "profile-defaults@example.com"
    assert body["locale"] == "en"
    assert body["timezone"] == "UTC"
    assert body["display_name"] is None
    assert body["gender"] is None
    assert body["birth_year"] is None
    assert body["avatar_url"] is None
    assert "password_hash" not in response.text


# --- updating the profile ------------------------------------------------------


async def test_patch_updates_allowed_fields(client: AsyncClient) -> None:
    tokens = await register_and_login(client, "profile-update@example.com")
    response = await client.patch(
        "/users/me",
        headers=auth_header(tokens),
        json={
            "display_name": "Foydalanuvchi",
            "locale": "uz",
            "timezone": "Asia/Tashkent",
            "gender": "male",
            "birth_year": 1995,
            "avatar_url": "https://example.com/a.png",
        },
    )
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["display_name"] == "Foydalanuvchi"
    assert body["locale"] == "uz"
    assert body["timezone"] == "Asia/Tashkent"
    assert body["gender"] == "male"
    assert body["birth_year"] == 1995
    assert body["avatar_url"] == "https://example.com/a.png"

    # And the change is actually persisted, not just echoed back.
    again = await client.get("/users/me", headers=auth_header(tokens))
    assert again.json() == body


async def test_partial_patch_preserves_untouched_fields(client: AsyncClient) -> None:
    tokens = await register_and_login(client, "profile-partial@example.com")
    await client.patch("/users/me", headers=auth_header(tokens), json={"display_name": "First"})
    second = await client.patch("/users/me", headers=auth_header(tokens), json={"birth_year": 2000})
    assert second.status_code == 200, second.text
    body = second.json()
    # birth_year changed, but display_name from the earlier PATCH survives.
    assert body["birth_year"] == 2000
    assert body["display_name"] == "First"


@pytest.mark.parametrize("locale", ["fr", "xx", "EN", ""])
async def test_patch_rejects_invalid_locale(client: AsyncClient, locale: str) -> None:
    tokens = await register_and_login(client, f"locale-{locale or 'empty'}@example.com")
    response = await client.patch("/users/me", headers=auth_header(tokens), json={"locale": locale})
    assert response.status_code == 422
    assert response.json()["error"]["code"] == "validation_error"


@pytest.mark.parametrize("locale", ["uz", "uz_Cyrl", "ru", "en"])
async def test_patch_accepts_every_supported_locale(client: AsyncClient, locale: str) -> None:
    tokens = await register_and_login(client, f"locale-ok-{locale}@example.com")
    response = await client.patch("/users/me", headers=auth_header(tokens), json={"locale": locale})
    assert response.status_code == 200, response.text
    assert response.json()["locale"] == locale


@pytest.mark.parametrize("timezone", ["Not/AZone", "Mars/OlympusMons", "gibberish", "UTC+5"])
async def test_patch_rejects_invalid_timezone(client: AsyncClient, timezone: str) -> None:
    tokens = await register_and_login(client, f"tz-{abs(hash(timezone))}@example.com")
    response = await client.patch(
        "/users/me", headers=auth_header(tokens), json={"timezone": timezone}
    )
    assert response.status_code == 422
    assert response.json()["error"]["code"] == "validation_error"


async def test_patch_rejects_null_locale_and_timezone(client: AsyncClient) -> None:
    """These columns are non-nullable; an explicit `null` must not slip through."""
    tokens = await register_and_login(client, "profile-null@example.com")
    response = await client.patch("/users/me", headers=auth_header(tokens), json={"locale": None})
    assert response.status_code == 422


# --- per-user isolation --------------------------------------------------------


async def test_user_cannot_see_or_modify_another_users_profile(client: AsyncClient) -> None:
    tokens_a = await register_and_login(client, "profile-a@example.com")
    tokens_b = await register_and_login(client, "profile-b@example.com")

    await client.patch("/users/me", headers=auth_header(tokens_a), json={"display_name": "Alice"})

    # There is no endpoint parameterised by another user's id; the only way
    # to prove isolation is that each token's own profile is independent.
    profile_a = (await client.get("/users/me", headers=auth_header(tokens_a))).json()
    profile_b = (await client.get("/users/me", headers=auth_header(tokens_b))).json()

    assert profile_a["display_name"] == "Alice"
    assert profile_b["display_name"] is None
    assert profile_a["id"] != profile_b["id"]
    assert profile_a["email"] != profile_b["email"]

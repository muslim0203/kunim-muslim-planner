"""What the account is asked at sign-up: occupation, interests, focus areas
and the minutes a day can hold.

These four exist so the app can suggest a day instead of handing the user an
empty grid. The wire shape is bounded but the vocabulary is not: a newer
client ships an occupation this server has never heard of, and carrying it is
the whole point (the same reasoning as `habits.kind`).

Fixtures mirror `tests/test_profile.py`, which this module extends.
"""

from __future__ import annotations

from collections.abc import AsyncGenerator
from typing import Any

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


async def patch(client: AsyncClient, tokens: dict, body: dict[str, Any]):
    return await client.patch("/users/me", json=body, headers=auth_header(tokens))


async def test_an_account_starts_with_nothing_asked_yet(client: AsyncClient) -> None:
    """Every account that existed before these questions is still valid."""
    tokens = await register_and_login(client, "asked-nothing@example.com")

    body = (await client.get("/users/me", headers=auth_header(tokens))).json()

    assert body["occupation"] is None
    assert body["interests"] == []
    assert body["focus_areas"] == []
    assert body["daily_minutes"] is None


async def test_the_answers_are_stored_and_read_back(client: AsyncClient) -> None:
    tokens = await register_and_login(client, "asked-answers@example.com")

    updated = await patch(
        client,
        tokens,
        {
            "occupation": "teacher",
            "interests": ["quran", "book", "sport"],
            "focus_areas": ["prayer", "health"],
            "daily_minutes": 45,
        },
    )

    assert updated.status_code == 200, updated.text
    body = (await client.get("/users/me", headers=auth_header(tokens))).json()
    assert body["occupation"] == "teacher"
    assert body["interests"] == ["quran", "book", "sport"]
    assert body["focus_areas"] == ["prayer", "health"]
    assert body["daily_minutes"] == 45


async def test_an_answer_this_server_has_never_heard_of_is_kept(
    client: AsyncClient,
) -> None:
    """A newer app offers more; rejecting it would lose the user's answer."""
    tokens = await register_and_login(client, "asked-unknown@example.com")

    response = await patch(client, tokens, {"occupation": "falconer"})

    assert response.status_code == 200, response.text
    assert response.json()["occupation"] == "falconer"


async def test_an_empty_list_clears_the_answer(client: AsyncClient) -> None:
    tokens = await register_and_login(client, "asked-clear@example.com")
    await patch(client, tokens, {"interests": ["sport"]})

    response = await patch(client, tokens, {"interests": []})

    assert response.status_code == 200, response.text
    assert response.json()["interests"] == []


async def test_answers_left_out_of_the_request_are_untouched(
    client: AsyncClient,
) -> None:
    tokens = await register_and_login(client, "asked-partial@example.com")
    await patch(client, tokens, {"occupation": "student", "daily_minutes": 30})

    await patch(client, tokens, {"display_name": "Aziza"})

    body = (await client.get("/users/me", headers=auth_header(tokens))).json()
    assert body["occupation"] == "student"
    assert body["daily_minutes"] == 30


@pytest.mark.parametrize(
    "body",
    [
        {"occupation": "Not A Slug"},
        {"occupation": "x" * 41},
        {"interests": ["ok", "Not A Slug"]},
        {"interests": [f"i{n}" for n in range(25)]},
        {"interests": None},
        {"focus_areas": None},
        {"daily_minutes": 0},
        {"daily_minutes": 601},
    ],
    ids=[
        "occupation-not-a-slug",
        "occupation-too-long",
        "interest-not-a-slug",
        "too-many-interests",
        "null-interests",
        "null-focus-areas",
        "no-minutes-at-all",
        "more-minutes-than-a-day-holds",
    ],
)
async def test_an_answer_that_is_not_an_answer_is_refused(
    client: AsyncClient, body: dict[str, Any]
) -> None:
    tokens = await register_and_login(client, f"asked-invalid-{abs(hash(str(body)))}@example.com")

    response = await patch(client, tokens, body)

    assert response.status_code == 422, response.text

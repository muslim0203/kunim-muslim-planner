"""Phase-1 preferences tests (`/preferences`).

Fixtures mirror `tests/test_auth.py` (see that module's docstring for why
they live here rather than in `tests/conftest.py`).
"""

from __future__ import annotations

from collections.abc import AsyncGenerator
from datetime import UTC, datetime

import pytest
from httpx import ASGITransport, AsyncClient
from sqlalchemy import select
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
from app.modules.preferences.models import Preferences

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
    await client.post(
        "/auth/register", json={"email": email, "password": password, "locale": "en"}
    )
    response = await client.post(
        "/auth/login", json={"email": email, "password": password, "device_id": "device-a"}
    )
    assert response.status_code == 200, response.text
    return response.json()


def auth_header(tokens: dict) -> dict[str, str]:
    return {"Authorization": f"Bearer {tokens['access_token']}"}


# --- authentication ------------------------------------------------------------


async def test_get_preferences_requires_authentication(client: AsyncClient) -> None:
    assert (await client.get("/preferences")).status_code == 401


async def test_patch_preferences_requires_authentication(client: AsyncClient) -> None:
    response = await client.patch("/preferences", json={"ui": {"theme": "dark"}})
    assert response.status_code == 401


# --- lazy creation with defaults -------------------------------------------------


async def test_get_creates_defaults_on_first_read(
    client: AsyncClient, session_factory: async_sessionmaker[AsyncSession]
) -> None:
    tokens = await register_and_login(client, "prefs-defaults@example.com")

    response = await client.get("/preferences", headers=auth_header(tokens))
    assert response.status_code == 200, response.text
    body = response.json()

    assert body["server_version"] == 0
    assert body["prayer_settings"]["method"] == "muslim_world_league"
    assert body["prayer_settings"]["madhab"] == "shafi"
    assert body["prayer_settings"]["high_latitude_rule"] == "middle_of_the_night"
    assert body["prayer_settings"]["adjustments"] == {
        "fajr": 0,
        "dhuhr": 0,
        "asr": 0,
        "maghrib": 0,
        "isha": 0,
    }
    assert body["prayer_settings"]["location"] == {
        "lat": None,
        "lon": None,
        "city": None,
        "timezone": None,
    }
    assert body["notifications"] == {
        "prayer": True,
        "habits": True,
        "tasks": True,
        "quran": True,
        "wellbeing": True,
        "ai_recommendations": True,
        "reviews": True,
        "system": True,
        "quiet_hours": {"enabled": False, "start": "22:00", "end": "06:00"},
    }
    assert body["privacy_consents"] == {
        "analytics": False,
        "ai_personalization": False,
        "dw_cloud_stats": False,
    }
    assert body["ui"] == {"theme": "system", "first_day_of_week": 1}

    # Exactly one row was created, not one per request.
    async with session_factory() as session:
        rows = (await session.execute(select(Preferences))).scalars().all()
        assert len(rows) == 1

    again = await client.get("/preferences", headers=auth_header(tokens))
    assert again.json()["id"] == body["id"]
    async with session_factory() as session:
        rows = (await session.execute(select(Preferences))).scalars().all()
        assert len(rows) == 1


# --- deep-merge PATCH: siblings survive at every nesting level ------------------


async def test_patch_top_level_key_preserves_sibling_keys(client: AsyncClient) -> None:
    tokens = await register_and_login(client, "prefs-siblings@example.com")
    await client.get("/preferences", headers=auth_header(tokens))  # create the row

    response = await client.patch(
        "/preferences",
        headers=auth_header(tokens),
        json={"ui": {"theme": "dark"}},
    )
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["ui"] == {"theme": "dark", "first_day_of_week": 1}
    # Untouched top-level keys are exactly the defaults still.
    assert body["notifications"]["prayer"] is True
    assert body["privacy_consents"]["analytics"] is False


async def test_patch_nested_prayer_field_preserves_other_prayer_fields(
    client: AsyncClient,
) -> None:
    tokens = await register_and_login(client, "prefs-nested-prayer@example.com")
    await client.get("/preferences", headers=auth_header(tokens))

    response = await client.patch(
        "/preferences",
        headers=auth_header(tokens),
        json={"prayer_settings": {"madhab": "hanafi"}},
    )
    assert response.status_code == 200, response.text
    body = response.json()["prayer_settings"]
    assert body["madhab"] == "hanafi"
    # Sibling keys inside prayer_settings, one level down, are untouched.
    assert body["method"] == "muslim_world_league"
    assert body["high_latitude_rule"] == "middle_of_the_night"
    assert body["adjustments"] == {"fajr": 0, "dhuhr": 0, "asr": 0, "maghrib": 0, "isha": 0}


async def test_patch_doubly_nested_adjustment_preserves_its_siblings(
    client: AsyncClient,
) -> None:
    """PATCHing `prayer_settings.adjustments.fajr` alone must not zero the
    other four adjustment minutes -- the deepest nesting level in the tree."""
    tokens = await register_and_login(client, "prefs-nested-adjustment@example.com")
    await client.get("/preferences", headers=auth_header(tokens))

    first = await client.patch(
        "/preferences",
        headers=auth_header(tokens),
        json={"prayer_settings": {"adjustments": {"maghrib": 3}}},
    )
    assert first.json()["prayer_settings"]["adjustments"] == {
        "fajr": 0,
        "dhuhr": 0,
        "asr": 0,
        "maghrib": 3,
        "isha": 0,
    }

    second = await client.patch(
        "/preferences",
        headers=auth_header(tokens),
        json={"prayer_settings": {"adjustments": {"fajr": -2}}},
    )
    assert second.status_code == 200, second.text
    adjustments = second.json()["prayer_settings"]["adjustments"]
    assert adjustments["fajr"] == -2
    # maghrib set by the previous PATCH must still be there.
    assert adjustments["maghrib"] == 3
    assert adjustments["dhuhr"] == 0
    assert adjustments["asr"] == 0
    assert adjustments["isha"] == 0


async def test_patch_notifications_quiet_hours_preserves_category_toggles(
    client: AsyncClient,
) -> None:
    tokens = await register_and_login(client, "prefs-quiet-hours@example.com")
    await client.get("/preferences", headers=auth_header(tokens))

    await client.patch(
        "/preferences",
        headers=auth_header(tokens),
        json={"notifications": {"habits": False}},
    )
    response = await client.patch(
        "/preferences",
        headers=auth_header(tokens),
        json={"notifications": {"quiet_hours": {"enabled": True, "start": "23:00"}}},
    )
    assert response.status_code == 200, response.text
    body = response.json()["notifications"]
    assert body["quiet_hours"] == {"enabled": True, "start": "23:00", "end": "06:00"}
    # habits, set False by the earlier PATCH, survives; other toggles default.
    assert body["habits"] is False
    assert body["prayer"] is True
    assert body["tasks"] is True


# --- privacy consents are independent -------------------------------------------


async def test_privacy_consents_are_independent(client: AsyncClient) -> None:
    tokens = await register_and_login(client, "prefs-consents@example.com")
    await client.get("/preferences", headers=auth_header(tokens))

    response = await client.patch(
        "/preferences",
        headers=auth_header(tokens),
        json={"privacy_consents": {"analytics": True}},
    )
    assert response.status_code == 200, response.text
    consents = response.json()["privacy_consents"]
    assert consents["analytics"] is True
    assert consents["ai_personalization"] is False
    assert consents["dw_cloud_stats"] is False

    response2 = await client.patch(
        "/preferences",
        headers=auth_header(tokens),
        json={"privacy_consents": {"dw_cloud_stats": True}},
    )
    consents2 = response2.json()["privacy_consents"]
    # Setting a second consent must not disturb the first, and must not have
    # touched ai_personalization either.
    assert consents2["analytics"] is True
    assert consents2["dw_cloud_stats"] is True
    assert consents2["ai_personalization"] is False


# --- server_version -------------------------------------------------------------


async def test_server_version_increases_on_every_write(client: AsyncClient) -> None:
    tokens = await register_and_login(client, "prefs-version@example.com")
    created = (await client.get("/preferences", headers=auth_header(tokens))).json()
    assert created["server_version"] == 0

    v1 = await client.patch(
        "/preferences", headers=auth_header(tokens), json={"ui": {"theme": "dark"}}
    )
    assert v1.json()["server_version"] == 1

    v2 = await client.patch(
        "/preferences",
        headers=auth_header(tokens),
        json={"privacy_consents": {"analytics": True}},
    )
    assert v2.json()["server_version"] == 2

    v3 = await client.patch(
        "/preferences",
        headers=auth_header(tokens),
        json={"notifications": {"prayer": False}},
    )
    assert v3.json()["server_version"] == 3

    # A plain GET must not itself bump the version.
    read_after = await client.get("/preferences", headers=auth_header(tokens))
    assert read_after.json()["server_version"] == 3


# --- validation ------------------------------------------------------------------


async def test_invalid_prayer_method_is_rejected(client: AsyncClient) -> None:
    tokens = await register_and_login(client, "prefs-bad-method@example.com")
    await client.get("/preferences", headers=auth_header(tokens))

    response = await client.patch(
        "/preferences",
        headers=auth_header(tokens),
        json={"prayer_settings": {"method": "not_a_real_method"}},
    )
    assert response.status_code == 422
    assert "error" in response.json()


async def test_invalid_madhab_is_rejected(client: AsyncClient) -> None:
    tokens = await register_and_login(client, "prefs-bad-madhab@example.com")
    await client.get("/preferences", headers=auth_header(tokens))

    response = await client.patch(
        "/preferences",
        headers=auth_header(tokens),
        json={"prayer_settings": {"madhab": "maliki"}},
    )
    assert response.status_code == 422


async def test_invalid_location_timezone_is_rejected(client: AsyncClient) -> None:
    tokens = await register_and_login(client, "prefs-bad-tz@example.com")
    await client.get("/preferences", headers=auth_header(tokens))

    response = await client.patch(
        "/preferences",
        headers=auth_header(tokens),
        json={"prayer_settings": {"location": {"timezone": "Not/AZone"}}},
    )
    assert response.status_code == 422

    # And the invalid write must not have partially applied.
    unchanged = await client.get("/preferences", headers=auth_header(tokens))
    assert unchanged.json()["prayer_settings"]["location"]["timezone"] is None


async def test_unknown_top_level_key_is_rejected(client: AsyncClient) -> None:
    tokens = await register_and_login(client, "prefs-unknown-key@example.com")
    response = await client.patch(
        "/preferences", headers=auth_header(tokens), json={"not_a_real_section": {}}
    )
    assert response.status_code == 422


# --- soft delete -------------------------------------------------------------------


async def test_soft_deleted_row_is_not_returned(
    client: AsyncClient, session_factory: async_sessionmaker[AsyncSession]
) -> None:
    tokens = await register_and_login(client, "prefs-soft-delete@example.com")
    original = (await client.get("/preferences", headers=auth_header(tokens))).json()

    async with session_factory() as session:
        row = (
            await session.execute(select(Preferences).where(Preferences.id == original["id"]))
        ).scalar_one()
        row.deleted_at = datetime.now(UTC)
        await session.commit()

    recreated = (await client.get("/preferences", headers=auth_header(tokens))).json()
    assert recreated["id"] != original["id"]
    assert recreated["server_version"] == 0  # fresh defaults, not the old row

    async with session_factory() as session:
        rows = (await session.execute(select(Preferences))).scalars().all()
        assert len(rows) == 2
        assert sum(1 for r in rows if r.deleted_at is None) == 1


# --- per-user isolation --------------------------------------------------------------


async def test_user_cannot_see_or_modify_another_users_preferences(client: AsyncClient) -> None:
    tokens_a = await register_and_login(client, "prefs-a@example.com")
    tokens_b = await register_and_login(client, "prefs-b@example.com")

    await client.patch(
        "/preferences",
        headers=auth_header(tokens_a),
        json={"privacy_consents": {"analytics": True}},
    )

    prefs_a = (await client.get("/preferences", headers=auth_header(tokens_a))).json()
    prefs_b = (await client.get("/preferences", headers=auth_header(tokens_b))).json()

    assert prefs_a["id"] != prefs_b["id"]
    assert prefs_a["privacy_consents"]["analytics"] is True
    assert prefs_b["privacy_consents"]["analytics"] is False

"""Friends, invite codes and the two boards.

Fixtures mirror `tests/test_profile.py`: in-memory SQLite per test, the real
ASGI app, rate limiter disabled.
"""

from __future__ import annotations

import uuid
from collections.abc import AsyncGenerator
from datetime import UTC, date, datetime, timedelta

import pytest
from httpx import ASGITransport, AsyncClient
from sqlalchemy import update
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.pool import StaticPool

from app.core.config import Settings
from app.db.base import Base
from app.main import app
from app.modules.auth.ratelimit import RateLimiter, auth_rate_limit, set_rate_limiter
from app.modules.scores.models import DailyScore
from app.modules.social.models import FriendInvite

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


def auth_header(tokens: dict) -> dict[str, str]:
    return {"Authorization": f"Bearer {tokens['access_token']}"}


async def sign_up(client: AsyncClient, email: str) -> dict:
    await client.post("/auth/register", json={"email": email, "password": PASSWORD, "locale": "en"})
    response = await client.post(
        "/auth/login", json={"email": email, "password": PASSWORD, "device_id": "device-a"}
    )
    assert response.status_code == 200, response.text
    return response.json()


async def user_id_of(client: AsyncClient, tokens: dict) -> uuid.UUID:
    response = await client.get("/auth/me", headers=auth_header(tokens))
    assert response.status_code == 200, response.text
    return uuid.UUID(response.json()["id"])


async def invite_code(client: AsyncClient, tokens: dict) -> str:
    response = await client.post("/social/invites", headers=auth_header(tokens))
    assert response.status_code == 201, response.text
    return response.json()["code"]


async def accept(client: AsyncClient, tokens: dict, code: str):
    return await client.post(
        "/social/invites/accept", json={"code": code}, headers=auth_header(tokens)
    )


async def award(
    session_factory: async_sessionmaker[AsyncSession],
    user_id: uuid.UUID,
    *,
    points: int,
    day: date,
) -> None:
    """A day's score, as the client would have synced it."""
    async with session_factory() as session:
        session.add(DailyScore(user_id=user_id, date=day, points=points, done=1, planned=1))
        await session.commit()


async def become_friends(client: AsyncClient, first: dict, second: dict) -> None:
    assert (await accept(client, second, await invite_code(client, first))).status_code == 204


# --- invites -------------------------------------------------------------------


async def test_an_invite_makes_two_people_friends(
    client: AsyncClient, session_factory: async_sessionmaker[AsyncSession]
) -> None:
    alice = await sign_up(client, "alice@example.com")
    bob = await sign_up(client, "bob@example.com")
    alice_id = await user_id_of(client, alice)
    bob_id = await user_id_of(client, bob)
    today = datetime.now(UTC).date()
    await award(session_factory, alice_id, points=35, day=today)
    await award(session_factory, bob_id, points=90, day=today)

    await become_friends(client, alice, bob)

    board = (await client.get("/social/friends", headers=auth_header(alice))).json()
    names = {entry["user_id"] for entry in board["entries"]}
    assert names == {str(alice_id), str(bob_id)}
    # Best week first: Bob's 90 beats Alice's 35.
    assert board["entries"][0]["user_id"] == str(bob_id)
    assert board["entries"][0]["points_week"] == 90
    assert board["my_rank"] == 2


async def test_a_board_never_carries_an_email(client: AsyncClient) -> None:
    alice = await sign_up(client, "alice@example.com")
    bob = await sign_up(client, "bob@example.com")
    await become_friends(client, alice, bob)

    response = await client.get("/social/friends", headers=auth_header(alice))

    assert "bob@example.com" not in response.text
    assert "alice@example.com" not in response.text


async def test_your_own_code_is_refused(client: AsyncClient) -> None:
    alice = await sign_up(client, "alice@example.com")

    response = await accept(client, alice, await invite_code(client, alice))

    assert response.status_code == 400


async def test_a_code_works_once(client: AsyncClient) -> None:
    alice = await sign_up(client, "alice@example.com")
    bob = await sign_up(client, "bob@example.com")
    carol = await sign_up(client, "carol@example.com")
    code = await invite_code(client, alice)
    assert (await accept(client, bob, code)).status_code == 204

    assert (await accept(client, carol, code)).status_code == 410


async def test_an_expired_code_is_refused(
    client: AsyncClient, session_factory: async_sessionmaker[AsyncSession]
) -> None:
    alice = await sign_up(client, "alice@example.com")
    bob = await sign_up(client, "bob@example.com")
    code = await invite_code(client, alice)
    async with session_factory() as session:
        await session.execute(
            update(FriendInvite)
            .where(FriendInvite.code == code)
            .values(expires_at=datetime.now(UTC) - timedelta(minutes=1))
        )
        await session.commit()

    assert (await accept(client, bob, code)).status_code == 410


async def test_an_unknown_code_is_refused(client: AsyncClient) -> None:
    bob = await sign_up(client, "bob@example.com")

    assert (await accept(client, bob, "ZZZZZZZZ")).status_code == 404


async def test_removing_a_friend_clears_both_sides(client: AsyncClient) -> None:
    alice = await sign_up(client, "alice@example.com")
    bob = await sign_up(client, "bob@example.com")
    alice_id = await user_id_of(client, alice)
    await become_friends(client, alice, bob)

    removed = await client.delete(f"/social/friends/{alice_id}", headers=auth_header(bob))

    assert removed.status_code == 204
    for tokens in (alice, bob):
        board = (await client.get("/social/friends", headers=auth_header(tokens))).json()
        assert len(board["entries"]) == 1  # only themselves


# --- the global board ----------------------------------------------------------


async def test_the_global_board_needs_a_nickname_first(client: AsyncClient) -> None:
    alice = await sign_up(client, "alice@example.com")

    refused = await client.patch(
        "/users/me", json={"leaderboard_opt_in": True}, headers=auth_header(alice)
    )

    assert refused.status_code == 400


async def test_two_people_cannot_share_a_nickname(client: AsyncClient) -> None:
    alice = await sign_up(client, "alice@example.com")
    bob = await sign_up(client, "bob@example.com")
    taken = await client.patch("/users/me", json={"nickname": "aziza"}, headers=auth_header(alice))
    assert taken.status_code == 200

    clash = await client.patch("/users/me", json={"nickname": "aziza"}, headers=auth_header(bob))

    assert clash.status_code == 409


async def test_only_people_who_opted_in_are_listed(
    client: AsyncClient, session_factory: async_sessionmaker[AsyncSession]
) -> None:
    alice = await sign_up(client, "alice@example.com")
    bob = await sign_up(client, "bob@example.com")
    alice_id = await user_id_of(client, alice)
    await award(session_factory, alice_id, points=35, day=datetime.now(UTC).date())
    joined = await client.patch(
        "/users/me",
        json={"nickname": "aziza", "leaderboard_opt_in": True},
        headers=auth_header(alice),
    )
    assert joined.status_code == 200

    seen_by_bob = (await client.get("/social/leaderboard", headers=auth_header(bob))).json()

    assert [entry["name"] for entry in seen_by_bob["entries"]] == ["aziza"]
    assert seen_by_bob["entries"][0]["points_week"] == 35
    # Bob never joined, so he is nowhere on it.
    assert seen_by_bob["my_rank"] is None


async def test_the_board_only_counts_the_last_week(
    client: AsyncClient, session_factory: async_sessionmaker[AsyncSession]
) -> None:
    alice = await sign_up(client, "alice@example.com")
    bob = await sign_up(client, "bob@example.com")
    alice_id = await user_id_of(client, alice)
    today = datetime.now(UTC).date()
    await award(session_factory, alice_id, points=35, day=today)
    await award(session_factory, alice_id, points=500, day=today - timedelta(days=30))
    await become_friends(client, alice, bob)

    board = (await client.get("/social/friends", headers=auth_header(alice))).json()
    mine = next(entry for entry in board["entries"] if entry["is_me"])

    assert mine["points_week"] == 35
    assert mine["points_total"] == 535

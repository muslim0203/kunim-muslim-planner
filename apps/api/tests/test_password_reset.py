"""Password reset by emailed code.

Fixtures mirror `tests/test_profile.py`: in-memory SQLite per test, the real
ASGI app, rate limiter disabled. The mail provider is a fake that keeps what
would have been sent, so the code can be read the way a user reads it out of
their inbox.
"""

from __future__ import annotations

import re
from collections.abc import AsyncGenerator
from datetime import UTC, datetime, timedelta

import pytest
from httpx import ASGITransport, AsyncClient
from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.pool import StaticPool

from app.core.config import Settings
from app.db.base import Base
from app.integrations.email import EmailMessage, set_email_sender
from app.main import app
from app.modules.auth.models import VerificationPurpose, VerificationToken
from app.modules.auth.ratelimit import RateLimiter, auth_rate_limit, set_rate_limiter

PASSWORD = "correct-horse-battery"
NEW_PASSWORD = "a-brand-new-password"
TEST_JWT_SECRET = "test-secret-key-that-is-comfortably-longer-than-32-bytes-ok!!"


def _test_settings() -> Settings:
    return Settings(_env_file=None, JWT_SECRET=TEST_JWT_SECRET)


class FakeEmailSender:
    """Keeps every message instead of delivering it."""

    def __init__(self, *, accepts: bool = True) -> None:
        self.sent: list[EmailMessage] = []
        self.accepts = accepts

    async def send(self, message: EmailMessage) -> bool:
        self.sent.append(message)
        return self.accepts

    @property
    def last_code(self) -> str:
        match = re.search(r"\b(\d{6})\b", self.sent[-1].body)
        assert match is not None, self.sent[-1].body
        return match.group(1)


@pytest.fixture
def mail() -> AsyncGenerator[FakeEmailSender, None]:
    sender = FakeEmailSender()
    set_email_sender(sender)
    try:
        yield sender
    finally:
        set_email_sender(None)


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


async def register(client: AsyncClient, email: str, *, locale: str = "en") -> None:
    response = await client.post(
        "/auth/register",
        json={"email": email, "password": PASSWORD, "locale": locale},
    )
    assert response.status_code == 201, response.text


async def login(client: AsyncClient, email: str, password: str):
    return await client.post(
        "/auth/login",
        json={"email": email, "password": password, "device_id": "device-a"},
    )


async def forgot(client: AsyncClient, email: str):
    return await client.post("/auth/forgot-password", json={"email": email})


async def reset(client: AsyncClient, email: str, code: str, password: str = NEW_PASSWORD):
    return await client.post(
        "/auth/reset-password",
        json={"email": email, "code": code, "new_password": password},
    )


# --- asking for a code ---------------------------------------------------------


async def test_an_unknown_address_is_answered_the_same_and_gets_no_mail(
    client: AsyncClient, mail: FakeEmailSender
) -> None:
    response = await forgot(client, "nobody@example.com")

    assert response.status_code == 202
    assert mail.sent == []


async def test_a_known_address_receives_a_code_in_its_own_language(
    client: AsyncClient, mail: FakeEmailSender
) -> None:
    await register(client, "aziza@example.com", locale="uz")

    response = await forgot(client, "aziza@example.com")

    assert response.status_code == 202
    assert len(mail.sent) == 1
    assert mail.sent[0].to == "aziza@example.com"
    assert "parolni tiklash" in mail.sent[0].subject.lower()
    assert re.search(r"\b\d{6}\b", mail.sent[0].body)


async def test_the_code_is_never_in_the_response(
    client: AsyncClient, mail: FakeEmailSender
) -> None:
    await register(client, "aziza@example.com")

    response = await forgot(client, "aziza@example.com")

    assert mail.last_code not in response.text


# --- using a code --------------------------------------------------------------


async def test_the_code_sets_a_new_password(client: AsyncClient, mail: FakeEmailSender) -> None:
    await register(client, "aziza@example.com")
    await forgot(client, "aziza@example.com")

    response = await reset(client, "aziza@example.com", mail.last_code)

    assert response.status_code == 204
    assert (await login(client, "aziza@example.com", NEW_PASSWORD)).status_code == 200
    assert (await login(client, "aziza@example.com", PASSWORD)).status_code == 401


async def test_a_reset_ends_every_session(client: AsyncClient, mail: FakeEmailSender) -> None:
    await register(client, "aziza@example.com")
    tokens = (await login(client, "aziza@example.com", PASSWORD)).json()
    await forgot(client, "aziza@example.com")

    assert (await reset(client, "aziza@example.com", mail.last_code)).status_code == 204

    refreshed = await client.post(
        "/auth/refresh",
        json={"refresh_token": tokens["refresh_token"], "device_id": "device-a"},
    )
    assert refreshed.status_code == 401


async def test_a_code_works_once(client: AsyncClient, mail: FakeEmailSender) -> None:
    await register(client, "aziza@example.com")
    await forgot(client, "aziza@example.com")
    code = mail.last_code
    assert (await reset(client, "aziza@example.com", code)).status_code == 204

    again = await reset(client, "aziza@example.com", code, "another-password-1")

    assert again.status_code == 400


async def test_a_new_code_retires_the_previous_one(
    client: AsyncClient, mail: FakeEmailSender
) -> None:
    await register(client, "aziza@example.com")
    await forgot(client, "aziza@example.com")
    first = mail.last_code
    await forgot(client, "aziza@example.com")

    assert (await reset(client, "aziza@example.com", first)).status_code == 400
    assert (await reset(client, "aziza@example.com", mail.last_code)).status_code == 204


async def test_a_wrong_code_is_refused(client: AsyncClient, mail: FakeEmailSender) -> None:
    await register(client, "aziza@example.com")
    await forgot(client, "aziza@example.com")
    wrong = "000000" if mail.last_code != "000000" else "111111"

    assert (await reset(client, "aziza@example.com", wrong)).status_code == 400
    assert (await login(client, "aziza@example.com", PASSWORD)).status_code == 200


async def test_a_code_belongs_to_one_account(client: AsyncClient, mail: FakeEmailSender) -> None:
    await register(client, "aziza@example.com")
    await register(client, "anvar@example.com")
    await forgot(client, "aziza@example.com")

    stolen = await reset(client, "anvar@example.com", mail.last_code)

    assert stolen.status_code == 400
    assert (await login(client, "anvar@example.com", PASSWORD)).status_code == 200


async def test_an_expired_code_is_refused(
    client: AsyncClient,
    mail: FakeEmailSender,
    session_factory: async_sessionmaker[AsyncSession],
) -> None:
    await register(client, "aziza@example.com")
    await forgot(client, "aziza@example.com")
    async with session_factory() as session:
        await session.execute(
            update(VerificationToken)
            .where(VerificationToken.purpose == VerificationPurpose.password_reset)
            .values(expires_at=datetime.now(UTC) - timedelta(minutes=1))
        )
        await session.commit()

    assert (await reset(client, "aziza@example.com", mail.last_code)).status_code == 400


async def test_only_a_digest_of_the_code_is_stored(
    client: AsyncClient,
    mail: FakeEmailSender,
    session_factory: async_sessionmaker[AsyncSession],
) -> None:
    await register(client, "aziza@example.com")
    await forgot(client, "aziza@example.com")

    async with session_factory() as session:
        # Registration also issues an email-verification token; only the reset
        # one matters here.
        stored = (
            (
                await session.execute(
                    select(VerificationToken).where(
                        VerificationToken.purpose == VerificationPurpose.password_reset
                    )
                )
            )
            .scalars()
            .all()
        )

    assert len(stored) == 1
    assert mail.last_code not in stored[0].token_hash

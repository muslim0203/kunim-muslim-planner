from __future__ import annotations

from collections.abc import AsyncGenerator, Generator

import pytest
from httpx import ASGITransport, AsyncClient

from app.db.types import DEV_FIELD_ENC_KEY, FieldCipher, set_field_cipher
from app.main import app


@pytest.fixture(autouse=True, scope="session")
def _deterministic_field_cipher() -> Generator[None, None, None]:
    """Encrypt `EncryptedText` columns under the public dev key in every test.

    Otherwise the key would come from whichever `.env` the suite happens to
    run next to. Tests that install another cipher must restore this one.
    """
    set_field_cipher(FieldCipher(DEV_FIELD_ENC_KEY))
    yield
    set_field_cipher(None)


@pytest.fixture
async def client() -> AsyncGenerator[AsyncClient, None]:
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        yield ac

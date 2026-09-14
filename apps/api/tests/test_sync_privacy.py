"""Private values stay out of the push idempotency cache and out of logs.

* `sync_batches.response` caches whole result rows for 7 days (ADR-0002
  section 3). A conflict's `server_row` carries decrypted notes, so
  `SyncRepository.save_batch` seals every `EncryptedText` column and
  `stored_response` opens it again when a retried push is replayed.
* A rejected or failed change is logged with entity, row id, field names and
  error codes only: pydantic and database errors both embed submitted values
  in their messages, so no exception message or traceback text is logged.
* A 422 body no longer echoes each rejected `input`, and the application
  engine hides SQL parameters in its error messages.

structlog here prints straight to stdout (`PrintLoggerFactory`), so pytest's
`caplog` never sees it. The tests swap each module's `logger` for a recorder
instead, which checks exactly the event and keywords that would be rendered.
"""

from __future__ import annotations

import importlib.util
import json
import re
import uuid
from collections.abc import Callable
from datetime import timedelta
from pathlib import Path
from types import ModuleType
from typing import Any

import pytest
from pydantic import BaseModel, Field, ValidationError
from sqlalchemy import select, text

from app.core.logging import safe_exception_fields
from app.db.types import (
    DEV_FIELD_ENC_KEY,
    FieldCipher,
    FieldDecryptionError,
    encrypted_column_names,
)
from app.modules.sync import registry
from app.modules.sync import service as sync_service
from app.modules.sync.models import RowHistory, SyncBatch
from tests import test_sync_harness as harness
from tests.test_wellbeing_sync import mood_payload

client = harness.client
session_factory = harness.session_factory
two_clients = harness.two_clients
BASE_TIME = harness.BASE_TIME
wire_time = harness.wire_time

MIGRATION_PATH = (
    Path(__file__).resolve().parents[1]
    / "app"
    / "db"
    / "migrations"
    / "versions"
    / "0009_seal_cached_batch_responses.py"
)


class RecordingLogger:
    """Stand-in for a module-level structlog logger."""

    def __init__(self) -> None:
        self.calls: list[tuple[str, str, dict[str, Any]]] = []

    def _record(self, level: str, event: str, **fields: Any) -> None:
        self.calls.append((level, event, fields))

    def debug(self, event: str, **fields: Any) -> None:
        self._record("debug", event, **fields)

    def info(self, event: str, **fields: Any) -> None:
        self._record("info", event, **fields)

    def warning(self, event: str, **fields: Any) -> None:
        self._record("warning", event, **fields)

    def error(self, event: str, **fields: Any) -> None:
        self._record("error", event, **fields)

    def exception(self, event: str, **fields: Any) -> None:
        self._record("exception", event, **fields)

    def events(self, name: str) -> list[dict[str, Any]]:
        return [fields for _, event, fields in self.calls if event == name]

    def rendered(self) -> str:
        return repr(self.calls)

    def used_exception_level(self) -> bool:
        return any(level == "exception" for level, _, _ in self.calls)


def _change(entity: str, payload: dict[str, Any]) -> dict[str, Any]:
    return {
        "client_seq": 1,
        "entity": entity,
        "row_id": payload["id"],
        "op": "upsert",
        "base_version": 0,
        "payload": payload,
    }


async def _stale_edit_of_a_row_with_note(alice, bob, *, note: str) -> dict[str, Any]:
    """Return Bob's pending change that will conflict with a newer row holding `note`."""
    row_id = str(uuid.uuid4())
    alice.stage("mood_logs", mood_payload(row_id, updated_at=BASE_TIME, note="first draft"))
    await alice.sync()
    await bob.pull_all()

    newer = dict(alice.rows[("mood_logs", row_id)])
    newer.update(note=note, score=5, updated_at=wire_time(BASE_TIME + timedelta(minutes=5)))
    alice.stage("mood_logs", newer)
    await alice.sync()

    stale = dict(bob.rows[("mood_logs", row_id)])
    stale.update(score=1, updated_at=wire_time(BASE_TIME + timedelta(minutes=2)))
    return bob.stage("mood_logs", stale)


async def _rewrite_cached_notes(session_factory, transform: Callable[[str], str]) -> None:
    async with session_factory() as session:
        for batch in (await session.execute(select(SyncBatch))).scalars().all():
            response = json.loads(json.dumps(batch.response))
            changed = False
            for result in response["results"]:
                server_row = result.get("server_row")
                if server_row and isinstance(server_row.get("note"), str):
                    server_row["note"] = transform(server_row["note"])
                    changed = True
            if changed:
                batch.response = response
        await session.commit()


# --- sync_batches.response ------------------------------------------------------------


async def test_a_conflict_answer_is_cached_with_its_note_sealed(
    two_clients, session_factory
) -> None:
    alice, bob = two_clients
    note = "private: grateful my mother is recovering"
    change = await _stale_edit_of_a_row_with_note(alice, bob, note=note)

    response = await bob.push(batch_id=str(uuid.uuid4()), changes=[change])
    result = response.json()["results"][0]
    assert result["status"] == "conflict"
    assert result["server_row"]["note"] == note  # the device still gets plaintext

    async with session_factory() as session:
        raw = (await session.execute(text("SELECT response FROM sync_batches"))).scalars().all()
        batches = (await session.execute(select(SyncBatch))).scalars().all()
    serialised = " ".join(value if isinstance(value, str) else json.dumps(value) for value in raw)
    assert note not in serialised

    sealed = [
        entry["server_row"]["note"]
        for batch in batches
        for entry in batch.response["results"]
        if entry.get("server_row")
    ]
    assert len(sealed) == 1
    assert sealed[0].startswith("v1:")
    assert FieldCipher(DEV_FIELD_ENC_KEY).decrypt(sealed[0]) == note


async def test_a_retried_batch_replays_the_original_plaintext_answer_byte_for_byte(
    two_clients, session_factory
) -> None:
    alice, bob = two_clients
    note = "a note only the user should ever read"
    change = await _stale_edit_of_a_row_with_note(alice, bob, note=note)
    batch_id = str(uuid.uuid4())

    first = await bob.push(batch_id=batch_id, changes=[change])
    async with session_factory() as session:
        history_before = len((await session.execute(select(RowHistory))).scalars().all())

    second = await bob.push(batch_id=batch_id, changes=[change])
    assert first.status_code == second.status_code == 200
    assert second.content == first.content
    assert second.json()["results"][0]["server_row"]["note"] == note

    async with session_factory() as session:  # nothing was applied a second time
        assert len((await session.execute(select(RowHistory))).scalars().all()) == history_before


@pytest.mark.parametrize("corruption", ["tampered_ciphertext", "legacy_plaintext"])
async def test_a_corrupt_cached_note_fails_the_replay_loudly_without_leaking_it(
    two_clients, session_factory, monkeypatch, corruption: str
) -> None:
    alice, bob = two_clients
    note = "never print this note"
    change = await _stale_edit_of_a_row_with_note(alice, bob, note=note)
    batch_id = str(uuid.uuid4())
    assert (await bob.push(batch_id=batch_id, changes=[change])).status_code == 200

    def corrupt(token: str) -> str:
        if corruption == "legacy_plaintext":
            return note
        prefix, body = token.split(":", 1)
        middle = len(body) // 2
        swapped = "A" if body[middle] != "A" else "B"
        return f"{prefix}:{body[:middle]}{swapped}{body[middle + 1 :]}"

    await _rewrite_cached_notes(session_factory, corrupt)

    recorder = RecordingLogger()
    monkeypatch.setattr("app.core.errors.logger", recorder)
    try:
        response = await bob.push(batch_id=batch_id, changes=[change])
    except FieldDecryptionError as exc:
        message = str(exc)
    else:
        assert response.status_code == 500
        message = response.text
    assert note not in message

    [logged] = recorder.events("unhandled_exception")
    assert logged["error_type"] == "FieldDecryptionError"
    assert note not in recorder.rendered()
    assert not recorder.used_exception_level()


# --- log lines ------------------------------------------------------------------------


async def test_a_schema_invalid_rejection_logs_field_names_and_codes_but_no_values(
    two_clients, monkeypatch
) -> None:
    alice, _ = two_clients
    recorder = RecordingLogger()
    monkeypatch.setattr(sync_service, "logger", recorder)

    note = "confidential note text"
    payload = mood_payload(
        str(uuid.uuid4()),
        updated_at=BASE_TIME,
        tags=[f"secret_tag_{i:02d}" for i in range(33)],
        note=note,
    )
    result = (await alice.push(changes=[_change("mood_logs", payload)])).json()["results"][0]
    assert (result["status"], result["reason"]) == ("rejected", "schema_invalid")

    [logged] = recorder.events("sync_change_rejected")
    assert logged["entity"] == "mood_logs"
    assert logged["row_id"] == payload["id"]
    assert logged["reason"] == "schema_invalid"
    assert "tags" in logged["error_fields"]
    assert "too_long" in logged["error_codes"]
    rendered = recorder.rendered()
    assert "secret_tag" not in rendered
    assert note not in rendered


async def test_an_unexpected_failure_applying_a_change_is_logged_without_values(
    two_clients, monkeypatch
) -> None:
    """A merged row that fails re-validation raises a pydantic error full of values."""
    alice, _ = two_clients
    recorder = RecordingLogger()
    monkeypatch.setattr(sync_service, "logger", recorder)

    real_merge_row = sync_service.merge_row

    def corrupting_merge_row(**kwargs: Any) -> Any:
        outcome = real_merge_row(**kwargs)
        if outcome.row is not None:
            outcome.row["tags"] = [f"leak_{i:02d}" for i in range(40)]
        return outcome

    monkeypatch.setattr(sync_service, "merge_row", corrupting_merge_row)

    note = "do not log this note"
    alice.stage("mood_logs", mood_payload(str(uuid.uuid4()), updated_at=BASE_TIME, note=note))
    result = (await alice.push()).json()["results"][0]
    assert (result["status"], result["reason"]) == ("rejected", "schema_invalid")

    [logged] = recorder.events("sync_change_failed")
    assert logged["entity"] == "mood_logs"
    assert logged["error_type"] == "ValidationError"
    assert "tags" in logged["error_fields"]
    assert logged["error_origin"]  # code locations survive for debugging
    rendered = recorder.rendered()
    assert "leak_" not in rendered
    assert note not in rendered
    assert not recorder.used_exception_level()


class _Probe(BaseModel):
    tags: list[str] = Field(max_length=1)
    note: str = Field(max_length=3)


def test_safe_exception_fields_never_carry_messages_or_inputs() -> None:
    with pytest.raises(ValidationError) as validation:
        _Probe.model_validate({"tags": ["secret_a", "secret_b"], "note": "secret note"})
    fields = safe_exception_fields(validation.value)
    assert fields["error_type"] == "ValidationError"
    assert fields["error_fields"] == ["note", "tags"]
    assert set(fields["error_codes"]) == {"string_too_long", "too_long"}
    assert "secret" not in repr(fields)

    with pytest.raises(KeyError) as key_error:
        {}["secret key value"]  # noqa: B018
    fields = safe_exception_fields(key_error.value)
    assert fields["error_type"] == "KeyError"
    assert "secret" not in repr(fields)
    assert any("test_sync_privacy.py" in frame for frame in fields["error_origin"])

    assert "error_origin" not in safe_exception_fields(key_error.value, include_origin=False)


async def test_a_request_validation_error_does_not_echo_the_submitted_input(client) -> None:
    response = await client.post(
        "/auth/login", json={"email": "leaky.person@example.com", "device_id": "d"}
    )
    assert response.status_code == 422
    assert "leaky.person" not in response.text
    details = response.json()["details"]
    assert details
    assert all("input" not in detail and "ctx" not in detail for detail in details)
    assert any(detail["loc"][-1] == "password" for detail in details)


def test_the_application_engine_hides_sql_parameters_in_errors() -> None:
    from app.db.session import get_engine

    assert get_engine().sync_engine.hide_parameters is True


# --- migration 0009 -------------------------------------------------------------------


def _load_migration() -> ModuleType:
    spec = importlib.util.spec_from_file_location("migration_0009", MIGRATION_PATH)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_the_cache_sweep_migration_names_only_columns_that_are_encrypted() -> None:
    migration = _load_migration()
    assert migration.down_revision == "0008_wellbeing_logs"
    encrypted = {
        entity.name: encrypted_column_names(entity.model) for entity in registry.all_entities()
    }
    for table, columns in migration.ENCRYPTED_COLUMNS.items():
        assert set(columns) <= encrypted[table], table


@pytest.mark.parametrize("version", [1, 2, 17])
def test_the_cache_sweep_recognises_ciphertext_and_nothing_else(version: int) -> None:
    pattern = re.compile(_load_migration().CIPHERTEXT_PATTERN)
    assert pattern.match(FieldCipher(DEV_FIELD_ENC_KEY, version=version).encrypt("x"))
    for not_ciphertext in ("plain note", "v1: spaced", "v1:", "V1:abc", "", "v:abc"):
        assert not pattern.match(not_ciphertext)

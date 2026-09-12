"""The server half of the cross-stack wire contract.

`packages/kunim_contracts/golden/<entity>.json` holds the payload each Flutter
repository actually enqueues, captured by
`apps/mobile/test/sync/wire_contract_test.dart`. Here we validate those exact
payloads against the Pydantic row schema the server really uses.

Why this exists: the Dart suite asserted against a Dart `FakeSyncServer` and
this suite against Python-built payloads, so nothing compared the two. All
seven Phase-2 entities were being rejected as `schema_invalid` by the real
server while both suites were green. With this test in place, changing either
side without the other fails here or in the Dart test.
"""

from __future__ import annotations

import json
from pathlib import Path

import pytest
from pydantic import ValidationError

from app.modules.sync import registry

GOLDEN_DIR = Path(__file__).resolve().parents[3] / "packages" / "kunim_contracts" / "golden"


def _golden_files() -> list[Path]:
    return sorted(GOLDEN_DIR.glob("*.json"))


def test_golden_directory_is_present_and_populated() -> None:
    assert GOLDEN_DIR.is_dir(), (
        f"{GOLDEN_DIR} is missing. Generate it with:\n"
        "  cd apps/mobile && flutter test test/sync/wire_contract_test.dart "
        "--dart-define=UPDATE_GOLDEN=true"
    )
    assert _golden_files(), "no golden payloads found"


@pytest.mark.parametrize("path", _golden_files(), ids=lambda p: p.stem)
def test_client_payload_validates_against_the_server_schema(path: Path) -> None:
    entity_name = path.stem
    entity = registry.get_entity(entity_name)
    assert entity is not None, (
        f"golden file exists for '{entity_name}' but no such sync entity is "
        "registered -- rename the file or register the entity."
    )

    payload = json.loads(path.read_text(encoding="utf-8"))

    try:
        entity.schema.model_validate(payload)
    except ValidationError as exc:  # pragma: no cover - failure path
        pytest.fail(
            f"the payload {entity_name} repository sends is rejected by "
            f"{entity.schema.__name__}:\n{exc}\n\n"
            "Either the client payload builder or the server row schema is "
            "wrong. They must describe the same field set, with the same "
            "names and value formats."
        )


def test_every_pushable_entity_has_a_golden_payload() -> None:
    """A new syncable entity must arrive with a captured client payload.

    Without this, an entity can be registered, ship, and only fail on a real
    device -- which is exactly how the Phase-2 breakage went unnoticed.
    """
    covered = {path.stem for path in _golden_files()}
    pushable = {entity.name for entity in registry.all_entities() if entity.pushable}

    # `preferences` is server-authored today: no client repository pushes it
    # (the local `Preferences` table is an unrelated key/value store), so there
    # is no client payload to capture yet.
    exempt = {"preferences"}

    missing = pushable - covered - exempt
    assert not missing, (
        f"pushable entities with no golden client payload: {sorted(missing)}. "
        "Add a case to apps/mobile/test/sync/wire_contract_test.dart."
    )

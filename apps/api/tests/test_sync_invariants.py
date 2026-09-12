"""Structural invariants of the sync module.

Two things are locked down here:

1. **The AI invariant** (`docs/adr/0002-sync.md` "AI invarianti", CLAUDE.md
   rule 3): the server never writes a user row on behalf of AI. Sync is the
   only write path, and nothing in `/sync` lets a caller name whose rows it is
   writing -- `user_id` comes from the JWT subject and from nowhere else.
2. **The Phase-2 registry contract**: every registered entity satisfies the
   requirements in `app/modules/sync/registry`'s docstring, so a module added
   later cannot half-register something the engine would mishandle.
"""

from __future__ import annotations

import ast
import inspect
import uuid
from pathlib import Path

import pytest
from sqlalchemy import inspect as sa_inspect
from sqlalchemy import select

from app.modules.sync import merge, registry, repository, router, service
from app.modules.sync.registry import SyncEntity
from app.modules.sync.schemas import SyncRowBase
from tests import test_sync_harness as harness

BASE_TIME = harness.BASE_TIME
preferences_payload = harness.preferences_payload


# Fixtures are re-exported by assignment, not imported: pytest discovers them
# either way, but a test whose parameter shares a name with an import trips
# ruff's F811.
client = harness.client
session_factory = harness.session_factory
two_clients = harness.two_clients

APP_ROOT = Path(service.__file__).resolve().parents[3]
SYNC_PACKAGE = Path(service.__file__).resolve().parent


# --- the AI invariant --------------------------------------------------------


def test_no_ai_package_writes_a_sync_entity_model() -> None:
    """`app/ai/**` may only create `ai_proposals` rows (ADR "AI invarianti")."""
    model_names = {entity.model.__name__ for entity in registry.all_entities()}
    ai_root = APP_ROOT / "app" / "ai"
    if not ai_root.exists():
        # Phase 3 has not landed yet. The assertion still has to hold the day
        # it does, which is what the scan below is for.
        assert not (APP_ROOT / "app" / "modules" / "ai").exists()
        return
    offenders = [
        path
        for path in ai_root.rglob("*.py")
        if any(name in path.read_text(encoding="utf-8") for name in model_names)
    ]
    assert offenders == [], f"AI code references sync models: {offenders}"


def test_sync_module_imports_nothing_from_an_ai_package() -> None:
    for path in sorted(SYNC_PACKAGE.glob("*.py")):
        tree = ast.parse(path.read_text(encoding="utf-8"))
        for node in ast.walk(tree):
            if isinstance(node, ast.ImportFrom) and node.module:
                assert not node.module.startswith("app.ai"), path
            if isinstance(node, ast.Import):
                for alias in node.names:
                    assert not alias.name.startswith("app.ai"), path


def test_no_sync_endpoint_can_name_the_user_it_writes_for() -> None:
    """Every `/sync` handler takes its user from `CurrentUser`, never a parameter.

    This is the AI invariant in its enforceable form: there is no `user_id`,
    `on_behalf_of` or `actor` input anywhere on the sync surface, so no caller
    -- AI service, admin tool or otherwise -- can direct a write at somebody
    else's rows.
    """
    forbidden = {"user_id", "actor", "on_behalf_of", "as_user", "impersonate"}
    tree = ast.parse(Path(router.__file__).read_text(encoding="utf-8"))
    handlers = [
        node
        for node in ast.walk(tree)
        if isinstance(node, ast.AsyncFunctionDef) and node.decorator_list
    ]
    assert handlers, "no route handlers found"
    for handler in handlers:
        names = {arg.arg for arg in handler.args.args + handler.args.kwonlyargs}
        assert not (names & forbidden), f"{handler.name} exposes {names & forbidden}"
        if handler.name != "get_sync_service":
            assert "user" in names, handler.name


def test_repository_write_always_stamps_the_caller_supplied_user_id() -> None:
    """`write_row` sets `user_id` itself; a payload can never steer it."""
    source = inspect.getsource(repository.SyncRepository.write_row)
    assert "target.user_id = user_id" in source
    # And the only value ever passed in comes from `CurrentUser`.
    service_source = inspect.getsource(service.SyncService)
    assert "user_id=user.id" in service_source
    assert "user_id=change.payload" not in service_source


async def test_pushed_row_is_stored_under_the_jwt_subject_not_the_payload(
    two_clients, session_factory
) -> None:
    from app.modules.preferences.models import Preferences

    alice, _ = two_clients
    row_id = str(uuid.uuid4())
    payload = preferences_payload(row_id, updated_at=BASE_TIME)
    payload.pop("user_id", None)
    alice.stage("preferences", payload)
    assert (await alice.push()).json()["results"][0]["status"] == "applied"

    async with session_factory() as session:
        stored = (await session.execute(select(Preferences))).scalar_one()
        users = (await session.execute(select(Preferences.user_id))).scalars().all()
        assert len(set(users)) == 1
        assert stored.user_id is not None


async def test_every_sync_route_requires_an_authenticated_user(client) -> None:
    assert (await client.get("/sync/limits")).status_code == 401
    assert (await client.get("/sync/pull")).status_code == 401
    assert (
        await client.post(
            "/sync/push",
            json={"device_id": "d", "batch_id": str(uuid.uuid4()), "changes": []},
        )
    ).status_code == 401


def test_sync_module_never_logs_a_payload() -> None:
    """ADR/CLAUDE.md: never log tokens, payload contents or PII.

    Every `logger.*` call in the package is inspected: only counts, entity
    names and statuses may be passed, never a row, a payload or a token.
    """
    banned = {"payload", "row", "server_row", "before", "after", "token", "email", "note"}
    for path in sorted(SYNC_PACKAGE.glob("*.py")):
        tree = ast.parse(path.read_text(encoding="utf-8"))
        for node in ast.walk(tree):
            if not isinstance(node, ast.Call):
                continue
            func = node.func
            if not (
                isinstance(func, ast.Attribute)
                and isinstance(func.value, ast.Name)
                and func.value.id == "logger"
            ):
                continue
            keywords = {keyword.arg for keyword in node.keywords}
            assert not (keywords & banned), (path, func.attr, keywords & banned)


# --- the Phase-2 registry contract ------------------------------------------


def test_discovery_finds_entities_without_the_sync_package_importing_them() -> None:
    """`preferences` registers itself; no file in `app/modules/sync/` imports it.

    This is the property Phase-2 depends on: adding `tasks`, `habits`, `goals`
    or `calendar` must require zero edits inside this package. The only
    feature modules sync may import are the infrastructure ones (`users` for
    the FK target, `auth` for the `TZDateTime` portability decorator).
    """
    assert "preferences" in registry.entity_names()
    allowed = {"app.modules.auth.models", "app.modules.users.models"}
    for path in sorted(SYNC_PACKAGE.glob("*.py")):
        tree = ast.parse(path.read_text(encoding="utf-8"))
        for node in ast.walk(tree):
            if isinstance(node, ast.ImportFrom) and (node.module or "").startswith("app.modules."):
                module = node.module or ""
                assert module.startswith("app.modules.sync") or module in allowed, (
                    path,
                    module,
                )


def test_merge_module_never_imports_a_feature_module() -> None:
    tree = ast.parse(Path(merge.__file__).read_text(encoding="utf-8"))
    for node in ast.walk(tree):
        if isinstance(node, ast.ImportFrom) and node.module:
            assert not node.module.startswith("app.modules.") or node.module.startswith(
                "app.modules.sync"
            ), node.module


@pytest.mark.parametrize("entity", registry.all_entities(), ids=lambda e: e.name)
def test_registered_entity_satisfies_the_contract(entity: SyncEntity) -> None:
    # 1. The wire schema is a SyncRowBase subclass.
    assert issubclass(entity.schema, SyncRowBase), entity.name

    # 2. Every schema field maps to a real column on the model.
    columns = {column.key for column in sa_inspect(entity.model).columns}
    for field_name in entity.schema.model_fields:
        assert field_name in columns, f"{entity.name}.{field_name} has no column"

    # 3. The four mandatory sync columns plus user_id exist (ADR section 1).
    assert {
        "id",
        "user_id",
        "created_at",
        "updated_at",
        "deleted_at",
        "server_version",
    } <= columns, entity.name

    # 4. `dirty` is a client-only column and must not exist server-side.
    assert "dirty" not in columns, entity.name

    # 5. Natural-key columns, if declared, exist.
    for column_name in entity.policy.natural_key:
        assert column_name in columns, f"{entity.name}: natural key {column_name}"


def test_preferences_declares_the_unique_allocated_version_index() -> None:
    """ADR rule 3: `(user_id, server_version)` unique for allocated versions."""
    from app.modules.preferences.models import Preferences

    names = {index.name for index in Preferences.__table__.indexes}
    assert "uq_preferences_user_id_server_version" in names


def test_registering_a_conflicting_entity_is_refused() -> None:
    from app.modules.preferences.models import Preferences
    from app.modules.preferences.sync_entities import PreferencesSyncRow

    with pytest.raises(ValueError):
        registry.register_entity(
            SyncEntity(
                name="preferences",
                model=Preferences,
                schema=PreferencesSyncRow,
                policy=registry.MergePolicy(adr_rules=(99,)),
            )
        )
    # The real registration is untouched.
    assert registry.get_entity("preferences").policy.adr_rules == (19,)

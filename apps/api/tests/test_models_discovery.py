"""Guards for the Alembic metadata completeness invariant.

`alembic revision --autogenerate` diffs `Base.metadata` against the live
database. A model module that is never imported is missing from the metadata,
and autogenerate reads that absence as "table removed" -- it will happily
write `op.drop_table()` for a table full of user data.

That is not hypothetical: `env.py` used to import `auth` and `users` only,
while `preferences`, `sync`, `tasks`, `habits`, `goals` and `calendar` had all
grown model modules, so `alembic check` reported ten live tables as removed.

These tests fail if a feature package grows a `models.py` that discovery
cannot see, or if the model layer and the migration history drift apart.
"""

from __future__ import annotations

import re
from pathlib import Path

from app.db.base import Base
from app.db.models_discovery import import_all_models

API_ROOT = Path(__file__).resolve().parents[1]
MODULES_DIR = API_ROOT / "app" / "modules"
VERSIONS_DIR = API_ROOT / "app" / "db" / "migrations" / "versions"

_CREATE_TABLE = re.compile(r"""create_table\(\s*["']([a-z_]+)["']""")
_TABLENAME = re.compile(r"""__tablename__\s*=\s*["']([a-z_]+)["']""")

# Tables declared by the test suite itself (e.g. the registry contract
# fixture) live on `Base.metadata` so `create_all` builds them, but they
# deliberately have no migration. A test-only table MUST use this prefix, and
# `_test_only_tables` checks it really is declared under `tests/`.
TEST_ONLY_TABLE_PREFIX = "sync_fixture_"


def _tables_created_by_migrations() -> set[str]:
    """Every table name passed to `op.create_table` in the version history."""
    names: set[str] = set()
    for path in sorted(VERSIONS_DIR.glob("*.py")):
        names.update(_CREATE_TABLE.findall(path.read_text(encoding="utf-8")))
    return names


def _test_only_tables() -> set[str]:
    """Prefixed tables that are genuinely declared under `tests/`.

    Reading the declarations from disk means a *production* model cannot get
    itself excused from the migration check just by adopting the prefix.
    """
    declared: set[str] = set()
    for path in sorted(Path(__file__).resolve().parent.glob("*.py")):
        declared.update(_TABLENAME.findall(path.read_text(encoding="utf-8")))
    return {name for name in declared if name.startswith(TEST_ONLY_TABLE_PREFIX)}


def test_every_models_module_on_disk_is_discovered() -> None:
    """Discovery must find every `app/modules/*/models.py` that exists."""
    on_disk = {f"app.modules.{path.parent.name}.models" for path in MODULES_DIR.glob("*/models.py")}
    assert on_disk, "no model modules found on disk -- the glob or layout changed"

    discovered = set(import_all_models())

    missing = on_disk - discovered
    assert not missing, (
        f"model modules exist on disk but were not imported: {sorted(missing)}. "
        "Autogenerate would emit drop_table for their tables."
    )


def test_metadata_and_migrations_describe_the_same_tables() -> None:
    """The ORM metadata and the migration history must not drift apart.

    Derived from the migration files rather than a hand-kept list, so the
    guard cannot rot the way the `env.py` import list did.
    """
    import_all_models()

    migrated = _tables_created_by_migrations()
    assert migrated, "no create_table calls found -- the regex or layout changed"

    # Whether the test suite has been imported yet depends on run order, so
    # subtract only the fixture tables that really exist under `tests/`.
    registered = set(Base.metadata.tables) - _test_only_tables()

    only_in_metadata = registered - migrated
    only_in_migrations = migrated - registered

    assert not only_in_metadata, (
        f"models define tables with no migration: {sorted(only_in_metadata)}. "
        "Write a migration, or the table will not exist in a real database."
    )
    assert not only_in_migrations, (
        f"migrations create tables no model describes: {sorted(only_in_migrations)}. "
        "Import the model module, or autogenerate will emit drop_table for it."
    )


def test_import_all_models_is_idempotent() -> None:
    first = import_all_models()
    second = import_all_models()
    assert first == second

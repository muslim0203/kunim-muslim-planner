"""Declarative registry of syncable entities -- the Phase-2 contract.

`docs/adr/0002-sync.md` makes `SYNC_ENTITIES` the **single** list of syncable
tables on the server: it drives `/sync/push` validation, `/sync/pull`
projection and `/sync/limits`. This module is that list, plus the data model
the conflict matrix is written in.

What a feature module must provide
==================================

A feature module (e.g. `app/modules/tasks/`) makes its table syncable by
adding **one file**, `sync_entities.py`, inside its own package::

    # app/modules/tasks/sync_entities.py
    from app.modules.sync.registry import (
        FieldRule, MergePolicy, MergeStrategy, SyncEntity, register_entity,
    )
    from app.modules.sync.schemas import SyncRowBase, UtcDatetime
    from app.modules.tasks.models import Task


    class TaskSyncRow(SyncRowBase):           # wire schema
        title: str
        completed_at: UtcDatetime | None = None
        ...

    register_entity(
        SyncEntity(
            name="tasks",                     # == table name == wire `entity`
            model=Task,                       # ORM class
            schema=TaskSyncRow,               # wire schema (subclass of SyncRowBase)
            policy=MergePolicy(
                adr_rules=(8,),
                field_rules=(
                    FieldRule("completed_at", MergeStrategy.max_wins, adr_rule=8),
                ),
                ignored_fields=("completed",),
            ),
        )
    )

`discover()` imports every `app.modules.*.sync_entities` module exactly once,
so **nothing inside `app/modules/sync/` changes** when an entity is added.

Hard requirements on the registered pieces (ADR §1 / rule 3):

1. The ORM model carries `UUIDPk`, `Timestamps`, `SoftDelete`, `Versioned`
   from `app/db/mixins.py`, plus a `user_id` FK.
2. The wire schema subclasses `SyncRowBase`, so it always has
   `id`/`user_id`/`created_at`/`updated_at`/`deleted_at`/`server_version`.
   Every field name in the schema must match a column name on the model --
   persistence is `setattr(row, field, value)` for exactly those names.
   Timestamp fields use `UtcDatetime`, never a bare `datetime`.
3. The migration adds `UNIQUE (user_id, server_version) WHERE server_version > 0`
   (allocated versions are unique per user; `0` is the ADR's "never allocated"
   sentinel).
4. Any natural key is declared in `MergePolicy.natural_key` -- otherwise ADR
   rule 14 (two devices, same natural key, different UUIDs) cannot fire and
   the collision surfaces as a 500 from a unique-index violation instead.

Merge policies are *data*
=========================

A `MergePolicy` is a table of `FieldRule`s, each tagged with the ADR conflict
matrix row it implements, so a test can address one rule at a time (ADR
"Test majburiyati"). `merge.py` interprets them; it contains no per-entity
branching. Ready-made policies for every entity named in the ADR matrix live
in `merge.ADR_ENTITY_POLICIES`, so a Phase-2 module can reference the
normative policy instead of re-typing it.
"""

from __future__ import annotations

import importlib
import pkgutil
from dataclasses import dataclass, field
from enum import StrEnum
from typing import TYPE_CHECKING, Any

if TYPE_CHECKING:  # pragma: no cover - typing only
    from pydantic import BaseModel


class SyncDirection(StrEnum):
    """Which way rows are allowed to travel (ADR "Jadval tasnifi")."""

    bidirectional = "bidirectional"
    upload_only = "upload_only"
    """Pushed by the client, never returned by pull (`dw_*`, ADR rules 21-22)."""
    pull_only = "pull_only"
    """Server-owned cache (`content`, Qur'an text, presets). Push -> rule 24."""


class MergeStrategy(StrEnum):
    """How one field is combined when two devices disagree."""

    lww = "lww"
    """Take the field from the last-write-wins winner (the default)."""
    max_wins = "max_wins"
    """Take the larger of the two values; `None` is the smallest (ADR 8, 9, 13, 16, 21, 25)."""
    enum_max_wins = "enum_max_wins"
    """`max_wins` over an explicit ordering of string values (ADR 10)."""
    set_union = "set_union"
    """Union of two lists treated as sets, order-stabilised (ADR 11, 25)."""
    grouped_lww = "grouped_lww"
    """Every field sharing `group` comes from one and the same winner (ADR 12)."""
    derived = "derived"
    """Server-recomputed from other fields; never max-wins (ADR 12 `duration_min`)."""


@dataclass(frozen=True, slots=True)
class FieldRule:
    """One addressable cell of the conflict matrix.

    `adr_rule` is the row number in `docs/adr/0002-sync.md`; every rule must
    carry it, and `tests/test_sync_merge_matrix.py` names its test after it.
    """

    field: str
    strategy: MergeStrategy
    adr_rule: int
    enum_order: tuple[str, ...] = ()
    """Ordering for `enum_max_wins`, smallest first."""
    group: str | None = None
    """Group name for `grouped_lww` / `derived` (fields decided together)."""
    max_items: int | None = None
    """Upper bound on a `set_union` result; `None` means unbounded.

    Must equal the wire schema's list limit for the field, so a merged row
    always re-validates. See `merge._set_union` for the deterministic cut.
    """

    def __post_init__(self) -> None:
        if self.strategy is MergeStrategy.enum_max_wins and not self.enum_order:
            raise ValueError(f"enum_max_wins rule for {self.field!r} needs enum_order")
        if self.strategy in (MergeStrategy.grouped_lww, MergeStrategy.derived) and not self.group:
            raise ValueError(f"{self.strategy} rule for {self.field!r} needs a group")
        if self.max_items is not None:
            if self.strategy is not MergeStrategy.set_union:
                raise ValueError(f"max_items on {self.field!r} is only valid for set_union")
            if self.max_items < 1:
                raise ValueError(f"max_items on {self.field!r} must be >= 1")


@dataclass(frozen=True, slots=True)
class MergePolicy:
    """Per-entity merge rules. An empty policy means pure row-level LWW."""

    adr_rules: tuple[int, ...] = ()
    """ADR matrix rows this policy implements (documentation + test index)."""
    natural_key: tuple[str, ...] = ()
    """Columns forming the natural key, e.g. `("user_id", "ref_id", "date")`.

    Empty means the row has no identity beyond its UUID, and ADR rule 14
    (natural-key collision) does not apply.
    """
    field_rules: tuple[FieldRule, ...] = ()
    append_only: bool = False
    """ADR rule 22: idempotent insert by `id`, never a conflict."""
    ignored_fields: tuple[str, ...] = ()
    """Fields that are never synced (ADR rule 8: `tasks.completed`)."""

    def rule_for(self, name: str) -> FieldRule | None:
        for rule in self.field_rules:
            if rule.field == name:
                return rule
        return None

    def rules_for_adr(self, adr_rule: int) -> tuple[FieldRule, ...]:
        """Every field rule implementing one matrix row (test addressing)."""
        return tuple(rule for rule in self.field_rules if rule.adr_rule == adr_rule)

    def group_members(self, group: str) -> tuple[str, ...]:
        return tuple(rule.field for rule in self.field_rules if rule.group == group)


@dataclass(frozen=True, slots=True)
class SyncEntity:
    """One syncable table as the sync engine sees it."""

    name: str
    """Wire `entity` value; equal to the table name."""
    model: type[Any]
    """SQLAlchemy ORM class (see the requirements in the module docstring)."""
    schema: type[BaseModel]
    """Wire schema; must subclass `app.modules.sync.schemas.SyncRowBase`."""
    policy: MergePolicy = field(default_factory=MergePolicy)
    direction: SyncDirection = SyncDirection.bidirectional

    @property
    def pushable(self) -> bool:
        return self.direction is not SyncDirection.pull_only

    @property
    def pullable(self) -> bool:
        return self.direction is SyncDirection.bidirectional


# --- the registry itself ----------------------------------------------------

_ENTITIES: dict[str, SyncEntity] = {}
_DISCOVERED = False


def register_entity(entity: SyncEntity) -> SyncEntity:
    """Register one entity. Idempotent for an identical re-registration."""
    existing = _ENTITIES.get(entity.name)
    if existing is not None and existing != entity:
        raise ValueError(f"sync entity {entity.name!r} is already registered with different rules")
    _ENTITIES[entity.name] = entity
    return entity


def unregister_entity(name: str) -> None:
    """Remove an entity. Only for tests that register a fixture entity."""
    _ENTITIES.pop(name, None)


def discover() -> None:
    """Import every `app.modules.<pkg>.sync_entities` module once.

    This is what keeps `app/modules/sync/` free of imports of feature
    modules: an entity is added by creating a file in its own package, never
    by editing a list here.
    """
    global _DISCOVERED
    if _DISCOVERED:
        return
    # Set before importing: a feature module that (transitively) triggers
    # discovery again must not recurse.
    _DISCOVERED = True

    import app.modules as modules_pkg

    for module_info in pkgutil.iter_modules(modules_pkg.__path__):
        if not module_info.ispkg or module_info.name == "sync":
            continue
        candidate = f"app.modules.{module_info.name}.sync_entities"
        try:
            importlib.import_module(candidate)
        except ModuleNotFoundError as exc:
            # Only swallow "this package has no sync_entities module"; a real
            # ImportError inside an existing one must not be hidden.
            if exc.name != candidate:
                raise


def get_entity(name: str) -> SyncEntity | None:
    """Look up an entity by wire name, or `None` -> ADR `unknown_entity`."""
    discover()
    return _ENTITIES.get(name)


def all_entities() -> tuple[SyncEntity, ...]:
    discover()
    return tuple(_ENTITIES[name] for name in sorted(_ENTITIES))


def entity_names() -> tuple[str, ...]:
    discover()
    return tuple(sorted(_ENTITIES))

"""Import every `app.modules.<pkg>.models` module so it registers on
`Base.metadata`.

Alembic's autogenerate compares `Base.metadata` against the live database.
Any model module that has not been imported is simply *absent* from the
metadata, and autogenerate reads that absence as "the table was removed" --
so a forgotten import turns the next `alembic revision --autogenerate` into a
migration that drops real tables.

Listing the modules by hand is what caused exactly that: `env.py` imported
`auth` and `users` only, while `preferences`, `sync`, `tasks`, `habits`,
`goals` and `calendar` had all grown model modules. Discovery removes the
class of bug rather than the instance -- adding a module needs no edit here.

Mirrors `app.modules.sync.registry.discover()`, which does the same thing for
`sync_entities` modules.
"""

from __future__ import annotations

import importlib
import pkgutil

_DISCOVERED = False


def import_all_models() -> tuple[str, ...]:
    """Import all feature model modules once; return the module names found.

    Idempotent: later calls return the same list without re-importing.
    """
    global _DISCOVERED

    import app.modules as modules_pkg

    found: list[str] = []
    for module_info in pkgutil.iter_modules(modules_pkg.__path__):
        if not module_info.ispkg:
            continue
        candidate = f"app.modules.{module_info.name}.models"
        try:
            importlib.import_module(candidate)
        except ModuleNotFoundError as exc:
            # Swallow only "this package has no models module"; a genuine
            # ImportError *inside* an existing one must not be hidden, or a
            # broken model would silently disappear from the metadata again.
            if exc.name != candidate:
                raise
            continue
        found.append(candidate)

    _DISCOVERED = True
    return tuple(sorted(found))

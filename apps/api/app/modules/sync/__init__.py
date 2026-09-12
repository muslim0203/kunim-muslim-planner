"""Offline-first sync: the single write path for user rows.

Specified by `docs/adr/0002-sync.md` (normative). Layout:

* `registry.py`   -- the declarative entity registry + merge-policy data model.
                     This is the contract feature modules code against.
* `schemas.py`    -- wire contract (push/pull/limits) and the row base schema.
* `models.py`     -- sync-owned tables: `sync_user_state`, `sync_batches`,
                     `row_history`, `sync_merged_rows`.
* `merge.py`      -- the ADR conflict matrix expressed as *data*; the only
                     place merge decisions are made (ADR: "Merge faqat
                     serverda").
* `repository.py` -- generic, entity-agnostic data access.
* `service.py`    -- push/pull orchestration, savepoints, idempotency,
                     retention.
* `router.py`     -- `POST /sync/push`, `GET /sync/pull`, `GET /sync/limits`.

Nothing in this package imports a feature module: entities register themselves
(see `registry`), so adding `tasks`/`habits`/`goals`/`calendar` in Phase 2
requires **no edit inside this package**.
"""

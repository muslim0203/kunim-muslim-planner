"""Retention cleanup (ADR-0002 rule 11).

`SyncService.run_retention` purges tombstones (90 days), `row_history`
(30 days) and `sync_batches` (7 days), and records the tombstone watermark in
`sync_user_state.purged_up_to_version`. It was implemented and tested but
never scheduled -- the worker registered only a diagnostic `ping` -- so in a
running deployment nothing ever called it. Three consequences, all silent:

* tombstones, row history and batch records grow without bound;
* `purged_up_to_version` stays 0, so `full_resync_required` never fires, and a
  client whose cursor has fallen behind the tombstone window is never told to
  resync -- it just quietly stops receiving deletes;
* the ADR's 90/30/7-day retention promises are not kept, which matters for the
  privacy commitment in `docs/plan.md` section 11 as much as for disk.

Scheduled daily; see `app.jobs.worker.WorkerSettings.cron_jobs`.
"""

from __future__ import annotations

from typing import Any

import structlog

from app.core.logging import safe_exception_fields
from app.db.session import get_sessionmaker
from app.modules.sync.service import SyncService

logger = structlog.get_logger(__name__)


async def sync_retention(ctx: dict[str, Any]) -> dict[str, int]:  # noqa: ARG001
    """Run the sync retention sweep once.

    Returns the per-category counts so a run is visible in arq's job results.
    Failures are logged and re-raised: rule 11 requires a failed sweep to be
    noticed, and swallowing it here would let retention silently lapse again
    -- the very thing this job exists to prevent.
    """
    session_factory = get_sessionmaker()
    async with session_factory() as session:
        try:
            stats = await SyncService(session).run_retention()
        except Exception as exc:
            # No payloads, row contents or exception text (which can carry SQL
            # parameters) in the log -- type and code location only.
            logger.error("sync_retention_failed", **safe_exception_fields(exc))
            raise

    logger.info(
        "sync_retention",
        batches=stats["batches"],
        row_history=stats["row_history"],
        tombstones=stats["tombstones"],
    )
    return stats

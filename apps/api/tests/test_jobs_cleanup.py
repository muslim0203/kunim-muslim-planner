"""The retention sweep must actually be scheduled, not merely implemented.

`SyncService.run_retention` was written, correct and unit-tested from the
start -- and never called anywhere but a test. The worker registered only a
diagnostic `ping`, so in a running deployment tombstones, `row_history` and
`sync_batches` grew for ever and `purged_up_to_version` stayed 0, which means
`full_resync_required` could never fire for a client whose cursor had fallen
behind the tombstone window.

"Implemented but unreachable" is invisible to a test that calls the function
directly, so these tests assert the wiring itself.
"""

from __future__ import annotations

import uuid
from datetime import timedelta
from typing import Any

import pytest
from sqlalchemy import select

from app.db.models_discovery import import_all_models
from app.jobs import cleanup
from app.jobs.worker import WorkerSettings
from app.modules.sync.models import SyncUserState
from tests import test_sync_harness as harness

# `run_retention` sweeps EVERY registered entity, and the registry imports
# entity modules lazily. Without this the harness's `create_all` runs before
# the phase-2 models are on `Base.metadata`, and the sweep hits a table that
# was never created.
import_all_models()

BASE_TIME = harness.BASE_TIME
preferences_payload = harness.preferences_payload

client = harness.client
session_factory = harness.session_factory
two_clients = harness.two_clients


def test_the_retention_job_is_registered_with_the_worker() -> None:
    assert cleanup.sync_retention in WorkerSettings.functions, (
        "`sync_retention` must be registered, or it can never be enqueued"
    )


def test_the_retention_job_is_scheduled() -> None:
    """A registered-but-unscheduled job is the bug this file exists for."""
    assert WorkerSettings.cron_jobs, "no cron jobs configured"

    names = {
        getattr(job.coroutine, "__name__", None)
        for job in WorkerSettings.cron_jobs
        if hasattr(job, "coroutine")
    }
    assert "sync_retention" in names, (
        f"the retention sweep has no cron entry; scheduled jobs are {names}"
    )


async def test_the_job_runs_the_sweep_and_reports_what_it_purged(
    two_clients: Any,
    session_factory: Any,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Exercise the job body, not just `run_retention` underneath it.

    The job opens its own session through `get_sessionmaker`, so that is what
    gets pointed at the test database.
    """
    alice, _ = two_clients

    # Dated well over the 90-day tombstone window before the real clock, so
    # the job's own `datetime.now(UTC)` is already past it. The job takes no
    # `now` argument on purpose -- a cron entry has no business being told
    # what time it is -- so the data has to be old rather than the clock moved.
    long_ago = BASE_TIME - timedelta(days=400)
    row_id = str(uuid.uuid4())
    alice.stage("preferences", preferences_payload(row_id, updated_at=long_ago))
    await alice.sync()
    alice.stage_delete("preferences", row_id, deleted_at=long_ago + timedelta(minutes=1))
    await alice.sync()

    monkeypatch.setattr(cleanup, "get_sessionmaker", lambda: session_factory)

    stats = await cleanup.sync_retention({})

    assert stats["tombstones"] >= 1, "the old tombstone was not purged"
    # `sync_batches` is dated by a server-side default, so the batches this
    # test just wrote are seconds old and correctly outside the 7-day window.
    assert stats["batches"] == 0

    async with session_factory() as session:
        state = (await session.execute(select(SyncUserState))).scalar_one()
        assert state.purged_up_to_version > 0, (
            "the watermark must rise, or `full_resync_required` can never fire"
        )


async def test_a_failing_sweep_is_not_swallowed(
    session_factory: Any, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Rule 11 wants a failed sweep noticed; a silent failure re-creates the
    exact "retention quietly lapsed" state this job was added to fix."""
    monkeypatch.setattr(cleanup, "get_sessionmaker", lambda: session_factory)

    async def boom(self: Any, **kwargs: Any) -> dict[str, int]:
        raise RuntimeError("purge failed")

    monkeypatch.setattr(cleanup.SyncService, "run_retention", boom)

    with pytest.raises(RuntimeError, match="purge failed"):
        await cleanup.sync_retention({})

"""arq worker entrypoint.

Run with:  arq app.jobs.worker.WorkerSettings

`ping` is a diagnostic job kept so the worker's Redis queue can be verified
end to end. `sync_retention` is the ADR-0002 rule 11 sweep.

Still to come (phases 5-8): stats_aggregate, daily_review, weekly_review,
monthly_review, notif_scheduler, daily_wisdom, ai_batch.
"""

from __future__ import annotations

from typing import Any

from arq import cron
from arq.connections import RedisSettings

from app.core.config import check_jwt_secret, get_settings
from app.core.logging import configure_logging
from app.db.types import get_field_cipher
from app.jobs.cleanup import sync_retention


async def startup(ctx: dict[str, Any]) -> None:  # noqa: ARG001
    settings = get_settings()
    # Same guards as `create_app`: the retention sweep loads rows with
    # encrypted notes, and the worker shares the API's configuration.
    check_jwt_secret(settings)
    get_field_cipher()
    configure_logging(settings)


async def shutdown(ctx: dict[str, Any]) -> None:  # noqa: ARG001
    return None


async def ping(ctx: dict[str, Any]) -> str:  # noqa: ARG001
    """Verify that queued jobs reach the worker and return results."""
    return "pong"


class WorkerSettings:
    """arq worker configuration."""

    functions: list[Any] = [ping, sync_retention]

    # 03:00 UTC daily: off the daily-review window (user-local 21:00) so a
    # long sweep cannot delay user-facing jobs. `run_retention` is idempotent,
    # so a missed or repeated run is harmless.
    cron_jobs: list[Any] = [
        cron(sync_retention, hour=3, minute=0, run_at_startup=False),
    ]
    on_startup = startup
    on_shutdown = shutdown
    max_jobs = 10
    job_timeout = 300

    redis_settings = RedisSettings.from_dsn(get_settings().REDIS_URL)

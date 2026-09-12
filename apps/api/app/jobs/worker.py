"""arq worker entrypoint.

Run with:  arq app.jobs.worker.WorkerSettings

Phase 0 registers a diagnostic ping job so the worker can start and its
Redis queue can be verified end to end.
Real jobs (stats_aggregate, daily_review, weekly_review, monthly_review,
notif_scheduler, daily_wisdom, ai_batch, cleanup) land in phases 2-8.
"""

from __future__ import annotations

from typing import Any

from arq.connections import RedisSettings

from app.core.config import get_settings
from app.core.logging import configure_logging


async def startup(ctx: dict[str, Any]) -> None:
    configure_logging(get_settings())


async def shutdown(ctx: dict[str, Any]) -> None:  # noqa: ARG001
    return None


async def ping(ctx: dict[str, Any]) -> str:  # noqa: ARG001
    """Verify that queued jobs reach the worker and return results."""
    return "pong"


class WorkerSettings:
    """arq worker configuration."""

    functions: list[Any] = [ping]
    cron_jobs: list[Any] = []
    on_startup = startup
    on_shutdown = shutdown
    max_jobs = 10
    job_timeout = 300

    redis_settings = RedisSettings.from_dsn(get_settings().REDIS_URL)

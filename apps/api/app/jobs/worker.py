"""arq worker entrypoint.

Run with:  arq app.jobs.worker.WorkerSettings

Phase 0 registers no jobs — this module exists so the `worker` container in
infra/docker-compose.yml has a valid entrypoint instead of crash-looping.
Real jobs (stats_aggregate, daily_review, weekly_review, monthly_review,
notif_scheduler, daily_wisdom, ai_batch, cleanup) land in phases 2-8.
"""

from __future__ import annotations

from typing import Any

from arq.connections import RedisSettings

from app.core.config import get_settings
from app.core.logging import configure_logging


async def startup(ctx: dict[str, Any]) -> None:
    configure_logging()


async def shutdown(ctx: dict[str, Any]) -> None:  # noqa: ARG001
    return None


class WorkerSettings:
    """arq worker configuration."""

    functions: list[Any] = []
    cron_jobs: list[Any] = []
    on_startup = startup
    on_shutdown = shutdown
    max_jobs = 10
    job_timeout = 300

    @staticmethod
    def redis_settings() -> RedisSettings:
        return RedisSettings.from_dsn(get_settings().REDIS_URL)

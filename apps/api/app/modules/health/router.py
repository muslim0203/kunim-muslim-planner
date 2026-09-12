"""Liveness/readiness endpoints.

`/health` never touches the database or Redis — it must return 200 even if
every downstream dependency is unreachable. `/health/ready` checks each
dependency but never raises; it reports per-dependency status instead.
"""

from __future__ import annotations

from importlib.metadata import PackageNotFoundError, version

import structlog
from fastapi import APIRouter
from sqlalchemy import text

from app.core.config import get_settings
from app.db.session import get_engine

logger = structlog.get_logger(__name__)

router = APIRouter(tags=["health"])


def _app_version() -> str:
    try:
        return version("kunim-api")
    except PackageNotFoundError:
        return "0.0.0-dev"


@router.get("/health")
async def health() -> dict:
    settings = get_settings()
    return {"status": "ok", "version": _app_version(), "env": settings.ENV}


async def _check_database() -> str:
    try:
        engine = get_engine()
        async with engine.connect() as conn:
            await conn.execute(text("SELECT 1"))
        return "ok"
    except Exception:  # noqa: BLE001 - any failure means "unavailable"
        logger.warning("health_ready_database_unavailable", exc_info=True)
        return "unavailable"


async def _check_redis() -> str:
    try:
        import redis.asyncio as redis

        settings = get_settings()
        client = redis.from_url(settings.REDIS_URL, socket_connect_timeout=1)
        try:
            await client.ping()
            return "ok"
        finally:
            await client.aclose()
    except Exception:  # noqa: BLE001 - any failure means "unavailable"
        logger.warning("health_ready_redis_unavailable", exc_info=True)
        return "unavailable"


@router.get("/health/ready")
async def health_ready() -> dict:
    database_status = await _check_database()
    redis_status = await _check_redis()
    return {
        "status": "ok",
        "dependencies": {
            "database": database_status,
            "redis": redis_status,
        },
    }

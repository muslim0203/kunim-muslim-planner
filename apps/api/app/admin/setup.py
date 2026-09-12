"""Mount SQLAdmin onto the app, without requiring a live database.

`sqladmin.Admin` and `ModelView` registration only build routes/metadata at
import/mount time — they do not open a database connection — so this is
safe to call even when Postgres is unreachable.
"""

from __future__ import annotations

import structlog
from fastapi import FastAPI

from app.core.config import Settings
from app.db.session import get_engine

logger = structlog.get_logger(__name__)


def mount_admin(app: FastAPI, settings: Settings) -> None:
    if not settings.ADMIN_ENABLED:
        return

    try:
        from sqladmin import Admin

        from app.admin.views import UserAdmin

        admin = Admin(app, get_engine(), title=f"{settings.APP_NAME} Admin")
        admin.add_view(UserAdmin)
    except Exception:  # noqa: BLE001 - admin is optional, never break app startup
        logger.error("admin_mount_failed", exc_info=True)

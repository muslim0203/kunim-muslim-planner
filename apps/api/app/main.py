"""FastAPI application factory."""

from __future__ import annotations

from importlib.metadata import PackageNotFoundError, version

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.admin.setup import mount_admin
from app.core.config import get_settings
from app.core.errors import register_exception_handlers
from app.core.logging import configure_logging
from app.middleware.request_id import RequestIDMiddleware
from app.modules.health.router import router as health_router


def _package_version() -> str:
    try:
        return version("kunim-api")
    except PackageNotFoundError:
        return "0.0.0-dev"


def create_app() -> FastAPI:
    settings = get_settings()
    configure_logging(settings)

    app = FastAPI(
        title="KUNIM API",
        version=_package_version(),
        debug=settings.DEBUG,
    )

    app.add_middleware(RequestIDMiddleware)

    if settings.CORS_ORIGINS:
        app.add_middleware(
            CORSMiddleware,
            allow_origins=settings.CORS_ORIGINS,
            allow_credentials=True,
            allow_methods=["*"],
            allow_headers=["*"],
        )

    register_exception_handlers(app, settings)

    app.include_router(health_router)

    mount_admin(app, settings)

    return app


app = create_app()

"""Structured logging setup using structlog.

Dev: human-readable console output.
Staging/Prod: single-line JSON, safe to ship to a log aggregator.

Log discipline (CLAUDE.md rule 7): never log secrets or personal data.
Exception messages are the easy way to break that by accident -- pydantic's
`ValidationError` repeats every rejected value, and a database error can
repeat bound parameters -- so code that logs a failure passes
`safe_exception_fields(exc)` instead of calling `logger.exception`.
"""

from __future__ import annotations

import logging
import sys
import traceback
from pathlib import Path
from typing import Any

import structlog
from pydantic import ValidationError

from app.core.config import Settings

_MAX_ORIGIN_FRAMES = 5


def configure_logging(settings: Settings) -> None:
    """Configure stdlib logging + structlog processors for the given env."""
    shared_processors: list[structlog.types.Processor] = [
        structlog.contextvars.merge_contextvars,
        structlog.processors.add_log_level,
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.processors.StackInfoRenderer(),
    ]

    if settings.ENV == "dev":
        renderer: structlog.types.Processor = structlog.dev.ConsoleRenderer()
    else:
        shared_processors.append(structlog.processors.format_exc_info)
        renderer = structlog.processors.JSONRenderer()

    structlog.configure(
        processors=[*shared_processors, renderer],
        wrapper_class=structlog.make_filtering_bound_logger(
            logging.DEBUG if settings.DEBUG else logging.INFO
        ),
        context_class=dict,
        logger_factory=structlog.PrintLoggerFactory(sys.stdout),
        cache_logger_on_first_use=True,
    )


def get_logger(name: str | None = None) -> structlog.BoundLogger:
    return structlog.get_logger(name)


def safe_exception_fields(exc: BaseException, *, include_origin: bool = True) -> dict[str, Any]:
    """Describe a failure for a log line without any of the data it carries.

    Returns the exception type; for a pydantic `ValidationError`, the failing
    field locations and error codes; and unless `include_origin` is false, the
    innermost code locations as ``file:line function``. Never `str(exc)`,
    source lines, local variables or input values.
    """
    fields: dict[str, Any] = {"error_type": type(exc).__name__}
    if isinstance(exc, ValidationError):
        errors = exc.errors(include_url=False, include_context=False, include_input=False)
        fields["error_fields"] = sorted(
            {".".join(str(part) for part in error["loc"]) or "__root__" for error in errors}
        )
        fields["error_codes"] = sorted({error["type"] for error in errors})
    if include_origin:
        frames = traceback.extract_tb(exc.__traceback__)[-_MAX_ORIGIN_FRAMES:]
        fields["error_origin"] = [
            f"{Path(frame.filename).name}:{frame.lineno} {frame.name}" for frame in frames
        ]
    return fields

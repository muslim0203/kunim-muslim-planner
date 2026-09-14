"""Problem-detail style JSON error responses.

Shape (loosely inspired by RFC 9457):
{
    "error": {
        "code": "http_404" | "internal_error" | ...,
        "message": "human readable message",
        "request_id": "..."
    }
}

Tracebacks are never included in the response body. Unhandled exceptions are
logged by exception type and code location only (`safe_exception_fields`) --
never the exception message, which can carry submitted values or SQL
parameters -- and returned to the client as a generic 500 unless DEBUG is
true, in which case the message is included in the response to ease local
development.

Unhandled exceptions are caught by `UnhandledExceptionMiddleware`, not by an
`@app.exception_handler(Exception)`: Starlette runs that handler inside its
`ServerErrorMiddleware`, which re-raises after responding so the server can
log the error -- and uvicorn then logs the full traceback, exception message
included (with DEBUG on, it even skips the handler and renders the traceback
into the response). Catching one layer further in keeps both the log and the
body free of the message.

Validation errors (422) list each failing location, code and message, but not
the rejected `input` or the constraint context: a body that echoes back a
password or a private note is exactly what proxies, error trackers and support
screenshots end up storing.
"""

from __future__ import annotations

from typing import Any

import structlog
from fastapi import FastAPI, HTTPException, Request, status
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.types import ASGIApp, Message, Receive, Scope, Send

from app.core.config import Settings
from app.core.logging import safe_exception_fields

logger = structlog.get_logger(__name__)

_DETAIL_KEYS_NEVER_ECHOED = frozenset({"input", "ctx", "url"})


def _error_body(code: str, message: str, request_id: str | None) -> dict:
    return {"error": {"code": code, "message": message, "request_id": request_id}}


def _request_id(request: Request) -> str | None:
    return getattr(request.state, "request_id", None)


class UnhandledExceptionMiddleware:
    """Last-resort JSON 500 that never logs or re-raises the exception message."""

    def __init__(self, app: ASGIApp, *, debug: bool) -> None:
        self.app = app
        self.debug = debug

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        response_started = False

        async def tracking_send(message: Message) -> None:
            nonlocal response_started
            if message["type"] == "http.response.start":
                response_started = True
            await send(message)

        try:
            await self.app(scope, receive, tracking_send)
        except Exception as exc:
            logger.error(
                "unhandled_exception", path=scope.get("path"), **safe_exception_fields(exc)
            )
            if response_started:
                # Too late for a 500; the server closes the broken response.
                return
            state: Any = scope.get("state") or {}
            request_id = state.get("request_id") if isinstance(state, dict) else None
            message = str(exc) if self.debug else "Internal server error"
            response = JSONResponse(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                content=_error_body("internal_error", message, request_id),
                headers={"X-Request-ID": request_id} if request_id else None,
            )
            await response(scope, receive, send)


def register_exception_handlers(app: FastAPI, settings: Settings) -> None:
    @app.exception_handler(HTTPException)
    async def http_exception_handler(request: Request, exc: HTTPException) -> JSONResponse:
        code = f"http_{exc.status_code}"
        return JSONResponse(
            status_code=exc.status_code,
            content=_error_body(code, str(exc.detail), _request_id(request)),
            headers=exc.headers,
        )

    @app.exception_handler(RequestValidationError)
    async def validation_exception_handler(
        request: Request, exc: RequestValidationError
    ) -> JSONResponse:
        details = [
            {key: value for key, value in error.items() if key not in _DETAIL_KEYS_NEVER_ECHOED}
            for error in exc.errors()
        ]
        return JSONResponse(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            content=_error_body("validation_error", "Invalid request", _request_id(request))
            | {"details": details},
        )

    # Added last, so it wraps every other user middleware (including
    # `RequestIDMiddleware`) and sits directly inside `ServerErrorMiddleware`.
    app.add_middleware(UnhandledExceptionMiddleware, debug=settings.DEBUG)

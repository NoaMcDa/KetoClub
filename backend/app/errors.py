"""The one path every backend-originated error takes.

A route or service raises ``BackendError(status_code, reason)``; the handler
``create_app`` registers turns it into a ``JSONResponse`` with an
``ErrorResponse`` body, exactly ``{"reason": ..., "status_code": ...}``: the
shape the Dart client parses. ``HTTPException`` is not used for these because
its body is ``{"detail": ...}``.

A request that fails validation keeps FastAPI's ``{"detail": [...]}`` 422, but
``handle_validation_error`` drops each entry's ``input`` (the submitted value,
which for ``/v1/chat`` can be a page's base64), ``ctx`` and ``url``.

Anything else a route raises is caught by ``UnhandledErrorMiddleware`` (#270)
and answered as ``500 {"reason":"internalError"}``, inside CORS, so a
browser sees the status instead of a CORS failure.
"""

import logging
from typing import Any, Final

from fastapi.exceptions import RequestValidationError
from starlette.requests import Request
from starlette.responses import JSONResponse
from starlette.types import ASGIApp, Message, Receive, Scope, Send

from app.schemas import ErrorResponse

_MAX_VALIDATION_ERRORS: Final = 20
_MAX_MESSAGE_CHARS: Final = 200

logger = logging.getLogger("ketoclub.errors")


class BackendError(Exception):
    """An error response this backend originates, as ``{reason, status_code}``."""

    def __init__(self, status_code: int, reason: str) -> None:
        super().__init__(f"{status_code} {reason}")
        self.status_code = status_code
        self.reason = reason


async def handle_backend_error(_request: Request, exc: Exception) -> JSONResponse:
    """Render a ``BackendError`` as its ``ErrorResponse`` body.

    Typed on ``Exception`` because that is the handler signature Starlette
    accepts; it is only ever registered for ``BackendError``.
    """
    if not isinstance(exc, BackendError):  # pragma: no cover - registration
        raise exc
    body = ErrorResponse(reason=exc.reason, status_code=exc.status_code)
    return JSONResponse(status_code=exc.status_code, content=body.model_dump())


async def handle_validation_error(_request: Request, exc: Exception) -> JSONResponse:
    """Render a validation failure as a 422 ``{"detail": [...]}`` that never
    echoes the request: each entry keeps only ``type``, ``loc`` and ``msg``,
    and both the entry count and each message are capped.

    Typed on ``Exception`` for the Starlette handler signature; it is only
    ever registered for ``RequestValidationError``.
    """
    if not isinstance(exc, RequestValidationError):  # pragma: no cover
        raise exc
    detail: list[dict[str, Any]] = [
        {
            "type": str(error.get("type", "")),
            "loc": list(error.get("loc", ())),
            "msg": str(error.get("msg", ""))[:_MAX_MESSAGE_CHARS],
        }
        for error in exc.errors()[:_MAX_VALIDATION_ERRORS]
    ]
    return JSONResponse(status_code=422, content={"detail": detail})


class UnhandledErrorMiddleware:
    """Answer any exception a route did not handle as a 500 ``internalError``.

    Starlette turns such an exception into a plain-text 500 in its outermost
    layer, outside ``CORSMiddleware``, so the response carried no
    ``Access-Control-Allow-Origin`` and the browser reported a CORS failure
    instead of the status (#270). Installed inside CORS, this one answers the
    backend's own ``{reason, status_code}`` body, which CORS then stamps.

    The log line names the exception's type only: its message can quote
    request content (a URL, a body fragment).
    """

    def __init__(self, app: ASGIApp) -> None:
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return
        started = False

        async def tracking_send(message: Message) -> None:
            nonlocal started
            if message["type"] == "http.response.start":
                started = True
            await send(message)

        try:
            await self.app(scope, receive, tracking_send)
        except Exception as error:
            if started:
                raise
            logger.error("unhandled error type=%s", type(error).__name__)
            body = ErrorResponse(reason="internalError", status_code=500)
            response = JSONResponse(status_code=500, content=body.model_dump())
            await response(scope, receive, send)

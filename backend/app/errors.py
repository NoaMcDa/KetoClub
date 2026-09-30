"""The one path every backend-originated error takes.

A route or service raises ``BackendError(status_code, reason)``; the handler
``create_app`` registers turns it into a ``JSONResponse`` with an
``ErrorResponse`` body, exactly ``{"reason": ..., "status_code": ...}``: the
shape the Dart client parses. ``HTTPException`` is not used for these because
its body is ``{"detail": ...}``.

A request that fails validation keeps FastAPI's ``{"detail": [...]}`` 422, but
``handle_validation_error`` drops each entry's ``input`` (the submitted value,
which for ``/v1/chat`` can be a page's base64), ``ctx`` and ``url``.
"""

from typing import Any, Final

from fastapi.exceptions import RequestValidationError
from starlette.requests import Request
from starlette.responses import JSONResponse

from app.schemas import ErrorResponse

_MAX_VALIDATION_ERRORS: Final = 20
_MAX_MESSAGE_CHARS: Final = 200


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

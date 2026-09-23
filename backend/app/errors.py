"""The one path every backend-originated error takes.

A route or service raises ``BackendError(status_code, reason)``; the handler
``create_app`` registers turns it into a ``JSONResponse`` with an
``ErrorResponse`` body, exactly ``{"reason": ..., "status_code": ...}``: the
shape the Dart client parses. ``HTTPException`` is not used for these because
its body is ``{"detail": ...}``.
"""

from starlette.requests import Request
from starlette.responses import JSONResponse

from app.schemas import ErrorResponse


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

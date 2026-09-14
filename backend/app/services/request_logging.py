"""Structured per-request logging middleware.

Emits exactly one log line per request: request id, route, method, status
code and latency. Never a key, an ``Authorization`` header, an upstream body
or prompt text (backend_plan.md §3.5) — the middleware never reads headers or
bodies at all, only the request's method and path and the response's status.
"""

import logging
import time
import uuid
from collections.abc import Awaitable, Callable

from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import Response

logger = logging.getLogger("ketoclub.request")
logger.setLevel(logging.INFO)
if not logger.handlers:
    # Attached directly to this logger rather than relying on root logging
    # configuration: uvicorn configures its own loggers, so a request line
    # would otherwise silently vanish unless something else happens to set
    # up the root logger first.
    _handler = logging.StreamHandler()
    _handler.setFormatter(
        logging.Formatter(
            "%(asctime)s request_id=%(request_id)s method=%(method)s "
            "route=%(route)s status=%(status)s latency_ms=%(latency_ms)s"
        )
    )
    logger.addHandler(_handler)


class RequestLoggingMiddleware(BaseHTTPMiddleware):
    """Logs one structured line per request and stamps ``X-Request-Id``."""

    async def dispatch(
        self,
        request: Request,
        call_next: Callable[[Request], Awaitable[Response]],
    ) -> Response:
        request_id = uuid.uuid4().hex
        started_at = time.perf_counter()
        response = await call_next(request)
        latency_ms = round((time.perf_counter() - started_at) * 1000, 2)

        response.headers["X-Request-Id"] = request_id
        logger.info(
            "request",
            extra={
                "request_id": request_id,
                "route": request.url.path,
                "method": request.method,
                "status": response.status_code,
                "latency_ms": latency_ms,
            },
        )
        return response

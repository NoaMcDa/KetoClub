"""Application factory, lifespan and middleware.

Run it with:

    uv run uvicorn app.main:app --reload --port 8000
"""

import logging
import time
from collections.abc import AsyncIterator, Awaitable, Callable
from contextlib import asynccontextmanager

import httpx
from fastapi import FastAPI, Request, Response
from fastapi.middleware.cors import CORSMiddleware

from app import __version__
from app import models as _models  # noqa: F401  (registers tables on Base)
from app.config import Settings, get_settings
from app.db import Base, create_db_engine, create_session_factory
from app.routers import health, proxy

logger = logging.getLogger("ketoclub")

API_PREFIX = "/v1"

# The browser sends a preflight for the install-id header, so it has to be
# allowed by name; a wildcard is not accepted for a custom header.
ALLOWED_HEADERS = ["Content-Type", "Accept", "X-KetoClub-Install-Id"]


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    """Opens the database and one shared HTTP client for the process lifetime.

    One client, not one per request: connection reuse is most of the latency
    saving a proxy can offer.
    """
    settings: Settings = app.state.settings
    engine = create_db_engine(settings.database_url)
    Base.metadata.create_all(engine)
    app.state.engine = engine
    app.state.session_factory = create_session_factory(engine)
    try:
        async with httpx.AsyncClient() as client:
            app.state.http_client = client
            yield
    finally:
        engine.dispose()


async def log_requests(
    request: Request,
    call_next: Callable[[Request], Awaitable[Response]],
) -> Response:
    """Logs one line per request.

    Path, status and duration only. Never a body, a header, a query string or a
    key: an error body from an upstream can echo the request that produced it,
    and that request carries a bearer token (architecture.md §10, §11).
    """
    started = time.perf_counter()
    response = await call_next(request)
    elapsed_ms = (time.perf_counter() - started) * 1000.0
    logger.info(
        "%s %s -> %d in %.0fms cache=%s",
        request.method,
        request.url.path,
        response.status_code,
        elapsed_ms,
        response.headers.get("X-KetoClub-Cache", "-"),
    )
    return response


def create_app(settings: Settings | None = None) -> FastAPI:
    """Builds the application, optionally with settings a test supplies."""
    resolved = settings if settings is not None else get_settings()

    app = FastAPI(
        title="KetoClub backend",
        version=__version__,
        lifespan=lifespan,
    )
    app.state.settings = resolved

    app.add_middleware(
        CORSMiddleware,
        allow_origin_regex=resolved.cors_origin_regex,
        allow_methods=["GET", "POST"],
        allow_headers=ALLOWED_HEADERS,
        allow_credentials=False,
    )
    app.middleware("http")(log_requests)

    app.include_router(health.router, prefix=API_PREFIX)
    app.include_router(proxy.router, prefix=API_PREFIX)

    if settings is not None:
        app.dependency_overrides[get_settings] = lambda: resolved

    return app


app = create_app()

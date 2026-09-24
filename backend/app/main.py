"""FastAPI application factory.

``create_app`` builds the app; the module-level ``app`` is what
``uvicorn app.main:app`` serves. Tests call ``create_app`` directly with a
``Settings`` override (an in-memory database, no keys) instead of touching
environment variables, so tests never share state through the process-wide
``get_settings`` cache.
"""

import uuid
from collections.abc import AsyncGenerator
from contextlib import asynccontextmanager

import httpx
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app import __version__
from app.config import Settings, get_settings
from app.db import build_engine
from app.errors import BackendError, handle_backend_error
from app.models import Base
from app.routers import chat, discovery, health, proxy
from app.services.rate_limit import RateLimiter
from app.services.request_logging import RequestLoggingMiddleware

# "No daily cap" (#123) expressed as a bound no real install could reach in
# a day, so the discovery limiter's day window never binds.
_DISCOVERY_NO_DAILY_CAP = 10**9


def create_app(settings: Settings | None = None) -> FastAPI:
    """Build a configured ``FastAPI`` app.

    ``settings`` defaults to the process-wide cached settings; passing one
    explicitly (as tests do) keeps the lifespan, the health route and the
    caller all reading the same instance.
    """
    resolved_settings = settings or get_settings()

    @asynccontextmanager
    async def lifespan(app: FastAPI) -> AsyncGenerator[None, None]:
        engine = build_engine(resolved_settings)
        Base.metadata.create_all(engine)
        app.state.engine = engine
        app.state.http_client = httpx.AsyncClient()
        try:
            yield
        finally:
            await app.state.http_client.aclose()
            engine.dispose()

    app = FastAPI(
        title="KetoClub backend",
        version=__version__,
        lifespan=lifespan,
    )
    app.state.settings = resolved_settings
    # One id per process, generated at startup and never persisted or
    # reused: Wolt's web client sends a per-install uuid on every discovery
    # request (#123, phase2_discovery_research.md §2.2), and it must never
    # be the KetoClub install id — that one is sent only to this backend.
    app.state.wolt_web_client_id = str(uuid.uuid4())
    # Built here rather than in the lifespan so a test can reach it before the
    # first request; in memory, so it resets whenever the process restarts.
    app.state.rate_limiter = RateLimiter(
        per_minute=resolved_settings.RATE_LIMIT_PER_MINUTE,
        per_day=resolved_settings.RATE_LIMIT_PER_DAY,
    )
    # The discovery routes' own bucket (#123): Wolt itself throttles a
    # bursty caller (phase2_discovery_research.md §2.3), so this limiter
    # protects the backend's own IP rather than rationing a scarce quota,
    # and so it has no daily cap.
    app.state.discovery_rate_limiter = RateLimiter(
        per_minute=resolved_settings.DISCOVERY_RATE_LIMIT_PER_MINUTE,
        per_day=_DISCOVERY_NO_DAILY_CAP,
    )
    app.add_exception_handler(BackendError, handle_backend_error)

    app.add_middleware(RequestLoggingMiddleware)
    app.add_middleware(
        CORSMiddleware,
        allow_origin_regex=resolved_settings.CORS_ORIGIN_REGEX,
        allow_methods=["GET", "POST"],
        allow_headers=["Content-Type", "Accept", "X-KetoClub-Install-Id"],
        allow_credentials=False,
        # A browser hides every response header from JS unless it is listed
        # here (issue #103): both /v1/chat and the Wolt proxy answer
        # X-KetoClub-Cache, and the client needs to read it.
        expose_headers=["X-KetoClub-Cache"],
    )

    app.include_router(health.router, prefix="/v1")
    app.include_router(chat.router, prefix="/v1")
    app.include_router(proxy.router, prefix="/v1")
    app.include_router(discovery.router, prefix="/v1")

    return app


app = create_app()

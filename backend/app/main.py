"""FastAPI application factory.

``create_app`` builds the app; the module-level ``app`` is what
``uvicorn app.main:app`` serves. Tests call ``create_app`` directly with a
``Settings`` override (an in-memory database, no keys) instead of touching
environment variables, so tests never share state through the process-wide
``get_settings`` cache.
"""

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
from app.routers import chat, health, proxy
from app.services.rate_limit import RateLimiter
from app.services.request_logging import RequestLoggingMiddleware


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
    # Built here rather than in the lifespan so a test can reach it before the
    # first request; in memory, so it resets whenever the process restarts.
    app.state.rate_limiter = RateLimiter(
        per_minute=resolved_settings.RATE_LIMIT_PER_MINUTE,
        per_day=resolved_settings.RATE_LIMIT_PER_DAY,
    )
    app.add_exception_handler(BackendError, handle_backend_error)

    app.add_middleware(RequestLoggingMiddleware)
    app.add_middleware(
        CORSMiddleware,
        allow_origin_regex=resolved_settings.CORS_ORIGIN_REGEX,
        allow_methods=["GET", "POST"],
        allow_headers=["Content-Type", "Accept", "X-KetoClub-Install-Id"],
        allow_credentials=False,
    )

    app.include_router(health.router, prefix="/v1")
    app.include_router(chat.router, prefix="/v1")
    app.include_router(proxy.router, prefix="/v1")

    return app


app = create_app()

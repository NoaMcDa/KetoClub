"""Shared fixtures.

Every test runs against an in-memory database and a faked upstream: no test
makes a network call, matching the rule the Flutter side already follows
(architecture.md constraint 12).
"""

from collections.abc import Iterator

import pytest
from fastapi.testclient import TestClient
from sqlalchemy.orm import Session

from app.config import Settings
from app.db import Base, create_db_engine, create_session_factory
from app.main import create_app

WOLT_BASE_URL = "https://wolt.test"


@pytest.fixture
def settings() -> Settings:
    """Test settings, isolated from any `.env` the developer happens to have."""
    return Settings(
        _env_file=None,
        database_url="sqlite://",
        wolt_base_url=WOLT_BASE_URL,
        openrouter_api_key="",
        menu_cache_ttl_seconds=3600,
    )


@pytest.fixture
def client(settings: Settings) -> Iterator[TestClient]:
    """A client over the real application, with the lifespan run."""
    app = create_app(settings)
    with TestClient(app) as test_client:
        yield test_client


@pytest.fixture
def session() -> Iterator[Session]:
    """A standalone session for unit-testing the storage helpers."""
    engine = create_db_engine("sqlite://")
    Base.metadata.create_all(engine)
    factory = create_session_factory(engine)
    with factory() as db_session:
        yield db_session
    engine.dispose()

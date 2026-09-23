"""Shared pytest fixtures.

Every test runs the app over an in-memory SQLite database and with respx
blocking any real network call (architecture.md constraint 12): a request
that is not explicitly mocked raises instead of leaving the sandbox.
"""

from collections.abc import Iterator

import pytest
import respx
from fastapi.testclient import TestClient

from app.config import Settings
from app.main import create_app


@pytest.fixture
def settings() -> Settings:
    """Settings for tests: in-memory database, no keys configured."""
    return Settings(
        DATABASE_URL="sqlite:///:memory:",
        GEMINI_API_KEY="",
        ADMIN_TOKEN="",
    )


@pytest.fixture
def client(settings: Settings) -> Iterator[TestClient]:
    """A ``TestClient`` over the app, running the lifespan on enter/exit."""
    app = create_app(settings=settings)
    with TestClient(app) as test_client:
        yield test_client


@pytest.fixture(autouse=True)
def _block_network() -> Iterator[None]:
    """Fail any request that is not mocked by respx in the test itself."""
    with respx.mock(assert_all_called=False):
        yield

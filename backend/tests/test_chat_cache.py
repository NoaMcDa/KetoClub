"""Tests for the #103 shared chat completion cache.

``generativelanguage.googleapis.com`` is unreachable from the sandbox and
CI, so every upstream exchange here is a respx route on the default
``GEMINI_BASE_URL``, nested inside the autouse network block from
``conftest.py`` exactly as ``tests/test_chat.py`` does: a module-level
``respx.post(...)`` does not match anything, because the autouse
``_block_network`` fixture has already activated its own ``MockRouter``.
"""

from collections.abc import Iterator
from contextlib import contextmanager
from datetime import UTC, datetime

import httpx
import pytest
import respx
from fastapi.testclient import TestClient
from sqlalchemy import inspect

from app.config import Settings
from app.main import create_app
from app.schemas import ChatRequest
from app.services import chat_cache

_KEY = "test-gemini-key-for-chat-cache-that-must-never-be-logged"
_INSTALL_ID = "0123456789abcdef0123456789abcdef"
_URL = (
    "https://generativelanguage.googleapis.com"
    "/v1beta/models/gemini-2.5-flash:generateContent"
)
_SYSTEM = "You are the keto-diet menu analyst for KetoClub. CACHE-SYSTEM-MARKER"
_USER = "1 | Mains | Entrecote | 300g steak with fries CACHE-USER-MARKER"


def _settings(**overrides: object) -> Settings:
    fields: dict[str, object] = {
        "DATABASE_URL": "sqlite:///:memory:",
        "GEMINI_API_KEY": _KEY,
        "RATE_LIMIT_PER_MINUTE": 100,
        "RATE_LIMIT_PER_DAY": 1000,
    }
    fields.update(overrides)
    return Settings(**fields)  # type: ignore[arg-type]


@contextmanager
def _client(settings: Settings) -> Iterator[TestClient]:
    with TestClient(create_app(settings=settings)) as client:
        yield client


@pytest.fixture
def chat_client() -> Iterator[TestClient]:
    """A client over an app holding a Gemini key and a roomy rate limit."""
    with _client(_settings()) as client:
        yield client


@pytest.fixture
def gemini() -> Iterator[respx.MockRouter]:
    """A respx router for the Gemini host, active for the test's duration."""
    with respx.mock(assert_all_called=False) as router:
        yield router


def _request_body(user_prompt: str = _USER) -> dict[str, object]:
    return {"system_prompt": _SYSTEM, "user_prompt": user_prompt}


def _post(
    client: TestClient,
    body: dict[str, object] | None = None,
    headers: dict[str, str] | None = None,
) -> httpx.Response:
    response: httpx.Response = client.post(
        "/v1/chat",
        json=_request_body() if body is None else body,
        headers={"X-KetoClub-Install-Id": _INSTALL_ID} if headers is None else headers,
    )
    return response


def _reply(text: str = '{"dishes": []}') -> dict[str, object]:
    return {
        "candidates": [
            {
                "content": {"role": "model", "parts": [{"text": text}]},
                "finishReason": "STOP",
            }
        ],
        "modelVersion": "gemini-2.5-flash-001",
    }


# --- key stability --------------------------------------------------------------


def test_key_is_stable_across_nested_schema_key_order() -> None:
    schema_a: dict[str, object] = {
        "type": "object",
        "properties": {"a": {"type": "string"}, "b": {"type": "number"}},
    }
    schema_b: dict[str, object] = {
        "properties": {"b": {"type": "number"}, "a": {"type": "string"}},
        "type": "object",
    }
    request_a = ChatRequest(
        system_prompt=_SYSTEM,
        user_prompt=_USER,
        response_schema=schema_a,
        schema_name="menu_analysis",
    )
    request_b = ChatRequest(
        system_prompt=_SYSTEM,
        user_prompt=_USER,
        response_schema=schema_b,
        schema_name="menu_analysis",
    )

    key_a = chat_cache.cache_key("gemini-2.5-flash", request_a)
    key_b = chat_cache.cache_key("gemini-2.5-flash", request_b)

    assert key_a == key_b


def test_key_changes_with_the_model() -> None:
    request = ChatRequest(system_prompt=_SYSTEM, user_prompt=_USER)

    assert chat_cache.cache_key("model-a", request) != chat_cache.cache_key(
        "model-b", request
    )


def test_key_changes_with_the_prompt() -> None:
    request_a = ChatRequest(system_prompt=_SYSTEM, user_prompt=_USER)
    request_b = ChatRequest(system_prompt=_SYSTEM, user_prompt=f"{_USER} different")

    key_a = chat_cache.cache_key("gemini-2.5-flash", request_a)
    key_b = chat_cache.cache_key("gemini-2.5-flash", request_b)

    assert key_a != key_b


# --- miss then hit ---------------------------------------------------------------


def test_second_identical_request_is_served_from_the_cache(
    chat_client: TestClient, gemini: respx.MockRouter
) -> None:
    route = gemini.post(_URL).mock(return_value=httpx.Response(200, json=_reply()))

    first = _post(chat_client)
    second = _post(chat_client)

    assert first.status_code == 200
    assert first.headers["X-KetoClub-Cache"] == "miss"
    assert second.status_code == 200
    assert second.headers["X-KetoClub-Cache"] == "hit"
    assert second.json() == first.json()
    assert route.call_count == 1


# --- TTL expiry --------------------------------------------------------------------


def test_expired_entry_is_a_miss_and_is_refetched(gemini: respx.MockRouter) -> None:
    # Its own app, not the shared `chat_client` fixture: a zero-second TTL
    # means every read is already stale, forcing the second call upstream.
    route = gemini.post(_URL).mock(return_value=httpx.Response(200, json=_reply()))

    with _client(_settings(CHAT_CACHE_TTL_SECONDS=0)) as client:
        first = _post(client)
        second = _post(client)

    assert first.headers["X-KetoClub-Cache"] == "miss"
    assert second.headers["X-KetoClub-Cache"] == "miss"
    assert route.call_count == 2


# --- failures are never cached ------------------------------------------------------


def test_a_failed_completion_is_never_cached(
    chat_client: TestClient, gemini: respx.MockRouter
) -> None:
    route = gemini.post(_URL).mock(
        side_effect=[
            httpx.Response(500, json={"error": {"code": 500}}),
            httpx.Response(200, json=_reply()),
        ]
    )

    first = _post(chat_client)
    second = _post(chat_client)

    assert first.status_code == 502
    assert first.json() == {"reason": "badResponse", "status_code": 502}
    assert second.status_code == 200
    assert second.headers["X-KetoClub-Cache"] == "miss"
    assert route.call_count == 2


# --- a cache hit bypasses the rate limiter -------------------------------------------


def test_cache_hit_bypasses_the_rate_limiter(gemini: respx.MockRouter) -> None:
    route = gemini.post(_URL).mock(return_value=httpx.Response(200, json=_reply()))

    with _client(_settings(RATE_LIMIT_PER_MINUTE=1)) as client:
        first = _post(client)
        second = _post(client)
        third = _post(client, body=_request_body(user_prompt=f"{_USER} different"))

    assert first.status_code == 200
    assert first.headers["X-KetoClub-Cache"] == "miss"
    assert second.status_code == 200
    assert second.headers["X-KetoClub-Cache"] == "hit"
    assert third.status_code == 429
    assert third.json() == {"reason": "rateLimited", "status_code": 429}
    assert route.call_count == 1


# --- the stored row carries no install id --------------------------------------------


def test_stored_row_holds_no_install_id(gemini: respx.MockRouter) -> None:
    gemini.post(_URL).mock(return_value=httpx.Response(200, json=_reply()))
    settings = _settings()
    app = create_app(settings=settings)

    with TestClient(app) as client:
        _post(client)

        engine = app.state.engine
        key = chat_cache.cache_key(
            settings.GEMINI_MODEL,
            ChatRequest(system_prompt=_SYSTEM, user_prompt=_USER),
        )
        cached = chat_cache.read_cached(engine, key, 86400, datetime.now(UTC))
        columns = {
            column["name"] for column in inspect(engine).get_columns("chat_cache")
        }

    assert cached is not None
    assert _INSTALL_ID not in cached.content
    assert _INSTALL_ID not in cached.model
    assert columns == {"key", "content", "model", "created_at"}

"""Tests for ``POST /v1/chat``.

``generativelanguage.googleapis.com`` is unreachable from the sandbox and CI,
so every upstream exchange here is a respx route on the default
``GEMINI_BASE_URL``. The ``gemini`` fixture's router is nested inside the
autouse network block from ``conftest``: a request it does not match still
fails there instead of leaving the sandbox.
"""

import json
import logging
from collections.abc import Iterator
from contextlib import contextmanager
from pathlib import Path

import httpx
import pytest
import respx
from fastapi.testclient import TestClient

from app.config import Settings
from app.main import create_app
from app.services.gemini import CHAT_FAILURE_REASONS, to_gemini_schema

_KEY = "test-gemini-key-that-must-never-be-logged"
_INSTALL_ID = "0123456789abcdef0123456789abcdef"
_URL = (
    "https://generativelanguage.googleapis.com"
    "/v1beta/models/gemini-2.5-flash:generateContent"
)
_SYSTEM = "You are the keto-diet menu analyst for KetoClub. SYSTEM-MARKER"
_USER = "1 | Mains | Entrecote | 300g steak with fries USER-MARKER"
_SCHEMA_FILE = Path(__file__).parent / "fixtures" / "menu_analysis_schema.json"
_SCHEMA: dict[str, object] = json.loads(_SCHEMA_FILE.read_text(encoding="utf-8"))
_ANSWER = '{"dishes": []}'


def _settings(api_key: str = _KEY, per_minute: int = 100) -> Settings:
    return Settings(
        DATABASE_URL="sqlite:///:memory:",
        GEMINI_API_KEY=api_key,
        RATE_LIMIT_PER_MINUTE=per_minute,
        RATE_LIMIT_PER_DAY=1000,
    )


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


def _request_body(with_schema: bool = True) -> dict[str, object]:
    body: dict[str, object] = {"system_prompt": _SYSTEM, "user_prompt": _USER}
    if with_schema:
        body["response_schema"] = _SCHEMA
        body["schema_name"] = "menu_analysis"
    return body


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


def _reply(
    parts: list[dict[str, object]] | None = None,
    finish_reason: str = "STOP",
    model_version: str | None = "gemini-2.5-flash-001",
) -> dict[str, object]:
    body: dict[str, object] = {
        "candidates": [
            {
                "content": {
                    "role": "model",
                    "parts": [{"text": _ANSWER}] if parts is None else parts,
                },
                "finishReason": finish_reason,
            }
        ]
    }
    if model_version is not None:
        body["modelVersion"] = model_version
    return body


def _sent_body(call: respx.models.Call) -> dict[str, object]:
    sent: dict[str, object] = json.loads(call.request.content)
    return sent


def _generation_config(call: respx.models.Call) -> dict[str, object]:
    config = _sent_body(call)["generationConfig"]
    assert isinstance(config, dict)
    return config


def _error(status_code: int, reason: str) -> dict[str, object]:
    assert reason in CHAT_FAILURE_REASONS
    return {"reason": reason, "status_code": status_code}


_INVALID_KEY_BODY = {
    "error": {
        "code": 400,
        "message": "API key not valid. Please pass a valid API key.",
        "status": "INVALID_ARGUMENT",
        "details": [
            {
                "@type": "type.googleapis.com/google.rpc.ErrorInfo",
                "reason": "API_KEY_INVALID",
                "domain": "googleapis.com",
            }
        ],
    }
}

_GENERIC_400_BODY = {
    "error": {
        "code": 400,
        "message": "Invalid JSON payload received. UPSTREAM-BODY-MARKER",
        "status": "INVALID_ARGUMENT",
    }
}


# --- success ------------------------------------------------------------------


def test_success_joins_parts_and_reports_the_upstream_model(
    chat_client: TestClient, gemini: respx.MockRouter
) -> None:
    route = gemini.post(_URL).mock(
        return_value=httpx.Response(
            200,
            json=_reply(parts=[{"text": '{"dishes": '}, {"text": "[]}"}]),
        )
    )

    response = _post(chat_client)

    assert response.status_code == 200
    assert response.json() == {"content": _ANSWER, "model": "gemini-2.5-flash-001"}
    assert route.call_count == 1


def test_key_travels_only_in_the_header(
    chat_client: TestClient, gemini: respx.MockRouter
) -> None:
    route = gemini.post(_URL).mock(return_value=httpx.Response(200, json=_reply()))

    _post(chat_client)

    sent = route.calls.last.request
    assert sent.headers["x-goog-api-key"] == _KEY
    assert sent.headers["content-type"] == "application/json"
    assert "key=" not in str(sent.url)
    assert sent.url.query == b""
    assert _KEY not in sent.content.decode()


def test_request_body_carries_prompts_converted_schema_and_config(
    chat_client: TestClient, gemini: respx.MockRouter
) -> None:
    route = gemini.post(_URL).mock(return_value=httpx.Response(200, json=_reply()))

    _post(chat_client)

    body = _sent_body(route.calls.last)
    assert body["system_instruction"] == {"parts": [{"text": _SYSTEM}]}
    assert body["contents"] == [{"role": "user", "parts": [{"text": _USER}]}]
    assert body["generationConfig"] == {
        "responseMimeType": "application/json",
        "responseSchema": to_gemini_schema(_SCHEMA),
        "maxOutputTokens": 8192,
        "temperature": 0,
        "thinkingConfig": {"thinkingBudget": 0},
    }
    assert "additionalProperties" not in json.dumps(body)
    assert "menu_analysis" not in json.dumps(body)


def test_no_schema_sends_mime_type_only(
    chat_client: TestClient, gemini: respx.MockRouter
) -> None:
    route = gemini.post(_URL).mock(return_value=httpx.Response(200, json=_reply()))

    response = _post(chat_client, body=_request_body(with_schema=False))

    assert response.status_code == 200
    config = _generation_config(route.calls.last)
    assert config["responseMimeType"] == "application/json"
    assert "responseSchema" not in config


def test_model_falls_back_to_the_configured_one_without_model_version(
    chat_client: TestClient, gemini: respx.MockRouter
) -> None:
    gemini.post(_URL).mock(
        return_value=httpx.Response(200, json=_reply(model_version=None))
    )

    response = _post(chat_client)

    assert response.status_code == 200
    assert response.json()["model"] == "gemini-2.5-flash"


def test_thought_parts_are_not_part_of_the_answer(
    chat_client: TestClient, gemini: respx.MockRouter
) -> None:
    gemini.post(_URL).mock(
        return_value=httpx.Response(
            200,
            json=_reply(
                parts=[{"text": "Let me think.", "thought": True}, {"text": _ANSWER}]
            ),
        )
    )

    response = _post(chat_client)

    assert response.json()["content"] == _ANSWER


# --- configuration ------------------------------------------------------------


def test_no_key_is_not_configured_without_an_upstream_call(
    gemini: respx.MockRouter,
) -> None:
    route = gemini.post(_URL).mock(return_value=httpx.Response(200, json=_reply()))

    with _client(_settings(api_key="")) as client:
        response = _post(client)

    assert response.status_code == 503
    assert response.json() == _error(503, "notConfigured")
    assert not route.called


# --- upstream failures ----------------------------------------------------------


@pytest.mark.parametrize(
    ("upstream_status", "upstream_body", "status_code", "reason"),
    [
        (400, _INVALID_KEY_BODY, 503, "notConfigured"),
        (
            400,
            {"error": {"code": 400, "status": "API_KEY_INVALID"}},
            503,
            "notConfigured",
        ),
        (
            400,
            {"error": {"code": 400, "message": "API_KEY_INVALID"}},
            503,
            "notConfigured",
        ),
        (401, {"error": {"code": 401}}, 503, "notConfigured"),
        (
            403,
            {"error": {"code": 403, "status": "PERMISSION_DENIED"}},
            503,
            "notConfigured",
        ),
        (
            429,
            {"error": {"code": 429, "status": "RESOURCE_EXHAUSTED"}},
            429,
            "rateLimited",
        ),
        (500, {"error": {"code": 500}}, 502, "badResponse"),
        (503, {"error": {"code": 503, "status": "UNAVAILABLE"}}, 502, "badResponse"),
        (404, {"error": {"code": 404, "status": "NOT_FOUND"}}, 502, "badResponse"),
    ],
)
def test_upstream_status_maps_to_a_reason_without_retry(
    chat_client: TestClient,
    gemini: respx.MockRouter,
    upstream_status: int,
    upstream_body: dict[str, object],
    status_code: int,
    reason: str,
) -> None:
    route = gemini.post(_URL).mock(
        return_value=httpx.Response(upstream_status, json=upstream_body)
    )

    response = _post(chat_client)

    assert response.status_code == status_code
    assert response.json() == _error(status_code, reason)
    assert route.call_count == 1


@pytest.mark.parametrize(
    ("error", "status_code", "reason"),
    [
        (httpx.ConnectError, 502, "offline"),
        (httpx.ReadError, 502, "offline"),
        (httpx.ReadTimeout, 504, "timeout"),
        (httpx.ConnectTimeout, 504, "timeout"),
        (httpx.RemoteProtocolError, 502, "badResponse"),
    ],
)
def test_transport_errors_map_to_a_reason(
    chat_client: TestClient,
    gemini: respx.MockRouter,
    error: type[Exception],
    status_code: int,
    reason: str,
) -> None:
    route = gemini.post(_URL).mock(side_effect=error)

    response = _post(chat_client)

    assert response.status_code == status_code
    assert response.json() == _error(status_code, reason)
    assert route.call_count == 1


@pytest.mark.parametrize(
    "upstream",
    [
        httpx.Response(200, json=_reply(finish_reason="MAX_TOKENS")),
        httpx.Response(200, json=_reply(finish_reason="SAFETY")),
        httpx.Response(200, json={"modelVersion": "gemini-2.5-flash-001"}),
        httpx.Response(200, json={"candidates": []}),
        httpx.Response(200, json={"candidates": ["not an object"]}),
        httpx.Response(200, json={"candidates": [{"finishReason": "STOP"}]}),
        httpx.Response(
            200, json={"candidates": [{"finishReason": "STOP", "content": {}}]}
        ),
        httpx.Response(200, json=_reply(parts=[])),
        httpx.Response(200, json=_reply(parts=[{"inlineData": {}}])),
        httpx.Response(200, json=_reply(parts=[{"text": ""}])),
        httpx.Response(200, json=_reply(parts=[{"text": "x", "thought": True}])),
        httpx.Response(200, json=["not", "an", "object"]),
        httpx.Response(200, text="<html>not json</html>"),
    ],
    ids=[
        "max-tokens",
        "safety",
        "no-candidates",
        "empty-candidates",
        "candidate-not-object",
        "no-content",
        "no-parts",
        "empty-parts",
        "no-text-part",
        "empty-text",
        "thought-only",
        "json-array",
        "not-json",
    ],
)
def test_unusable_success_body_is_bad_response(
    chat_client: TestClient, gemini: respx.MockRouter, upstream: httpx.Response
) -> None:
    gemini.post(_URL).mock(return_value=upstream)

    response = _post(chat_client)

    assert response.status_code == 502
    assert response.json() == _error(502, "badResponse")


# --- the single schema retry ----------------------------------------------------


@pytest.mark.parametrize(
    "first",
    [
        httpx.Response(400, json=_GENERIC_400_BODY),
        httpx.Response(400, text="not json"),
        httpx.Response(400, json=["not", "an", "object"]),
        httpx.Response(400, json={"error": "not an object"}),
        httpx.Response(400, json={"error": {"details": [{"reason": "OTHER"}]}}),
    ],
    ids=["generic", "not-json", "json-array", "error-string", "other-reason"],
)
def test_a_generic_400_is_retried_once_without_the_schema(
    chat_client: TestClient, gemini: respx.MockRouter, first: httpx.Response
) -> None:
    route = gemini.post(_URL).mock(
        side_effect=[first, httpx.Response(200, json=_reply())]
    )

    response = _post(chat_client)

    assert response.status_code == 200
    assert response.json()["content"] == _ANSWER
    assert route.call_count == 2
    first_config = _generation_config(route.calls[0])
    retry_config = _generation_config(route.calls[1])
    assert "responseSchema" in first_config
    assert "responseSchema" not in retry_config
    assert retry_config["responseMimeType"] == "application/json"
    assert retry_config["thinkingConfig"] == {"thinkingBudget": 0}


def test_a_second_400_is_bad_response_and_never_retried_again(
    chat_client: TestClient, gemini: respx.MockRouter
) -> None:
    route = gemini.post(_URL).mock(
        side_effect=[
            httpx.Response(400, json=_GENERIC_400_BODY),
            httpx.Response(400, json=_GENERIC_400_BODY),
            httpx.Response(200, json=_reply()),
        ]
    )

    response = _post(chat_client)

    assert response.status_code == 502
    assert response.json() == _error(502, "badResponse")
    assert route.call_count == 2


def test_a_400_without_a_schema_is_not_retried(
    chat_client: TestClient, gemini: respx.MockRouter
) -> None:
    route = gemini.post(_URL).mock(
        side_effect=[
            httpx.Response(400, json=_GENERIC_400_BODY),
            httpx.Response(200, json=_reply()),
        ]
    )

    response = _post(chat_client, body=_request_body(with_schema=False))

    assert response.status_code == 502
    assert response.json() == _error(502, "badResponse")
    assert route.call_count == 1


# --- inbound validation ----------------------------------------------------------


def test_inbound_authorization_is_rejected_before_anything_else(
    chat_client: TestClient, gemini: respx.MockRouter
) -> None:
    route = gemini.post(_URL).mock(return_value=httpx.Response(200, json=_reply()))

    response = _post(
        chat_client,
        body={},
        headers={"Authorization": "Bearer sk-user", "X-KetoClub-Install-Id": "bad"},
    )

    assert response.status_code == 400
    assert response.json() == _error(400, "badResponse")
    assert not route.called


@pytest.mark.parametrize(
    "headers",
    [
        {},
        {"X-KetoClub-Install-Id": ""},
        {"X-KetoClub-Install-Id": _INSTALL_ID.upper()},
        {"X-KetoClub-Install-Id": _INSTALL_ID[:-1]},
    ],
    ids=["missing", "empty", "uppercase", "short"],
)
def test_missing_or_malformed_install_id_is_bad_response(
    chat_client: TestClient, gemini: respx.MockRouter, headers: dict[str, str]
) -> None:
    route = gemini.post(_URL).mock(return_value=httpx.Response(200, json=_reply()))

    response = _post(chat_client, headers=headers)

    assert response.status_code == 400
    assert response.json() == _error(400, "badResponse")
    assert not route.called


@pytest.mark.parametrize(
    "body",
    [
        {"system_prompt": "", "user_prompt": _USER},
        {"system_prompt": _SYSTEM, "user_prompt": ""},
        {"user_prompt": _USER},
        {"system_prompt": "x" * 20001, "user_prompt": _USER},
        {"system_prompt": _SYSTEM, "user_prompt": "x" * 60001},
        {"system_prompt": _SYSTEM, "user_prompt": _USER, "schema_name": "x" * 65},
    ],
    ids=[
        "empty-system",
        "empty-user",
        "missing-system",
        "long-system",
        "long-user",
        "long-name",
    ],
)
def test_invalid_body_is_422_without_an_upstream_call(
    chat_client: TestClient, gemini: respx.MockRouter, body: dict[str, object]
) -> None:
    route = gemini.post(_URL).mock(return_value=httpx.Response(200, json=_reply()))

    response = _post(chat_client, body=body)

    assert response.status_code == 422
    assert not route.called


# --- rate limit ----------------------------------------------------------------


def _prompt_variant(suffix: str) -> dict[str, object]:
    """``_request_body()`` with a distinct ``user_prompt``.

    A distinct prompt means a distinct #103 cache key, so a test that needs
    a genuine upstream miss (rather than a cache hit) uses this instead of
    repeating the same default body.
    """
    body = _request_body()
    body["user_prompt"] = f"{_USER} {suffix}"
    return body


def test_over_the_per_install_limit_is_rate_limited(
    gemini: respx.MockRouter,
) -> None:
    route = gemini.post(_URL).mock(return_value=httpx.Response(200, json=_reply()))

    with _client(_settings(per_minute=1)) as client:
        first = _post(client, body=_prompt_variant("A"))
        second = _post(client, body=_prompt_variant("B"))
        other_install = _post(
            client,
            body=_prompt_variant("C"),
            headers={"X-KetoClub-Install-Id": "f" * 32},
        )

    assert first.status_code == 200
    assert second.status_code == 429
    assert second.json() == _error(429, "rateLimited")
    assert other_install.status_code == 200
    assert route.call_count == 3


# --- logging -------------------------------------------------------------------


def test_logs_never_carry_the_key_prompts_upstream_body_or_full_install_id(
    chat_client: TestClient,
    gemini: respx.MockRouter,
    caplog: pytest.LogCaptureFixture,
) -> None:
    gemini.post(_URL).mock(
        side_effect=[
            httpx.Response(400, json=_GENERIC_400_BODY),
            httpx.Response(200, json=_reply()),
            httpx.Response(500, json=_GENERIC_400_BODY),
        ]
    )

    with caplog.at_level(logging.DEBUG):
        # A distinct prompt on the second call: the same body would be a
        # #103 cache hit and never reach the third mocked (500) response.
        assert _post(chat_client).status_code == 200
        assert _post(chat_client, body=_prompt_variant("second")).status_code == 502

    text = caplog.text
    assert _KEY not in text
    assert "SYSTEM-MARKER" not in text
    assert "USER-MARKER" not in text
    assert "UPSTREAM-BODY-MARKER" not in text
    assert _INSTALL_ID not in text

    chat_lines = [r.getMessage() for r in caplog.records if r.name == "ketoclub.chat"]
    assert f"chat install_id={_INSTALL_ID[:8]}" in chat_lines
    assert "gemini upstream_status=400 retrying without responseSchema" in chat_lines
    assert "gemini upstream_status=500" in chat_lines

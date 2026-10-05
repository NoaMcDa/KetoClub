"""Tests for ``POST /v1/chat``.

``generativelanguage.googleapis.com`` is unreachable from the sandbox and CI,
so every upstream exchange here is a respx route on the default
``GEMINI_BASE_URL``. The ``gemini`` fixture's router is nested inside the
autouse network block from ``conftest``: a request it does not match still
fails there instead of leaving the sandbox.
"""

import base64
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
from app.schemas import ImagePart
from app.services.gemini import CHAT_FAILURE_REASONS, to_gemini_schema

_KEY = "test-gemini-key-that-must-never-be-logged"
_INSTALL_ID = "0123456789abcdef0123456789abcdef"
_URL = (
    "https://generativelanguage.googleapis.com"
    "/v1beta/models/gemini-3.5-flash:generateContent"
)
_SYSTEM = "You are the keto-diet menu analyst for KetoClub. SYSTEM-MARKER"
_USER = "1 | Mains | Entrecote | 300g steak with fries USER-MARKER"
_SCHEMA_FILE = Path(__file__).parent / "fixtures" / "menu_analysis_schema.json"
_SCHEMA: dict[str, object] = json.loads(_SCHEMA_FILE.read_text(encoding="utf-8"))
_ANSWER = '{"dishes": []}'

# A real 1x1 transparent PNG: what a phone would never send, but a valid page.
_PNG_B64 = (
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAC"
    "hwGA60e6kgAAAABJRU5ErkJggg=="
)
_PDF_B64 = base64.b64encode(b"%PDF-1.4 a one-page menu").decode("ascii")


def _settings(
    api_key: str = _KEY, per_minute: int = 100, log_upstream_errors: bool = False
) -> Settings:
    return Settings(
        DATABASE_URL="sqlite:///:memory:",
        GEMINI_API_KEY=api_key,
        RATE_LIMIT_PER_MINUTE=per_minute,
        RATE_LIMIT_PER_DAY=1000,
        GEMINI_LOG_UPSTREAM_ERRORS=log_upstream_errors,
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
        "maxOutputTokens": 65536,
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
    assert response.json()["model"] == "gemini-3.5-flash"


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
        {"system_prompt": _SYSTEM, "user_prompt": "x" * 400001},
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
            httpx.Response(200, json=_reply()),
        ]
    )

    image_b64 = base64.b64encode(b"IMAGE-BYTES-MARKER " * 8).decode("ascii")
    with caplog.at_level(logging.DEBUG):
        # A distinct prompt on the second call: the same body would be a
        # #103 cache hit and never reach the third mocked (500) response.
        assert _post(chat_client).status_code == 200
        assert _post(chat_client, body=_prompt_variant("second")).status_code == 502
        # A page (#170): only its count may reach a log line.
        assert (
            _post(chat_client, body=_image_body(("image/webp", image_b64))).status_code
            == 200
        )

    text = caplog.text
    assert _KEY not in text
    assert "SYSTEM-MARKER" not in text
    assert "USER-MARKER" not in text
    assert "UPSTREAM-BODY-MARKER" not in text
    assert _INSTALL_ID not in text
    assert image_b64 not in text
    assert image_b64[:16] not in text
    assert "IMAGE-BYTES-MARKER" not in text
    assert "image/webp" not in text

    chat_lines = [r.getMessage() for r in caplog.records if r.name == "ketoclub.chat"]
    assert f"chat install_id={_INSTALL_ID[:8]}" in chat_lines
    assert f"chat install_id={_INSTALL_ID[:8]} images=1" in chat_lines
    assert f"chat install_id={_INSTALL_ID[:8]} cache=bypass" in chat_lines
    assert "gemini upstream_status=400 retrying without responseSchema" in chat_lines
    assert "gemini upstream_status=500" in chat_lines


# --- images (D15, #170) ---------------------------------------------------------


def _image_body(
    *images: tuple[str, str], base: dict[str, object] | None = None
) -> dict[str, object]:
    """``_request_body()`` (or ``base``) carrying ``images`` as (mime, base64)."""
    body = dict(_request_body() if base is None else base)
    body["images"] = [{"mime_type": mime, "data": data} for mime, data in images]
    return body


def test_images_follow_the_prompt_as_inline_data_parts_in_order(
    chat_client: TestClient, gemini: respx.MockRouter
) -> None:
    route = gemini.post(_URL).mock(return_value=httpx.Response(200, json=_reply()))

    response = _post(
        chat_client,
        body=_image_body(("image/png", _PNG_B64), ("application/pdf", _PDF_B64)),
    )

    assert response.status_code == 200
    assert response.json()["content"] == _ANSWER
    body = _sent_body(route.calls.last)
    assert body["contents"] == [
        {
            "role": "user",
            "parts": [
                {"text": _USER},
                {"inline_data": {"mime_type": "image/png", "data": _PNG_B64}},
                {"inline_data": {"mime_type": "application/pdf", "data": _PDF_B64}},
            ],
        }
    ]
    # The system prompt and generation config are what a text request sends.
    assert body["system_instruction"] == {"parts": [{"text": _SYSTEM}]}
    assert _generation_config(route.calls.last)["responseSchema"] == (
        to_gemini_schema(_SCHEMA)
    )


def test_the_schema_retry_resends_the_images(
    chat_client: TestClient, gemini: respx.MockRouter
) -> None:
    route = gemini.post(_URL).mock(
        side_effect=[
            httpx.Response(400, json=_GENERIC_400_BODY),
            httpx.Response(200, json=_reply()),
        ]
    )

    response = _post(chat_client, body=_image_body(("image/png", _PNG_B64)))

    assert response.status_code == 200
    assert route.call_count == 2
    retried = _sent_body(route.calls.last)
    assert "responseSchema" not in _generation_config(route.calls.last)
    assert retried["contents"] == _sent_body(route.calls[0])["contents"]


def test_a_request_with_images_bypasses_the_completion_cache(
    chat_client: TestClient, gemini: respx.MockRouter
) -> None:
    route = gemini.post(_URL).mock(return_value=httpx.Response(200, json=_reply()))
    with_image = _image_body(("image/png", _PNG_B64))

    first = _post(chat_client, body=with_image)
    second = _post(chat_client, body=with_image)
    # Same prompts, no images: the image calls wrote no row it could hit.
    text_only = _post(chat_client)
    # And a cached text answer is never served to an image request.
    text_again = _post(chat_client)
    image_after_text = _post(chat_client, body=with_image)

    assert [r.status_code for r in (first, second, text_only)] == [200, 200, 200]
    assert first.headers["X-KetoClub-Cache"] == "bypass"
    assert second.headers["X-KetoClub-Cache"] == "bypass"
    assert text_only.headers["X-KetoClub-Cache"] == "miss"
    assert text_again.headers["X-KetoClub-Cache"] == "hit"
    assert image_after_text.headers["X-KetoClub-Cache"] == "bypass"
    assert route.call_count == 4


@pytest.mark.parametrize(
    "images",
    [
        [{"mime_type": "image/png", "data": _PNG_B64}] * 7,
        [
            {
                "mime_type": "image/jpeg",
                "data": base64.b64encode(b"\xff" * (4 * 1024 * 1024)).decode(),
            }
        ],
        [{"mime_type": "image/png", "data": "not base64!"}],
        [{"mime_type": "image/png", "data": _PNG_B64.rstrip("=")}],
        [{"mime_type": "image/png", "data": ""}],
        [{"mime_type": "image/gif", "data": _PNG_B64}],
        [{"data": _PNG_B64}],
        [{"mime_type": "image/png"}],
    ],
    ids=[
        "seven-images",
        "four-mib-part",
        "bad-base64",
        "unpadded-base64",
        "empty-data",
        "gif",
        "no-mime-type",
        "no-data",
    ],
)
def test_out_of_bounds_images_are_422_without_an_upstream_call(
    chat_client: TestClient,
    gemini: respx.MockRouter,
    images: list[dict[str, str]],
) -> None:
    route = gemini.post(_URL).mock(return_value=httpx.Response(200, json=_reply()))
    body = _request_body()
    body["images"] = images

    response = _post(chat_client, body=body)

    assert response.status_code == 422
    assert not route.called


def test_a_422_never_echoes_the_submitted_image(
    chat_client: TestClient,
    gemini: respx.MockRouter,
    caplog: pytest.LogCaptureFixture,
) -> None:
    route = gemini.post(_URL).mock(return_value=httpx.Response(200, json=_reply()))
    submitted = "NOT-BASE64-MARKER!" * 600  # about 10 KiB
    body = _image_body(("image/png", submitted))

    with caplog.at_level(logging.DEBUG):
        response = _post(chat_client, body=body)

    assert response.status_code == 422
    assert submitted not in response.text
    assert "NOT-BASE64-MARKER" not in response.text
    assert "NOT-BASE64-MARKER" not in caplog.text
    detail = response.json()["detail"]
    assert isinstance(detail, list)
    assert detail[0]["loc"][-1] == "data"
    assert detail[0]["msg"]
    assert set(detail[0]) == {"type", "loc", "msg"}
    assert not route.called


def test_image_bounds_come_from_settings(gemini: respx.MockRouter) -> None:
    route = gemini.post(_URL).mock(return_value=httpx.Response(200, json=_reply()))
    settings = Settings(
        DATABASE_URL="sqlite:///:memory:",
        GEMINI_API_KEY=_KEY,
        VISION_MAX_IMAGES=1,
        VISION_MAX_IMAGE_BYTES=70,
    )

    with _client(settings) as client:
        at_bound = _post(client, body=_image_body(("image/png", _PNG_B64)))
        two = _post(
            client,
            body=_image_body(("image/png", _PNG_B64), ("image/png", _PNG_B64)),
        )
        too_big = _post(
            client,
            body=_image_body(("image/png", base64.b64encode(b"x" * 71).decode())),
        )

    assert at_bound.status_code == 200
    assert two.status_code == 422
    assert too_big.status_code == 422
    assert route.call_count == 1


def test_a_request_with_images_spends_the_per_install_limit(
    gemini: respx.MockRouter,
) -> None:
    route = gemini.post(_URL).mock(return_value=httpx.Response(200, json=_reply()))

    with _client(_settings(per_minute=1)) as client:
        with_image = _post(client, body=_image_body(("image/png", _PNG_B64)))
        text_after = _post(client, body=_prompt_variant("after-image"))
        image_after = _post(client, body=_image_body(("image/png", _PNG_B64)))

    assert with_image.status_code == 200
    assert text_after.status_code == 429
    assert image_after.status_code == 429
    assert image_after.json() == _error(429, "rateLimited")
    assert route.call_count == 1


def test_image_decoded_size_is_exact_for_every_padding() -> None:
    for raw in (b"", b"a", b"ab", b"abc", b"abcd", b"\x00" * 1000):
        encoded = base64.b64encode(raw).decode("ascii")
        if not encoded:
            continue
        part = ImagePart(mime_type="image/png", data=encoded)
        assert part.decoded_size == len(raw)


# --- upstream error diagnostics (#187) ----------------------------------------


def test_a_404_names_the_error_status_and_the_model_hint_without_the_body(
    chat_client: TestClient,
    gemini: respx.MockRouter,
    caplog: pytest.LogCaptureFixture,
) -> None:
    gemini.post(_URL).mock(
        return_value=httpx.Response(
            404,
            json={
                "error": {
                    "code": 404,
                    "message": (
                        "models/gemini-2.5-flash is not found for API version "
                        "v1beta UPSTREAM-BODY-MARKER"
                    ),
                    "status": "NOT_FOUND",
                }
            },
        )
    )

    with caplog.at_level(logging.INFO):
        response = _post(chat_client)

    # The wire contract is unchanged: still a generic badResponse to the app.
    assert response.status_code == 502
    assert response.json() == _error(502, "badResponse")

    chat_lines = [r.getMessage() for r in caplog.records if r.name == "ketoclub.chat"]
    assert "gemini upstream_status=404" in chat_lines
    assert "gemini upstream error_status=NOT_FOUND error_code=404" in chat_lines
    hints = [line for line in chat_lines if "GEMINI_MODEL" in line]
    assert len(hints) == 1
    assert "404" in hints[0]
    # Google's message quotes the request, so it is never logged (§3.5).
    assert "UPSTREAM-BODY-MARKER" not in caplog.text
    assert _KEY not in caplog.text


@pytest.mark.parametrize(
    "upstream_body",
    [{"error": {"code": 500}}, {"error": "boom"}, "not json at all"],
    ids=["no-status", "error-not-a-dict", "not-json"],
)
def test_a_non_404_error_without_a_status_logs_only_the_status_code(
    chat_client: TestClient,
    gemini: respx.MockRouter,
    caplog: pytest.LogCaptureFixture,
    upstream_body: object,
) -> None:
    if isinstance(upstream_body, str):
        mocked = httpx.Response(500, text=upstream_body)
    else:
        mocked = httpx.Response(500, json=upstream_body)
    gemini.post(_URL).mock(return_value=mocked)

    with caplog.at_level(logging.INFO):
        assert _post(chat_client).status_code == 502

    chat_lines = [r.getMessage() for r in caplog.records if r.name == "ketoclub.chat"]
    assert "gemini upstream_status=500" in chat_lines
    assert not any("error_status" in line for line in chat_lines)
    assert not any("GEMINI_MODEL" in line for line in chat_lines)


# --- request / reply shape lines ----------------------------------------------


def _chat_lines(caplog: pytest.LogCaptureFixture) -> list[str]:
    return [r.getMessage() for r in caplog.records if r.name == "ketoclub.chat"]


def test_a_request_and_its_reply_are_described_by_shape_only(
    chat_client: TestClient,
    gemini: respx.MockRouter,
    caplog: pytest.LogCaptureFixture,
) -> None:
    reply = _reply()
    reply["usageMetadata"] = {
        "promptTokenCount": 1234,
        "candidatesTokenCount": 567,
        "totalTokenCount": 1801,
    }
    upstream = httpx.Response(200, json=reply)
    gemini.post(_URL).mock(return_value=upstream)
    body = _request_body()
    body["user_prompt"] = f"{_USER}\n2 | Mains | Salmon | with rice USER-MARKER"

    with caplog.at_level(logging.INFO):
        assert _post(chat_client, body=body).status_code == 200

    lines = _chat_lines(caplog)
    assert (
        "gemini request attempt=1 model=gemini-3.5-flash schema=yes "
        f"system_chars={len(_SYSTEM)} user_chars={len(body['user_prompt'])} "
        "user_lines=2 images=0 image_bytes=0 max_output_tokens=65536 "
        "thinking_budget=0"
    ) in lines
    responses = [line for line in lines if line.startswith("gemini response ")]
    assert len(responses) == 1
    assert responses[0].startswith("gemini response status=200 latency_ms=")
    assert responses[0].endswith(f" body_bytes={len(upstream.content)}")
    assert (
        f"gemini reply finish_reason=STOP content_chars={len(_ANSWER)} "
        "prompt_tokens=1234 output_tokens=567 thoughts_tokens=none "
        "total_tokens=1801"
    ) in lines
    assert "USER-MARKER" not in caplog.text
    assert "SYSTEM-MARKER" not in caplog.text


def test_the_schema_less_retry_is_described_as_a_second_attempt(
    chat_client: TestClient,
    gemini: respx.MockRouter,
    caplog: pytest.LogCaptureFixture,
) -> None:
    gemini.post(_URL).mock(
        side_effect=[
            httpx.Response(400, json=_GENERIC_400_BODY),
            httpx.Response(200, json=_reply()),
        ]
    )

    with caplog.at_level(logging.INFO):
        assert _post(chat_client).status_code == 200

    requests = [
        line for line in _chat_lines(caplog) if line.startswith("gemini request ")
    ]
    assert len(requests) == 2
    assert requests[0].startswith(
        "gemini request attempt=1 model=gemini-3.5-flash schema=yes "
    )
    assert requests[1].startswith(
        "gemini request attempt=2 model=gemini-3.5-flash schema=no "
    )


def test_an_image_request_logs_the_byte_count_never_the_bytes(
    chat_client: TestClient,
    gemini: respx.MockRouter,
    caplog: pytest.LogCaptureFixture,
) -> None:
    gemini.post(_URL).mock(return_value=httpx.Response(200, json=_reply()))

    with caplog.at_level(logging.INFO):
        body = _image_body(("image/png", _PNG_B64), ("application/pdf", _PDF_B64))
        assert _post(chat_client, body=body).status_code == 200

    requests = [
        line for line in _chat_lines(caplog) if line.startswith("gemini request ")
    ]
    assert len(requests) == 1
    assert f" images=2 image_bytes={len(_PNG_B64) + len(_PDF_B64)} " in requests[0]
    assert _PNG_B64[:16] not in caplog.text
    assert "image/png" not in caplog.text


@pytest.mark.parametrize(
    ("upstream", "reason"),
    [
        (
            httpx.Response(200, json=_reply(finish_reason="MAX_TOKENS")),
            "finish_reason=MAX_TOKENS",
        ),
        (
            httpx.Response(200, json=_reply(finish_reason="SAFETY")),
            "finish_reason=SAFETY",
        ),
        (
            httpx.Response(200, json=_reply(finish_reason="<html>")),
            "finish_reason=other",
        ),
        (httpx.Response(200, json={"candidates": []}), "no_candidates"),
        (
            httpx.Response(200, json={"candidates": [{"finishReason": "STOP"}]}),
            "no_content",
        ),
        (httpx.Response(200, json=_reply(parts=[{"text": ""}])), "no_text_part"),
        (httpx.Response(200, text="not json"), "not_json"),
        (httpx.Response(200, json=[]), "not_an_object"),
    ],
    ids=[
        "max-tokens",
        "safety",
        "free-text-finish",
        "no-candidates",
        "no-content",
        "empty-text",
        "not-json",
        "not-an-object",
    ],
)
def test_a_thrown_away_200_names_why(
    chat_client: TestClient,
    gemini: respx.MockRouter,
    caplog: pytest.LogCaptureFixture,
    upstream: httpx.Response,
    reason: str,
) -> None:
    gemini.post(_URL).mock(return_value=upstream)

    with caplog.at_level(logging.INFO):
        response = _post(chat_client)

    assert response.status_code == 502
    assert response.json() == _error(502, "badResponse")
    unusable = [line for line in _chat_lines(caplog) if "reply unusable" in line]
    assert len(unusable) == 1
    assert unusable[0].startswith(f"gemini reply unusable reason={reason}")


def test_a_max_tokens_reply_logs_the_token_counts_it_hit(
    chat_client: TestClient,
    gemini: respx.MockRouter,
    caplog: pytest.LogCaptureFixture,
) -> None:
    reply = _reply(finish_reason="MAX_TOKENS")
    reply["usageMetadata"] = {
        "promptTokenCount": 9000,
        "candidatesTokenCount": 8192,
        "thoughtsTokenCount": 0,
        "totalTokenCount": 17192,
    }
    gemini.post(_URL).mock(return_value=httpx.Response(200, json=reply))

    with caplog.at_level(logging.INFO):
        assert _post(chat_client).status_code == 502

    assert (
        "gemini reply unusable reason=finish_reason=MAX_TOKENS prompt_tokens=9000 "
        "output_tokens=8192 thoughts_tokens=0 total_tokens=17192"
    ) in _chat_lines(caplog)


# --- GEMINI_LOG_UPSTREAM_ERRORS ------------------------------------------------

_UNAVAILABLE_BODY = {
    "error": {
        "code": 503,
        "message": (
            f"The model is overloaded. Please try again later. key={_KEY} "
            "UPSTREAM-BODY-MARKER"
        ),
        "status": "UNAVAILABLE",
        "details": [
            {
                "@type": "type.googleapis.com/google.rpc.ErrorInfo",
                "reason": "OVERLOADED",
            },
            {"@type": "type.googleapis.com/google.rpc.Help"},
        ],
    }
}


def test_upstream_error_message_is_not_logged_by_default(
    chat_client: TestClient,
    gemini: respx.MockRouter,
    caplog: pytest.LogCaptureFixture,
) -> None:
    gemini.post(_URL).mock(return_value=httpx.Response(503, json=_UNAVAILABLE_BODY))

    with caplog.at_level(logging.INFO):
        assert _post(chat_client).status_code == 502

    lines = _chat_lines(caplog)
    assert "gemini upstream error_status=UNAVAILABLE error_code=503" in lines
    assert not [line for line in lines if "error_message=" in line]
    assert "UPSTREAM-BODY-MARKER" not in caplog.text
    assert "OVERLOADED" not in caplog.text
    assert _KEY not in caplog.text


def test_upstream_error_message_is_logged_with_the_key_redacted_when_enabled(
    gemini: respx.MockRouter,
    caplog: pytest.LogCaptureFixture,
) -> None:
    gemini.post(_URL).mock(return_value=httpx.Response(503, json=_UNAVAILABLE_BODY))

    with _client(_settings(log_upstream_errors=True)) as client:
        with caplog.at_level(logging.INFO):
            assert _post(client).status_code == 502

    lines = _chat_lines(caplog)
    assert "gemini upstream error_status=UNAVAILABLE error_code=503" in lines
    assert (
        "gemini upstream error_message='The model is overloaded. Please try again "
        "later. key=<redacted> UPSTREAM-BODY-MARKER' error_reasons=OVERLOADED"
    ) in lines
    assert _KEY not in caplog.text


def test_an_enabled_error_message_is_capped_and_absent_without_an_error_object(
    gemini: respx.MockRouter,
    caplog: pytest.LogCaptureFixture,
) -> None:
    gemini.post(_URL).mock(
        side_effect=[
            httpx.Response(
                500,
                json={
                    "error": {"code": 500, "status": "INTERNAL", "message": "x" * 2000}
                },
            ),
            httpx.Response(500, text="<html>a proxy error page</html>"),
        ]
    )

    with _client(_settings(log_upstream_errors=True)) as client:
        with caplog.at_level(logging.INFO):
            assert _post(client).status_code == 502
            assert _post(client, body=_prompt_variant("second")).status_code == 502

    messages = [line for line in _chat_lines(caplog) if "error_message=" in line]
    assert len(messages) == 1
    assert messages[0] == (
        f"gemini upstream error_message='{'x' * 500}' error_reasons=none"
    )
    assert "proxy error page" not in caplog.text

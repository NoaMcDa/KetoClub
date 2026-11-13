"""#269: ``POST /v1/chat`` bounds its body before reading it whole, and its
images before decoding any.

The issue's reproduction: a 240 MB body of 60 images of 3 MiB each was
correctly refused with 422, but only after memory went from 319 MB to
1279 MB, because every part was base64-decoded during validation before the
count was looked at. Now an oversized body is 413 ``payloadTooLarge`` as
soon as its bytes pass the cap, and too many parts, or a part too long as
sent, is 422 with no part decoded at all. respx only; nothing reaches Gemini.
"""

import base64
from collections.abc import Iterator

import httpx
import pytest
import respx
from fastapi.testclient import TestClient

import app.schemas
from app.config import Settings
from app.main import create_app
from app.routers.chat import max_chat_body_bytes

_INSTALL_ID = "0123456789abcdef0123456789abcdef"
_HEADERS = {"X-KetoClub-Install-Id": _INSTALL_ID}
_PNG_B64 = (
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAC"
    "hwGA60e6kgAAAABJRU5ErkJggg=="
)
_REPLY = {
    "candidates": [
        {"content": {"parts": [{"text": '{"dishes": []}'}]}, "finishReason": "STOP"}
    ]
}


def _settings(**overrides: object) -> Settings:
    return Settings(
        DATABASE_URL="sqlite:///:memory:",
        GEMINI_API_KEY="test-key",
        RATE_LIMIT_PER_MINUTE=100,
        RATE_LIMIT_PER_DAY=1000,
        **overrides,  # type: ignore[arg-type]
    )


@pytest.fixture
def gemini() -> Iterator[respx.Route]:
    with respx.mock(assert_all_called=False) as router:
        yield router.route(host="generativelanguage.googleapis.com").mock(
            return_value=httpx.Response(200, json=_REPLY)
        )


@pytest.fixture
def decodes(monkeypatch: pytest.MonkeyPatch) -> list[int]:
    """Every base64 decode validation performs, by input length."""
    seen: list[int] = []
    real = base64.b64decode

    def counting(data: str | bytes, *args: object, **kwargs: object) -> bytes:
        seen.append(len(data))
        return real(data, *args, **kwargs)  # type: ignore[arg-type]

    monkeypatch.setattr(app.schemas.base64, "b64decode", counting)
    return seen


def _body(*images: str) -> dict[str, object]:
    return {
        "system_prompt": "You classify menus.",
        "user_prompt": "1 | Mains | Steak",
        "images": [{"mime_type": "image/png", "data": data} for data in images],
    }


def test_a_body_over_the_cap_is_413_before_anything_parses_it(
    gemini: respx.Route, decodes: list[int]
) -> None:
    settings = _settings(
        CHAT_MAX_TEXT_BODY_BYTES=1024, VISION_MAX_IMAGES=1, VISION_MAX_IMAGE_BYTES=300
    )
    oversized = base64.b64encode(b"x" * 4096).decode()

    with TestClient(create_app(settings=settings)) as client:
        response = client.post("/v1/chat", json=_body(oversized), headers=_HEADERS)

    assert response.status_code == 413
    assert response.json() == {"reason": "payloadTooLarge", "status_code": 413}
    assert decodes == []
    assert not gemini.called


def test_a_body_without_a_content_length_is_cut_off_at_the_cap(
    gemini: respx.Route,
) -> None:
    settings = _settings(
        CHAT_MAX_TEXT_BODY_BYTES=1024, VISION_MAX_IMAGES=1, VISION_MAX_IMAGE_BYTES=300
    )

    def chunks() -> Iterator[bytes]:
        yield b'{"system_prompt": "s", "user_prompt": "'
        for _ in range(64):
            yield b"u" * 1024
        yield b'"}'

    with TestClient(create_app(settings=settings)) as client:
        response = client.post(
            "/v1/chat",
            content=chunks(),
            headers={**_HEADERS, "Content-Type": "application/json"},
        )

    assert response.status_code == 413
    assert not gemini.called


def test_too_many_images_are_422_before_any_is_decoded(
    gemini: respx.Route, decodes: list[int]
) -> None:
    with TestClient(create_app(settings=_settings())) as client:
        response = client.post(
            "/v1/chat", json=_body(*[_PNG_B64] * 7), headers=_HEADERS
        )

    assert response.status_code == 422
    assert response.json()["detail"][0]["loc"] == ["body", "images"]
    assert "at most 6 images" in response.json()["detail"][0]["msg"]
    assert decodes == []
    assert not gemini.called


def test_a_part_too_long_as_sent_is_422_before_it_is_decoded(
    gemini: respx.Route, decodes: list[int]
) -> None:
    settings = _settings(VISION_MAX_IMAGE_BYTES=300)
    # 300 bytes encode to 400 characters; 404 is the first longer valid length.
    too_long = base64.b64encode(b"x" * 301).decode()
    assert len(too_long) == 404

    with TestClient(create_app(settings=settings)) as client:
        at_bound = client.post(
            "/v1/chat",
            json=_body(base64.b64encode(b"x" * 300).decode()),
            headers=_HEADERS,
        )
        over = client.post("/v1/chat", json=_body(too_long), headers=_HEADERS)

    assert at_bound.status_code == 200
    assert decodes == [400]  # only the part within the bound was decoded
    assert over.status_code == 422
    assert "image 0 is over 300 bytes" in over.json()["detail"][0]["msg"]
    assert gemini.call_count == 1


def test_a_body_at_the_largest_valid_size_is_accepted(gemini: respx.Route) -> None:
    settings = _settings(
        CHAT_MAX_TEXT_BODY_BYTES=4096, VISION_MAX_IMAGES=2, VISION_MAX_IMAGE_BYTES=3000
    )
    page = base64.b64encode(b"\x89PNG" + b"x" * 2996).decode()

    with TestClient(create_app(settings=settings)) as client:
        response = client.post("/v1/chat", json=_body(page, page), headers=_HEADERS)

    assert response.status_code == 200
    assert max_chat_body_bytes(settings) == 4096 + 2 * (4000 + 256)


@pytest.mark.parametrize(
    "raw",
    [b"not json", b"[]", b'{"images": "none"}', b'{"images": [7]}'],
    ids=["not-json", "a-list", "images-not-a-list", "a-part-not-an-object"],
)
def test_a_malformed_body_is_still_the_models_own_422(
    gemini: respx.Route, raw: bytes
) -> None:
    with TestClient(create_app(settings=_settings())) as client:
        response = client.post(
            "/v1/chat",
            content=raw,
            headers={**_HEADERS, "Content-Type": "application/json"},
        )

    assert response.status_code == 422
    assert not gemini.called


def test_the_default_cap_admits_six_full_pages_and_both_prompts() -> None:
    settings = Settings(DATABASE_URL="sqlite:///:memory:")
    full_pages = 6 * 4 * -(-settings.VISION_MAX_IMAGE_BYTES // 3)
    prompts_escaped = 6 * (400_000 + 20_000)
    assert max_chat_body_bytes(settings) > full_pages + prompts_escaped
    # ...and is nowhere near the 240 MB body of the reproduction.
    assert max_chat_body_bytes(settings) < 32 * 1024 * 1024


def test_the_openapi_page_still_documents_the_chat_body() -> None:
    with TestClient(create_app(settings=_settings())) as client:
        schema = client.get("/openapi.json").json()

    body = schema["paths"]["/v1/chat"]["post"]["requestBody"]
    assert "system_prompt" in str(body)

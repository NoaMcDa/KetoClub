"""Error paths that used to escape as a bare 500 with no CORS header (#270).

Every case here answered ``500 Internal Server Error`` in plain text, outside
``CORSMiddleware``, so a browser saw a CORS failure instead of the reason.
respx only; no network.
"""

from collections.abc import Iterator

import httpx
import pytest
import respx
from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.config import Settings
from app.main import create_app
from app.services.menu_store import score_of

_INSTALL_ID = "0123456789abcdef0123456789abcdef"
_HEADERS = {"X-KetoClub-Install-Id": _INSTALL_ID}
_ORIGIN = "http://localhost:5000"
_PUBLIC = "93.184.216.34"


@pytest.fixture
def web() -> Iterator[respx.MockRouter]:
    with respx.mock(assert_all_called=False) as router:
        yield router


def _site_app(settings: Settings) -> FastAPI:
    app = create_app(settings=settings)

    async def resolve(host: str) -> list[str]:
        return [_PUBLIC]

    app.state.resolve_host = resolve
    return app


@pytest.fixture
def site_client(settings: Settings) -> Iterator[TestClient]:
    with TestClient(_site_app(settings)) as test_client:
        yield test_client


def _fetch(client: TestClient, url: str) -> httpx.Response:
    return client.post("/v1/website/fetch", json={"url": url}, headers=_HEADERS)


# --- upstream transport errors -------------------------------------------------


@pytest.mark.parametrize(
    "error",
    [
        httpx.ReadError("reset"),
        httpx.RemoteProtocolError("garbled"),
        httpx.WriteError("broken pipe"),
    ],
)
def test_a_wolt_menu_transport_error_is_offline(
    client: TestClient, web: respx.MockRouter, error: httpx.TransportError
) -> None:
    web.get(
        "https://consumer-api.wolt.com/consumer-api/consumer-assortment/v1/venues"
        "/slug/hamosad/assortment"
    ).mock(side_effect=error)

    response = client.get(
        "/v1/proxy/wolt/venues/slug/hamosad/assortment",
        headers={"Origin": _ORIGIN},
    )

    assert response.status_code == 502
    assert response.json()["reason"] == "offline"
    assert response.headers["access-control-allow-origin"] == _ORIGIN


def test_a_discovery_read_error_is_offline(
    client: TestClient, web: respx.MockRouter
) -> None:
    web.get("https://consumer-api.wolt.com/v1/pages/restaurants").mock(
        side_effect=httpx.ReadError("reset")
    )

    response = client.get(
        "/v1/proxy/wolt/pages/restaurants",
        params={"lat": 32.07, "lon": 34.77},
        headers={**_HEADERS, "Origin": _ORIGIN},
    )

    assert response.status_code == 502
    assert response.json()["reason"] == "offline"
    assert response.headers["access-control-allow-origin"] == _ORIGIN


# --- website URLs ----------------------------------------------------------------


def test_an_ipv6_literal_keeps_its_brackets_for_robots_txt(
    site_client: TestClient, web: respx.MockRouter
) -> None:
    robots = web.get("http://[2606:4700::1111]/robots.txt").mock(
        return_value=httpx.Response(404)
    )
    web.get("http://[2606:4700::1111]/menu").mock(
        return_value=httpx.Response(
            200,
            content=b"<html><body><h1>Menu</h1>"
            + b"<p>Dish with a long description 52</p>" * 20
            + b"</body></html>",
            headers={"content-type": "text/html; charset=utf-8"},
        )
    )

    response = _fetch(site_client, "http://[2606:4700::1111]/menu")

    assert robots.called
    assert response.status_code == 200


def test_a_host_label_over_63_characters_is_invalid(site_client: TestClient) -> None:
    response = _fetch(site_client, "http://" + "a" * 64 + ".com/")

    assert response.status_code == 400
    assert response.json()["reason"] == "invalidUrl"


def test_a_resolver_encoding_error_is_invalid(settings: Settings) -> None:
    app = create_app(settings=settings)

    async def resolve(host: str) -> list[str]:
        raise UnicodeError("label empty or too long")

    app.state.resolve_host = resolve
    with TestClient(app) as test_client:
        response = _fetch(test_client, "http://cafe.example/")

    assert response.status_code == 400
    assert response.json()["reason"] == "invalidUrl"


@pytest.mark.parametrize(
    "url",
    [
        "http://cafe.example/\r\nX-Injected: 1",
        "http://cafe.example/a\tb",
        "http://cafe.example/a b",
        "http://cafe.example/\x7f",
    ],
)
def test_a_url_with_a_control_character_is_invalid_before_any_fetch(
    site_client: TestClient, web: respx.MockRouter, url: str
) -> None:
    robots = web.get("http://cafe.example/robots.txt").mock(
        return_value=httpx.Response(404)
    )

    response = _fetch(site_client, url)

    assert response.status_code == 400
    assert response.json()["reason"] == "invalidUrl"
    assert not robots.called


def test_the_website_menu_route_escapes_a_control_character_and_answers(
    site_client: TestClient, web: respx.MockRouter
) -> None:
    # This route reads the URL as Dart's Uri does, which percent-encodes the
    # CR/LF, so the fetch goes ahead on the escaped path; it never 500s.
    web.get("http://cafe.example/robots.txt").mock(return_value=httpx.Response(404))
    page = web.get(host="cafe.example").mock(return_value=httpx.Response(404))

    response = site_client.post(
        "/v1/website-menu",
        json={
            "url": "http://cafe.example/\r\nX-Injected: 1",
            "options": {"netCarbLimitGrams": 6, "dietaryConstraints": []},
        },
        headers=_HEADERS,
    )

    assert response.status_code == 404
    assert "\r" not in str(page.calls.last.request.url)


# --- request bodies --------------------------------------------------------------


@pytest.mark.parametrize("depth", [40, 3000])
def test_a_deeply_nested_response_schema_is_422(client: TestClient, depth: int) -> None:
    schema = '{"type": "string"}'
    for _ in range(depth):
        schema = '{"type": "object", "properties": {"x": ' + schema + "}}"
    response = client.post(
        "/v1/chat",
        content='{"system_prompt": "s", "user_prompt": "u", "response_schema": '
        + schema
        + "}",
        headers={**_HEADERS, "Origin": _ORIGIN, "Content-Type": "application/json"},
    )

    assert response.status_code == 422
    assert response.headers["access-control-allow-origin"] == _ORIGIN


def test_the_real_prompt_schemas_are_within_the_depth_cap() -> None:
    from app.keto import prompt
    from app.schemas import MAX_SCHEMA_DEPTH, _nesting_depth

    assert _nesting_depth(prompt.response_schema()) <= MAX_SCHEMA_DEPTH


def test_an_integer_score_too_large_for_a_float_is_no_score() -> None:
    assert score_of({"score": -(10**400)}) is None
    assert score_of({"score": 10**400}) is None
    assert score_of({"score": 80}) == 80.0


def test_a_menu_upload_with_a_huge_integer_score_is_stored_without_one(
    client: TestClient,
) -> None:
    response = client.post(
        "/v1/menus",
        content=(
            '{"source": "wolt", "platform_id": "hamosad", "menu": {"categories":'
            ' [{"name": "Mains", "dishes": [{"name": "Steak"}]}]},'
            ' "analysis": {"score": -1' + "0" * 400 + "}}"
        ),
        headers={**_HEADERS, "Content-Type": "application/json"},
    )

    assert response.status_code == 201


# --- the catch-all ---------------------------------------------------------------


def test_an_unhandled_exception_is_a_500_body_with_cors(settings: Settings) -> None:
    app = create_app(settings=settings)

    @app.get("/v1/boom")
    async def boom() -> None:
        raise RuntimeError("a message that may quote request content")

    with TestClient(app, raise_server_exceptions=False) as test_client:
        response = test_client.get("/v1/boom", headers={"Origin": _ORIGIN})

    assert response.status_code == 500
    assert response.json() == {"reason": "internalError", "status_code": 500}
    assert response.headers["access-control-allow-origin"] == _ORIGIN
    assert response.headers["X-Request-Id"]

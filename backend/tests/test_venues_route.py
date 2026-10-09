"""Tests for ``/v1/venues/nearby`` and ``/v1/venues/search`` (D25, #335)."""

import json
import logging
from collections.abc import Iterator
from pathlib import Path
from typing import Any

import httpx
import pytest
import respx
from fastapi.testclient import TestClient

from app.config import Settings
from app.main import create_app

_INSTALL_ID = "0123456789abcdef0123456789abcdef"

_NEARBY_PATH = "/v1/venues/nearby"
_SEARCH_PATH = "/v1/venues/search"
_UPSTREAM_RESTAURANTS = "https://consumer-api.wolt.com/v1/pages/restaurants"
_UPSTREAM_SEARCH = "https://restaurant-api.wolt.com/v1/pages/search"

_LAT = 32.0700
_LON = 34.7700

_GOLDEN = Path(__file__).parent / "fixtures" / "golden" / "wolt_venues.json"
_ENTRIES: list[dict[str, Any]] = json.loads(_GOLDEN.read_text(encoding="utf-8"))
_MAPPABLE = [entry for entry in _ENTRIES if entry["venues"] is not None]


def _headers(install_id: str | None = _INSTALL_ID) -> dict[str, str]:
    return {} if install_id is None else {"X-KetoClub-Install-Id": install_id}


def _entry(name: str) -> dict[str, Any]:
    return next(entry for entry in _ENTRIES if entry["name"] == name)


@pytest.fixture
def wolt_discovery() -> Iterator[respx.MockRouter]:
    """A respx router covering both discovery hosts."""
    with respx.mock(assert_all_called=False) as router:
        yield router


def _nearby(client: TestClient, **params: object) -> httpx.Response:
    query = {"lat": _LAT, "lon": _LON, **params}
    return client.get(_NEARBY_PATH, params=query, headers=_headers())


def _search(client: TestClient, **body: object) -> httpx.Response:
    payload = {"query": "vitrina", "lang": "en", "lat": _LAT, "lon": _LON, **body}
    return client.post(_SEARCH_PATH, json=payload, headers=_headers())


# --- the golden pages -------------------------------------------------------


@pytest.mark.parametrize("entry", _MAPPABLE, ids=[e["name"] for e in _MAPPABLE])
def test_nearby_returns_golden_venues(
    client: TestClient, wolt_discovery: respx.MockRouter, entry: dict[str, Any]
) -> None:
    wolt_discovery.get(_UPSTREAM_RESTAURANTS).mock(
        return_value=httpx.Response(200, json=entry["raw"])
    )

    response = _nearby(client)

    assert response.status_code == 200
    assert response.headers["content-type"] == "application/json"
    assert response.headers["X-KetoClub-Cache"] == "miss"
    assert response.json() == {"venues": entry["venues"]}


@pytest.mark.parametrize("entry", _MAPPABLE, ids=[e["name"] for e in _MAPPABLE])
def test_search_returns_golden_venues(
    client: TestClient, wolt_discovery: respx.MockRouter, entry: dict[str, Any]
) -> None:
    wolt_discovery.post(_UPSTREAM_SEARCH).mock(
        return_value=httpx.Response(200, json=entry["raw"])
    )

    response = _search(client)

    assert response.status_code == 200
    assert response.headers["X-KetoClub-Cache"] == "miss"
    assert response.json() == {"venues": entry["venues"]}


def test_empty_page_is_an_empty_list_not_an_error(
    client: TestClient, wolt_discovery: respx.MockRouter
) -> None:
    wolt_discovery.get(_UPSTREAM_RESTAURANTS).mock(
        return_value=httpx.Response(200, json=_entry("synthetic_empty_sections")["raw"])
    )

    response = _nearby(client)

    assert response.status_code == 200
    assert response.json() == {"venues": []}


def test_venues_keep_wolts_order(
    client: TestClient, wolt_discovery: respx.MockRouter
) -> None:
    entry = _entry("wolt_pages_restaurants.json")
    wolt_discovery.get(_UPSTREAM_RESTAURANTS).mock(
        return_value=httpx.Response(200, json=entry["raw"])
    )

    venues = _nearby(client).json()["venues"]

    assert [v["ref"]["platformId"] for v in venues] == [
        v["ref"]["platformId"] for v in entry["venues"]
    ]


# --- upstream requests ------------------------------------------------------


def test_search_forwards_the_query_as_a_venue_search(
    client: TestClient, wolt_discovery: respx.MockRouter
) -> None:
    wolt_discovery.post(_UPSTREAM_SEARCH).mock(
        return_value=httpx.Response(200, json=_MAPPABLE[0]["raw"])
    )

    _search(client, query="  Vitrina  ")

    sent = json.loads(wolt_discovery.calls.last.request.content)
    assert sent == {"q": "Vitrina", "target": "venues", "lat": _LAT, "lon": _LON}
    assert _INSTALL_ID not in str(wolt_discovery.calls.last.request.headers)


def test_search_without_position_sends_no_coordinates(
    client: TestClient, wolt_discovery: respx.MockRouter
) -> None:
    wolt_discovery.post(_UPSTREAM_SEARCH).mock(
        return_value=httpx.Response(200, json=_MAPPABLE[0]["raw"])
    )

    response = client.post(_SEARCH_PATH, json={"query": "vitrina"}, headers=_headers())

    assert response.status_code == 200
    sent = json.loads(wolt_discovery.calls.last.request.content)
    assert sent == {"q": "vitrina", "target": "venues"}


def test_nearby_sends_lat_and_lon(
    client: TestClient, wolt_discovery: respx.MockRouter
) -> None:
    wolt_discovery.get(_UPSTREAM_RESTAURANTS).mock(
        return_value=httpx.Response(200, json=_MAPPABLE[0]["raw"])
    )

    _nearby(client)

    sent_url = wolt_discovery.calls.last.request.url
    assert float(sent_url.params["lat"]) == _LAT
    assert float(sent_url.params["lon"]) == _LON


# --- cache and limiter ------------------------------------------------------


def test_nearby_cache_hit_makes_no_upstream_call(
    client: TestClient, wolt_discovery: respx.MockRouter
) -> None:
    route = wolt_discovery.get(_UPSTREAM_RESTAURANTS).mock(
        return_value=httpx.Response(200, json=_MAPPABLE[0]["raw"])
    )

    first = _nearby(client)
    second = _nearby(client)

    assert route.call_count == 1
    assert first.headers["X-KetoClub-Cache"] == "miss"
    assert second.headers["X-KetoClub-Cache"] == "hit"
    assert second.json() == first.json()


def test_search_cache_hit_makes_no_upstream_call(
    client: TestClient, wolt_discovery: respx.MockRouter
) -> None:
    route = wolt_discovery.post(_UPSTREAM_SEARCH).mock(
        return_value=httpx.Response(200, json=_MAPPABLE[0]["raw"])
    )

    _search(client)
    second = _search(client, query="VITRINA")

    assert route.call_count == 1
    assert second.headers["X-KetoClub-Cache"] == "hit"
    assert second.json() == {"venues": _MAPPABLE[0]["venues"]}


def test_proxy_and_venues_share_one_cache_row(
    client: TestClient, wolt_discovery: respx.MockRouter
) -> None:
    route = wolt_discovery.get(_UPSTREAM_RESTAURANTS).mock(
        return_value=httpx.Response(200, json=_MAPPABLE[0]["raw"])
    )

    proxied = client.get(
        "/v1/proxy/wolt/pages/restaurants",
        params={"lat": _LAT, "lon": _LON},
        headers=_headers(),
    )
    venues = _nearby(client)

    assert proxied.headers["X-KetoClub-Cache"] == "miss"
    assert venues.headers["X-KetoClub-Cache"] == "hit"
    assert route.call_count == 1


def test_cache_hit_bypasses_the_limiter_and_empty_bucket_is_429(
    wolt_discovery: respx.MockRouter,
) -> None:
    settings = Settings(
        DATABASE_URL="sqlite:///:memory:", DISCOVERY_RATE_LIMIT_PER_MINUTE=2
    )
    wolt_discovery.get(_UPSTREAM_RESTAURANTS).mock(
        return_value=httpx.Response(200, json=_MAPPABLE[0]["raw"])
    )

    with TestClient(create_app(settings=settings)) as client:
        miss_1 = _nearby(client)
        cache_hit = _nearby(client)
        miss_2 = _nearby(client, lat=10.0, lon=20.0)
        limited = _nearby(client, lat=5.0, lon=6.0)

    assert miss_1.status_code == 200
    assert cache_hit.headers["X-KetoClub-Cache"] == "hit"
    assert miss_2.status_code == 200
    assert limited.status_code == 429
    assert limited.json() == {"reason": "rateLimited", "status_code": 429}


def test_search_shares_the_discovery_bucket(
    wolt_discovery: respx.MockRouter,
) -> None:
    settings = Settings(
        DATABASE_URL="sqlite:///:memory:", DISCOVERY_RATE_LIMIT_PER_MINUTE=1
    )
    wolt_discovery.get(_UPSTREAM_RESTAURANTS).mock(
        return_value=httpx.Response(200, json=_MAPPABLE[0]["raw"])
    )
    wolt_discovery.post(_UPSTREAM_SEARCH).mock(
        return_value=httpx.Response(200, json=_MAPPABLE[0]["raw"])
    )

    with TestClient(create_app(settings=settings)) as client:
        nearby = _nearby(client)
        search = _search(client)

    assert nearby.status_code == 200
    assert search.status_code == 429
    assert search.json() == {"reason": "rateLimited", "status_code": 429}


# --- failures ---------------------------------------------------------------


def test_mapper_none_is_502_platform_changed(
    client: TestClient, wolt_discovery: respx.MockRouter
) -> None:
    wolt_discovery.get(_UPSTREAM_RESTAURANTS).mock(
        return_value=httpx.Response(200, json=_entry("synthetic_no_sections")["raw"])
    )

    response = _nearby(client)

    assert response.status_code == 502
    assert response.json() == {"reason": "platformChanged", "status_code": 502}


@pytest.mark.parametrize("status", [400, 404, 410, 500, 503])
def test_non_2xx_upstream_is_502_platform_changed(
    client: TestClient, wolt_discovery: respx.MockRouter, status: int
) -> None:
    wolt_discovery.post(_UPSTREAM_SEARCH).mock(
        return_value=httpx.Response(status, json={"error_code": 430})
    )

    response = _search(client)

    assert response.status_code == 502
    assert response.json() == {"reason": "platformChanged", "status_code": 502}


def test_unreadable_body_is_502_platform_changed(
    client: TestClient, wolt_discovery: respx.MockRouter
) -> None:
    wolt_discovery.get(_UPSTREAM_RESTAURANTS).mock(
        return_value=httpx.Response(200, content=b"<html>not json</html>")
    )

    response = _nearby(client)

    assert response.status_code == 502
    assert response.json() == {"reason": "platformChanged", "status_code": 502}


def test_failures_are_not_cached(
    client: TestClient, wolt_discovery: respx.MockRouter
) -> None:
    route = wolt_discovery.get(_UPSTREAM_RESTAURANTS).mock(
        return_value=httpx.Response(410, json={})
    )

    _nearby(client)
    _nearby(client)

    assert route.call_count == 2


def test_connect_error_is_502_offline(
    client: TestClient, wolt_discovery: respx.MockRouter
) -> None:
    wolt_discovery.get(_UPSTREAM_RESTAURANTS).mock(
        side_effect=httpx.ConnectError("refused")
    )

    response = _nearby(client)

    assert response.status_code == 502
    assert response.json() == {"reason": "offline", "status_code": 502}


def test_timeout_is_504(client: TestClient, wolt_discovery: respx.MockRouter) -> None:
    wolt_discovery.post(_UPSTREAM_SEARCH).mock(
        side_effect=httpx.ReadTimeout("timed out")
    )

    response = _search(client)

    assert response.status_code == 504
    assert response.json() == {"reason": "timeout", "status_code": 504}


# --- request validation and credentials -------------------------------------


@pytest.mark.parametrize(
    "params",
    [
        {"lat": 91, "lon": _LON},
        {"lat": _LAT, "lon": -181},
        {"lat": _LAT, "lon": _LON, "lang": "fr"},
    ],
)
def test_nearby_rejects_bad_query(
    client: TestClient, wolt_discovery: respx.MockRouter, params: dict[str, Any]
) -> None:
    response = client.get(_NEARBY_PATH, params=params, headers=_headers())

    assert response.status_code == 422
    assert wolt_discovery.calls.call_count == 0


@pytest.mark.parametrize(
    "body",
    [
        {"query": "   "},
        {"query": "x" * 101},
        {"query": "vitrina", "lat": _LAT},
        {"query": "vitrina", "lang": "fr"},
        {"query": "vitrina", "lat": 100, "lon": _LON},
    ],
)
def test_search_rejects_bad_body(
    client: TestClient, wolt_discovery: respx.MockRouter, body: dict[str, Any]
) -> None:
    response = client.post(_SEARCH_PATH, json=body, headers=_headers())

    assert response.status_code == 422
    assert wolt_discovery.calls.call_count == 0


def test_search_accepts_a_100_character_query(
    client: TestClient, wolt_discovery: respx.MockRouter
) -> None:
    wolt_discovery.post(_UPSTREAM_SEARCH).mock(
        return_value=httpx.Response(200, json=_MAPPABLE[0]["raw"])
    )

    assert _search(client, query="x" * 100).status_code == 200


@pytest.mark.parametrize("install_id", [None, "short", "G" * 32])
def test_missing_or_malformed_install_id_is_400(
    client: TestClient, wolt_discovery: respx.MockRouter, install_id: str | None
) -> None:
    nearby = client.get(
        _NEARBY_PATH,
        params={"lat": _LAT, "lon": _LON},
        headers=_headers(install_id),
    )
    search = client.post(
        _SEARCH_PATH, json={"query": "vitrina"}, headers=_headers(install_id)
    )

    for response in (nearby, search):
        assert response.status_code == 400
        assert response.json() == {"reason": "badResponse", "status_code": 400}
    assert wolt_discovery.calls.call_count == 0


def test_authorization_header_is_rejected(
    client: TestClient, wolt_discovery: respx.MockRouter
) -> None:
    headers = {**_headers(), "Authorization": "Bearer secret"}

    nearby = client.get(
        _NEARBY_PATH, params={"lat": _LAT, "lon": _LON}, headers=headers
    )
    search = client.post(_SEARCH_PATH, json={"query": "vitrina"}, headers=headers)

    for response in (nearby, search):
        assert response.status_code == 400
        assert response.json() == {"reason": "badResponse", "status_code": 400}
    assert wolt_discovery.calls.call_count == 0


def test_install_id_is_in_no_log_line(
    client: TestClient,
    wolt_discovery: respx.MockRouter,
    caplog: pytest.LogCaptureFixture,
) -> None:
    wolt_discovery.get(_UPSTREAM_RESTAURANTS).mock(
        return_value=httpx.Response(200, json=_MAPPABLE[0]["raw"])
    )
    wolt_discovery.post(_UPSTREAM_SEARCH).mock(
        return_value=httpx.Response(410, json={})
    )

    with caplog.at_level(logging.DEBUG):
        _nearby(client)
        _search(client)

    rendered = " ".join(
        f"{record.getMessage()} {record.__dict__}" for record in caplog.records
    )
    assert _INSTALL_ID not in rendered
    assert _INSTALL_ID[:8] not in rendered

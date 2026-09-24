"""Tests for the Wolt venue-discovery proxy routes (#123)."""

import json
from collections.abc import Iterator

import httpx
import pytest
import respx
from fastapi.testclient import TestClient

from app.config import Settings
from app.main import create_app
from app.services.wolt import WOLT_USER_AGENT

_INSTALL_ID = "0123456789abcdef0123456789abcdef"

_RESTAURANTS_PATH = "/v1/proxy/wolt/pages/restaurants"
_SEARCH_PATH = "/v1/proxy/wolt/pages/search"
_UPSTREAM_RESTAURANTS = "https://consumer-api.wolt.com/v1/pages/restaurants"
_UPSTREAM_SEARCH = "https://restaurant-api.wolt.com/v1/pages/search"

_LAT = 32.0700
_LON = 34.7700


def _headers(install_id: str | None = _INSTALL_ID) -> dict[str, str]:
    return {} if install_id is None else {"X-KetoClub-Install-Id": install_id}


def _venues_body() -> dict[str, object]:
    return {"sections": [{"items": [{"venue": {"slug": "vitrina-lilinblum"}}]}]}


@pytest.fixture
def wolt_discovery() -> Iterator[respx.MockRouter]:
    """A respx router covering both discovery hosts.

    Nested inside the autouse network block from ``conftest.py``, the same
    pattern ``test_proxy.py``'s ``wolt`` fixture uses. Unlike that fixture
    this one is not scoped to a single ``base_url``: the two routes call two
    different Wolt hosts (``consumer-api.wolt.com``,
    ``restaurant-api.wolt.com``), so routes are registered against their
    full URLs instead.
    """
    with respx.mock(assert_all_called=False) as router:
        yield router


# --- GET /pages/restaurants -----------------------------------------------


def test_nearby_200_preserves_body_and_content_type(
    client: TestClient, wolt_discovery: respx.MockRouter
) -> None:
    wolt_discovery.get(_UPSTREAM_RESTAURANTS).mock(
        return_value=httpx.Response(200, json=_venues_body())
    )

    response = client.get(
        _RESTAURANTS_PATH, params={"lat": _LAT, "lon": _LON}, headers=_headers()
    )

    assert response.status_code == 200
    assert response.json() == _venues_body()
    assert response.headers["content-type"] == "application/json"
    assert response.headers["X-KetoClub-Cache"] == "miss"


def test_nearby_passthrough_410(
    client: TestClient, wolt_discovery: respx.MockRouter
) -> None:
    # 410 is Wolt's own "update the app" code (phase2_discovery_research.md
    # §2.2), and must reach the client unchanged rather than as a 5xx.
    wolt_discovery.get(_UPSTREAM_RESTAURANTS).mock(
        return_value=httpx.Response(410, json={"error_code": 430})
    )

    response = client.get(
        _RESTAURANTS_PATH, params={"lat": _LAT, "lon": _LON}, headers=_headers()
    )

    assert response.status_code == 410
    assert response.json() == {"error_code": 430}


def test_nearby_passthrough_500(
    client: TestClient, wolt_discovery: respx.MockRouter
) -> None:
    wolt_discovery.get(_UPSTREAM_RESTAURANTS).mock(
        return_value=httpx.Response(500, json={"error": "boom"})
    )

    response = client.get(
        _RESTAURANTS_PATH, params={"lat": _LAT, "lon": _LON}, headers=_headers()
    )

    assert response.status_code == 500
    assert response.json() == {"error": "boom"}


def test_nearby_connect_error_returns_502_offline(
    client: TestClient, wolt_discovery: respx.MockRouter
) -> None:
    wolt_discovery.get(_UPSTREAM_RESTAURANTS).mock(
        side_effect=httpx.ConnectError("connection refused")
    )

    response = client.get(
        _RESTAURANTS_PATH, params={"lat": _LAT, "lon": _LON}, headers=_headers()
    )

    assert response.status_code == 502
    assert response.json() == {"reason": "offline", "status_code": 502}


def test_nearby_timeout_returns_504_timeout(
    client: TestClient, wolt_discovery: respx.MockRouter
) -> None:
    wolt_discovery.get(_UPSTREAM_RESTAURANTS).mock(
        side_effect=httpx.ReadTimeout("timed out")
    )

    response = client.get(
        _RESTAURANTS_PATH, params={"lat": _LAT, "lon": _LON}, headers=_headers()
    )

    assert response.status_code == 504
    assert response.json() == {"reason": "timeout", "status_code": 504}


@pytest.mark.parametrize(
    "params",
    [
        {"lat": 91, "lon": _LON},
        {"lat": -91, "lon": _LON},
        {"lat": _LAT, "lon": 181},
        {"lat": _LAT, "lon": -181},
        {"lat": _LAT, "lon": _LON, "lang": "fr"},
    ],
    ids=["lat-too-high", "lat-too-low", "lon-too-high", "lon-too-low", "bad-lang"],
)
def test_nearby_invalid_params_are_422(
    client: TestClient, wolt_discovery: respx.MockRouter, params: dict[str, object]
) -> None:
    response = client.get(_RESTAURANTS_PATH, params=params, headers=_headers())

    assert response.status_code == 422
    assert len(wolt_discovery.calls) == 0


def test_nearby_missing_install_id_is_400(
    client: TestClient, wolt_discovery: respx.MockRouter
) -> None:
    response = client.get(_RESTAURANTS_PATH, params={"lat": _LAT, "lon": _LON})

    assert response.status_code == 400
    assert response.json() == {"reason": "badResponse", "status_code": 400}
    assert len(wolt_discovery.calls) == 0


def test_nearby_second_call_is_served_from_cache(
    client: TestClient, wolt_discovery: respx.MockRouter
) -> None:
    route = wolt_discovery.get(_UPSTREAM_RESTAURANTS).mock(
        return_value=httpx.Response(200, json=_venues_body())
    )

    first = client.get(
        _RESTAURANTS_PATH, params={"lat": _LAT, "lon": _LON}, headers=_headers()
    )
    second = client.get(
        _RESTAURANTS_PATH, params={"lat": _LAT, "lon": _LON}, headers=_headers()
    )

    assert first.headers["X-KetoClub-Cache"] == "miss"
    assert second.headers["X-KetoClub-Cache"] == "hit"
    assert second.json() == _venues_body()
    assert route.call_count == 1


def test_nearby_expired_cache_entry_is_refetched(
    wolt_discovery: respx.MockRouter,
) -> None:
    settings = Settings(
        DATABASE_URL="sqlite:///:memory:", DISCOVERY_CACHE_TTL_SECONDS=0
    )
    app = create_app(settings=settings)
    route = wolt_discovery.get(_UPSTREAM_RESTAURANTS).mock(
        return_value=httpx.Response(200, json=_venues_body())
    )

    with TestClient(app) as client:
        first = client.get(
            _RESTAURANTS_PATH, params={"lat": _LAT, "lon": _LON}, headers=_headers()
        )
        second = client.get(
            _RESTAURANTS_PATH, params={"lat": _LAT, "lon": _LON}, headers=_headers()
        )

    assert first.headers["X-KetoClub-Cache"] == "miss"
    assert second.headers["X-KetoClub-Cache"] == "miss"
    assert route.call_count == 2


def test_nearby_failed_response_is_not_cached(
    client: TestClient, wolt_discovery: respx.MockRouter
) -> None:
    route = wolt_discovery.get(_UPSTREAM_RESTAURANTS).mock(
        side_effect=[
            httpx.Response(500, json={"error": "boom"}),
            httpx.Response(200, json=_venues_body()),
        ]
    )

    first = client.get(
        _RESTAURANTS_PATH, params={"lat": _LAT, "lon": _LON}, headers=_headers()
    )
    second = client.get(
        _RESTAURANTS_PATH, params={"lat": _LAT, "lon": _LON}, headers=_headers()
    )

    assert first.status_code == 500
    assert first.headers["X-KetoClub-Cache"] == "miss"
    assert second.status_code == 200
    assert second.headers["X-KetoClub-Cache"] == "miss"
    assert route.call_count == 2


def test_nearby_header_set_and_no_inbound_headers(
    client: TestClient, wolt_discovery: respx.MockRouter
) -> None:
    wolt_discovery.get(_UPSTREAM_RESTAURANTS).mock(
        return_value=httpx.Response(200, json={})
    )

    client.get(
        _RESTAURANTS_PATH,
        params={"lat": _LAT, "lon": _LON, "lang": "he"},
        headers={
            **_headers(),
            "Cookie": "session=secret",
            "Authorization": "Bearer user-key",
            "Origin": "http://localhost:5000",
            "X-Custom-Header": "should-not-forward",
        },
    )

    sent = wolt_discovery.calls.last.request.headers
    assert sent["platform"] == "Web"
    assert sent["client-version"] == "1.16.125"
    assert sent["clientversionnumber"] == "1.16.125"
    assert sent["app-language"] == "he"
    assert sent["w-wolt-session-id"] == "no-analytics-consent"
    assert sent["accept"] == "application/json"
    assert sent["user-agent"] == WOLT_USER_AGENT
    # A per-process uuid4, not the KetoClub install id.
    assert sent["x-wolt-web-clientid"] != _INSTALL_ID
    assert len(sent["x-wolt-web-clientid"]) == 36
    assert "cookie" not in sent
    assert "authorization" not in sent
    assert "origin" not in sent
    assert "x-ketoclub-install-id" not in sent
    assert "x-custom-header" not in sent


def test_nearby_sends_lat_and_lon_as_query_params(
    client: TestClient, wolt_discovery: respx.MockRouter
) -> None:
    wolt_discovery.get(_UPSTREAM_RESTAURANTS).mock(
        return_value=httpx.Response(200, json={})
    )

    client.get(_RESTAURANTS_PATH, params={"lat": _LAT, "lon": _LON}, headers=_headers())

    sent_url = wolt_discovery.calls.last.request.url
    assert float(sent_url.params["lat"]) == _LAT
    assert float(sent_url.params["lon"]) == _LON


# --- rate limiting, shared by both routes ----------------------------------


def test_cache_hit_bypasses_the_rate_limiter(wolt_discovery: respx.MockRouter) -> None:
    settings = Settings(
        DATABASE_URL="sqlite:///:memory:", DISCOVERY_RATE_LIMIT_PER_MINUTE=2
    )
    app = create_app(settings=settings)
    wolt_discovery.get(_UPSTREAM_RESTAURANTS).mock(
        return_value=httpx.Response(200, json=_venues_body())
    )

    with TestClient(app) as client:
        miss_1 = client.get(
            _RESTAURANTS_PATH, params={"lat": _LAT, "lon": _LON}, headers=_headers()
        )
        # Same key as miss_1: a cache hit, so it must not spend the
        # limiter's two-per-minute quota.
        cache_hit = client.get(
            _RESTAURANTS_PATH, params={"lat": _LAT, "lon": _LON}, headers=_headers()
        )
        # A distinct key: the limiter's second real consumption.
        miss_2 = client.get(
            _RESTAURANTS_PATH, params={"lat": 10.0, "lon": 20.0}, headers=_headers()
        )
        # A third distinct key: the quota (2) is now spent.
        limited = client.get(
            _RESTAURANTS_PATH, params={"lat": 5.0, "lon": 6.0}, headers=_headers()
        )

    assert miss_1.status_code == 200
    assert miss_1.headers["X-KetoClub-Cache"] == "miss"
    assert cache_hit.status_code == 200
    assert cache_hit.headers["X-KetoClub-Cache"] == "hit"
    assert miss_2.status_code == 200
    assert miss_2.headers["X-KetoClub-Cache"] == "miss"
    assert limited.status_code == 429
    assert limited.json() == {"reason": "rateLimited", "status_code": 429}


def test_over_the_per_install_limit_is_rate_limited(
    wolt_discovery: respx.MockRouter,
) -> None:
    route = wolt_discovery.get(_UPSTREAM_RESTAURANTS).mock(
        return_value=httpx.Response(200, json=_venues_body())
    )
    settings = Settings(
        DATABASE_URL="sqlite:///:memory:", DISCOVERY_RATE_LIMIT_PER_MINUTE=1
    )
    app = create_app(settings=settings)

    with TestClient(app) as client:
        first = client.get(
            _RESTAURANTS_PATH, params={"lat": _LAT, "lon": _LON}, headers=_headers()
        )
        second = client.get(
            _RESTAURANTS_PATH, params={"lat": 1.0, "lon": 2.0}, headers=_headers()
        )
        other_install = client.get(
            _RESTAURANTS_PATH,
            params={"lat": 1.0, "lon": 2.0},
            headers=_headers("f" * 32),
        )

    assert first.status_code == 200
    assert second.status_code == 429
    assert second.json() == {"reason": "rateLimited", "status_code": 429}
    assert other_install.status_code == 200
    assert route.call_count == 2


# --- POST /pages/search -----------------------------------------------------


def _search_body(q: str = "vitrina", lang: str = "en") -> dict[str, object]:
    return {"q": q, "lat": _LAT, "lon": _LON, "lang": lang}


def test_search_200_preserves_body_and_content_type(
    client: TestClient, wolt_discovery: respx.MockRouter
) -> None:
    wolt_discovery.post(_UPSTREAM_SEARCH).mock(
        return_value=httpx.Response(200, json=_venues_body())
    )

    response = client.post(_SEARCH_PATH, json=_search_body(), headers=_headers())

    assert response.status_code == 200
    assert response.json() == _venues_body()
    assert response.headers["content-type"] == "application/json"
    assert response.headers["X-KetoClub-Cache"] == "miss"


def test_search_passthrough_410(
    client: TestClient, wolt_discovery: respx.MockRouter
) -> None:
    wolt_discovery.post(_UPSTREAM_SEARCH).mock(
        return_value=httpx.Response(410, json={"error_code": 430})
    )

    response = client.post(_SEARCH_PATH, json=_search_body(), headers=_headers())

    assert response.status_code == 410
    assert response.json() == {"error_code": 430}


def test_search_passthrough_500(
    client: TestClient, wolt_discovery: respx.MockRouter
) -> None:
    wolt_discovery.post(_UPSTREAM_SEARCH).mock(
        return_value=httpx.Response(500, json={"error": "boom"})
    )

    response = client.post(_SEARCH_PATH, json=_search_body(), headers=_headers())

    assert response.status_code == 500
    assert response.json() == {"error": "boom"}


def test_search_connect_error_returns_502_offline(
    client: TestClient, wolt_discovery: respx.MockRouter
) -> None:
    wolt_discovery.post(_UPSTREAM_SEARCH).mock(
        side_effect=httpx.ConnectError("connection refused")
    )

    response = client.post(_SEARCH_PATH, json=_search_body(), headers=_headers())

    assert response.status_code == 502
    assert response.json() == {"reason": "offline", "status_code": 502}


def test_search_timeout_returns_504_timeout(
    client: TestClient, wolt_discovery: respx.MockRouter
) -> None:
    wolt_discovery.post(_UPSTREAM_SEARCH).mock(
        side_effect=httpx.ReadTimeout("timed out")
    )

    response = client.post(_SEARCH_PATH, json=_search_body(), headers=_headers())

    assert response.status_code == 504
    assert response.json() == {"reason": "timeout", "status_code": 504}


@pytest.mark.parametrize(
    "body",
    [
        {**_search_body(), "q": ""},
        {**_search_body(), "q": "   "},
        {**_search_body(), "q": "a" * 81},
        {**_search_body(), "lat": 91},
        {**_search_body(), "lon": -181},
        {**_search_body(), "lang": "fr"},
    ],
    ids=[
        "empty-q",
        "whitespace-only-q",
        "too-long-q",
        "lat-too-high",
        "lon-too-low",
        "bad-lang",
    ],
)
def test_search_invalid_body_is_422(
    client: TestClient, wolt_discovery: respx.MockRouter, body: dict[str, object]
) -> None:
    response = client.post(_SEARCH_PATH, json=body, headers=_headers())

    assert response.status_code == 422
    assert len(wolt_discovery.calls) == 0


def test_search_missing_install_id_is_400(
    client: TestClient, wolt_discovery: respx.MockRouter
) -> None:
    response = client.post(_SEARCH_PATH, json=_search_body())

    assert response.status_code == 400
    assert response.json() == {"reason": "badResponse", "status_code": 400}
    assert len(wolt_discovery.calls) == 0


def test_search_trims_q_before_forwarding(
    client: TestClient, wolt_discovery: respx.MockRouter
) -> None:
    wolt_discovery.post(_UPSTREAM_SEARCH).mock(
        return_value=httpx.Response(200, json={})
    )

    client.post(_SEARCH_PATH, json=_search_body(q="  vitrina  "), headers=_headers())

    sent_body = json.loads(wolt_discovery.calls.last.request.content)
    assert sent_body["q"] == "vitrina"


def test_search_target_is_fixed_server_side(
    client: TestClient, wolt_discovery: respx.MockRouter
) -> None:
    wolt_discovery.post(_UPSTREAM_SEARCH).mock(
        return_value=httpx.Response(200, json={})
    )

    client.post(
        _SEARCH_PATH,
        json={**_search_body(), "target": "items"},
        headers=_headers(),
    )

    sent_body = json.loads(wolt_discovery.calls.last.request.content)
    assert sent_body == {
        "q": "vitrina",
        "target": "venues",
        "lat": _LAT,
        "lon": _LON,
    }


def test_search_without_a_position_forwards_no_lat_lon(
    client: TestClient, wolt_discovery: respx.MockRouter
) -> None:
    wolt_discovery.post(_UPSTREAM_SEARCH).mock(
        return_value=httpx.Response(200, json={})
    )

    response = client.post(
        _SEARCH_PATH, json={"q": "vitrina", "lang": "en"}, headers=_headers()
    )

    assert response.status_code == 200
    sent_body = json.loads(wolt_discovery.calls.last.request.content)
    assert sent_body == {"q": "vitrina", "target": "venues"}


@pytest.mark.parametrize(
    "body",
    [
        {"q": "vitrina", "lat": _LAT},
        {"q": "vitrina", "lon": _LON},
    ],
)
def test_search_with_half_a_position_is_422(
    client: TestClient, body: dict[str, object]
) -> None:
    response = client.post(_SEARCH_PATH, json=body, headers=_headers())

    assert response.status_code == 422


def test_search_with_and_without_a_position_do_not_share_a_cache_key(
    client: TestClient, wolt_discovery: respx.MockRouter
) -> None:
    route = wolt_discovery.post(_UPSTREAM_SEARCH).mock(
        return_value=httpx.Response(200, json={})
    )

    client.post(_SEARCH_PATH, json=_search_body(), headers=_headers())
    client.post(_SEARCH_PATH, json={"q": "vitrina", "lang": "en"}, headers=_headers())

    assert route.call_count == 2


def test_search_second_call_is_served_from_cache(
    client: TestClient, wolt_discovery: respx.MockRouter
) -> None:
    route = wolt_discovery.post(_UPSTREAM_SEARCH).mock(
        return_value=httpx.Response(200, json=_venues_body())
    )

    first = client.post(_SEARCH_PATH, json=_search_body(), headers=_headers())
    second = client.post(_SEARCH_PATH, json=_search_body(), headers=_headers())

    assert first.headers["X-KetoClub-Cache"] == "miss"
    assert second.headers["X-KetoClub-Cache"] == "hit"
    assert second.json() == _venues_body()
    assert route.call_count == 1


def test_search_expired_cache_entry_is_refetched(
    wolt_discovery: respx.MockRouter,
) -> None:
    settings = Settings(
        DATABASE_URL="sqlite:///:memory:", DISCOVERY_CACHE_TTL_SECONDS=0
    )
    app = create_app(settings=settings)
    route = wolt_discovery.post(_UPSTREAM_SEARCH).mock(
        return_value=httpx.Response(200, json=_venues_body())
    )

    with TestClient(app) as client:
        first = client.post(_SEARCH_PATH, json=_search_body(), headers=_headers())
        second = client.post(_SEARCH_PATH, json=_search_body(), headers=_headers())

    assert first.headers["X-KetoClub-Cache"] == "miss"
    assert second.headers["X-KetoClub-Cache"] == "miss"
    assert route.call_count == 2


def test_search_header_set_and_no_inbound_headers(
    client: TestClient, wolt_discovery: respx.MockRouter
) -> None:
    wolt_discovery.post(_UPSTREAM_SEARCH).mock(
        return_value=httpx.Response(200, json={})
    )

    client.post(
        _SEARCH_PATH,
        json=_search_body(lang="he"),
        headers={
            **_headers(),
            "Cookie": "session=secret",
            "Authorization": "Bearer user-key",
            "Origin": "http://localhost:5000",
            "X-Custom-Header": "should-not-forward",
        },
    )

    sent = wolt_discovery.calls.last.request.headers
    assert sent["platform"] == "Web"
    assert sent["client-version"] == "1.16.125"
    assert sent["clientversionnumber"] == "1.16.125"
    assert sent["app-language"] == "he"
    assert sent["w-wolt-session-id"] == "no-analytics-consent"
    assert sent["accept"] == "application/json"
    assert sent["user-agent"] == WOLT_USER_AGENT
    assert sent["x-wolt-web-clientid"] != _INSTALL_ID
    assert "cookie" not in sent
    assert "authorization" not in sent
    assert "origin" not in sent
    assert "x-ketoclub-install-id" not in sent
    assert "x-custom-header" not in sent


def test_restaurants_and_search_do_not_share_a_cache_key(
    client: TestClient, wolt_discovery: respx.MockRouter
) -> None:
    # A distinct upstream call for the same lat/lon/lang pair proves the two
    # routes' cache rows (`wolt-restaurants` vs `wolt-search`) never collide.
    restaurants_route = wolt_discovery.get(_UPSTREAM_RESTAURANTS).mock(
        return_value=httpx.Response(200, json={"kind": "restaurants"})
    )
    search_route = wolt_discovery.post(_UPSTREAM_SEARCH).mock(
        return_value=httpx.Response(200, json={"kind": "search"})
    )

    restaurants = client.get(
        _RESTAURANTS_PATH, params={"lat": _LAT, "lon": _LON}, headers=_headers()
    )
    search = client.post(
        _SEARCH_PATH, json=_search_body(q=f"{_LAT},{_LON},en"), headers=_headers()
    )

    assert restaurants.json() == {"kind": "restaurants"}
    assert search.json() == {"kind": "search"}
    assert restaurants_route.call_count == 1
    assert search_route.call_count == 1

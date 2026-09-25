"""Tests for ``GET /v1/proxy/wolt/venues/slug/{slug}/assortment`` (#95, #168)."""

from collections.abc import Iterator

import httpx
import pytest
import respx
from fastapi.testclient import TestClient

from app.config import Settings
from app.main import create_app
from app.services.wolt import (
    SOURCE,
    WOLT_USER_AGENT,
    read_cached_menu,
    write_cached_menu,
)

SLUG = "hamosad"
UPSTREAM_PATH = f"/consumer-api/consumer-assortment/v1/venues/slug/{SLUG}/assortment"
PROXY_PATH = f"/v1/proxy/wolt/venues/slug/{SLUG}/assortment"


@pytest.fixture
def wolt() -> Iterator[respx.MockRouter]:
    """A respx router nested inside the autouse one in ``conftest.py``.

    The autouse ``_block_network`` fixture activates its own ``MockRouter``,
    so routes registered on the module-level ``respx.get(...)`` (which
    targets the *default* router, not the active one) never match. Opening a
    second, nested router here — scoped to Wolt's consumer host, where the
    assortment endpoint lives — makes routes registered against it the
    active ones for the duration of the test, and an unmatched request still
    fails loudly (``assert_all_mocked`` stays at its default of ``True`` on
    this router).
    """
    with respx.mock(
        base_url="https://consumer-api.wolt.com", assert_all_called=False
    ) as router:
        yield router


def test_passthrough_200_preserves_body_and_content_type(
    client: TestClient, wolt: respx.MockRouter
) -> None:
    wolt.get(UPSTREAM_PATH).mock(
        return_value=httpx.Response(200, json={"items": ["salad"]})
    )

    response = client.get(PROXY_PATH)

    assert response.status_code == 200
    assert response.json() == {"items": ["salad"]}
    assert response.headers["content-type"] == "application/json"
    assert response.headers["X-KetoClub-Cache"] == "miss"


def test_passthrough_404(client: TestClient, wolt: respx.MockRouter) -> None:
    wolt.get(UPSTREAM_PATH).mock(
        return_value=httpx.Response(404, json={"error": "not found"})
    )

    response = client.get(PROXY_PATH)

    assert response.status_code == 404
    assert response.json() == {"error": "not found"}


def test_passthrough_500(client: TestClient, wolt: respx.MockRouter) -> None:
    wolt.get(UPSTREAM_PATH).mock(
        return_value=httpx.Response(500, json={"error": "boom"})
    )

    response = client.get(PROXY_PATH)

    assert response.status_code == 500
    assert response.json() == {"error": "boom"}


def test_retired_v4_route_is_gone(client: TestClient, wolt: respx.MockRouter) -> None:
    response = client.get(f"/v1/proxy/wolt/v4/venues/slug/{SLUG}/menu/data")

    assert response.status_code == 404
    assert len(wolt.calls) == 0


def test_uppercase_slug_is_rejected(client: TestClient, wolt: respx.MockRouter) -> None:
    response = client.get("/v1/proxy/wolt/venues/slug/UPPER/assortment")

    assert response.status_code == 422
    assert len(wolt.calls) == 0


def test_leading_dash_slug_is_rejected(
    client: TestClient, wolt: respx.MockRouter
) -> None:
    response = client.get("/v1/proxy/wolt/venues/slug/-abc/assortment")

    assert response.status_code == 422
    assert len(wolt.calls) == 0


def test_too_long_slug_is_rejected(client: TestClient, wolt: respx.MockRouter) -> None:
    too_long = "a" * 101

    response = client.get(f"/v1/proxy/wolt/venues/slug/{too_long}/assortment")

    assert response.status_code == 422
    assert len(wolt.calls) == 0


def test_connect_error_returns_502_offline(
    client: TestClient, wolt: respx.MockRouter
) -> None:
    wolt.get(UPSTREAM_PATH).mock(side_effect=httpx.ConnectError("connection refused"))

    response = client.get(PROXY_PATH)

    assert response.status_code == 502
    assert response.json() == {"reason": "offline", "status_code": 502}


def test_read_timeout_returns_504_timeout(
    client: TestClient, wolt: respx.MockRouter
) -> None:
    wolt.get(UPSTREAM_PATH).mock(side_effect=httpx.ReadTimeout("timed out"))

    response = client.get(PROXY_PATH)

    assert response.status_code == 504
    assert response.json() == {"reason": "timeout", "status_code": 504}


def test_second_call_is_served_from_cache(
    client: TestClient, wolt: respx.MockRouter
) -> None:
    route = wolt.get(UPSTREAM_PATH).mock(
        return_value=httpx.Response(200, json={"items": ["salad"]})
    )

    first = client.get(PROXY_PATH)
    second = client.get(PROXY_PATH)

    assert first.headers["X-KetoClub-Cache"] == "miss"
    assert second.headers["X-KetoClub-Cache"] == "hit"
    assert second.json() == {"items": ["salad"]}
    assert route.call_count == 1


def test_expired_cache_entry_is_refetched(wolt: respx.MockRouter) -> None:
    # Its own app, not the shared `client` fixture: a zero-second TTL means
    # every read is already stale, forcing the second call to refetch.
    settings = Settings(DATABASE_URL="sqlite:///:memory:", MENU_CACHE_TTL_SECONDS=0)
    app = create_app(settings=settings)

    route = wolt.get(UPSTREAM_PATH).mock(
        return_value=httpx.Response(200, json={"items": ["salad"]})
    )

    with TestClient(app) as client:
        first = client.get(PROXY_PATH)
        second = client.get(PROXY_PATH)

    assert first.headers["X-KetoClub-Cache"] == "miss"
    assert second.headers["X-KetoClub-Cache"] == "miss"
    assert route.call_count == 2


def test_failed_response_is_not_cached(
    client: TestClient, wolt: respx.MockRouter
) -> None:
    route = wolt.get(UPSTREAM_PATH).mock(
        side_effect=[
            httpx.Response(404, json={"error": "not found"}),
            httpx.Response(200, json={"items": ["salad"]}),
        ]
    )

    first = client.get(PROXY_PATH)
    second = client.get(PROXY_PATH)

    assert first.status_code == 404
    assert first.headers["X-KetoClub-Cache"] == "miss"
    assert second.status_code == 200
    assert second.headers["X-KetoClub-Cache"] == "miss"
    assert route.call_count == 2


def test_empty_200_is_passed_through_but_not_cached(
    client: TestClient, wolt: respx.MockRouter
) -> None:
    # The zero-byte 200 Wolt's retired /v4 menu endpoint answers with
    # (#168): the client must see it (and report platformChanged), but it
    # must never be served from cache once the upstream recovers.
    route = wolt.get(UPSTREAM_PATH).mock(
        side_effect=[
            httpx.Response(200, content=b""),
            httpx.Response(200, json={"items": ["salad"]}),
        ]
    )

    first = client.get(PROXY_PATH)
    second = client.get(PROXY_PATH)

    assert first.status_code == 200
    assert first.content == b""
    assert first.headers["X-KetoClub-Cache"] == "miss"
    assert second.json() == {"items": ["salad"]}
    assert second.headers["X-KetoClub-Cache"] == "miss"
    assert route.call_count == 2


def test_a_row_cached_under_the_retired_source_is_never_served(
    settings: Settings, wolt: respx.MockRouter
) -> None:
    # A row the pre-#168 route cached under source "wolt" — an empty /v4
    # body — must not answer the assortment route.
    app = create_app(settings=settings)
    route = wolt.get(UPSTREAM_PATH).mock(
        return_value=httpx.Response(200, json={"items": ["salad"]})
    )

    with TestClient(app) as client:
        engine = app.state.engine
        write_cached_menu(engine, "wolt", SLUG, 200, "application/json", "")
        response = client.get(PROXY_PATH)
        cached = read_cached_menu(engine, SOURCE, SLUG, 3600)

    assert SOURCE != "wolt"
    assert response.headers["X-KetoClub-Cache"] == "miss"
    assert response.json() == {"items": ["salad"]}
    assert route.call_count == 1
    assert cached is not None


def test_inbound_credentials_and_origin_are_not_forwarded(
    client: TestClient, wolt: respx.MockRouter
) -> None:
    wolt.get(UPSTREAM_PATH).mock(return_value=httpx.Response(200, json={}))

    client.get(
        PROXY_PATH,
        headers={
            "Cookie": "session=secret",
            "Authorization": "Bearer user-key",
            "Origin": "http://localhost:5000",
            "X-KetoClub-Install-Id": "a" * 32,
        },
    )

    sent_headers = wolt.calls.last.request.headers
    assert "cookie" not in sent_headers
    assert "authorization" not in sent_headers
    assert "origin" not in sent_headers
    assert "x-ketoclub-install-id" not in sent_headers


def test_upstream_request_carries_the_web_client_header_set(
    client: TestClient, wolt: respx.MockRouter
) -> None:
    wolt.get(UPSTREAM_PATH).mock(return_value=httpx.Response(200, json={}))

    client.get(PROXY_PATH, headers={"X-KetoClub-Install-Id": "a" * 32})

    sent = wolt.calls.last.request.headers
    assert sent["user-agent"] == WOLT_USER_AGENT
    assert sent["accept"] == "application/json"
    assert sent["platform"] == "Web"
    assert sent["app-language"] == "en"
    assert sent["client-version"] == "1.16.125"
    assert sent["clientversionnumber"] == "1.16.125"
    assert sent["w-wolt-session-id"] == "no-analytics-consent"
    # A per-process uuid4, never the KetoClub install id.
    assert sent["x-wolt-web-clientid"] != "a" * 32
    assert len(sent["x-wolt-web-clientid"]) == 36

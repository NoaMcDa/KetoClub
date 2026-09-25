"""Tests for ``GET /v1/proxy/tenbis/api/v1.0/Restaurants/{id}/Menu`` (#122)."""

from collections.abc import Iterator

import httpx
import pytest
import respx
from fastapi.testclient import TestClient

from app.config import Settings
from app.main import create_app
from app.services.wolt import WOLT_USER_AGENT

RESTAURANT_ID = "123456"
UPSTREAM_PATH = f"/api/v1.0/Restaurants/{RESTAURANT_ID}/Menu"
PROXY_PATH = f"/v1/proxy/tenbis/api/v1.0/Restaurants/{RESTAURANT_ID}/Menu"

# A digits-only string is a valid Wolt slug (`^[a-z0-9][a-z0-9-]{0,99}$`)
# *and* a valid 10bis restaurant id (`^[0-9]{1,12}$`), so it can be used as
# the same cache key on both platforms to prove they do not collide.
SHARED_ID = "555555"
WOLT_UPSTREAM_PATH = (
    f"/consumer-api/consumer-assortment/v1/venues/slug/{SHARED_ID}/assortment"
)
WOLT_PROXY_PATH = f"/v1/proxy/wolt/venues/slug/{SHARED_ID}/assortment"


@pytest.fixture
def tenbis() -> Iterator[respx.MockRouter]:
    """A respx router nested inside the autouse one in ``conftest.py``.

    See ``tests/test_proxy.py``'s ``wolt`` fixture for why this has to be a
    nested router rather than the module-level ``respx.get(...)``: the
    autouse ``_block_network`` fixture activates its own ``MockRouter``, so
    routes registered against the default router never match.
    """
    with respx.mock(
        base_url="https://www.10bis.co.il", assert_all_called=False
    ) as router:
        yield router


def test_passthrough_200_preserves_body_and_content_type(
    client: TestClient, tenbis: respx.MockRouter
) -> None:
    tenbis.get(UPSTREAM_PATH).mock(
        return_value=httpx.Response(200, json={"categories": ["mains"]})
    )

    response = client.get(PROXY_PATH)

    assert response.status_code == 200
    assert response.json() == {"categories": ["mains"]}
    assert response.headers["content-type"] == "application/json"
    assert response.headers["X-KetoClub-Cache"] == "miss"


def test_passthrough_404(client: TestClient, tenbis: respx.MockRouter) -> None:
    tenbis.get(UPSTREAM_PATH).mock(
        return_value=httpx.Response(404, json={"error": "not found"})
    )

    response = client.get(PROXY_PATH)

    assert response.status_code == 404
    assert response.json() == {"error": "not found"}


def test_passthrough_500(client: TestClient, tenbis: respx.MockRouter) -> None:
    tenbis.get(UPSTREAM_PATH).mock(
        return_value=httpx.Response(500, json={"error": "boom"})
    )

    response = client.get(PROXY_PATH)

    assert response.status_code == 500
    assert response.json() == {"error": "boom"}


def test_letters_are_rejected(client: TestClient, tenbis: respx.MockRouter) -> None:
    response = client.get("/v1/proxy/tenbis/api/v1.0/Restaurants/abc123/Menu")

    assert response.status_code == 422
    assert len(tenbis.calls) == 0


def test_thirteen_digits_are_rejected(
    client: TestClient, tenbis: respx.MockRouter
) -> None:
    too_long = "1" * 13

    response = client.get(f"/v1/proxy/tenbis/api/v1.0/Restaurants/{too_long}/Menu")

    assert response.status_code == 422
    assert len(tenbis.calls) == 0


def test_empty_id_never_reaches_the_route(
    client: TestClient, tenbis: respx.MockRouter
) -> None:
    # An empty path segment does not match {restaurant_id} at all (Starlette
    # routing, independent of the `Path(pattern=...)` validation), so this
    # is FastAPI's own 404, not our 422 — but it proves the same thing the
    # acceptance criteria asks for either way: no upstream call.
    response = client.get("/v1/proxy/tenbis/api/v1.0/Restaurants//Menu")

    assert response.status_code == 404
    assert len(tenbis.calls) == 0


def test_connect_error_returns_502_offline(
    client: TestClient, tenbis: respx.MockRouter
) -> None:
    tenbis.get(UPSTREAM_PATH).mock(side_effect=httpx.ConnectError("connection refused"))

    response = client.get(PROXY_PATH)

    assert response.status_code == 502
    assert response.json() == {"reason": "offline", "status_code": 502}


def test_read_timeout_returns_504_timeout(
    client: TestClient, tenbis: respx.MockRouter
) -> None:
    tenbis.get(UPSTREAM_PATH).mock(side_effect=httpx.ReadTimeout("timed out"))

    response = client.get(PROXY_PATH)

    assert response.status_code == 504
    assert response.json() == {"reason": "timeout", "status_code": 504}


def test_second_call_is_served_from_cache(
    client: TestClient, tenbis: respx.MockRouter
) -> None:
    route = tenbis.get(UPSTREAM_PATH).mock(
        return_value=httpx.Response(200, json={"categories": ["mains"]})
    )

    first = client.get(PROXY_PATH)
    second = client.get(PROXY_PATH)

    assert first.headers["X-KetoClub-Cache"] == "miss"
    assert second.headers["X-KetoClub-Cache"] == "hit"
    assert second.json() == {"categories": ["mains"]}
    assert route.call_count == 1


def test_expired_cache_entry_is_refetched(tenbis: respx.MockRouter) -> None:
    # Its own app, not the shared `client` fixture: a zero-second TTL means
    # every read is already stale, forcing the second call to refetch.
    settings = Settings(DATABASE_URL="sqlite:///:memory:", MENU_CACHE_TTL_SECONDS=0)
    app = create_app(settings=settings)

    route = tenbis.get(UPSTREAM_PATH).mock(
        return_value=httpx.Response(200, json={"categories": ["mains"]})
    )

    with TestClient(app) as client:
        first = client.get(PROXY_PATH)
        second = client.get(PROXY_PATH)

    assert first.headers["X-KetoClub-Cache"] == "miss"
    assert second.headers["X-KetoClub-Cache"] == "miss"
    assert route.call_count == 2


def test_failed_response_is_not_cached(
    client: TestClient, tenbis: respx.MockRouter
) -> None:
    route = tenbis.get(UPSTREAM_PATH).mock(
        side_effect=[
            httpx.Response(404, json={"error": "not found"}),
            httpx.Response(200, json={"categories": ["mains"]}),
        ]
    )

    first = client.get(PROXY_PATH)
    second = client.get(PROXY_PATH)

    assert first.status_code == 404
    assert first.headers["X-KetoClub-Cache"] == "miss"
    assert second.status_code == 200
    assert second.headers["X-KetoClub-Cache"] == "miss"
    assert route.call_count == 2


def test_inbound_credentials_and_origin_are_not_forwarded(
    client: TestClient, tenbis: respx.MockRouter
) -> None:
    tenbis.get(UPSTREAM_PATH).mock(return_value=httpx.Response(200, json={}))

    client.get(
        PROXY_PATH,
        headers={
            "Cookie": "session=secret",
            "Authorization": "Bearer user-key",
            "Origin": "http://localhost:5000",
            "X-KetoClub-Install-Id": "a" * 32,
        },
    )

    sent_headers = tenbis.calls.last.request.headers
    assert "cookie" not in sent_headers
    assert "authorization" not in sent_headers
    assert "origin" not in sent_headers
    assert "x-ketoclub-install-id" not in sent_headers


def test_upstream_request_carries_user_agent_and_accept(
    client: TestClient, tenbis: respx.MockRouter
) -> None:
    tenbis.get(UPSTREAM_PATH).mock(return_value=httpx.Response(200, json={}))

    client.get(PROXY_PATH)

    sent_headers = tenbis.calls.last.request.headers
    assert sent_headers["user-agent"] == WOLT_USER_AGENT
    assert sent_headers["accept"] == "application/json"


def test_wolt_and_tenbis_entries_with_the_same_id_do_not_collide(
    client: TestClient, tenbis: respx.MockRouter
) -> None:
    """The same id string, cached under both platforms, does not collide.

    ``SHARED_ID`` is a valid Wolt slug and a valid 10bis restaurant id at
    once; caching it under both proves the primary key is
    ``(source, id)``, not ``id`` alone.
    """
    with respx.mock(
        base_url="https://consumer-api.wolt.com", assert_all_called=False
    ) as wolt:
        wolt_route = wolt.get(WOLT_UPSTREAM_PATH).mock(
            return_value=httpx.Response(200, json={"platform": "wolt"})
        )
        tenbis_route = tenbis.get(f"/api/v1.0/Restaurants/{SHARED_ID}/Menu").mock(
            return_value=httpx.Response(200, json={"platform": "tenbis"})
        )

        wolt_first = client.get(WOLT_PROXY_PATH)
        tenbis_first = client.get(
            f"/v1/proxy/tenbis/api/v1.0/Restaurants/{SHARED_ID}/Menu"
        )
        wolt_second = client.get(WOLT_PROXY_PATH)
        tenbis_second = client.get(
            f"/v1/proxy/tenbis/api/v1.0/Restaurants/{SHARED_ID}/Menu"
        )

    assert wolt_first.json() == {"platform": "wolt"}
    assert tenbis_first.json() == {"platform": "tenbis"}
    assert wolt_second.headers["X-KetoClub-Cache"] == "hit"
    assert tenbis_second.headers["X-KetoClub-Cache"] == "hit"
    assert wolt_second.json() == {"platform": "wolt"}
    assert tenbis_second.json() == {"platform": "tenbis"}
    assert wolt_route.call_count == 1
    assert tenbis_route.call_count == 1

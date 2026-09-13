"""The Wolt menu proxy.

The contract these tests pin is "transparent passthrough": Wolt's status, body
and content type reach the caller unchanged, so the Flutter adapter needs no
knowledge that a proxy is in the path. The only statuses this service invents
are 502 and 504.
"""

import httpx
import pytest
import respx
from fastapi.testclient import TestClient

from app.services.wolt import WOLT_USER_AGENT
from tests.conftest import WOLT_BASE_URL

MENU_URL = f"{WOLT_BASE_URL}/v4/venues/slug/vitrina-lilinblum/menu/data"
PROXY_PATH = "/v1/proxy/wolt/v4/venues/slug/vitrina-lilinblum/menu/data"
MENU_BODY = b'{"categories": [], "items": []}'


@respx.mock
def test_a_successful_menu_is_passed_through_unchanged(client: TestClient) -> None:
    route = respx.get(MENU_URL).mock(
        return_value=httpx.Response(
            200, content=MENU_BODY, headers={"content-type": "application/json"}
        )
    )

    response = client.get(PROXY_PATH)

    assert route.called
    assert response.status_code == 200
    assert response.content == MENU_BODY
    assert response.headers["content-type"] == "application/json"
    assert response.headers["X-KetoClub-Cache"] == "miss"


@respx.mock
def test_the_upstream_request_carries_a_browser_user_agent(
    client: TestClient,
) -> None:
    route = respx.get(MENU_URL).mock(return_value=httpx.Response(200, content=b"{}"))

    client.get(PROXY_PATH)

    sent = route.calls.last.request
    assert sent.headers["user-agent"] == WOLT_USER_AGENT
    assert sent.headers["accept"] == "application/json"


@respx.mock
def test_nothing_from_the_caller_is_forwarded_upstream(client: TestClient) -> None:
    route = respx.get(MENU_URL).mock(return_value=httpx.Response(200, content=b"{}"))

    client.get(
        PROXY_PATH,
        headers={
            "Origin": "http://localhost:1234",
            "Cookie": "session=secret",
            "Authorization": "Bearer caller-token",
        },
    )

    sent = route.calls.last.request
    assert "origin" not in sent.headers
    assert "cookie" not in sent.headers
    assert "authorization" not in sent.headers


@respx.mock
def test_a_second_request_is_served_from_the_cache(client: TestClient) -> None:
    route = respx.get(MENU_URL).mock(
        return_value=httpx.Response(
            200, content=MENU_BODY, headers={"content-type": "application/json"}
        )
    )

    first = client.get(PROXY_PATH)
    second = client.get(PROXY_PATH)

    assert route.call_count == 1
    assert first.headers["X-KetoClub-Cache"] == "miss"
    assert second.headers["X-KetoClub-Cache"] == "hit"
    assert second.content == MENU_BODY


@respx.mock
def test_a_missing_venue_passes_its_404_through(client: TestClient) -> None:
    respx.get(MENU_URL).mock(return_value=httpx.Response(404, content=b"not found"))

    response = client.get(PROXY_PATH)

    assert response.status_code == 404


@respx.mock
def test_an_upstream_server_error_passes_its_status_through(
    client: TestClient,
) -> None:
    respx.get(MENU_URL).mock(return_value=httpx.Response(503, content=b"oops"))

    response = client.get(PROXY_PATH)

    assert response.status_code == 503


@respx.mock
def test_a_failure_status_is_not_cached(client: TestClient) -> None:
    route = respx.get(MENU_URL).mock(return_value=httpx.Response(500, content=b"x"))

    client.get(PROXY_PATH)
    client.get(PROXY_PATH)

    assert route.call_count == 2


@respx.mock
def test_an_unreachable_upstream_answers_502_offline(client: TestClient) -> None:
    respx.get(MENU_URL).mock(side_effect=httpx.ConnectError("no route"))

    response = client.get(PROXY_PATH)

    assert response.status_code == 502
    assert response.json() == {"reason": "offline", "status_code": 502}


@respx.mock
def test_a_slow_upstream_answers_504_timeout(client: TestClient) -> None:
    respx.get(MENU_URL).mock(side_effect=httpx.ReadTimeout("too slow"))

    response = client.get(PROXY_PATH)

    assert response.status_code == 504
    assert response.json() == {"reason": "timeout", "status_code": 504}


@pytest.mark.parametrize(
    "slug",
    ["Vitrina", "with_underscore", "-leading-hyphen", "a" * 101, "..", "a%2Fb"],
)
@respx.mock
def test_a_slug_outside_the_allow_list_is_rejected_without_calling_upstream(
    client: TestClient, slug: str
) -> None:
    route = respx.get(url__startswith=WOLT_BASE_URL).mock(
        return_value=httpx.Response(200)
    )

    response = client.get(f"/v1/proxy/wolt/v4/venues/slug/{slug}/menu/data")

    assert response.status_code in {404, 422}
    assert not route.called

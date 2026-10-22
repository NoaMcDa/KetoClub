"""#271: a request whose ``Host`` header names a host this server is not is
refused before any route, CORS or log sees it.

The issue's attack: a page on ``evil.example`` rebinds its own name to
127.0.0.1, so the browser treats the backend as same-origin and CORS never
applies; the request still says ``Host: evil.example``. These tests use the
real default of ``ALLOWED_HOSTS`` unless they set it (conftest admits
``testserver`` for every other test).
"""

from collections.abc import Iterator

import httpx
import pytest
import respx
from fastapi.testclient import TestClient

from app.config import Settings
from app.main import create_app
from app.services.trusted_host import host_of

_DEFAULT_HOSTS = "localhost,127.0.0.1,[::1]"
_INSTALL_ID = "0123456789abcdef0123456789abcdef"
_REFUSED = {"reason": "invalidHost", "status_code": 400}


def _client(allowed_hosts: str = _DEFAULT_HOSTS, **overrides: object) -> TestClient:
    settings = Settings(
        DATABASE_URL="sqlite:///:memory:",
        ALLOWED_HOSTS=allowed_hosts,
        **overrides,  # type: ignore[arg-type]
    )
    return TestClient(create_app(settings=settings), base_url="http://localhost:8000")


@pytest.fixture
def client() -> Iterator[TestClient]:
    with _client() as test_client:
        yield test_client


def _health(client: TestClient, host: str | None) -> httpx.Response:
    headers = {} if host is None else {"host": host}
    return client.get("/v1/health", headers=headers)


def test_the_default_admits_localhost_only() -> None:
    assert Settings.model_fields["ALLOWED_HOSTS"].default == _DEFAULT_HOSTS
    assert Settings(ALLOWED_HOSTS=_DEFAULT_HOSTS).allowed_hosts == [
        "localhost",
        "127.0.0.1",
        "[::1]",
    ]


@pytest.mark.parametrize(
    "host",
    ["localhost", "localhost:8000", "LocalHost:8000", "127.0.0.1:8000", "[::1]:8000"],
)
def test_localhost_in_any_spelling_is_served(client: TestClient, host: str) -> None:
    assert _health(client, host).status_code == 200


@pytest.mark.parametrize(
    "host",
    [
        "evil.example",
        "evil.example:8000",
        "localhost.evil.example",
        "127.0.0.1.nip.io:8000",
        "[::2]:8000",
        "10.0.2.2:8000",
        "",
    ],
)
def test_any_other_host_is_refused(client: TestClient, host: str) -> None:
    response = _health(client, host)

    assert response.status_code == 400
    assert response.json() == _REFUSED


def test_a_rebinding_page_cannot_spend_the_servers_gemini_key() -> None:
    with respx.mock(assert_all_called=False) as router:
        gemini = router.route(host="generativelanguage.googleapis.com").mock(
            return_value=httpx.Response(500)
        )
        with _client(GEMINI_API_KEY="server-key") as client:
            response = client.post(
                "/v1/chat",
                json={"system_prompt": "s", "user_prompt": "u"},
                headers={
                    "host": "evil.example:8000",
                    "origin": "http://evil.example:8000",
                    "X-KetoClub-Install-Id": _INSTALL_ID,
                },
            )

    assert response.status_code == 400
    assert response.json() == _REFUSED
    assert not gemini.called


def test_a_lan_address_is_served_once_listed() -> None:
    # #99: phones on the same Wi-Fi reach the machine by its LAN address.
    with _client(_DEFAULT_HOSTS + ",192.168.1.20") as client:
        assert _health(client, "192.168.1.20:8000").status_code == 200
        assert _health(client, "192.168.1.21:8000").status_code == 400


def test_a_hosted_name_and_its_subdomains_by_pattern() -> None:
    # #171: a hosted deploy lists its public name.
    with _client("api.ketoclub.example, *.preview.ketoclub.example") as client:
        assert _health(client, "api.ketoclub.example").status_code == 200
        assert _health(client, "pr-12.preview.ketoclub.example").status_code == 200
        assert _health(client, "preview.ketoclub.example").status_code == 400
        assert _health(client, "localhost:8000").status_code == 400


def test_a_star_turns_the_check_off() -> None:
    with _client("*") as client:
        assert _health(client, "anything.example").status_code == 200


@pytest.mark.parametrize(
    ("header", "host"),
    [
        ("localhost:8000", "localhost"),
        ("EXAMPLE.com", "example.com"),
        ("[::1]:8000", "[::1]"),
        ("[::1]", "[::1]"),
        ("[::1", "[::1"),
        (" 127.0.0.1 ", "127.0.0.1"),
    ],
)
def test_host_of_cuts_the_port_off_even_for_ipv6(header: str, host: str) -> None:
    assert host_of(header) == host

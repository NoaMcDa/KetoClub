"""#267: the website fetch connects only to the public addresses it checked.

These tests run the website client's real transport and connection pool
down to the network layer, where a fake network (:class:`FakeNetwork`)
stands in for sockets: respx passes the website hosts through to it instead
of answering them, and refuses every other host as usual. Nothing leaves the
process.

The reproduction from the issue: a resolver that answers a public address
to the check and ``127.0.0.1`` to the connection used to get the internal
page back with a 200; it is now 400 ``invalidUrl``, and nothing ever dials
the private address.
"""

from collections.abc import Iterator

import anyio
import httpcore
import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.config import Settings
from app.main import create_app
from app.services.website import is_public_address
from app.services.website_transport import (
    BlockedAddressError,
    PublicOnlyNetworkBackend,
    website_client,
)
from tests.website_network import (
    PUBLIC,
    FakeNetwork,
    ScriptedResolver,
    html_response,
    passing_through,
)

_INSTALL_ID = "0123456789abcdef0123456789abcdef"
_PATH = "/v1/website/fetch"
_PUBLIC = PUBLIC
_OTHER_PUBLIC = "93.184.216.35"
_MENU_PAGE = (
    "<html><body><h1>Menu</h1>"
    + "".join(f"<p>Dish {i} with a long description 52</p>" for i in range(20))
    + "</body></html>"
)
_ADMIN_PAGE = (
    "<html><body><h1>INTERNAL ADMIN PANEL</h1>"
    + "<p>Every secret this network holds, in plain text.</p>" * 5
    + "</body></html>"
)


@pytest.fixture(autouse=True)
def _block_network() -> Iterator[None]:
    """Overrides conftest's: the website hosts pass through respx to the
    fake network; every other host is still refused."""
    with passing_through("cafe.example", "localhost", "internal.example"):
        yield


def _app(resolver: ScriptedResolver, network: FakeNetwork) -> FastAPI:
    app = create_app(settings=Settings(DATABASE_URL="sqlite:///:memory:"))
    app.state.resolve_host = resolver
    app.state.website_network_backend = network
    return app


def _post(client: TestClient, url: str) -> tuple[int, dict[str, object]]:
    response = client.post(
        _PATH, json={"url": url}, headers={"X-KetoClub-Install-Id": _INSTALL_ID}
    )
    return response.status_code, response.json()


def test_a_resolver_that_rebinds_after_the_check_is_refused() -> None:
    # The issue's reproduction: the check sees a public address, the
    # connection would have gone to 127.0.0.1 and read the admin panel.
    resolver = ScriptedResolver({"localhost": [[_PUBLIC], ["127.0.0.1"]]})
    network = FakeNetwork(
        {
            "127.0.0.1": html_response("200 OK", _ADMIN_PAGE),
            _PUBLIC: html_response("200 OK"),
        }
    )

    with TestClient(_app(resolver, network)) as client:
        status, body = _post(client, "http://localhost/")

    assert (status, body) == (400, {"reason": "invalidUrl", "status_code": 400})
    assert "127.0.0.1" not in network.dialled
    assert resolver.lookups == ["localhost", "localhost"]


def test_the_connection_dials_the_checked_address_not_the_name() -> None:
    resolver = ScriptedResolver({"cafe.example": [[_PUBLIC]]})
    network = FakeNetwork({_PUBLIC: html_response("200 OK", _MENU_PAGE)})

    with TestClient(_app(resolver, network)) as client:
        status, body = _post(client, "http://cafe.example/")

    assert status == 200
    assert "Dish 3" in str(body["body"])
    # robots.txt and the page, each over its own connection, each to the IP.
    assert network.dialled == [_PUBLIC, _PUBLIC]


def test_a_connection_whose_answer_mixes_in_a_private_address_is_refused() -> None:
    resolver = ScriptedResolver(
        {"cafe.example": [[_PUBLIC], [_OTHER_PUBLIC, "10.0.0.1"]]}
    )
    network = FakeNetwork({_PUBLIC: html_response("200 OK", _MENU_PAGE)})

    with TestClient(_app(resolver, network)) as client:
        status, _ = _post(client, "http://cafe.example/")

    assert status == 400
    assert network.dialled == []


def test_a_redirect_hop_that_rebinds_is_refused_too() -> None:
    resolver = ScriptedResolver(
        {
            "cafe.example": [[_PUBLIC]],
            "internal.example": [[_OTHER_PUBLIC], ["169.254.169.254"]],
        }
    )
    network = FakeNetwork(
        {
            _PUBLIC: html_response("302 Found", Location="http://internal.example/"),
            "169.254.169.254": html_response("200 OK", _ADMIN_PAGE),
        }
    )

    with TestClient(_app(resolver, network)) as client:
        status, body = _post(client, "http://cafe.example/")

    assert (status, body) == (400, {"reason": "invalidUrl", "status_code": 400})
    assert "169.254.169.254" not in network.dialled


def test_an_environment_proxy_is_never_used(monkeypatch: pytest.MonkeyPatch) -> None:
    # httpx would otherwise route through the proxy, which resolves the name
    # itself, outside the guard. Port 9 on loopback: a regression fails
    # fast, with no request leaving the machine.
    for name in ("HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY"):
        monkeypatch.setenv(name, "http://127.0.0.1:9")
    resolver = ScriptedResolver({"cafe.example": [[_PUBLIC]]})
    network = FakeNetwork({_PUBLIC: html_response("200 OK", _MENU_PAGE)})

    with TestClient(_app(resolver, network)) as client:
        status, _ = _post(client, "http://cafe.example/")
        assert client.app.state.website_http_client.trust_env is False  # type: ignore[attr-defined]

    assert status == 200
    assert network.dialled == [_PUBLIC, _PUBLIC]


def test_an_unresolvable_host_at_connect_time_is_offline() -> None:
    async def resolve(host: str) -> list[str]:
        raise OSError("no such host")

    backend = PublicOnlyNetworkBackend(resolve, FakeNetwork({}))

    async def connect() -> None:
        await backend.connect_tcp("cafe.example", 80)

    with pytest.raises(httpcore.ConnectError):
        anyio.run(connect)


def test_the_backend_tries_each_checked_address_in_turn() -> None:
    async def resolve(host: str) -> list[str]:
        return [_OTHER_PUBLIC, _PUBLIC, _OTHER_PUBLIC]

    network = FakeNetwork({_PUBLIC: html_response("200 OK")})
    backend = PublicOnlyNetworkBackend(resolve, network)

    async def connect() -> None:
        await backend.connect_tcp("cafe.example", 80)

    anyio.run(connect)
    assert network.dialled == [_OTHER_PUBLIC, _PUBLIC]

    network.responses.clear()
    network.dialled.clear()
    with pytest.raises(httpcore.ConnectError):
        anyio.run(connect)
    assert network.dialled == [_OTHER_PUBLIC, _PUBLIC]


@pytest.mark.parametrize("answer", [[], ["127.0.0.1"], ["64:ff9b::a00:1"]])
def test_the_backend_refuses_no_answer_or_a_private_one(answer: list[str]) -> None:
    async def resolve(host: str) -> list[str]:
        return answer

    network = FakeNetwork({})
    backend = PublicOnlyNetworkBackend(resolve, network)

    async def connect() -> None:
        await backend.connect_tcp("cafe.example", 80)

    with pytest.raises(BlockedAddressError):
        anyio.run(connect)
    assert network.dialled == []


def test_the_backend_never_opens_a_unix_socket_and_sleeps_on_the_inner_one() -> None:
    async def resolve(host: str) -> list[str]:
        return [_PUBLIC]

    backend = PublicOnlyNetworkBackend(resolve, FakeNetwork({}))

    async def unix() -> None:
        await backend.connect_unix_socket("/tmp/socket")

    with pytest.raises(BlockedAddressError):
        anyio.run(unix)
    anyio.run(backend.sleep, 0)


def test_the_website_client_ignores_the_environment() -> None:
    async def resolve(host: str) -> list[str]:
        return [_PUBLIC]

    client = website_client(resolve)
    assert client.trust_env is False
    assert client.follow_redirects is False


@pytest.mark.parametrize(
    "address",
    [
        "64:ff9b::a00:1",  # NAT64 for 10.0.0.1
        "64:ff9b::5db8:d822",  # NAT64 even for a public IPv4 address
        "64:ff9b:1::a00:1",  # local-use NAT64
        "::127.0.0.1",  # IPv4-compatible loopback
        "::8.8.8.8",  # IPv4-compatible, refused whatever it embeds
        "::ffff:127.0.0.1",  # IPv4-mapped loopback
        "::ffff:10.0.0.1",  # IPv4-mapped private
    ],
)
def test_ipv6_forms_of_ipv4_addresses_are_refused(address: str) -> None:
    assert is_public_address(address) is False


def test_an_ipv4_mapped_public_address_is_public() -> None:
    assert is_public_address("::ffff:93.184.216.34") is True

"""A fake network for the website fetch tests (#267, #269).

respx answers a request above the connection pool, so a test that must run
the website client's real pool, transport and stream (the public-only
connection, the raw body read) passes the request through respx to the
pool and lets :class:`FakeNetwork` stand in for the sockets underneath it.
Nothing leaves the process.
"""

from collections.abc import Iterable, Iterator
from contextlib import contextmanager

import httpcore
import respx

PUBLIC = "93.184.216.34"


def http_response(status: str, body: bytes = b"", **headers: str) -> list[bytes]:
    """An HTTP/1.1 response as the chunks a socket would hand over: the head,
    then the body in 64 KiB reads. ``Connection: close``, so no connection is
    reused (a fake stream serves one response)."""
    head = [
        f"HTTP/1.1 {status}",
        f"Content-Length: {len(body)}",
        "Connection: close",
        *(f"{name.replace('_', '-')}: {value}" for name, value in headers.items()),
    ]
    chunks = [("\r\n".join(head) + "\r\n\r\n").encode()]
    chunks.extend(body[at : at + 65536] for at in range(0, len(body), 65536))
    return chunks


def html_response(status: str, page: str = "", **headers: str) -> list[bytes]:
    """:func:`http_response` for an HTML page."""
    return http_response(
        status, page.encode(), content_type="text/html; charset=utf-8", **headers
    )


class FakeNetwork(httpcore.AsyncNetworkBackend):
    """Sockets, faked: one canned response per address, served afresh on
    every connection, and a log of every address dialled. An unknown
    address is unreachable."""

    def __init__(self, responses: dict[str, list[bytes]]) -> None:
        self.responses = responses
        self.dialled: list[str] = []

    async def connect_tcp(
        self,
        host: str,
        port: int,
        timeout: float | None = None,
        local_address: str | None = None,
        socket_options: Iterable[httpcore.SOCKET_OPTION] | None = None,
    ) -> httpcore.AsyncNetworkStream:
        self.dialled.append(host)
        if host not in self.responses:
            raise httpcore.ConnectError(f"{host} is unreachable")
        return httpcore.AsyncMockStream(list(self.responses[host]))

    async def connect_unix_socket(
        self,
        path: str,
        timeout: float | None = None,
        socket_options: Iterable[httpcore.SOCKET_OPTION] | None = None,
    ) -> httpcore.AsyncNetworkStream:
        raise AssertionError("no unix socket is ever opened")

    async def sleep(self, seconds: float) -> None:
        return None


class ScriptedResolver:
    """DNS, scripted: each host answers its listed results in turn, then
    repeats the last; an unlisted host answers :data:`PUBLIC`. Every lookup
    is logged."""

    def __init__(self, answers: dict[str, list[list[str]]] | None = None) -> None:
        self.answers = answers or {}
        self.lookups: list[str] = []

    async def __call__(self, host: str) -> list[str]:
        self.lookups.append(host)
        script = self.answers.get(host, [[PUBLIC]])
        return script.pop(0) if len(script) > 1 else script[0]


@contextmanager
def passing_through(*hosts: str) -> Iterator[None]:
    """respx with ``hosts`` passed through to the pool (and so to the fake
    network) and every other host refused, as conftest refuses them."""
    with respx.mock(assert_all_called=False) as router:
        for host in hosts:
            router.route(host=host).pass_through()
        yield

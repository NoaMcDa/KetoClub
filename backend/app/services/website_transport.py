"""The website fetcher's own HTTP client: it connects only to public addresses
(#267).

``POST /v1/website/fetch`` and ``POST /v1/website-menu`` fetch URLs a caller
chose, so checking a host's addresses before the request is not enough: the
HTTP client used to resolve the name **again** when it connected, and a DNS
server answering a public address to the check and a private one to the
connection (DNS rebinding) got this server to fetch from its own network.

Here the connection itself is guarded. :class:`PublicOnlyNetworkBackend` is
the network layer under the client's connection pool: every TCP connection,
for the page, for ``robots.txt`` and for every redirect hop, resolves the
host once, refuses the whole connection unless every address is public
(``app.services.website.is_public_address``), and then connects to those
very addresses, never to a name. TLS still verifies the certificate against
the host name, which httpcore sends as the SNI whatever address it dialled.

The client is built with ``trust_env=False``: an ``HTTP(S)_PROXY`` from the
environment would make the proxy resolve the name, outside this guard.
"""

from collections.abc import Awaitable, Callable, Iterable
from typing import Final

import httpcore
import httpx

from app.services.website import is_public_address

HostResolver = Callable[[str], Awaitable[list[str]]]

# The httpx default, spelled out because the pool is built by hand below.
_LIMITS: Final = httpx.Limits(max_connections=100, max_keepalive_connections=20)


class BlockedAddressError(Exception):
    """A connection's host resolved to an address that is not public, or to
    none. Deliberately not an httpx/httpcore error, so httpx passes it
    through untranslated and the fetcher answers ``invalidUrl``, not
    ``offline``."""


class PublicOnlyNetworkBackend(httpcore.AsyncNetworkBackend):
    """Resolves each host itself and connects only to public addresses.

    ``resolve`` is called once per connection, and the addresses it returns
    are the ones checked and the ones dialled; ``inner`` does the dialling
    (the real network by default; a fake in tests).
    """

    def __init__(
        self,
        resolve: HostResolver,
        inner: httpcore.AsyncNetworkBackend | None = None,
    ) -> None:
        self._resolve = resolve
        self._inner = inner or httpcore.AnyIOBackend()

    async def connect_tcp(
        self,
        host: str,
        port: int,
        timeout: float | None = None,
        local_address: str | None = None,
        socket_options: Iterable[httpcore.SOCKET_OPTION] | None = None,
    ) -> httpcore.AsyncNetworkStream:
        try:
            addresses = await self._resolve(host)
        except OSError as error:
            raise httpcore.ConnectError(f"cannot resolve host: {error}") from None
        if not addresses or not all(map(is_public_address, addresses)):
            raise BlockedAddressError("host does not resolve to public addresses")
        failure: Exception | None = None
        for address in dict.fromkeys(addresses):
            try:
                return await self._inner.connect_tcp(
                    address,
                    port,
                    timeout=timeout,
                    local_address=local_address,
                    socket_options=socket_options,
                )
            except (httpcore.ConnectError, httpcore.ConnectTimeout) as error:
                failure = error
        assert failure is not None
        raise failure

    async def connect_unix_socket(
        self,
        path: str,
        timeout: float | None = None,
        socket_options: Iterable[httpcore.SOCKET_OPTION] | None = None,
    ) -> httpcore.AsyncNetworkStream:
        """Never used: the website client has no socket path."""
        raise BlockedAddressError("unix sockets are never fetched")

    async def sleep(self, seconds: float) -> None:
        await self._inner.sleep(seconds)


class _PublicOnlyTransport(httpx.AsyncHTTPTransport):
    """httpx's own transport over a pool whose network layer is
    :class:`PublicOnlyNetworkBackend`. httpx takes no network backend, so
    the pool it built is replaced with an equivalent one that has it."""

    def __init__(self, backend: httpcore.AsyncNetworkBackend) -> None:
        super().__init__(trust_env=False, limits=_LIMITS)
        self._pool = httpcore.AsyncConnectionPool(
            ssl_context=httpx.create_ssl_context(trust_env=False),
            max_connections=_LIMITS.max_connections,
            max_keepalive_connections=_LIMITS.max_keepalive_connections,
            keepalive_expiry=_LIMITS.keepalive_expiry,
            network_backend=backend,
        )


def website_client(
    resolve: HostResolver,
    inner: httpcore.AsyncNetworkBackend | None = None,
) -> httpx.AsyncClient:
    """The client every website fetch uses: public addresses only, no
    environment proxy, no redirects followed by httpx itself."""
    return httpx.AsyncClient(
        transport=_PublicOnlyTransport(PublicOnlyNetworkBackend(resolve, inner)),
        trust_env=False,
        follow_redirects=False,
    )

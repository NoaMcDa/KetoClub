"""One platform menu body, from the shared menu cache or upstream.

The cache-then-fetch-then-cache mechanics the menu proxy routes
(``app/routers/proxy.py``, #95, #122) always had, lifted out unchanged so
``GET /v1/venue-menus`` (D25, #333) reads the very same ``menu_cache`` rows
the proxies write: a cache hit answers without an upstream call; a miss
fetches ``url`` with headers built from scratch by the caller (nothing of the
inbound request is forwarded) and caches only a 2xx result with a non-empty
body under ``(source, cache_key)``. An empty 2xx body is how Wolt retired its
previous menu endpoint (#168): it is returned, but never cached.
"""

from dataclasses import dataclass
from datetime import UTC, datetime
from typing import Literal

import httpx
from sqlalchemy import Engine
from starlette.concurrency import run_in_threadpool

from app.services.wolt import read_cached_menu, write_cached_menu

SLUG_PATTERN = r"^[a-z0-9][a-z0-9-]{0,99}$"
"""A Wolt venue slug, as the proxy and ``/v1/venue-menus`` accept it."""

RESTAURANT_ID_PATTERN = r"^[0-9]{1,12}$"
"""A 10bis restaurant id, as the proxy and ``/v1/venue-menus`` accept it."""


@dataclass(frozen=True)
class UpstreamMenu:
    """One menu response: the platform's status, ``Content-Type`` and body.

    ``body`` is the text a cache hit stored or the bytes a fresh fetch
    read. ``fetched_at`` is when the upstream fetch happened (aware UTC, at
    millisecond precision for a fresh fetch).
    """

    status_code: int
    content_type: str
    body: str | bytes
    from_cache: bool
    fetched_at: datetime


class UpstreamUnreachable(Exception):
    """The platform could not be reached: 502 ``offline`` or 504 ``timeout``."""

    def __init__(self, reason: Literal["offline", "timeout"], status_code: int):
        super().__init__(f"{status_code} {reason}")
        self.reason = reason
        self.status_code = status_code


async def fetch_menu_body(
    *,
    engine: Engine,
    http_client: httpx.AsyncClient,
    ttl_seconds: int,
    source: str,
    cache_key: str,
    url: str,
    headers: dict[str, str],
    timeout: httpx.Timeout,
) -> UpstreamMenu:
    """The menu for ``(source, cache_key)`` from cache, or fetched and cached.

    Raises :class:`UpstreamUnreachable` when the upstream connection fails
    (``offline``, 502) or times out (``timeout``, 504); a proxy-originated
    failure is never cached.
    """
    cached = await run_in_threadpool(
        read_cached_menu, engine, source, cache_key, ttl_seconds
    )
    if cached is not None:
        return UpstreamMenu(
            status_code=cached.status_code,
            content_type=cached.content_type,
            body=cached.body,
            from_cache=True,
            fetched_at=cached.fetched_at or datetime.now(UTC),
        )

    now = datetime.now(UTC)
    fetched_at = now.replace(microsecond=now.microsecond // 1000 * 1000)
    try:
        upstream = await http_client.get(url, headers=headers, timeout=timeout)
    except httpx.ConnectError:
        raise UpstreamUnreachable("offline", 502) from None
    except httpx.TimeoutException:
        raise UpstreamUnreachable("timeout", 504) from None

    content_type = upstream.headers.get("content-type", "application/json")
    if 200 <= upstream.status_code < 300 and upstream.content:
        await run_in_threadpool(
            write_cached_menu,
            engine,
            source,
            cache_key,
            upstream.status_code,
            content_type,
            upstream.text,
            fetched_at,
        )
    return UpstreamMenu(
        status_code=upstream.status_code,
        content_type=content_type,
        body=upstream.content,
        from_cache=False,
        fetched_at=fetched_at,
    )

"""``GET /proxy/wolt/...`` and ``GET /proxy/tenbis/...``: the CORS-forwarding
menu proxies.

The only two proxy routes this backend has — not a generic passthrough.
Each upstream host always comes from its own ``Settings.*_BASE_URL``; it is
never taken from the request (``backend_plan.md`` §3.3, issues #95, #122).
Both routes share ``_proxy_menu`` for the cache-then-fetch-then-cache
mechanics; only the URL, headers, timeout and cache ``source`` differ.
"""

from typing import Annotated

import httpx
from fastapi import APIRouter, Path, Request, Response
from starlette.concurrency import run_in_threadpool

from app.schemas import ErrorResponse
from app.services.tenbis import SOURCE as TENBIS_SOURCE
from app.services.tenbis import TENBIS_HEADERS, TENBIS_TIMEOUT, tenbis_menu_url
from app.services.wolt import SOURCE as WOLT_SOURCE
from app.services.wolt import (
    WOLT_HEADERS,
    WOLT_TIMEOUT,
    read_cached_menu,
    wolt_menu_url,
    write_cached_menu,
)

router = APIRouter()

_SLUG_PATTERN = r"^[a-z0-9][a-z0-9-]{0,99}$"
_RESTAURANT_ID_PATTERN = r"^[0-9]{1,12}$"

SlugPath = Annotated[str, Path(pattern=_SLUG_PATTERN)]
RestaurantIdPath = Annotated[str, Path(pattern=_RESTAURANT_ID_PATTERN)]


@router.get("/proxy/wolt/v4/venues/slug/{slug}/menu/data")
async def get_wolt_menu(request: Request, slug: SlugPath) -> Response:
    """Forward one Wolt menu request, transparently, behind a short cache.

    Wolt's status, body and ``Content-Type`` are returned unchanged, 404
    included, so the Dart adapter's status mapping needs no change. A fresh
    cache hit skips the upstream call entirely; only a 2xx response is
    cached, and a proxy-originated failure (502/504) is never cached.
    """
    settings = request.app.state.settings
    return await _proxy_menu(
        request=request,
        source=WOLT_SOURCE,
        cache_key=slug,
        url=wolt_menu_url(settings.WOLT_BASE_URL, slug),
        headers=WOLT_HEADERS,
        timeout=WOLT_TIMEOUT,
    )


@router.get("/proxy/tenbis/api/v1.0/Restaurants/{restaurant_id}/Menu")
async def get_tenbis_menu(
    request: Request, restaurant_id: RestaurantIdPath
) -> Response:
    """Forward one 10bis menu request, transparently, behind a short cache.

    Shaped exactly like ``get_wolt_menu`` (#95): 10bis's status, body and
    ``Content-Type`` are returned unchanged, 404 included. ``restaurant_id``
    and a Wolt ``slug`` share ``menu_cache`` but never collide, because the
    cache key is ``(source, id)``, not ``id`` alone.
    """
    settings = request.app.state.settings
    return await _proxy_menu(
        request=request,
        source=TENBIS_SOURCE,
        cache_key=restaurant_id,
        url=tenbis_menu_url(settings.TENBIS_BASE_URL, restaurant_id),
        headers=TENBIS_HEADERS,
        timeout=TENBIS_TIMEOUT,
    )


async def _proxy_menu(
    *,
    request: Request,
    source: str,
    cache_key: str,
    url: str,
    headers: dict[str, str],
    timeout: httpx.Timeout,
) -> Response:
    """Serve one proxied menu fetch from cache, or fetch and cache it.

    Shared by every proxy route: a cache hit answers without an upstream
    call; a miss fetches ``url`` with headers built from scratch (nothing of
    the inbound request is forwarded) and caches only a 2xx result under
    ``(source, cache_key)``.
    """
    settings = request.app.state.settings
    engine = request.app.state.engine

    cached = await run_in_threadpool(
        read_cached_menu, engine, source, cache_key, settings.MENU_CACHE_TTL_SECONDS
    )
    if cached is not None:
        return Response(
            content=cached.body,
            status_code=cached.status_code,
            media_type=cached.content_type,
            headers={"X-KetoClub-Cache": "hit"},
        )

    http_client: httpx.AsyncClient = request.app.state.http_client
    try:
        upstream = await http_client.get(url, headers=headers, timeout=timeout)
    except httpx.ConnectError:
        return _proxy_error(reason="offline", status_code=502)
    except httpx.TimeoutException:
        return _proxy_error(reason="timeout", status_code=504)

    content_type = upstream.headers.get("content-type", "application/json")
    if 200 <= upstream.status_code < 300:
        await run_in_threadpool(
            write_cached_menu,
            engine,
            source,
            cache_key,
            upstream.status_code,
            content_type,
            upstream.text,
        )

    return Response(
        content=upstream.content,
        status_code=upstream.status_code,
        media_type=content_type,
        headers={"X-KetoClub-Cache": "miss"},
    )


def _proxy_error(*, reason: str, status_code: int) -> Response:
    """Build the ``{reason, status_code}`` body for a proxy-originated error."""
    body = ErrorResponse(reason=reason, status_code=status_code)
    return Response(
        content=body.model_dump_json(),
        status_code=status_code,
        media_type="application/json",
    )

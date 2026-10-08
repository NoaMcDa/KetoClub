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

from app.schemas import ErrorResponse
from app.services.platform_menu import (
    RESTAURANT_ID_PATTERN,
    SLUG_PATTERN,
    UpstreamUnreachable,
    fetch_menu_body,
)
from app.services.tenbis import SOURCE as TENBIS_SOURCE
from app.services.tenbis import TENBIS_HEADERS, TENBIS_TIMEOUT, tenbis_menu_url
from app.services.wolt import SOURCE as WOLT_SOURCE
from app.services.wolt import (
    WOLT_MENU_LANG,
    WOLT_TIMEOUT,
    wolt_assortment_url,
    wolt_web_headers,
)

router = APIRouter()

SlugPath = Annotated[str, Path(pattern=SLUG_PATTERN)]
RestaurantIdPath = Annotated[str, Path(pattern=RESTAURANT_ID_PATTERN)]


@router.get("/proxy/wolt/venues/slug/{slug}/assortment")
async def get_wolt_menu(request: Request, slug: SlugPath) -> Response:
    """Forward one Wolt menu request, transparently, behind a short cache.

    The upstream is Wolt's consumer-assortment endpoint on
    ``WOLT_CONSUMER_BASE_URL`` (#168), asked with the web-client header set
    the discovery routes send. The route path mirrors the upstream's own
    ``venues/slug/{slug}/assortment`` tail without its ``consumer-api``
    prefix, the same way the discovery routes mirror ``pages/...``.

    Wolt's status, body and ``Content-Type`` are returned unchanged, 404
    included, so the Dart adapter's status mapping needs no change. A fresh
    cache hit skips the upstream call entirely; only a 2xx response with a
    body is cached, and a proxy-originated failure (502/504) is never
    cached.
    """
    settings = request.app.state.settings
    return await _proxy_menu(
        request=request,
        source=WOLT_SOURCE,
        cache_key=slug,
        url=wolt_assortment_url(settings.WOLT_CONSUMER_BASE_URL, slug),
        headers=wolt_web_headers(
            lang=WOLT_MENU_LANG,
            client_id=request.app.state.wolt_web_client_id,
            client_version=settings.WOLT_CLIENT_VERSION,
        ),
        timeout=WOLT_TIMEOUT,
    )


@router.get("/proxy/tenbis/api/v1.0/Restaurants/{restaurant_id}/Menu")
async def get_tenbis_menu(
    request: Request, restaurant_id: RestaurantIdPath
) -> Response:
    """Forward one 10bis menu request, transparently, behind a short cache.

    Shaped like ``get_wolt_menu`` (#95): 10bis's status, body and
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

    Shared by every proxy route; the mechanics live in
    ``app.services.platform_menu.fetch_menu_body`` (shared with
    ``GET /v1/venue-menus``, #333): a cache hit answers without an upstream
    call; a miss fetches ``url`` with headers built from scratch (nothing of
    the inbound request is forwarded) and caches only a 2xx result with a
    non-empty body under ``(source, cache_key)``. An empty 2xx body is how
    Wolt retired its previous menu endpoint (#168): it is still passed
    through, so the client reports ``platformChanged``, but never cached, so
    an upstream that recovers is seen on the very next request.
    """
    settings = request.app.state.settings
    try:
        fetched = await fetch_menu_body(
            engine=request.app.state.engine,
            http_client=request.app.state.http_client,
            ttl_seconds=settings.MENU_CACHE_TTL_SECONDS,
            source=source,
            cache_key=cache_key,
            url=url,
            headers=headers,
            timeout=timeout,
        )
    except UpstreamUnreachable as error:
        return _proxy_error(reason=error.reason, status_code=error.status_code)

    return Response(
        content=fetched.body,
        status_code=fetched.status_code,
        media_type=fetched.content_type,
        headers={"X-KetoClub-Cache": "hit" if fetched.from_cache else "miss"},
    )


def _proxy_error(*, reason: str, status_code: int) -> Response:
    """Build the ``{reason, status_code}`` body for a proxy-originated error."""
    body = ErrorResponse(reason=reason, status_code=status_code)
    return Response(
        content=body.model_dump_json(),
        status_code=status_code,
        media_type="application/json",
    )

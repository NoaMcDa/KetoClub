"""``GET /proxy/wolt/pages/restaurants`` and ``POST /proxy/wolt/pages/search``:
the Wolt venue-discovery proxy routes (#123).

Wolt's discovery endpoints are unofficial, origin-locked to
``https://wolt.com`` and answer 410 without the full web-client header set
(``phase2_discovery_research.md`` §2.2, §2.3), so the web build can only
reach them through this backend — the same CORS rule the menu proxy in
``app/routers/proxy.py`` follows. Kept in their own module rather than
folded into ``proxy.py``: unlike a menu fetch, a discovery request is
validated (lat/lon/q/lang), rate limited per install, and one of the two
routes is a ``POST`` whose body this backend itself reshapes before
forwarding it — different enough mechanics that sharing ``_proxy_menu``
would blur more than it saves. Only two routes exist; there is no wildcard
passthrough.
"""

from typing import Annotated, Literal

import httpx
from fastapi import APIRouter, Depends, Query, Request, Response
from starlette.concurrency import run_in_threadpool

from app.errors import BackendError
from app.schemas import DiscoverySearchRequest, ErrorResponse
from app.services.install_id import require_install_id
from app.services.rate_limit import RateLimiter
from app.services.wolt import (
    SOURCE_RESTAURANTS,
    SOURCE_SEARCH,
    WOLT_TIMEOUT,
    WoltLang,
    read_cached_menu,
    wolt_restaurants_url,
    wolt_search_url,
    wolt_web_headers,
    write_cached_menu,
)

router = APIRouter()

# Matches the GET route's `lat`/`lon` bounds; the POST body's Field(ge=,
# le=) in `app.schemas.DiscoverySearchRequest` repeats the same numbers
# because a Query and a pydantic Field are declared differently.
LatQuery = Annotated[float, Query(ge=-90, le=90)]
LonQuery = Annotated[float, Query(ge=-180, le=180)]


@router.get("/proxy/wolt/pages/restaurants")
async def search_wolt_nearby(
    request: Request,
    install_id: Annotated[str, Depends(require_install_id)],
    lat: LatQuery,
    lon: LonQuery,
    lang: WoltLang = "en",
) -> Response:
    """Forward one "venues near a point" request, behind a short cache.

    Wolt's status, body and ``Content-Type`` are returned unchanged, 410
    included, so a Dart mapper can tell "the endpoint moved" apart from
    "no results". A fresh cache hit skips both the upstream call and the
    rate limiter; only a 2xx response is cached.
    """
    settings = request.app.state.settings
    headers = wolt_web_headers(
        lang=lang,
        client_id=request.app.state.wolt_web_client_id,
        client_version=settings.WOLT_CLIENT_VERSION,
    )
    return await _proxy_discovery(
        request=request,
        install_id=install_id,
        source=SOURCE_RESTAURANTS,
        cache_key=f"{lat:.4f},{lon:.4f},{lang}",
        method="GET",
        url=wolt_restaurants_url(settings.WOLT_CONSUMER_BASE_URL),
        headers=headers,
        params={"lat": lat, "lon": lon},
        json_body=None,
    )


@router.post("/proxy/wolt/pages/search")
async def search_wolt_by_name(
    request: Request,
    install_id: Annotated[str, Depends(require_install_id)],
    body: DiscoverySearchRequest,
) -> Response:
    """Forward one "search venues by name" request, behind a short cache.

    ``target`` is fixed to ``"venues"`` here, never taken from the client
    (``DiscoverySearchRequest`` has no such field at all), so this route can
    never be used to proxy a dish search instead. Otherwise shaped exactly
    like ``search_wolt_nearby`` above.
    """
    settings = request.app.state.settings
    headers = wolt_web_headers(
        lang=body.lang,
        client_id=request.app.state.wolt_web_client_id,
        client_version=settings.WOLT_CLIENT_VERSION,
    )
    # A search without a position (location denied, #37) is its own cache
    # row and is forwarded without `lat`/`lon` rather than with nulls.
    has_position = body.lat is not None and body.lon is not None
    position = f"{body.lat:.4f},{body.lon:.4f}" if has_position else "none"
    cache_key = f"{body.q.lower()},{position},{body.lang}"
    json_body: dict[str, object] = {"q": body.q, "target": "venues"}
    if has_position:
        json_body["lat"] = body.lat
        json_body["lon"] = body.lon
    return await _proxy_discovery(
        request=request,
        install_id=install_id,
        source=SOURCE_SEARCH,
        cache_key=cache_key,
        method="POST",
        url=wolt_search_url(settings.WOLT_BASE_URL),
        headers=headers,
        params=None,
        json_body=json_body,
    )


async def _proxy_discovery(
    *,
    request: Request,
    install_id: str,
    source: str,
    cache_key: str,
    method: Literal["GET", "POST"],
    url: str,
    headers: dict[str, str],
    params: dict[str, float] | None,
    json_body: dict[str, object] | None,
) -> Response:
    """Serve one discovery request from cache, or rate-limit, fetch and cache.

    The cache is checked before the rate limiter, the same order
    ``POST /chat`` (#100) uses: a hit answers directly and never spends the
    install's quota. ``menu_cache`` is reused as-is (``source`` keeps a
    discovery row from ever colliding with a menu row); nothing of the
    inbound request (``Origin``, ``Cookie``, ``Authorization``, the install
    id) reaches Wolt — only ``headers``, built from scratch by the caller,
    does.
    """
    settings = request.app.state.settings
    engine = request.app.state.engine

    cached = await run_in_threadpool(
        read_cached_menu,
        engine,
        source,
        cache_key,
        settings.DISCOVERY_CACHE_TTL_SECONDS,
    )
    if cached is not None:
        return Response(
            content=cached.body,
            status_code=cached.status_code,
            media_type=cached.content_type,
            headers={"X-KetoClub-Cache": "hit"},
        )

    limiter: RateLimiter = request.app.state.discovery_rate_limiter
    if not limiter.allow(install_id):
        raise BackendError(429, "rateLimited")

    http_client: httpx.AsyncClient = request.app.state.http_client
    try:
        if method == "GET":
            upstream = await http_client.get(
                url, headers=headers, params=params, timeout=WOLT_TIMEOUT
            )
        else:
            upstream = await http_client.post(
                url, headers=headers, json=json_body, timeout=WOLT_TIMEOUT
            )
    except httpx.ConnectError:
        return _discovery_error(reason="offline", status_code=502)
    except httpx.TimeoutException:
        return _discovery_error(reason="timeout", status_code=504)

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


def _discovery_error(*, reason: str, status_code: int) -> Response:
    """Build the ``{reason, status_code}`` body for a proxy-originated error."""
    body = ErrorResponse(reason=reason, status_code=status_code)
    return Response(
        content=body.model_dump_json(),
        status_code=status_code,
        media_type="application/json",
    )

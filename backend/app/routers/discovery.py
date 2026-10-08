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

from dataclasses import dataclass
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
    return await _proxy_discovery(
        request=request,
        install_id=install_id,
        call=nearby_call(request, lat=lat, lon=lon, lang=lang),
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
    return await _proxy_discovery(
        request=request,
        install_id=install_id,
        call=search_call(request, q=body.q, lat=body.lat, lon=body.lon, lang=body.lang),
    )


@dataclass(frozen=True)
class DiscoveryCall:
    """One upstream discovery request: where it goes and how it is cached."""

    source: str
    cache_key: str
    method: Literal["GET", "POST"]
    url: str
    headers: dict[str, str]
    params: dict[str, float] | None
    json_body: dict[str, object] | None


@dataclass(frozen=True)
class DiscoveryReply:
    """What Wolt (or the cache) answered: status, type and body, unchanged."""

    status_code: int
    content_type: str
    body: bytes
    cache: Literal["hit", "miss"]


@dataclass(frozen=True)
class DiscoveryFailure:
    """The upstream could not be reached: ``offline`` (502) or ``timeout``
    (504). A refused limiter is not one of these; it raises ``BackendError``.
    """

    reason: Literal["offline", "timeout"]
    status_code: Literal[502, 504]


def nearby_call(
    request: Request, *, lat: float, lon: float, lang: WoltLang
) -> DiscoveryCall:
    """The "venues near a point" request and its cache key."""
    settings = request.app.state.settings
    return DiscoveryCall(
        source=SOURCE_RESTAURANTS,
        cache_key=f"{lat:.4f},{lon:.4f},{lang}",
        method="GET",
        url=wolt_restaurants_url(settings.WOLT_CONSUMER_BASE_URL),
        headers=_web_headers(request, lang),
        params={"lat": lat, "lon": lon},
        json_body=None,
    )


def search_call(
    request: Request,
    *,
    q: str,
    lat: float | None,
    lon: float | None,
    lang: WoltLang,
) -> DiscoveryCall:
    """The "search venues by name" request and its cache key.

    ``target`` is fixed to ``"venues"`` here, never taken from a client, so
    no route can be used to proxy a dish search instead. A search without a
    position (location denied, #37) is its own cache row and is forwarded
    without ``lat``/``lon`` rather than with nulls.
    """
    settings = request.app.state.settings
    has_position = lat is not None and lon is not None
    position = f"{lat:.4f},{lon:.4f}" if has_position else "none"
    json_body: dict[str, object] = {"q": q, "target": "venues"}
    if has_position:
        json_body["lat"] = lat
        json_body["lon"] = lon
    return DiscoveryCall(
        source=SOURCE_SEARCH,
        cache_key=f"{q.lower()},{position},{lang}",
        method="POST",
        url=wolt_search_url(settings.WOLT_BASE_URL),
        headers=_web_headers(request, lang),
        params=None,
        json_body=json_body,
    )


def _web_headers(request: Request, lang: WoltLang) -> dict[str, str]:
    settings = request.app.state.settings
    return wolt_web_headers(
        lang=lang,
        client_id=request.app.state.wolt_web_client_id,
        client_version=settings.WOLT_CLIENT_VERSION,
    )


async def _proxy_discovery(
    *, request: Request, install_id: str, call: DiscoveryCall
) -> Response:
    """Serve ``call`` as Wolt's own response, status and body unchanged."""
    outcome = await fetch_discovery(request=request, install_id=install_id, call=call)
    if isinstance(outcome, DiscoveryFailure):
        return _discovery_error(reason=outcome.reason, status_code=outcome.status_code)
    return Response(
        content=outcome.body,
        status_code=outcome.status_code,
        media_type=outcome.content_type,
        headers={"X-KetoClub-Cache": outcome.cache},
    )


async def fetch_discovery(
    *, request: Request, install_id: str, call: DiscoveryCall
) -> DiscoveryReply | DiscoveryFailure:
    """Serve one discovery request from cache, or rate-limit, fetch and cache.

    The cache is checked before the rate limiter, the same order
    ``POST /chat`` (#100) uses: a hit answers directly and never spends the
    install's quota. ``menu_cache`` is reused as-is (``source`` keeps a
    discovery row from ever colliding with a menu row); nothing of the
    inbound request (``Origin``, ``Cookie``, ``Authorization``, the install
    id) reaches Wolt — only ``call.headers``, built from scratch, does.
    Shared by the proxy routes above and ``/v1/venues/*`` (#335).

    Raises ``BackendError`` (429 ``rateLimited``) when the bucket is empty.
    """
    settings = request.app.state.settings
    engine = request.app.state.engine

    cached = await run_in_threadpool(
        read_cached_menu,
        engine,
        call.source,
        call.cache_key,
        settings.DISCOVERY_CACHE_TTL_SECONDS,
    )
    if cached is not None:
        return DiscoveryReply(
            status_code=cached.status_code,
            content_type=cached.content_type,
            body=cached.body.encode("utf-8"),
            cache="hit",
        )

    limiter: RateLimiter = request.app.state.discovery_rate_limiter
    if not limiter.allow(install_id):
        raise BackendError(429, "rateLimited")

    http_client: httpx.AsyncClient = request.app.state.http_client
    try:
        if call.method == "GET":
            upstream = await http_client.get(
                call.url,
                headers=call.headers,
                params=call.params,
                timeout=WOLT_TIMEOUT,
            )
        else:
            upstream = await http_client.post(
                call.url,
                headers=call.headers,
                json=call.json_body,
                timeout=WOLT_TIMEOUT,
            )
    except httpx.ConnectError:
        return DiscoveryFailure(reason="offline", status_code=502)
    except httpx.TimeoutException:
        return DiscoveryFailure(reason="timeout", status_code=504)

    content_type = upstream.headers.get("content-type", "application/json")
    if 200 <= upstream.status_code < 300:
        await run_in_threadpool(
            write_cached_menu,
            engine,
            call.source,
            call.cache_key,
            upstream.status_code,
            content_type,
            upstream.text,
        )

    return DiscoveryReply(
        status_code=upstream.status_code,
        content_type=content_type,
        body=upstream.content,
        cache="miss",
    )


def _discovery_error(*, reason: str, status_code: int) -> Response:
    """Build the ``{reason, status_code}`` body for a proxy-originated error."""
    body = ErrorResponse(reason=reason, status_code=status_code)
    return Response(
        content=body.model_dump_json(),
        status_code=status_code,
        media_type="application/json",
    )

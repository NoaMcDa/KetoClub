"""``GET /proxy/wolt/...``: the Wolt menu CORS-forwarding proxy.

The **only** proxy route this backend has — not a generic passthrough. The
upstream host always comes from ``Settings.WOLT_BASE_URL``; it is never
taken from the request (``backend_plan.md`` §3.3, issue #95).
"""

from typing import Annotated

import httpx
from fastapi import APIRouter, Path, Request, Response
from starlette.concurrency import run_in_threadpool

from app.schemas import ErrorResponse
from app.services.wolt import (
    WOLT_HEADERS,
    WOLT_TIMEOUT,
    read_cached_menu,
    wolt_menu_url,
    write_cached_menu,
)

router = APIRouter()

_SLUG_PATTERN = r"^[a-z0-9][a-z0-9-]{0,99}$"

SlugPath = Annotated[str, Path(pattern=_SLUG_PATTERN)]


@router.get("/proxy/wolt/v4/venues/slug/{slug}/menu/data")
async def get_wolt_menu(request: Request, slug: SlugPath) -> Response:
    """Forward one Wolt menu request, transparently, behind a short cache.

    Wolt's status, body and ``Content-Type`` are returned unchanged, 404
    included, so the Dart adapter's status mapping needs no change. A fresh
    cache hit skips the upstream call entirely; only a 2xx response is
    cached, and a proxy-originated failure (502/504) is never cached.
    """
    settings = request.app.state.settings
    engine = request.app.state.engine

    cached = await run_in_threadpool(
        read_cached_menu, engine, slug, settings.MENU_CACHE_TTL_SECONDS
    )
    if cached is not None:
        return Response(
            content=cached.body,
            status_code=cached.status_code,
            media_type=cached.content_type,
            headers={"X-KetoClub-Cache": "hit"},
        )

    http_client: httpx.AsyncClient = request.app.state.http_client
    url = wolt_menu_url(settings.WOLT_BASE_URL, slug)
    try:
        upstream = await http_client.get(
            url, headers=WOLT_HEADERS, timeout=WOLT_TIMEOUT
        )
    except httpx.ConnectError:
        return _proxy_error(reason="offline", status_code=502)
    except httpx.TimeoutException:
        return _proxy_error(reason="timeout", status_code=504)

    content_type = upstream.headers.get("content-type", "application/json")
    if 200 <= upstream.status_code < 300:
        await run_in_threadpool(
            write_cached_menu,
            engine,
            slug,
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

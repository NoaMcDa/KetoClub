"""The Wolt menu proxy: the reason this service exists.

`restaurant-api.wolt.com` sends no `Access-Control-Allow-Origin`, so a browser
refuses the request before it leaves and the web build cannot read a menu at
all (architecture.md §13, D9). This route forwards the request from a server,
where CORS does not apply, and answers the browser with the header it needs.

It is deliberately not a general proxy. There is exactly one route, the slug is
validated, and the upstream host comes from configuration rather than from the
request, so this cannot be used to reach an arbitrary address.
"""

from typing import Annotated

import httpx
from fastapi import APIRouter, Depends, Path, Request, Response
from sqlalchemy.orm import Session
from starlette.concurrency import run_in_threadpool

from app.config import Settings, get_settings
from app.db import get_session
from app.schemas import FailureResponse
from app.services.cache import read_menu_cache, write_menu_cache
from app.services.clock import utc_now
from app.services.wolt import UpstreamResponse, fetch_menu

router = APIRouter(tags=["proxy"])

SOURCE = "wolt"

# Wolt slugs seen in the wild are lowercase letters, digits and hyphens, which
# is what a venue URL carries. Anything else is rejected with 422 rather than
# forwarded: the point of an allow-list is that it is narrow.
SLUG_PATTERN = r"^[a-z0-9][a-z0-9-]{0,99}$"

CACHE_HEADER = "X-KetoClub-Cache"

# The two statuses this service invents, and the reason each maps to on the
# client. Every other status a caller sees came from Wolt itself.
_UNREACHABLE_REASONS = {502: "offline", 504: "timeout"}


def get_http_client(request: Request) -> httpx.AsyncClient:
    """Returns the shared client created once for the process lifetime."""
    client: httpx.AsyncClient = request.app.state.http_client
    return client


@router.get(
    "/proxy/wolt/v4/venues/slug/{slug}/menu/data",
    response_class=Response,
    responses={502: {"model": FailureResponse}, 504: {"model": FailureResponse}},
)
async def wolt_menu(
    slug: Annotated[str, Path(pattern=SLUG_PATTERN)],
    settings: Annotated[Settings, Depends(get_settings)],
    session: Annotated[Session, Depends(get_session)],
    client: Annotated[httpx.AsyncClient, Depends(get_http_client)],
) -> Response:
    """Forwards one menu request to Wolt and returns its answer unchanged.

    Wolt's status, body and content type are passed through as received, 404
    included, so the Flutter adapter's existing failure mapping keeps working
    without a special case for the proxy. Only a 2xx body is cached.
    """
    now = utc_now()
    cached = await run_in_threadpool(
        read_menu_cache,
        session,
        source=SOURCE,
        slug=slug,
        ttl_seconds=settings.menu_cache_ttl_seconds,
        now=now,
    )
    if cached is not None:
        return Response(
            content=cached.body,
            status_code=200,
            media_type=cached.content_type,
            headers={CACHE_HEADER: "hit"},
        )

    result = await fetch_menu(client, base_url=settings.wolt_base_url, slug=slug)

    if not isinstance(result, UpstreamResponse):
        failure = FailureResponse(
            reason=_UNREACHABLE_REASONS[result.status_code],
            status_code=result.status_code,
        )
        return Response(
            content=failure.model_dump_json(),
            status_code=result.status_code,
            media_type="application/json",
        )

    if 200 <= result.status_code < 300:
        await run_in_threadpool(
            write_menu_cache,
            session,
            source=SOURCE,
            slug=slug,
            body=result.body,
            content_type=result.content_type,
            now=now,
        )

    return Response(
        content=result.body,
        status_code=result.status_code,
        media_type=result.content_type,
        headers={CACHE_HEADER: "miss"},
    )

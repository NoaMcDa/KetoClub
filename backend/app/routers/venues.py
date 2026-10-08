"""``GET /venues/nearby`` and ``POST /venues/search``: complete venue results
(D25, #335).

The discovery proxy (``app/routers/discovery.py``, #123) hands the client
Wolt's raw page for the Dart ``WoltVenueMapper`` to read. These two routes
read it here instead, with ``map_wolt_venues`` (#323), and answer
``{"venues": [Venue JSON]}`` in the shape the Dart ``Venue.toJson`` writes,
in Wolt's order: nearest-first sorting stays on the client.

They share the proxy's upstream request, cache keys (so a row written by one
is a hit for the other) and discovery rate limiter, through
``fetch_discovery``. A cache hit spends no quota. The install id is read for
limiting only: it is neither stored nor logged here.

Errors are ``{reason, status_code}``: 429 ``rateLimited``; 502 ``offline``;
504 ``timeout``; 502 ``platformChanged`` for any non-2xx upstream status
(410 included), a body that is not JSON, or a page the mapper cannot read.
"""

import json
from typing import Annotated, Any

from fastapi import APIRouter, Depends, Request
from fastapi.responses import JSONResponse

from app.errors import BackendError
from app.keto.models import to_json
from app.platforms.wolt_venues import map_wolt_venues
from app.routers.discovery import (
    DiscoveryCall,
    DiscoveryFailure,
    LatQuery,
    LonQuery,
    fetch_discovery,
    nearby_call,
    search_call,
)
from app.schemas import VenueSearchRequest, VenuesResponse
from app.services.auth import reject_authorization
from app.services.install_id import require_install_id
from app.services.wolt import WoltLang

router = APIRouter(dependencies=[Depends(reject_authorization)])


@router.get("/venues/nearby")
async def venues_nearby(
    request: Request,
    install_id: Annotated[str, Depends(require_install_id)],
    lat: LatQuery,
    lon: LonQuery,
    lang: WoltLang = "en",
) -> JSONResponse:
    """The venues Wolt lists near a point, normalised."""
    return await _venues(
        request, install_id, nearby_call(request, lat=lat, lon=lon, lang=lang)
    )


@router.post("/venues/search")
async def venues_search(
    request: Request,
    install_id: Annotated[str, Depends(require_install_id)],
    body: VenueSearchRequest,
) -> JSONResponse:
    """The venues whose name matches ``query``, normalised."""
    call = search_call(
        request, q=body.query, lat=body.lat, lon=body.lon, lang=body.lang
    )
    return await _venues(request, install_id, call)


async def _venues(
    request: Request, install_id: str, call: DiscoveryCall
) -> JSONResponse:
    """Fetch ``call`` and answer its page as a ``VenuesResponse``."""
    outcome = await fetch_discovery(request=request, install_id=install_id, call=call)
    if isinstance(outcome, DiscoveryFailure):
        raise BackendError(outcome.status_code, outcome.reason)
    if not 200 <= outcome.status_code < 300:
        raise BackendError(502, "platformChanged")

    try:
        page: Any = json.loads(outcome.body)
    except ValueError:
        raise BackendError(502, "platformChanged") from None
    venues = map_wolt_venues(page)
    if venues is None:
        raise BackendError(502, "platformChanged")

    return JSONResponse(
        content=to_json(VenuesResponse(venues=venues)),
        headers={"X-KetoClub-Cache": outcome.cache},
    )

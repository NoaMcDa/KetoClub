"""``POST /places/search``: a typed street turned into coordinates (#449).

Discovery's custom location can be a street, not only one of the bundled
cities. The text is geocoded by Photon (OpenStreetMap data, no key) through
this backend, so the provider sees the server rather than the user's
device. The mapping lives in ``app.services.places``.

Nothing is stored and nothing is cached: the query, the labels and the
coordinates never reach a log line or a table. The install id keys the
per-install limiter only, as on the discovery routes. When
``PLACE_SEARCH_ENABLED`` is false this router is not mounted (404).

Errors are ``{reason, status_code}``: 429 ``rateLimited``; 502 ``offline``
(Photon could not be reached); 502 ``providerChanged`` (a non-2xx status,
or a body that is not the expected GeoJSON); 504 ``timeout``.
"""

import logging
from typing import Annotated, Any

import httpx
from fastapi import APIRouter, Depends, Request

from app.errors import BackendError
from app.schemas import PlaceResponse, PlaceSearchRequest, PlacesResponse
from app.services.auth import reject_authorization
from app.services.install_id import require_install_id
from app.services.places import (
    GEOCODER_TIMEOUT,
    geocoder_params,
    geocoder_url,
    map_photon_places,
)
from app.services.rate_limit import RateLimiter

router = APIRouter(dependencies=[Depends(reject_authorization)])

logger = logging.getLogger("ketoclub.places")


@router.post("/places/search")
async def search_places(
    request: Request,
    install_id: Annotated[str, Depends(require_install_id)],
    body: PlaceSearchRequest,
) -> PlacesResponse:
    """At most six Israeli streets or addresses matching ``body.query``."""
    limiter: RateLimiter = request.app.state.place_search_rate_limiter
    if not limiter.allow(install_id):
        logger.info("places outcome=rateLimited")
        raise BackendError(429, "rateLimited")

    settings = request.app.state.settings
    http_client: httpx.AsyncClient = request.app.state.http_client
    try:
        upstream = await http_client.get(
            geocoder_url(settings.GEOCODER_BASE_URL),
            params=geocoder_params(body.query, body.language),
            headers={
                "Accept": "application/json",
                "User-Agent": settings.GEOCODER_USER_AGENT,
            },
            timeout=GEOCODER_TIMEOUT,
        )
    except httpx.TimeoutException:
        logger.info("places outcome=timeout")
        raise BackendError(504, "timeout") from None
    except httpx.TransportError:
        logger.info("places outcome=offline")
        raise BackendError(502, "offline") from None

    if not 200 <= upstream.status_code < 300:
        logger.info(
            "places outcome=providerChanged upstream_status=%d", upstream.status_code
        )
        raise BackendError(502, "providerChanged")
    try:
        reply: Any = upstream.json()
    except ValueError:
        reply = None
    places = map_photon_places(reply)
    if places is None:
        logger.info("places outcome=providerChanged shape=unexpected")
        raise BackendError(502, "providerChanged")

    features = reply.get("features") if isinstance(reply, dict) else None
    logger.info(
        "places outcome=ok features=%d places=%d",
        len(features) if isinstance(features, list) else 0,
        len(places),
    )
    return PlacesResponse(
        places=[
            PlaceResponse(
                label=place.label,
                city=place.city,
                latitude=place.latitude,
                longitude=place.longitude,
            )
            for place in places
        ]
    )

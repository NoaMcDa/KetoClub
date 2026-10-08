"""``GET /venue-menus/{source}/{platform_id}``: one platform menu, mapped and
usually analysed, in one request (D25, #333).

``source`` is ``wolt`` or ``tenbis``; ``platform_id`` is a Wolt slug or a
10bis restaurant id, under the menu proxy's own patterns (422 otherwise).
The body comes through the menu proxy's own cache
(``app.services.platform_menu``, the same ``menu_cache`` rows), so a venue
the proxy just served is a hit here too; ``X-KetoClub-Cache`` reports that
cache. The payload is mapped by the ports of the Dart mappers
(``app.platforms``), so the client's ``Menu.tryFrom`` reads it as if it had
mapped it itself.

With ``classify=true`` the menu is analysed by
``app.services.classify.classify`` under ``netCarbLimitGrams`` and the
repeated ``constraints`` parameters (the prompt fragments, under the body
rule: unknown or repeated is 422). This route also fetched a menu, so an
empty analysis bucket keeps the menu and answers the rules stamped
``rateLimited`` rather than refusing; a menu with no dish answers
``analysis: null``. With ``classify=false`` nothing is analysed and no
bucket is spent: the proxy itself has none.

A returned analysis is also written to the shared menu store
(``stored_menus``, D24) when it is enabled: the menu and the analysis
without its ``options``, keyed by venue, never by install id.

Errors are ``{reason, status_code}`` bodies the client's
``BackendMenuAdapter.venueReasonFor`` maps: 404 ``notFound`` (the
platform's 404), 502 ``platformChanged`` (any other non-2xx, an empty or
non-JSON body, or a payload the mapper cannot read), 502 ``offline``, 504
``timeout``, plus the shared 400 ``badResponse`` for a missing install id
or an ``Authorization`` header.
"""

import json
import logging
import re
from datetime import UTC, datetime
from typing import Annotated, Any, Final, Literal

from fastapi import APIRouter, Depends, Path, Query, Request, Response
from fastapi.exceptions import RequestValidationError
from pydantic import ValidationError
from starlette.concurrency import run_in_threadpool

from app.errors import BackendError
from app.keto.models import Menu, MenuAnalysed, VenueRef, to_json
from app.platforms.tenbis_menu import map_tenbis_menu
from app.platforms.wolt_menu import map_wolt_menu
from app.schemas import ClassificationOptionsBody, ErrorResponse, VenueMenuResponse
from app.services import menu_store
from app.services.auth import reject_authorization
from app.services.classify import ClassifyContext, classify, dart_now
from app.services.install_id import require_install_id
from app.services.platform_menu import (
    RESTAURANT_ID_PATTERN,
    SLUG_PATTERN,
    UpstreamMenu,
    UpstreamUnreachable,
    fetch_menu_body,
)
from app.services.tenbis import SOURCE as TENBIS_CACHE_SOURCE
from app.services.tenbis import TENBIS_HEADERS, TENBIS_TIMEOUT, tenbis_menu_url
from app.services.wolt import SOURCE as WOLT_CACHE_SOURCE
from app.services.wolt import (
    WOLT_MENU_LANG,
    WOLT_TIMEOUT,
    wolt_assortment_url,
    wolt_web_headers,
)

router = APIRouter()

logger = logging.getLogger("ketoclub.venue_menus")

VenueMenuSource = Literal["wolt", "tenbis"]

_ID_PATTERNS: Final[dict[str, re.Pattern[str]]] = {
    "wolt": re.compile(SLUG_PATTERN),
    "tenbis": re.compile(RESTAURANT_ID_PATTERN),
}


def _reject_constant(name: str) -> Any:
    raise ValueError(f"{name} is not JSON")


def _query_error(loc: tuple[str, ...], msg: str) -> RequestValidationError:
    return RequestValidationError(
        [{"type": "value_error", "loc": loc, "msg": msg, "input": None}]
    )


def _options(
    net_carb_limit_grams: int, constraints: list[str]
) -> ClassificationOptionsBody:
    """The query's options under the body rule, or FastAPI's 422."""
    try:
        return ClassificationOptionsBody(
            net_carb_limit_grams=net_carb_limit_grams,
            dietary_constraints=constraints,
        )
    except ValidationError as error:
        raise RequestValidationError(
            [
                {
                    "type": entry.get("type", "value_error"),
                    "loc": ("query", "constraints"),
                    "msg": entry.get("msg", ""),
                    "input": None,
                }
                for entry in error.errors(include_url=False)
            ]
        ) from None


async def _fetch(
    request: Request, source: VenueMenuSource, platform_id: str
) -> UpstreamMenu:
    settings = request.app.state.settings
    if source == "wolt":
        url = wolt_assortment_url(settings.WOLT_CONSUMER_BASE_URL, platform_id)
        headers = wolt_web_headers(
            lang=WOLT_MENU_LANG,
            client_id=request.app.state.wolt_web_client_id,
            client_version=settings.WOLT_CLIENT_VERSION,
        )
        cache_source, timeout = WOLT_CACHE_SOURCE, WOLT_TIMEOUT
    else:
        url = tenbis_menu_url(settings.TENBIS_BASE_URL, platform_id)
        headers = dict(TENBIS_HEADERS)
        cache_source, timeout = TENBIS_CACHE_SOURCE, TENBIS_TIMEOUT
    try:
        return await fetch_menu_body(
            engine=request.app.state.engine,
            http_client=request.app.state.http_client,
            ttl_seconds=settings.MENU_CACHE_TTL_SECONDS,
            source=cache_source,
            cache_key=platform_id,
            url=url,
            headers=headers,
            timeout=timeout,
        )
    except UpstreamUnreachable as error:
        raise BackendError(error.status_code, error.reason) from None


def _mapped(upstream: UpstreamMenu, ref: VenueRef, fetched_at: str) -> Menu:
    """The platform's answer as a ``Menu``, or the error it amounts to."""
    status = upstream.status_code
    if status == 404:
        raise BackendError(404, "notFound")
    if not 200 <= status < 300 or not upstream.body:
        raise BackendError(502, "platformChanged")
    try:
        raw: object = json.loads(upstream.body, parse_constant=_reject_constant)
    except (ValueError, RecursionError):
        raise BackendError(502, "platformChanged") from None
    mapper = map_wolt_menu if ref.source == "wolt" else map_tenbis_menu
    menu = mapper(raw, ref=ref, fetched_at=fetched_at)
    if menu is None:
        raise BackendError(502, "platformChanged")
    return menu


async def _store(request: Request, menu: Menu, analysis: MenuAnalysed) -> None:
    """Upsert the shared menu store's row for ``menu`` (D24), when enabled.

    The analysis goes in without its ``options`` (the user's limit and
    toggles), as the client's own upload sends it; nothing here can carry
    the install id. A failure is logged and swallowed: the store is a side
    effect, never the answer.
    """
    if not request.app.state.settings.MENU_STORE_ENABLED:
        return
    shared = to_json(analysis)
    shared.pop("options", None)
    try:
        await run_in_threadpool(
            lambda: menu_store.upsert(
                request.app.state.engine,
                source=menu.venue_ref.source,
                platform_id=menu.venue_ref.platform_id,
                venue_name=menu.venue_name,
                city=None,
                menu=to_json(menu),
                analysis=shared,
                now=datetime.now(UTC),
            )
        )
    except Exception:  # noqa: BLE001 - a side effect must not fail the read
        logger.warning("venue_menus store failed source=%s", menu.venue_ref.source)


@router.get(
    "/venue-menus/{source}/{platform_id}",
    response_model=VenueMenuResponse,
    dependencies=[Depends(reject_authorization)],
    responses={
        status: {"model": ErrorResponse} for status in (400, 404, 422, 429, 502, 504)
    },
)
async def read_venue_menu(
    request: Request,
    response: Response,
    source: VenueMenuSource,
    platform_id: Annotated[str, Path(min_length=1, max_length=100)],
    install_id: Annotated[str, Depends(require_install_id)],
    classify_menu: Annotated[bool, Query(alias="classify")] = False,
    net_carb_limit_grams: Annotated[
        int, Query(alias="netCarbLimitGrams", ge=1, le=50)
    ] = 6,
    constraints: Annotated[list[str] | None, Query()] = None,
) -> VenueMenuResponse:
    """The venue's menu, and its analysis when ``classify`` is true.

    ``constraints`` is repeated, one prompt fragment each, and absent when
    there are none; at most ``MAX_DIETARY_CONSTRAINTS``, each a known
    fragment given once (422 otherwise), checked even when ``classify`` is
    false so a malformed request never depends on the cache.
    """
    if _ID_PATTERNS[source].fullmatch(platform_id) is None:
        raise _query_error(("path", "platform_id"), "not a platform id for this source")
    options = _options(net_carb_limit_grams, constraints or [])

    upstream = await _fetch(request, source, platform_id)
    response.headers["X-KetoClub-Cache"] = "hit" if upstream.from_cache else "miss"
    fetched_at = dart_now(upstream.fetched_at)
    ref = VenueRef(source=source, platform_id=platform_id)
    menu = _mapped(upstream, ref, fetched_at)

    analysis: MenuAnalysed | None = None
    if classify_menu:
        result = await classify(
            menu,
            options.snapshot(),
            ClassifyContext.of(request, install_id),
            when_rate_limited="rules",
        )
        if result is not None:
            analysis = result.analysis
            await _store(request, menu, analysis)
    logger.info(
        "venue_menus source=%s cache=%s classified=%s",
        source,
        "hit" if upstream.from_cache else "miss",
        analysis is not None,
    )
    return VenueMenuResponse(
        menu=menu,
        analysis=analysis,
        from_cache=upstream.from_cache,
        fetched_at=fetched_at,
    )

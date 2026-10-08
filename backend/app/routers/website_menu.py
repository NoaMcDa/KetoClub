"""``POST /website-menu``: a restaurant's own site, read and analysed in one
request (D19, D25; #334).

The body is ``WebsiteMenuRequest {url, options}``. The route does what the
app's ``WebsiteMenuAdapter`` (``lib/services/menu/website/
website_adapter.dart``) does, with every fetch going through
``app.services.website_fetch.fetch_document`` (public hosts only, robots.txt,
the AI opt-out headers, size caps, the install and per-site budgets: the
``/v1/website/fetch`` rules) and every reading through the port of the Dart
reader (``app.website.adapter``):

1. The pasted page is fetched. A PDF goes to the vision path
   (``app.services.scan.scan``) as one ``application/pdf`` page.
2. An HTML page is read by ``read_page``: JSON-LD markup or the page's own
   priced text is the menu; a menu link is fetched once (never a second
   hop) and read by ``read_linked_page``, or sent to the vision path when it
   is a PDF. When the link yields nothing, the page's own text is the last
   resort and the link's failure the answer only when there is none
   (``finish_after_link``).
3. A text menu is analysed by ``app.services.classify.classify``: an empty
   analysis bucket keeps the menu and answers the rules stamped
   ``rateLimited`` (this route also fetched a menu); a menu with no dish
   answers ``analysis: null``. A PDF's analysis is the scan's own.

The menu is addressed ``website/<normalised url>``, the ref the app gives
the same paste (``app.website.ref``). A returned analysis is also written to
the shared menu store (``stored_menus``, D24) when it is enabled: the menu
and the analysis without its ``options``, keyed by that ref, never by
install id; a store failure is logged and never fails the request.

Errors are ``{reason, status_code}`` bodies the client's
``BackendMenuAdapter.websiteReasonFor`` maps: every ``/v1/website/fetch``
reason at its status (400 ``invalidUrl``, 403 ``disallowedByRobots`` /
``aiReserved`` (a ``<meta>`` opt-out too), 404 ``notFound``, 413
``tooLarge``, 415 ``unsupportedContent``, 422 ``jsOnlyPage``, 429
``rateLimited``, 502 ``offline`` / ``upstreamStatus``, 504 ``timeout``),
404 ``menuNotFound`` (no menu on the site or its one linked page), and, for
a PDF that could not be read, 502 with the ``/v1/scan`` reason
(``notConfigured``, ``offline``, ``timeout``, ``rateLimited``,
``badResponse``) or 422 ``noDishesFound``. The URL travels in the body and
no log line carries it, nor the install id.
"""

import base64
import logging
from datetime import UTC, datetime
from typing import Annotated, Final

from fastapi import APIRouter, Depends, Request, Response
from starlette.concurrency import run_in_threadpool

from app.errors import BackendError
from app.keto.models import AnalysisOptionsSnapshot, Menu, MenuAnalysed, VenueRef
from app.keto.models import to_json as model_to_json
from app.schemas import (
    ErrorResponse,
    ScanPage,
    WebsiteMenuRequest,
    WebsiteMenuResponse,
)
from app.services import menu_store
from app.services.auth import reject_authorization
from app.services.classify import ClassifyContext, classify, dart_now, scrubbed
from app.services.install_id import require_install_id
from app.services.scan import Scanned, scan
from app.services.website_fetch import WebsiteDocument, fetch_document
from app.website.adapter import (
    DISALLOWED_BY_ROBOTS,
    Failed,
    Located,
    NeedsFetch,
    PdfLink,
    finish_after_link,
    read_linked_page,
    read_page,
)
from app.website.html import DartUri, UriFormatError
from app.website.ref import website_ref

router = APIRouter()

logger = logging.getLogger("ketoclub.website_menu")

_CURRENCY: Final = "ILS"
"""``WebsiteMenuAdapter._currency``: a site's prices are never read."""

_READING_STATUS: Final[dict[str, int]] = {
    "jsOnlyPage": 422,
    "menuNotFound": 404,
}


def _reading_error(failed: Failed) -> BackendError:
    """A failed reading as the route's error. A page's own ``<meta>`` opt-out
    (the reader's ``disallowedByRobots``) is ``aiReserved``, as
    ``/v1/website/fetch`` names it; the client reads both alike."""
    if failed.reason == DISALLOWED_BY_ROBOTS:
        return BackendError(403, "aiReserved")
    return BackendError(_READING_STATUS.get(failed.reason, 404), failed.reason)


class _Context:
    """What one request's reading needs: the request, the install id (for
    the budgets only), the options and the one clock reading."""

    def __init__(
        self,
        request: Request,
        install_id: str,
        options: AnalysisOptionsSnapshot,
        now: datetime,
    ) -> None:
        self.request = request
        self.install_id = install_id
        self.options = options
        self.now = now
        self.now_text = dart_now(now)

    async def fetch(self, url: str) -> WebsiteDocument:
        return await fetch_document(
            self.request, url, self.install_id, judge_page=False
        )

    async def read_pdf(self, document: WebsiteDocument) -> Scanned:
        """``WebsiteMenuAdapter._readPdf``: the PDF through the scan path. A
        scan failure is 502 with its reason (``noDishesFound`` stays 422); a
        PDF the vision request cannot carry is 413 ``tooLarge``."""
        settings = self.request.app.state.settings
        if len(document.content) > settings.VISION_MAX_IMAGE_BYTES:
            raise BackendError(413, "tooLarge")
        page = ScanPage(
            mime_type="application/pdf",
            data=base64.b64encode(document.content).decode("ascii"),
        )
        try:
            return await scan(
                [page],
                self.options,
                ClassifyContext.of(self.request, self.install_id),
                now=self.now,
            )
        except BackendError as error:
            if error.reason == "noDishesFound":
                raise
            raise BackendError(502, error.reason) from None


async def _follow(context: _Context, url: DartUri) -> Located | Scanned:
    """``WebsiteMenuAdapter._followLink``: the one hop a menu link is worth.
    A PDF goes to the vision path; a page is read for JSON-LD or text but
    never followed further. Raises the hop's own error."""
    document = await context.fetch(url.remove_fragment().to_string())
    if document.kind == "pdf":
        return await context.read_pdf(document)
    linked = read_linked_page(
        document.page or "", _final_url(document), now=context.now_text
    )
    if isinstance(linked, Failed):
        raise _reading_error(linked)
    return linked


async def _read(context: _Context, document: WebsiteDocument) -> Located | Scanned:
    """``WebsiteMenuAdapter.fetch`` once the pasted page is in hand."""
    if document.kind == "pdf":
        return await context.read_pdf(document)
    reading = read_page(document.page or "", _final_url(document), now=context.now_text)
    if isinstance(reading, Failed):
        raise _reading_error(reading)
    if isinstance(reading, Located):
        return reading
    return await _after_link(context, reading)


async def _after_link(
    context: _Context, pending: NeedsFetch | PdfLink
) -> Located | Scanned:
    try:
        return await _follow(context, pending.url)
    except BackendError as error:
        link_failure = Failed(error.reason)
        finished = finish_after_link(pending, link_failure)
        if finished is link_failure:
            raise
    if isinstance(finished, Failed):
        raise _reading_error(finished)
    return finished


def _final_url(document: WebsiteDocument) -> DartUri:
    try:
        return DartUri.parse(document.final_url)
    except UriFormatError:  # pragma: no cover - urlsplit accepted it already
        raise BackendError(400, "invalidUrl") from None


def _stamped(ref: VenueRef, menu: Menu, now_text: str) -> Menu:
    """``WebsiteMenuAdapter._stamp``: the categories under ``ref``, priced
    in ILS, fetched now; any lone surrogate a page carried becomes U+FFFD."""
    raw = scrubbed(model_to_json(menu.model_copy(update={"venue_ref": ref})))
    raw["currency"] = _CURRENCY
    raw["fetchedAt"] = now_text
    raw["venueName"] = None
    return Menu.model_validate(raw)


async def _store(request: Request, menu: Menu, analysis: MenuAnalysed) -> None:
    """Upsert the shared menu store's row for ``menu`` (D24), when enabled.

    The analysis goes in without its ``options``, as the client's own upload
    sends it; nothing here can carry the install id. A failure is logged and
    swallowed: the store is a side effect, never the answer.
    """
    if not request.app.state.settings.MENU_STORE_ENABLED:
        return
    shared = model_to_json(analysis)
    shared.pop("options", None)
    try:
        await run_in_threadpool(
            lambda: menu_store.upsert(
                request.app.state.engine,
                source=menu.venue_ref.source,
                platform_id=menu.venue_ref.platform_id,
                venue_name=None,
                city=None,
                menu=model_to_json(menu),
                analysis=shared,
                now=datetime.now(UTC),
            )
        )
    except Exception:  # noqa: BLE001 - a side effect must not fail the read
        logger.warning("website_menu store failed")


@router.post(
    "/website-menu",
    response_model=WebsiteMenuResponse,
    dependencies=[Depends(reject_authorization)],
    responses={
        status: {"model": ErrorResponse}
        for status in (400, 403, 404, 413, 415, 422, 429, 502, 504)
    },
)
async def read_website_menu(
    request: Request,
    response: Response,
    body: WebsiteMenuRequest,
    install_id: Annotated[str, Depends(require_install_id)],
) -> WebsiteMenuResponse:
    """The menu on the body's site, and its analysis."""
    url = body.url.strip()
    ref = website_ref(url)
    if ref is None:
        raise BackendError(400, "invalidUrl")
    now = datetime.now(UTC)
    options = body.options.snapshot()
    context = _Context(request, install_id, options, now)

    try:
        found = await _read(context, await context.fetch(ref.platform_id))
    except BackendError as error:
        logger.info("website_menu outcome=%s", error.reason)
        raise

    analysis: MenuAnalysed | None
    if isinstance(found, Scanned):
        menu = _stamped(ref, found.menu, context.now_text)
        analysis = found.analysis
        response.headers["X-KetoClub-Cache"] = "bypass"
    else:
        menu = _stamped(ref, found.to_menu(ref, now=context.now_text), context.now_text)
        result = await classify(
            menu,
            options,
            ClassifyContext.of(request, install_id),
            when_rate_limited="rules",
            now=now,
        )
        analysis = None if result is None else result.analysis
        response.headers["X-KetoClub-Cache"] = (
            "bypass" if result is None else result.cache
        )
    if analysis is not None:
        await _store(request, menu, analysis)
    logger.info(
        "website_menu outcome=menu source=%s classified=%s",
        "pdf" if isinstance(found, Scanned) else "page",
        analysis is not None,
    )
    return WebsiteMenuResponse(menu=menu, analysis=analysis)

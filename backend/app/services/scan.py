"""Server-side menu scanning: pages read and classified in one Gemini request
(D15, D22, D25; #334).

:func:`scan` is the one path ``POST /v1/scan`` and a website's PDF menu
(``POST /v1/website-menu``) take, and it mirrors the client's
``VisionMenuClassifier`` (``lib/services/classifier/
vision_menu_classifier.dart``):

1. No server key is 503 ``notConfigured``, with no bucket spent: no Gemini
   call was about to be made.
2. The analysis bucket is spent, always: pages are images, which never
   touch any cache, so every scan is a Gemini call. An empty bucket is 429
   ``rateLimited``.
3. ``app.services.gemini.complete`` with the vision prompt and schema
   (``app.keto.prompt``) and every page as an ``inline_data`` part, then
   ``app.keto.parser.parse_scanned`` with the page count. A Gemini failure
   is raised with its own status and reason (503 ``notConfigured``, 502
   ``offline``, 504 ``timeout``, 429 ``rateLimited``, 502 ``badResponse``):
   **there is no rules fallback** (D15), since the rule engine needs text a
   photograph does not have. An unusable reply is 502 ``badResponse``; a
   reply naming no dish is 422 ``noDishesFound``.

The menu is addressed ``scan/<fingerprint hex>`` (D18, D23) and every dish
carries its ``page`` (D22); the analysis carries the request's options
snapshot and ``schemaVersion`` 1, so the client's checks accept it as one it
made itself. A lone surrogate the reply carried becomes U+FFFD before the
menu is fingerprinted, so the ref is the one the client would compute over
what it receives.

Pages are forwarded and dropped: nothing here stores or logs them beyond
their count. The install id keys the analysis bucket and nothing else.
"""

import logging
from collections.abc import Sequence
from dataclasses import dataclass
from datetime import UTC, datetime

from pydantic import ValidationError

from app.errors import BackendError
from app.keto import parser, prompt
from app.keto.fingerprint import scan_ref
from app.keto.models import (
    AnalysisOptionsSnapshot,
    LlmEngine,
    Menu,
    MenuAnalysed,
    to_json,
)
from app.schemas import ChatRequest, ImagePart, ScanPage
from app.services import gemini
from app.services.classify import ClassifyContext, dart_now, scrubbed

logger = logging.getLogger("ketoclub.scan")


@dataclass(frozen=True, slots=True)
class Scanned:
    """The menu read from the pages, and its analysis."""

    menu: Menu
    analysis: MenuAnalysed


async def scan(
    pages: Sequence[ScanPage],
    options: AnalysisOptionsSnapshot,
    context: ClassifyContext,
    *,
    now: datetime | None = None,
) -> Scanned:
    """``pages`` transcribed and classified under ``options``, or a
    ``BackendError`` (see the module docstring). The caller bounds the pages
    (``VISION_MAX_IMAGES``, ``VISION_MAX_IMAGE_BYTES``)."""
    page_count = len(pages)
    if page_count == 0:
        raise BackendError(422, "noDishesFound")
    settings = context.settings
    if not settings.llm_configured:
        logger.info("scan pages=%d outcome=notConfigured", page_count)
        raise BackendError(503, "notConfigured")
    if not context.limiter.allow(context.install_id):
        logger.info("scan pages=%d outcome=rateLimited", page_count)
        raise BackendError(429, "rateLimited")

    request = ChatRequest.model_construct(
        system_prompt=prompt.vision_system_prompt(page_count, options),
        user_prompt=prompt.vision_user_prompt(page_count),
        response_schema=prompt.vision_response_schema(),
        schema_name=prompt.SCHEMA_NAME,
        images=[
            ImagePart.model_construct(mime_type=page.mime_type, data=page.data)
            for page in pages
        ],
    )
    try:
        reply = await gemini.complete(context.http_client, settings, request)
    except BackendError as error:
        logger.info("scan pages=%d outcome=%s", page_count, error.reason)
        raise

    parsed = parser.parse_scanned(
        reply.content,
        engine=LlmEngine(model=reply.model),
        analysed_at=dart_now(now or datetime.now(UTC)),
        net_carb_limit_grams=options.net_carb_limit_grams,
        page_count=page_count,
    )
    if isinstance(parsed, parser.Failed):
        logger.info("scan pages=%d outcome=%s", page_count, parsed.reason)
        status = 422 if parsed.reason == "noDishesFound" else 502
        raise BackendError(status, parsed.reason)

    finished = _finished(parsed, options)
    if finished is None:
        logger.info("scan pages=%d outcome=badResponse", page_count)
        raise BackendError(502, "badResponse")
    logger.info(
        "scan pages=%d engine=llm dishes=%d unclassified=%d",
        page_count,
        len(finished.analysis.dishes),
        len(finished.analysis.unclassified),
    )
    return finished


def _finished(
    read: parser.ScannedRead, options: AnalysisOptionsSnapshot
) -> Scanned | None:
    """The parser's read validated as wire models, lone surrogates replaced,
    the menu re-addressed by its (scrubbed) fingerprint and the analysis
    given ``options``; ``None`` when either does not validate."""
    try:
        menu = Menu.model_validate(scrubbed(to_json(read.menu)))
        analysis = MenuAnalysed.model_validate(
            scrubbed(to_json(read.analysis.model_copy(update={"options": options})))
        )
    except ValidationError:
        return None
    return Scanned(
        menu=menu.model_copy(update={"venue_ref": scan_ref(menu)}),
        analysis=analysis,
    )

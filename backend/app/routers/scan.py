"""``POST /scan``: photographed or PDF pages of one menu, read and analysed in
one Gemini request (D15, D22, D25; #334).

The body is ``ScanRequest {pages: [{mimeType, data}], options}``: each page
one of ``image/jpeg``, ``image/png``, ``image/webp`` or ``application/pdf``
(anything else is 422), ``data`` strict standard base64. The body is read by
hand under a cap sized for the largest valid request (every allowed page at
``VISION_MAX_IMAGE_BYTES``, plus base64's third and some slack), so a larger
one is 413 ``payloadTooLarge`` before any parsing; a valid-sized body with
more than ``VISION_MAX_IMAGES`` pages, or a page over
``VISION_MAX_IMAGE_BYTES`` once decoded, is FastAPI's 422.

The answer is ``ScannedMenuResponse {menu, analysis}``, from
``app.services.scan.scan``: ``menu.venueRef`` is ``scan/<fingerprint hex>``
and every dish carries its ``page``. There is **no rules fallback** (D15):
a Gemini failure is ``/v1/chat``'s status and reason (503
``notConfigured``, 502 ``offline``/``badResponse``, 504 ``timeout``, 429
``rateLimited``), an empty analysis bucket is 429 ``rateLimited`` and a
reply naming no dish is 422 ``noDishesFound``. Every scan spends the
analysis bucket (images are never cached: ``X-KetoClub-Cache: bypass``).
This route never writes ``stored_menus``: the client's own upload rule
covers a scan.
"""

from typing import Annotated, Any, Final

from fastapi import APIRouter, Depends, Request, Response
from fastapi.exceptions import RequestValidationError

from app.config import Settings
from app.schemas import MAX_SCAN_PAGES, ErrorResponse, ScannedMenuResponse, ScanRequest
from app.services.auth import reject_authorization
from app.services.classify import ClassifyContext
from app.services.install_id import require_install_id
from app.services.request_body import parse_body, read_capped_body
from app.services.scan import scan

router = APIRouter()

# Per page: the JSON around one ``{mimeType, data}`` object. For the whole
# body: the options and the braces, with room to spare.
_PAGE_OVERHEAD_BYTES: Final = 256
_BODY_OVERHEAD_BYTES: Final = 64 * 1024

# The body is read by hand, so the schema is declared for the OpenAPI page.
_OPENAPI: dict[str, Any] = {
    "requestBody": {
        "required": True,
        "content": {
            "application/json": {"schema": ScanRequest.model_json_schema(by_alias=True)}
        },
    }
}


def max_scan_body_bytes(settings: Settings) -> int:
    """The largest body a valid scan can be: every allowed page at
    ``VISION_MAX_IMAGE_BYTES``, base64-encoded (4 characters per 3 bytes,
    padded), plus the JSON around it."""
    pages = min(settings.VISION_MAX_IMAGES, MAX_SCAN_PAGES)
    encoded_page = 4 * -(-settings.VISION_MAX_IMAGE_BYTES // 3)
    return pages * (encoded_page + _PAGE_OVERHEAD_BYTES) + _BODY_OVERHEAD_BYTES


@router.post(
    "/scan",
    response_model=ScannedMenuResponse,
    dependencies=[Depends(reject_authorization)],
    responses={
        status: {"model": ErrorResponse}
        for status in (400, 413, 422, 429, 502, 503, 504)
    },
    openapi_extra=_OPENAPI,
)
async def scan_menu(
    request: Request,
    response: Response,
    install_id: Annotated[str, Depends(require_install_id)],
) -> ScannedMenuResponse:
    """The menu the body's pages show, and its analysis."""
    settings: Settings = request.app.state.settings
    raw = await read_capped_body(request, max_scan_body_bytes(settings))
    body = parse_body(ScanRequest, raw)
    violation = body.page_bound_violation(
        settings.VISION_MAX_IMAGES, settings.VISION_MAX_IMAGE_BYTES
    )
    if violation is not None:
        # FastAPI's own 422 shape; the message names the bound, never a page.
        raise RequestValidationError(
            [
                {
                    "type": "value_error",
                    "loc": ("body", "pages"),
                    "msg": violation,
                    "input": None,
                }
            ]
        )

    result = await scan(
        body.pages,
        body.options.snapshot(),
        ClassifyContext.of(request, install_id),
    )
    response.headers["X-KetoClub-Cache"] = "bypass"
    return ScannedMenuResponse(menu=result.menu, analysis=result.analysis)

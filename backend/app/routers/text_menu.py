"""``POST /text-menu``: a menu pasted as text, read and analysed (D18, D25,
#333).

The body is ``TextMenuRequest {text, options}``; the text is read by the
port of the Dart ``TextMenuSource`` (``app.keto.text_menu.parse``), so the
menu, its dish ids and its ``scan/<fingerprint hex>`` ref are exactly what
the app's own paste path produces (D18, D23), and pasting the same dishes on
any device is one cache entry there and one analysis-cache entry here.

Text with no dish in it is 422 ``noDishesFound`` with nothing spent. The
analysis is ``app.services.classify.classify``'s; an empty analysis bucket
is 429 ``rateLimited`` (the analysis is this route's only product). This
route never writes ``stored_menus``.
"""

from datetime import UTC, datetime
from typing import Annotated

from fastapi import APIRouter, Depends, Request, Response

from app.errors import BackendError
from app.keto import text_menu
from app.schemas import ErrorResponse, ScannedMenuResponse, TextMenuRequest
from app.services.auth import reject_authorization
from app.services.classify import ClassifyContext, classify, dart_now
from app.services.install_id import require_install_id

router = APIRouter()


@router.post(
    "/text-menu",
    response_model=ScannedMenuResponse,
    dependencies=[Depends(reject_authorization)],
    responses={status: {"model": ErrorResponse} for status in (400, 422, 429)},
)
async def read_text_menu(
    request: Request,
    response: Response,
    body: TextMenuRequest,
    install_id: Annotated[str, Depends(require_install_id)],
) -> ScannedMenuResponse:
    """The menu the body's text describes, and its analysis."""
    now = datetime.now(UTC)
    menu = text_menu.parse(body.text, now=dart_now(now))
    if menu is None:
        raise BackendError(422, "noDishesFound")

    result = await classify(
        menu,
        body.options.snapshot(),
        ClassifyContext.of(request, install_id),
        when_rate_limited="refuse",
        now=now,
    )
    if result is None:  # pragma: no cover - parse never returns an empty menu
        raise BackendError(422, "noDishesFound")
    response.headers["X-KetoClub-Cache"] = result.cache
    return ScannedMenuResponse(menu=menu, analysis=result.analysis)

"""``POST /classify``: a menu the client already holds, analysed (D25, #333).

The body is ``ClassifyRequest {menu, options}`` (camelCase, the Dart
``Menu`` JSON verbatim) and the answer ``ClassifyResponse {analysis}``, a
Dart ``MenuAnalysed`` the client's ``BackendMenuClassifier`` reads with
``tryFrom``. The body is read by hand so its size is checked first: over
``CLASSIFY_MAX_BODY_BYTES`` (768 KiB) is 413 ``payloadTooLarge`` before any
parsing.

The analysis is ``app.services.classify.classify``'s: an analysis-cache hit
is free, a Gemini failure is the rules stamped with its reason (200, not an
error), and only an empty analysis bucket is an error, 429 ``rateLimited``:
the analysis is this route's only product, so the client falls back on
device instead. A menu with no dish is 422 ``noDishesFound``, with nothing
spent. This route never writes ``stored_menus``: the client's own upload
rule covers a menu it already held (``backend_plan.md`` §3.3).
"""

from typing import Annotated, Any

from fastapi import APIRouter, Depends, Request, Response

from app.errors import BackendError
from app.schemas import ClassifyRequest, ClassifyResponse, ErrorResponse
from app.services.auth import reject_authorization
from app.services.classify import ClassifyContext, classify
from app.services.install_id import require_install_id
from app.services.request_body import parse_body, read_capped_body

router = APIRouter()

# The body is read by hand, so the schema is declared for the OpenAPI page.
_OPENAPI: dict[str, Any] = {
    "requestBody": {
        "required": True,
        "content": {
            "application/json": {
                "schema": ClassifyRequest.model_json_schema(by_alias=True)
            }
        },
    }
}


@router.post(
    "/classify",
    response_model=ClassifyResponse,
    dependencies=[Depends(reject_authorization)],
    responses={status: {"model": ErrorResponse} for status in (400, 413, 422, 429)},
    openapi_extra=_OPENAPI,
)
async def classify_menu(
    request: Request,
    response: Response,
    install_id: Annotated[str, Depends(require_install_id)],
) -> ClassifyResponse:
    """The analysis of the body's menu under the body's options."""
    settings = request.app.state.settings
    raw = await read_capped_body(request, settings.CLASSIFY_MAX_BODY_BYTES)
    body = parse_body(ClassifyRequest, raw)

    result = await classify(
        body.menu,
        body.options.snapshot(),
        ClassifyContext.of(request, install_id),
        when_rate_limited="refuse",
    )
    if result is None:
        raise BackendError(422, "noDishesFound")
    response.headers["X-KetoClub-Cache"] = result.cache
    return ClassifyResponse(analysis=result.analysis)

"""``POST /chat``: hosted classification with the server's Gemini key (#100).

The body mirrors the Dart ``LlmChatClient.complete`` one to one. Every error
this route originates is a ``BackendError`` rendered as
``{reason, status_code}``; a malformed body is FastAPI's own 422.

A completion cached by request hash (#103) is served before the rate
limiter is ever consulted: a cache hit costs no upstream quota, so it must
not spend the install's either.

A request carrying ``images`` (menu pages, D15, #170) never touches that
cache: it is neither read nor written, the answer says
``X-KetoClub-Cache: bypass``, and it spends the limiter like any miss. Pages
are forwarded to Gemini and dropped; nothing here stores or logs them beyond
their count.

The body is read by hand under a size cap (#269): over
:func:`max_chat_body_bytes` is 413 ``payloadTooLarge`` before anything
parses it, and the image count and each part's encoded length are checked on
the parsed JSON before any part is base64-decoded.
"""

import json
import logging
from datetime import UTC, datetime
from typing import Annotated, Any, Final

from fastapi import APIRouter, Depends, Request, Response
from fastapi.exceptions import RequestValidationError
from starlette.concurrency import run_in_threadpool

from app.config import Settings
from app.errors import BackendError
from app.schemas import ChatRequest, ChatResponse, ErrorResponse
from app.services import chat_cache, gemini
from app.services.auth import reject_authorization
from app.services.install_id import log_safe, require_install_id
from app.services.rate_limit import RateLimiter
from app.services.request_body import parse_body, read_capped_body

router = APIRouter()

logger = logging.getLogger("ketoclub.chat")

_ERROR_RESPONSES: dict[int | str, dict[str, object]] = {
    status: {"model": ErrorResponse} for status in (400, 413, 429, 502, 503, 504)
}

# Per image part: the JSON around one ``{mime_type, data}`` object.
_IMAGE_OVERHEAD_BYTES: Final = 256

# The body is read by hand, so the schema is declared for the OpenAPI page.
_OPENAPI: dict[str, Any] = {
    "requestBody": {
        "required": True,
        "content": {"application/json": {"schema": ChatRequest.model_json_schema()}},
    }
}


def max_chat_body_bytes(settings: Settings) -> int:
    """The largest body a valid request can be: ``CHAT_MAX_TEXT_BODY_BYTES``
    for the prompts and schema, plus every allowed image at
    ``VISION_MAX_IMAGE_BYTES``, base64-encoded (4 characters per 3 bytes)."""
    encoded_image = 4 * -(-settings.VISION_MAX_IMAGE_BYTES // 3)
    images = settings.VISION_MAX_IMAGES * (encoded_image + _IMAGE_OVERHEAD_BYTES)
    return settings.CHAT_MAX_TEXT_BODY_BYTES + images


def _image_bound_error(violation: str) -> RequestValidationError:
    """FastAPI's own 422 shape; the message names the bound, never a part."""
    return RequestValidationError(
        [
            {
                "type": "value_error",
                "loc": ("body", "images"),
                "msg": violation,
                "input": None,
            }
        ]
    )


def _parse(raw: bytes, settings: Settings) -> ChatRequest:
    """``raw`` as a ``ChatRequest``, the image bounds checked before any
    part is decoded and again, exactly, after. Runs in a worker thread."""
    try:
        parsed: object = json.loads(raw)
    except ValueError:
        parsed = None  # Not JSON: the model's own validation says why.
    violation = ChatRequest.raw_image_bound_violation(
        parsed, settings.VISION_MAX_IMAGES, settings.VISION_MAX_IMAGE_BYTES
    )
    if violation is not None:
        raise _image_bound_error(violation)
    body = parse_body(ChatRequest, raw)
    violation = body.image_bound_violation(
        settings.VISION_MAX_IMAGES, settings.VISION_MAX_IMAGE_BYTES
    )
    if violation is not None:
        raise _image_bound_error(violation)
    return body


@router.post(
    "/chat",
    response_model=ChatResponse,
    dependencies=[Depends(reject_authorization)],
    responses=_ERROR_RESPONSES,
    openapi_extra=_OPENAPI,
)
async def chat(
    request: Request,
    response: Response,
    install_id: Annotated[str, Depends(require_install_id)],
) -> ChatResponse:
    """Forward one completion to Gemini, within the install's rate limit.

    A cache hit (#103) answers directly, before the rate limiter and before
    the no-key check, and never touches the install's quota. A request with
    images skips the cache both ways (#170).
    """
    settings: Settings = request.app.state.settings
    engine = request.app.state.engine
    raw = await read_capped_body(request, max_chat_body_bytes(settings))
    body = await run_in_threadpool(_parse, raw, settings)
    image_count = len(body.images)
    if image_count:
        # The count only: never a part's bytes, mime type or base64.
        logger.info("chat install_id=%s images=%d", log_safe(install_id), image_count)
    else:
        logger.info("chat install_id=%s", log_safe(install_id))

    key = None if image_count else chat_cache.cache_key(settings.GEMINI_MODEL, body)

    if key is not None:
        cached = await run_in_threadpool(
            chat_cache.read_cached,
            engine,
            key,
            settings.CHAT_CACHE_TTL_SECONDS,
            datetime.now(UTC),
        )
        if cached is not None:
            logger.info("chat install_id=%s cache=hit", log_safe(install_id))
            response.headers["X-KetoClub-Cache"] = "hit"
            return cached

    limiter: RateLimiter = request.app.state.rate_limiter
    if not limiter.allow(install_id):
        logger.info("chat install_id=%s rate limited", log_safe(install_id))
        raise BackendError(429, "rateLimited")

    result = await gemini.complete(request.app.state.http_client, settings, body)

    if key is None:
        logger.info("chat install_id=%s cache=bypass", log_safe(install_id))
        response.headers["X-KetoClub-Cache"] = "bypass"
        return result

    await run_in_threadpool(
        chat_cache.write_cached, engine, key, result, datetime.now(UTC)
    )
    logger.info("chat install_id=%s cache=miss", log_safe(install_id))
    response.headers["X-KetoClub-Cache"] = "miss"
    return result

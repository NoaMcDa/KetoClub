"""``POST /chat``: hosted classification with the server's Gemini key (#100).

The body mirrors the Dart ``LlmChatClient.complete`` one to one. Every error
this route originates is a ``BackendError`` rendered as
``{reason, status_code}``; a malformed body is FastAPI's own 422.

A completion cached by request hash (#103) is served before the rate
limiter is ever consulted: a cache hit costs no upstream quota, so it must
not spend the install's either.
"""

import logging
from datetime import UTC, datetime
from typing import Annotated

from fastapi import APIRouter, Depends, Header, Request, Response
from starlette.concurrency import run_in_threadpool

from app.errors import BackendError
from app.schemas import ChatRequest, ChatResponse, ErrorResponse
from app.services import chat_cache, gemini
from app.services.install_id import log_safe, require_install_id
from app.services.rate_limit import RateLimiter

router = APIRouter()

logger = logging.getLogger("ketoclub.chat")


def reject_authorization(
    authorization: Annotated[str | None, Header()] = None,
) -> None:
    """400 ``badResponse`` for any inbound ``Authorization`` header.

    The backend holds the key; a client sending one is either confused or
    trying to have its own credential forwarded, and neither is served.
    Declared as a route-level dependency so it runs before anything else,
    body validation included.
    """
    if authorization is not None:
        raise BackendError(400, "badResponse")


_ERROR_RESPONSES: dict[int | str, dict[str, object]] = {
    status: {"model": ErrorResponse} for status in (400, 429, 502, 503, 504)
}


@router.post(
    "/chat",
    response_model=ChatResponse,
    dependencies=[Depends(reject_authorization)],
    responses=_ERROR_RESPONSES,
)
async def chat(
    request: Request,
    response: Response,
    body: ChatRequest,
    install_id: Annotated[str, Depends(require_install_id)],
) -> ChatResponse:
    """Forward one completion to Gemini, within the install's rate limit.

    A cache hit (#103) answers directly, before the rate limiter and before
    the no-key check, and never touches the install's quota.
    """
    logger.info("chat install_id=%s", log_safe(install_id))

    settings = request.app.state.settings
    engine = request.app.state.engine
    key = chat_cache.cache_key(settings.GEMINI_MODEL, body)

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

    await run_in_threadpool(
        chat_cache.write_cached, engine, key, result, datetime.now(UTC)
    )
    logger.info("chat install_id=%s cache=miss", log_safe(install_id))
    response.headers["X-KetoClub-Cache"] = "miss"
    return result

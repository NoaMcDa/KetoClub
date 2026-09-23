"""``POST /chat``: hosted classification with the server's Gemini key (#100).

The body mirrors the Dart ``LlmChatClient.complete`` one to one. Every error
this route originates is a ``BackendError`` rendered as
``{reason, status_code}``; a malformed body is FastAPI's own 422.
"""

import logging
from typing import Annotated

from fastapi import APIRouter, Depends, Header, Request

from app.errors import BackendError
from app.schemas import ChatRequest, ChatResponse, ErrorResponse
from app.services import gemini
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
    body: ChatRequest,
    install_id: Annotated[str, Depends(require_install_id)],
) -> ChatResponse:
    """Forward one completion to Gemini, within the install's rate limit."""
    logger.info("chat install_id=%s", log_safe(install_id))

    # #103 serves a chat_cache hit here, before the limiter: a cached
    # completion costs no upstream quota, so it must not spend the install's.
    limiter: RateLimiter = request.app.state.rate_limiter
    if not limiter.allow(install_id):
        logger.info("chat install_id=%s rate limited", log_safe(install_id))
        raise BackendError(429, "rateLimited")

    return await gemini.complete(
        request.app.state.http_client, request.app.state.settings, body
    )

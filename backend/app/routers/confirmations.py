"""``POST /confirmations``: anonymous post-meal facts about a dish (ALG-14, #356).

A user who asked the kitchen "is there sesame in this dish?" may tell KetoClub
what they were told. The body is one fact, ``{venue, dishFingerprint,
restrictionId, polarity}``; the route counts it in ``dish_confirmations``
(``app.services.confirmations``) and ``GET /v1/venue-menus`` serves the counts
that have reached three distinct confirmations.

**What is refused.** Any ``installId``/``install_id``, any ``note``/``notes``
and any restriction-profile key is a 422, as is any unknown field or a
``restrictionId`` outside the shipped taxonomy (``app.schemas``). Nothing
profile-shaped is accepted (Banto C1): one restriction id about one dish.

**What the install id is for.** ``X-KetoClub-Install-Id`` is required and does
two things: it spends this route's own per-install rate limit, and it is
turned into a one-way token that tells a repeat from a new confirmer
(``app.services.confirmations.voter_token``). It is ``del``-ed straight after
and is never stored, logged (not even truncated) or passed to the service.

The body is read by hand, like ``/v1/menus``, so its size is capped before
anything parses it: over ``MAX_BODY_BYTES`` is a 413 ``payloadTooLarge``. A
body that does not validate is FastAPI's usual 422 and spends no quota.
``create_app`` mounts this router only when ``CONFIRMATIONS_ENABLED`` is true.
"""

import logging
from datetime import UTC, datetime
from typing import Annotated, Any, Final

from fastapi import APIRouter, Depends, Request, Response, status
from fastapi.exceptions import RequestValidationError
from pydantic import ValidationError
from starlette.concurrency import run_in_threadpool

from app.errors import BackendError
from app.schemas import (
    ConfirmationRecordedResponse,
    ConfirmationRequest,
    ErrorResponse,
)
from app.services import confirmations
from app.services.auth import reject_authorization
from app.services.install_id import require_install_id
from app.services.rate_limit import RateLimiter

router = APIRouter()

logger = logging.getLogger("ketoclub.confirmations")

MAX_BODY_BYTES: Final = 4096
"""A confirmation is a few hundred bytes; anything near this is not one."""

_POST_ERRORS: dict[int | str, dict[str, Any]] = {
    status_code: {"model": ErrorResponse} for status_code in (400, 413, 429)
}

# The body is read by hand, so the schema is declared for the OpenAPI page.
_POST_OPENAPI: dict[str, Any] = {
    "requestBody": {
        "required": True,
        "content": {
            "application/json": {"schema": ConfirmationRequest.model_json_schema()}
        },
    }
}


async def _read_capped_body(request: Request) -> bytes:
    """The request body, or 413 ``payloadTooLarge`` once it passes the cap."""
    declared = request.headers.get("content-length")
    if declared is not None and declared.isdigit() and int(declared) > MAX_BODY_BYTES:
        raise BackendError(413, "payloadTooLarge")
    chunks: list[bytes] = []
    received = 0
    async for chunk in request.stream():
        received += len(chunk)
        if received > MAX_BODY_BYTES:
            raise BackendError(413, "payloadTooLarge")
        chunks.append(chunk)
    return b"".join(chunks)


def _parse(raw: bytes) -> ConfirmationRequest:
    """``raw`` as a ``ConfirmationRequest``, or FastAPI's 422 shape."""
    try:
        return ConfirmationRequest.model_validate_json(raw)
    except ValidationError as error:
        raise RequestValidationError(
            [
                {**entry, "loc": ("body", *entry.get("loc", ()))}
                for entry in error.errors(include_url=False)
            ]
        ) from None


@router.post(
    "/confirmations",
    response_model=ConfirmationRecordedResponse,
    status_code=status.HTTP_201_CREATED,
    dependencies=[Depends(reject_authorization)],
    responses={
        status.HTTP_200_OK: {
            "model": ConfirmationRecordedResponse,
            "description": "This install had already confirmed this fact",
        },
        **_POST_ERRORS,
    },
    openapi_extra=_POST_OPENAPI,
)
async def confirm_dish(
    request: Request,
    response: Response,
    install_id: Annotated[str, Depends(require_install_id)],
) -> ConfirmationRecordedResponse:
    """Count one confirmation (201), or recognise a repeat of it (200)."""
    settings = request.app.state.settings
    body = _parse(await _read_capped_body(request))

    limiter: RateLimiter = request.app.state.confirmation_rate_limiter
    if not limiter.allow(install_id):
        logger.info("confirmations rate limited")
        raise BackendError(429, "rateLimited")
    token = confirmations.voter_token(
        settings.CONFIRMATION_PEPPER,
        install_id,
        source=body.venue.source,
        platform_id=body.venue.platform_id,
        dish_fingerprint=body.dish_fingerprint,
        restriction_id=body.restriction_id,
        polarity=body.polarity,
    )
    # From here on the install id is out of scope: nothing below can store
    # or log it.
    del install_id

    counted = await run_in_threadpool(
        lambda: confirmations.record(
            request.app.state.engine,
            source=body.venue.source,
            platform_id=body.venue.platform_id,
            dish_fingerprint=body.dish_fingerprint,
            restriction_id=body.restriction_id,
            polarity=body.polarity,
            token=token,
            today=datetime.now(UTC).date(),
        )
    )

    # No venue, dish or restriction in the log line: only what happened.
    logger.info("confirmations counted=%s polarity=%s", counted, body.polarity)
    if not counted:
        response.status_code = status.HTTP_200_OK
    return ConfirmationRecordedResponse(counted=counted)

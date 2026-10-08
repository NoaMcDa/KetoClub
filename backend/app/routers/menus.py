"""``/menus``: the anonymous shared store of opened menus (#310).

``POST /menus`` stores one menu a user opened, keyed by
``(source, platform_id)``; ``GET /menus/{source}/{platform_id}`` reads it
back. Rows are keyed by venue, never by install id (D12, #164): the
``X-KetoClub-Install-Id`` the POST requires spends the per-install rate
limiter and is then dropped. It is never logged here, not even truncated
through ``log_safe``, and never passed to ``app.services.menu_store``.

The POST body is read by hand rather than declared as a parameter, so its
size is checked (``Content-Length`` first, then the bytes actually read)
before anything parses it: over ``MENU_STORE_MAX_BODY_BYTES`` is a 413
``payloadTooLarge``. A body that does not validate is FastAPI's usual 422
and spends no quota. ``create_app`` mounts this router only when
``MENU_STORE_ENABLED`` is true; otherwise both routes are a plain 404.
"""

import logging
from datetime import UTC, datetime
from typing import Annotated, Any

from fastapi import APIRouter, Depends, Path, Request, Response, status
from fastapi.exceptions import RequestValidationError
from pydantic import ValidationError
from starlette.concurrency import run_in_threadpool

from app.errors import BackendError
from app.schemas import (
    MENU_STORE_MAX_PLATFORM_ID,
    ErrorResponse,
    MenuStoredResponse,
    MenuStoreSource,
    MenuUploadRequest,
    StoredMenuResponse,
)
from app.services import menu_store
from app.services.auth import reject_authorization
from app.services.install_id import require_install_id
from app.services.rate_limit import RateLimiter

router = APIRouter()

logger = logging.getLogger("ketoclub.menus")

_POST_ERRORS: dict[int | str, dict[str, Any]] = {
    status_code: {"model": ErrorResponse} for status_code in (400, 413, 429)
}

# The body is read by hand, so the schema is declared for the OpenAPI page.
_POST_OPENAPI: dict[str, Any] = {
    "requestBody": {
        "required": True,
        "content": {
            "application/json": {"schema": MenuUploadRequest.model_json_schema()}
        },
    }
}


async def _read_capped_body(request: Request, max_bytes: int) -> bytes:
    """The request body, or 413 ``payloadTooLarge`` once it passes ``max_bytes``.

    A declared ``Content-Length`` over the cap is refused before a byte is
    read; a body without one (or lying about it) is refused as soon as the
    bytes read pass the cap, so an oversized upload is never held whole.
    """
    declared = request.headers.get("content-length")
    if declared is not None and declared.isdigit() and int(declared) > max_bytes:
        raise BackendError(413, "payloadTooLarge")
    chunks: list[bytes] = []
    received = 0
    async for chunk in request.stream():
        received += len(chunk)
        if received > max_bytes:
            raise BackendError(413, "payloadTooLarge")
        chunks.append(chunk)
    return b"".join(chunks)


def _body_error(loc: tuple[str, ...], msg: str) -> RequestValidationError:
    return RequestValidationError(
        [{"type": "value_error", "loc": loc, "msg": msg, "input": None}]
    )


def _parse(raw: bytes) -> MenuUploadRequest:
    """``raw`` as a ``MenuUploadRequest``, or FastAPI's 422 shape."""
    try:
        return MenuUploadRequest.model_validate_json(raw)
    except ValidationError as error:
        raise RequestValidationError(
            [
                {**entry, "loc": ("body", *entry.get("loc", ()))}
                for entry in error.errors(include_url=False)
            ]
        ) from None


@router.post(
    "/menus",
    response_model=MenuStoredResponse,
    status_code=status.HTTP_201_CREATED,
    dependencies=[Depends(reject_authorization)],
    responses={
        status.HTTP_200_OK: {
            "model": MenuStoredResponse,
            "description": "The menu was already stored and has been refreshed",
        },
        **_POST_ERRORS,
    },
    openapi_extra=_POST_OPENAPI,
)
async def store_menu(
    request: Request,
    response: Response,
    install_id: Annotated[str, Depends(require_install_id)],
) -> MenuStoredResponse:
    """Insert (201) or refresh (200) the stored menu for the body's venue."""
    settings = request.app.state.settings
    raw = await _read_capped_body(request, settings.MENU_STORE_MAX_BODY_BYTES)
    body = _parse(raw)

    limiter: RateLimiter = request.app.state.rate_limiter
    if not limiter.allow(install_id):
        logger.info("menus store rate limited")
        raise BackendError(429, "rateLimited")
    # From here on the install id is out of scope: nothing below can store
    # or log it.
    del install_id

    try:
        created, submission_count = await run_in_threadpool(
            lambda: menu_store.upsert(
                request.app.state.engine,
                source=body.source,
                platform_id=body.platform_id,
                venue_name=body.venue_name,
                city=body.city,
                menu=body.menu,
                analysis=body.analysis,
                now=datetime.now(UTC),
            )
        )
    except ValueError:
        raise _body_error(("body",), "NaN and Infinity are not JSON") from None

    logger.info("menus store source=%s created=%s", body.source, created)
    if not created:
        response.status_code = status.HTTP_200_OK
    return MenuStoredResponse(created=created, submission_count=submission_count)


@router.get(
    "/menus/{source}/{platform_id:path}",
    response_model=StoredMenuResponse,
    dependencies=[Depends(reject_authorization)],
    responses={status_code: {"model": ErrorResponse} for status_code in (400, 404)},
)
async def read_menu(
    request: Request,
    source: MenuStoreSource,
    platform_id: Annotated[
        str, Path(min_length=1, max_length=MENU_STORE_MAX_PLATFORM_ID)
    ],
) -> StoredMenuResponse:
    """The stored menu for ``(source, platform_id)``, or 404 ``menuNotFound``."""
    row = await run_in_threadpool(
        menu_store.get, request.app.state.engine, source, platform_id
    )
    if row is None:
        raise BackendError(404, "menuNotFound")
    analysis_json = row.analysis_json
    return StoredMenuResponse(
        source=source,
        platform_id=row.platform_id,
        venue_name=row.venue_name,
        city=row.city,
        menu=menu_store.from_json(row.menu_json),
        analysis=None if analysis_json is None else menu_store.from_json(analysis_json),
        dish_count=row.dish_count,
        score=row.score,
        first_seen_at=row.first_seen_at.replace(tzinfo=UTC),
        last_seen_at=row.last_seen_at.replace(tzinfo=UTC),
        submission_count=row.submission_count,
    )

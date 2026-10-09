"""Reading a request body by hand, under a size cap, into a pydantic model.

A route that declares its body as a parameter has it parsed whole before the
route runs; one with a size cap (``POST /v1/menus``'s 1 MiB, ``POST
/v1/classify``'s 768 KiB) reads it here instead, so an oversized body is a
413 ``payloadTooLarge`` before anything parses it, and a body that does not
validate is FastAPI's usual 422 shape.
"""

from fastapi.exceptions import RequestValidationError
from pydantic import BaseModel, ValidationError
from starlette.requests import Request

from app.errors import BackendError


async def read_capped_body(request: Request, max_bytes: int) -> bytes:
    """The request body, or 413 ``payloadTooLarge`` once it passes ``max_bytes``.

    A declared ``Content-Length`` over the cap is refused before a byte is
    read; a body without one (or lying about it) is refused as soon as the
    bytes read pass the cap, so an oversized body is never held whole.
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


def parse_body[M: BaseModel](model: type[M], raw: bytes) -> M:
    """``raw`` as ``model``, or FastAPI's 422 shape (which never echoes it)."""
    try:
        return model.model_validate_json(raw)
    except ValidationError as error:
        raise RequestValidationError(
            [
                {**entry, "loc": ("body", *entry.get("loc", ()))}
                for entry in error.errors(include_url=False)
            ]
        ) from None

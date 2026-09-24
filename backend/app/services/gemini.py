"""Gemini ``generateContent`` client for ``POST /v1/chat`` (#100).

Raw ``httpx`` over the app's shared ``AsyncClient``; no SDK. The server key is
sent only as the ``x-goog-api-key`` header, never as ``?key=`` in the URL, so
it cannot surface in an access log or an httpx log line.

Every failure is a ``BackendError`` whose ``reason`` is one of
``CHAT_FAILURE_REASONS``. Nothing here logs the key, prompt text or an
upstream body: only upstream status codes.
"""

import copy
import logging
from typing import Final

import httpx

from app.config import Settings
from app.errors import BackendError
from app.schemas import ChatRequest, ChatResponse

# The only ``reason`` values /v1/chat ever answers with. The Dart client
# parses them by name into ``ChatFailureReason``, so renaming one here is a
# breaking change to the app.
CHAT_FAILURE_REASONS: Final[tuple[str, ...]] = (
    "notConfigured",
    "offline",
    "timeout",
    "rateLimited",
    "badResponse",
)

# Read 110 s: the Dart client's own 120 s timeout is the outer bound, so the
# backend gives up first and answers ``timeout`` rather than being cut off.
UPSTREAM_TIMEOUT: Final = httpx.Timeout(connect=5.0, read=110.0, write=30.0, pool=5.0)

_INVALID_KEY_MARKER: Final = "API_KEY_INVALID"

logger = logging.getLogger("ketoclub.chat")
logger.setLevel(logging.INFO)
if not logger.handlers:
    # Attached directly, as in ``request_logging``: uvicorn configures only
    # its own loggers, so without this the chat lines would vanish.
    _handler = logging.StreamHandler()
    _handler.setFormatter(logging.Formatter("%(asctime)s %(name)s %(message)s"))
    logger.addHandler(_handler)


def to_gemini_schema(schema: dict[str, object]) -> dict[str, object]:
    """Convert a strict JSON schema to Gemini's OpenAPI-subset ``responseSchema``.

    - ``additionalProperties`` is dropped: Gemini's schema has no such field.
    - ``"type": [T, "null"]`` (either order) becomes ``"type": T`` plus
      ``"nullable": True``: Gemini takes one type name, not a union.
    - ``properties`` values and ``items`` are converted recursively.
    - Everything else (``enum``, ``required``, ``description``, ...) is kept.

    Pure: the input is never mutated and the output shares no mutable value
    with it.
    """
    converted: dict[str, object] = {}
    for key, value in schema.items():
        if key == "additionalProperties":
            continue
        if key == "type" and isinstance(value, list):
            non_null = [t for t in value if t != "null"]
            if len(non_null) == 1:
                converted["type"] = non_null[0]
                if len(non_null) < len(value):
                    converted["nullable"] = True
                continue
        if key == "properties" and isinstance(value, dict):
            converted[key] = {
                name: to_gemini_schema(sub) if isinstance(sub, dict) else sub
                for name, sub in value.items()
            }
            continue
        if key == "items" and isinstance(value, dict):
            converted[key] = to_gemini_schema(value)
            continue
        converted[key] = copy.deepcopy(value)
    return converted


async def complete(
    client: httpx.AsyncClient, settings: Settings, request: ChatRequest
) -> ChatResponse:
    """Forward ``request`` to Gemini and return its text, or raise ``BackendError``.

    The retry rule is the one D4 carried over from the m15 post-mortems (the
    Dart client that predated the backend applied it too): a request carrying a
    schema that is answered 400, for any reason other than an invalid key, is
    re-sent exactly once with ``responseMimeType`` only. 401, 403, 429 and 5xx
    are answers about the key, the quota or the provider and are never
    re-sent; neither is a second 400.
    """
    if not settings.GEMINI_API_KEY:
        raise BackendError(503, "notConfigured")

    url = (
        f"{settings.GEMINI_BASE_URL}/v1beta/models/"
        f"{settings.GEMINI_MODEL}:generateContent"
    )
    headers = {
        "x-goog-api-key": settings.GEMINI_API_KEY,
        "Content-Type": "application/json",
    }
    schema = (
        to_gemini_schema(request.response_schema)
        if request.response_schema is not None
        else None
    )

    response = await _post(client, url, headers, _body(settings, request, schema))
    if (
        schema is not None
        and response.status_code == 400
        and not _is_invalid_key(response)
    ):
        logger.info("gemini upstream_status=400 retrying without responseSchema")
        response = await _post(client, url, headers, _body(settings, request, None))

    return _read(response, settings)


def _body(
    settings: Settings, request: ChatRequest, schema: dict[str, object] | None
) -> dict[str, object]:
    generation_config: dict[str, object] = {
        "responseMimeType": "application/json",
        "maxOutputTokens": settings.GEMINI_MAX_OUTPUT_TOKENS,
        "temperature": 0,
        "thinkingConfig": {"thinkingBudget": settings.GEMINI_THINKING_BUDGET},
    }
    if schema is not None:
        generation_config["responseSchema"] = schema
    return {
        "system_instruction": {"parts": [{"text": request.system_prompt}]},
        "contents": [{"role": "user", "parts": [{"text": request.user_prompt}]}],
        "generationConfig": generation_config,
    }


async def _post(
    client: httpx.AsyncClient,
    url: str,
    headers: dict[str, str],
    body: dict[str, object],
) -> httpx.Response:
    try:
        response = await client.post(
            url, headers=headers, json=body, timeout=UPSTREAM_TIMEOUT
        )
    except httpx.TimeoutException as error:
        logger.info("gemini upstream timeout")
        raise BackendError(504, "timeout") from error
    except httpx.NetworkError as error:
        # ConnectError, and a connection dropped mid-exchange: no route.
        logger.info("gemini upstream unreachable")
        raise BackendError(502, "offline") from error
    except httpx.TransportError as error:
        # A protocol-level failure: the upstream answered something unusable.
        logger.info("gemini upstream transport error")
        raise BackendError(502, "badResponse") from error
    logger.info("gemini upstream_status=%d", response.status_code)
    return response


def _is_invalid_key(response: httpx.Response) -> bool:
    """Whether a 400 is Gemini's "API key not valid" rather than a bad request."""
    try:
        body: object = response.json()
    except ValueError:
        return False
    if not isinstance(body, dict):
        return False
    error = body.get("error")
    if not isinstance(error, dict):
        return False

    status = error.get("status")
    if isinstance(status, str) and _INVALID_KEY_MARKER in status:
        return True
    message = error.get("message")
    if isinstance(message, str) and (
        _INVALID_KEY_MARKER in message or "api key not valid" in message.lower()
    ):
        return True
    details = error.get("details")
    if isinstance(details, list):
        for detail in details:
            if isinstance(detail, dict) and detail.get("reason") == (
                _INVALID_KEY_MARKER
            ):
                return True
    return False


def _read(response: httpx.Response, settings: Settings) -> ChatResponse:
    status = response.status_code
    if status in (401, 403) or (status == 400 and _is_invalid_key(response)):
        # The *server's* key was refused: to the app this is "the backend has
        # no working key", never "your key was rejected".
        raise BackendError(503, "notConfigured")
    if status == 429:
        raise BackendError(429, "rateLimited")
    if status != 200:
        raise BackendError(502, "badResponse")

    try:
        body: object = response.json()
    except ValueError as error:
        raise BackendError(502, "badResponse") from error
    if not isinstance(body, dict):
        raise BackendError(502, "badResponse")

    content = _candidate_text(body.get("candidates"))
    if content is None:
        raise BackendError(502, "badResponse")

    model_version = body.get("modelVersion")
    model = (
        model_version
        if isinstance(model_version, str) and model_version
        else settings.GEMINI_MODEL
    )
    return ChatResponse(content=content, model=model)


def _candidate_text(candidates: object) -> str | None:
    """The first candidate's joined text, or None when it is unusable.

    Unusable: no candidate, a ``finishReason`` other than ``STOP`` (a
    ``MAX_TOKENS`` reply is truncated JSON; a ``SAFETY`` one is empty), or no
    non-empty text part. Parts flagged ``thought`` are the model's reasoning,
    not its answer, and are skipped.
    """
    if not isinstance(candidates, list) or not candidates:
        return None
    first = candidates[0]
    if not isinstance(first, dict) or first.get("finishReason") != "STOP":
        return None
    content = first.get("content")
    if not isinstance(content, dict):
        return None
    parts = content.get("parts")
    if not isinstance(parts, list):
        return None
    texts = [
        part["text"]
        for part in parts
        if isinstance(part, dict)
        and isinstance(part.get("text"), str)
        and part.get("thought") is not True
    ]
    joined = "".join(texts)
    return joined or None

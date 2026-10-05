"""Gemini ``generateContent`` client for ``POST /v1/chat`` (#100).

Raw ``httpx`` over the app's shared ``AsyncClient``; no SDK. The server key is
sent only as the ``x-goog-api-key`` header, never as ``?key=`` in the URL, so
it cannot surface in an access log or an httpx log line.

Every failure is a ``BackendError`` whose ``reason`` is one of
``CHAT_FAILURE_REASONS``. Nothing here logs the key, prompt text or an
upstream body: only upstream status codes and, on an error, Google's short
``error.status`` enum (#187).

What the log does carry, per upstream exchange, is the *shape* of the
request and the reply, so a failure can be correlated with the menu's size
without quoting either: ``gemini request`` (prompt sizes, line count,
images, the generation config) before the call, ``gemini response`` (status,
latency) after it, ``gemini reply`` (finish reason, token usage, content
length) for a 200, and ``gemini reply unusable reason=...`` naming exactly
why a 200 body was thrown away. With ``GEMINI_LOG_UPSTREAM_ERRORS`` on,
an error reply's ``error.message`` and ``details`` reasons are logged too,
with the server key redacted should Google ever echo it.
"""

import copy
import logging
import re
import time
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

# What Google's ``error.status`` looks like (``NOT_FOUND``,
# ``RESOURCE_EXHAUSTED``). Anything else — a proxy at ``GEMINI_BASE_URL``
# echoing free text — is not logged, so a log line can never carry a body.
_ERROR_STATUS_SHAPE: Final = re.compile(r"^[A-Z_]{1,64}$")

# ``usageMetadata`` counters worth a log line, in the order they are printed.
_USAGE_FIELDS: Final[tuple[tuple[str, str], ...]] = (
    ("promptTokenCount", "prompt_tokens"),
    ("candidatesTokenCount", "output_tokens"),
    ("thoughtsTokenCount", "thoughts_tokens"),
    ("totalTokenCount", "total_tokens"),
)

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

    The retry rule mirrors the Dart ``OpenRouterClient``: a request carrying a
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

    _log_request(settings, request, schema, attempt=1)
    response = await _post(
        client, settings, url, headers, _body(settings, request, schema)
    )
    if (
        schema is not None
        and response.status_code == 400
        and not _is_invalid_key(response)
    ):
        logger.info("gemini upstream_status=400 retrying without responseSchema")
        _log_request(settings, request, None, attempt=2)
        response = await _post(
            client, settings, url, headers, _body(settings, request, None)
        )

    return _read(response, settings)


def _log_request(
    settings: Settings,
    request: ChatRequest,
    schema: dict[str, object] | None,
    attempt: int,
) -> None:
    """One line describing the request's shape: sizes and config, no text.

    ``user_lines`` is the number of lines in the user prompt, which for the
    menu prompt is the dish count; it is what to read a failure against
    when deciding whether a menu is too big for one request.
    """
    logger.info(
        "gemini request attempt=%d model=%s schema=%s system_chars=%d "
        "user_chars=%d user_lines=%d images=%d image_bytes=%d "
        "max_output_tokens=%d thinking_budget=%d",
        attempt,
        settings.GEMINI_MODEL,
        "yes" if schema is not None else "no",
        len(request.system_prompt),
        len(request.user_prompt),
        request.user_prompt.count("\n") + 1 if request.user_prompt else 0,
        len(request.images),
        sum(len(image.data) for image in request.images),
        settings.GEMINI_MAX_OUTPUT_TOKENS,
        settings.GEMINI_THINKING_BUDGET,
    )


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
    # Menu pages (D15, #170) follow the prompt as inline_data parts; with
    # none, the parts list is exactly the text-only one it always was.
    user_parts: list[dict[str, object]] = [{"text": request.user_prompt}]
    user_parts.extend(
        {"inline_data": {"mime_type": image.mime_type, "data": image.data}}
        for image in request.images
    )
    return {
        "system_instruction": {"parts": [{"text": request.system_prompt}]},
        "contents": [{"role": "user", "parts": user_parts}],
        "generationConfig": generation_config,
    }


async def _post(
    client: httpx.AsyncClient,
    settings: Settings,
    url: str,
    headers: dict[str, str],
    body: dict[str, object],
) -> httpx.Response:
    started = time.monotonic()
    try:
        response = await client.post(
            url, headers=headers, json=body, timeout=UPSTREAM_TIMEOUT
        )
    except httpx.TimeoutException as error:
        logger.info("gemini upstream timeout latency_ms=%.1f", _since(started))
        raise BackendError(504, "timeout") from error
    except httpx.NetworkError as error:
        # ConnectError, and a connection dropped mid-exchange: no route.
        logger.info("gemini upstream unreachable latency_ms=%.1f", _since(started))
        raise BackendError(502, "offline") from error
    except httpx.TransportError as error:
        # A protocol-level failure: the upstream answered something unusable.
        logger.info("gemini upstream transport error latency_ms=%.1f", _since(started))
        raise BackendError(502, "badResponse") from error
    logger.info("gemini upstream_status=%d", response.status_code)
    logger.info(
        "gemini response status=%d latency_ms=%.1f body_bytes=%d",
        response.status_code,
        _since(started),
        len(response.content),
    )
    if response.status_code >= 400:
        _log_upstream_error(response, settings)
    return response


def _since(started: float) -> float:
    return (time.monotonic() - started) * 1000


def _log_upstream_error(response: httpx.Response, settings: Settings) -> None:
    """Name an upstream failure in the log without quoting Google's body.

    Only ``error.status`` — Google's short enum such as ``NOT_FOUND`` or
    ``RESOURCE_EXHAUSTED`` — and ``error.code`` are logged by default, never
    ``error.message`` (which quotes the request) and never the body. With
    ``GEMINI_LOG_UPSTREAM_ERRORS`` on, one more line carries the message and
    the ``details[].reason`` entries, with the server key redacted: Google is
    not known to echo the key, and this makes sure a log line never could.
    A 404 gets one more fixed line: it is what ``generateContent`` answers
    for a model id that is retired or not served for this key, and until
    #187 the only trace of that was a bare status code that the app
    rendered as "AI error".
    """
    error = _upstream_error(response)
    status = _upstream_error_status(response)
    if status is not None and _ERROR_STATUS_SHAPE.fullmatch(status):
        code = error.get("code") if error is not None else None
        logger.info(
            "gemini upstream error_status=%s error_code=%s",
            status,
            code if isinstance(code, int) else "none",
        )
    if error is not None and settings.GEMINI_LOG_UPSTREAM_ERRORS:
        logger.info(
            "gemini upstream error_message=%r error_reasons=%s",
            _redact(str(error.get("message", "")), settings.GEMINI_API_KEY),
            ",".join(_error_reasons(error)) or "none",
        )
    if response.status_code == 404:
        logger.warning(
            "gemini answered 404: the configured GEMINI_MODEL is not served "
            "for this key or API version; set GEMINI_MODEL in backend/.env "
            "to a model the key can use (see #179)"
        )


def _upstream_error(response: httpx.Response) -> dict[str, object] | None:
    """The ``error`` object of a Google error body, or None when it has none."""
    try:
        body: object = response.json()
    except ValueError:
        return None
    if not isinstance(body, dict):
        return None
    error = body.get("error")
    return error if isinstance(error, dict) else None


def _upstream_error_status(response: httpx.Response) -> str | None:
    """``error.status`` from a Google error body, or None when it has none."""
    error = _upstream_error(response)
    if error is None:
        return None
    status = error.get("status")
    return status if isinstance(status, str) and status else None


def _error_reasons(error: dict[str, object]) -> list[str]:
    """The ``reason`` of every ``details[]`` entry that has one."""
    details = error.get("details")
    if not isinstance(details, list):
        return []
    return [
        detail["reason"]
        for detail in details
        if isinstance(detail, dict) and isinstance(detail.get("reason"), str)
    ]


def _redact(text: str, api_key: str) -> str:
    """``text`` with every occurrence of ``api_key`` replaced, and capped."""
    redacted = text.replace(api_key, "<redacted>") if api_key else text
    return redacted[:_MAX_LOGGED_MESSAGE]


# Google's ``error.message`` is one sentence; anything longer is a proxy at
# ``GEMINI_BASE_URL`` echoing a page, which a log line should not carry whole.
_MAX_LOGGED_MESSAGE: Final = 500


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
        logger.info("gemini reply unusable reason=not_json")
        raise BackendError(502, "badResponse") from error
    if not isinstance(body, dict):
        logger.info("gemini reply unusable reason=not_an_object")
        raise BackendError(502, "badResponse")

    content, why = _candidate_text(body.get("candidates"))
    _log_reply(body, content, why)
    if content is None:
        raise BackendError(502, "badResponse")

    model_version = body.get("modelVersion")
    model = (
        model_version
        if isinstance(model_version, str) and model_version
        else settings.GEMINI_MODEL
    )
    return ChatResponse(content=content, model=model)


def _log_reply(body: dict[str, object], content: str | None, why: str) -> None:
    """One line per 200 reply: finish reason, token usage, content length.

    ``why`` names the reason a reply was thrown away (``finish_reason=
    MAX_TOKENS`` is the output cap, #188; ``no_candidates`` is usually a
    prompt-level block) so the log tells a truncated menu from a blocked
    one. Counters come from ``usageMetadata`` and are the numbers to read a
    menu's size against ``GEMINI_MAX_OUTPUT_TOKENS``.
    """
    usage = body.get("usageMetadata")
    counters = " ".join(
        f"{label}={_counter(usage, field)}" for field, label in _USAGE_FIELDS
    )
    if content is None:
        logger.info("gemini reply unusable reason=%s %s", why, counters)
        return
    logger.info(
        "gemini reply finish_reason=STOP content_chars=%d %s", len(content), counters
    )


def _counter(usage: object, field: str) -> str:
    if isinstance(usage, dict) and isinstance(usage.get(field), int):
        return str(usage[field])
    return "none"


def _candidate_text(candidates: object) -> tuple[str | None, str]:
    """The first candidate's joined text, or None and the reason it is unusable.

    Unusable: no candidate, a ``finishReason`` other than ``STOP`` (a
    ``MAX_TOKENS`` reply is truncated JSON; a ``SAFETY`` one is empty), or no
    non-empty text part. Parts flagged ``thought`` are the model's reasoning,
    not its answer, and are skipped.
    """
    if not isinstance(candidates, list) or not candidates:
        return None, "no_candidates"
    first = candidates[0]
    if not isinstance(first, dict):
        return None, "candidate_not_an_object"
    finish_reason = first.get("finishReason")
    if finish_reason != "STOP":
        named = finish_reason if isinstance(finish_reason, str) else "none"
        return None, f"finish_reason={_enum_or_other(named)}"
    content = first.get("content")
    if not isinstance(content, dict):
        return None, "no_content"
    parts = content.get("parts")
    if not isinstance(parts, list):
        return None, "no_parts"
    texts = [
        part["text"]
        for part in parts
        if isinstance(part, dict)
        and isinstance(part.get("text"), str)
        and part.get("thought") is not True
    ]
    joined = "".join(texts)
    if not joined:
        return None, "no_text_part"
    return joined, "ok"


def _enum_or_other(value: str) -> str:
    """``value`` if it looks like Google's enum, else ``other``: never free text."""
    return value if _ERROR_STATUS_SHAPE.fullmatch(value) else "other"

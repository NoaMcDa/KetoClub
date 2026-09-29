"""Pydantic request and response schemas."""

import base64
import binascii
from typing import Annotated, Literal

from pydantic import (
    BaseModel,
    Field,
    PrivateAttr,
    StringConstraints,
    field_validator,
    model_validator,
)

from app.services.wolt import WoltLang


class HealthResponse(BaseModel):
    """Response body for ``GET /v1/health``."""

    status: str
    version: str
    llm_configured: bool


class ErrorResponse(BaseModel):
    """Body of every error the backend itself originates."""

    reason: str
    status_code: int


ImageMimeType = Literal["image/jpeg", "image/png", "image/webp", "application/pdf"]


class ImagePart(BaseModel):
    """One menu page on ``POST /v1/chat`` (D15, #170), base64 in ``data``.

    ``mime_type`` is one of the four types Gemini reads natively; anything
    else (``image/gif``, ``image/heic``) is a 422 before any upstream call.
    ``data`` must be strict, padded standard base64: it is decoded here once,
    so a malformed part is a 422 too, and the decoded length is kept for the
    route's ``VISION_MAX_IMAGE_BYTES`` check. The bytes themselves are not
    kept; ``data`` is forwarded to Gemini as-is.

    The size and count bounds are configuration (``app.config``), which a
    Pydantic validator cannot reach, so ``ChatRequest.image_bound_violation``
    applies them from the route instead.
    """

    mime_type: ImageMimeType
    data: str = Field(..., min_length=1)
    _decoded_size: int = PrivateAttr(default=0)

    @field_validator("data")
    @classmethod
    def _data_is_base64(cls, value: str) -> str:
        try:
            base64.b64decode(value, validate=True)
        except (binascii.Error, ValueError):
            # A fixed message: the default one would not quote the value,
            # but nothing about a page's bytes belongs in an error either.
            raise ValueError("data must be standard base64") from None
        return value

    @model_validator(mode="after")
    def _record_decoded_size(self) -> "ImagePart":
        # Exact for input _data_is_base64 accepted: every 4 characters are
        # 3 bytes, less one per "=" of padding.
        padding = len(self.data) - len(self.data.rstrip("="))
        self._decoded_size = len(self.data) * 3 // 4 - padding
        return self

    @property
    def decoded_size(self) -> int:
        """The part's size in bytes once decoded."""
        return self._decoded_size


class ChatRequest(BaseModel):
    """Request body for ``POST /v1/chat``.

    Mirrors the Dart ``LlmChatClient.complete`` parameters one to one. The
    ``max_length`` bounds turn an oversized prompt into a 422 before any
    upstream call. ``schema_name`` is accepted for parity with the Dart
    contract (and as part of the #103 cache key); Gemini's
    ``responseSchema`` has no name, so it is not forwarded.

    ``user_prompt``'s bound is an abuse guard, not a model limit: the Dart
    prompt runs about 430 characters per dish on a real Wolt menu, so the
    old 60,000 rejected every venue over ~139 dishes with a 422 the app could
    only render as "AI error" (#188). Gemini's input window is over a
    million tokens; 400,000 characters is roughly 900 dishes, past any
    restaurant and most supermarkets, while still refusing a runaway body.

    ``images`` (D15, #170) are menu pages forwarded to Gemini as
    ``inline_data`` parts after the user prompt. Empty by default, so a
    text-only body is exactly what it was before images existed. They never
    enter the #103 cache key, and a request carrying any skips the cache.
    """

    system_prompt: str = Field(..., min_length=1, max_length=20000)
    user_prompt: str = Field(..., min_length=1, max_length=400000)
    response_schema: dict[str, object] | None = None
    schema_name: str | None = Field(default=None, max_length=64)
    images: list[ImagePart] = Field(default_factory=list)

    def image_bound_violation(self, max_images: int, max_bytes: int) -> str | None:
        """Why ``images`` breaks the configured bounds, or None when it does not.

        More than ``max_images`` parts, or any part over ``max_bytes`` once
        decoded. The message names the bound, never a part's content.
        """
        if len(self.images) > max_images:
            return f"at most {max_images} images per request"
        for index, image in enumerate(self.images):
            if image.decoded_size > max_bytes:
                return f"image {index} is over {max_bytes} bytes once decoded"
        return None


class ChatResponse(BaseModel):
    """Response body for a successful ``POST /v1/chat``."""

    content: str
    model: str


class DiscoverySearchRequest(BaseModel):
    """Request body for ``POST /v1/proxy/wolt/pages/search`` (#123).

    ``q`` is trimmed and bounded before it ever reaches Wolt. ``lat``/``lon``
    share the ``GET /v1/proxy/wolt/pages/restaurants`` route's range and are
    optional together: the app searches by name without a position when
    location was denied (#37), and Wolt ranks by proximity only when both
    are given, so one without the other is rejected rather than half-sent.
    There is no ``target`` field: the route itself fixes it to ``"venues"``,
    so a client cannot ask this backend to proxy a dish search instead.
    """

    q: Annotated[
        str, StringConstraints(strip_whitespace=True, min_length=1, max_length=80)
    ]
    lat: float | None = Field(default=None, ge=-90, le=90)
    lon: float | None = Field(default=None, ge=-180, le=180)
    lang: WoltLang = "en"

    @model_validator(mode="after")
    def _position_is_all_or_nothing(self) -> "DiscoverySearchRequest":
        if (self.lat is None) != (self.lon is None):
            raise ValueError("lat and lon must be given together or not at all")
        return self

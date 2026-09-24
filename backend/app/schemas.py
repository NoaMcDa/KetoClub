"""Pydantic request and response schemas."""

from typing import Annotated

from pydantic import BaseModel, Field, StringConstraints, model_validator

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


class ChatRequest(BaseModel):
    """Request body for ``POST /v1/chat``.

    Mirrors the Dart ``LlmChatClient.complete`` parameters one to one. The
    ``max_length`` bounds turn an oversized prompt into a 422 before any
    upstream call. ``schema_name`` is accepted for parity with the Dart
    contract (and as part of the #103 cache key); Gemini's
    ``responseSchema`` has no name, so it is not forwarded.
    """

    system_prompt: str = Field(..., min_length=1, max_length=20000)
    user_prompt: str = Field(..., min_length=1, max_length=60000)
    response_schema: dict[str, object] | None = None
    schema_name: str | None = Field(default=None, max_length=64)


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

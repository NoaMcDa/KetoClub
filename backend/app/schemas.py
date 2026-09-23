"""Pydantic request and response schemas."""

from pydantic import BaseModel, Field


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

"""Pydantic request and response schemas."""

from pydantic import BaseModel


class HealthResponse(BaseModel):
    """Response body for ``GET /v1/health``."""

    status: str
    version: str
    llm_configured: bool


class ErrorResponse(BaseModel):
    """Body of every error the backend itself originates."""

    reason: str
    status_code: int

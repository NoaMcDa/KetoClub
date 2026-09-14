"""Pydantic request and response schemas."""

from pydantic import BaseModel


class HealthResponse(BaseModel):
    """Response body for ``GET /v1/health``."""

    status: str
    version: str
    llm_configured: bool

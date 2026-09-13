"""Liveness and configuration readout."""

from typing import Annotated

from fastapi import APIRouter, Depends

from app import __version__
from app.config import Settings, get_settings
from app.schemas import HealthResponse

router = APIRouter(tags=["health"])


@router.get("/health")
def health(settings: Annotated[Settings, Depends(get_settings)]) -> HealthResponse:
    """Reports that the service is up and whether a model key is configured.

    Whether a key is present is reported; the key itself never is.
    """
    return HealthResponse(
        status="ok",
        version=__version__,
        llm_configured=bool(settings.openrouter_api_key),
    )

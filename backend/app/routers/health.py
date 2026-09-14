"""``GET /health``: liveness and configuration probe."""

from fastapi import APIRouter, Request

from app.schemas import HealthResponse

router = APIRouter()


@router.get("/health", response_model=HealthResponse)
def health(request: Request) -> HealthResponse:
    """Report service status, version and whether an LLM key is configured."""
    settings = request.app.state.settings
    return HealthResponse(
        status="ok",
        version=request.app.version,
        llm_configured=settings.llm_configured,
    )

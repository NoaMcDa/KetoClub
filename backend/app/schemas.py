"""Response bodies this service returns as JSON.

Wire names are snake_case; the Flutter clients read them explicitly, so the two
sides are coupled by these models and nothing else.
"""

from pydantic import BaseModel


class HealthResponse(BaseModel):
    """The answer to `GET /v1/health`."""

    status: str
    version: str
    llm_configured: bool


class FailureResponse(BaseModel):
    """A named failure.

    `reason` is the name of a `ChatFailureReason` or an equivalent transport
    failure, so the client maps it to its own enum without reading prose.
    Distinct reasons never share a message (architecture.md constraint 10).
    """

    reason: str
    status_code: int | None = None

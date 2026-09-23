"""The ``X-KetoClub-Install-Id`` header (backend_plan.md §3.4).

The app generates 16 random bytes once per install and sends them as 32
lowercase hex characters. The id is random and unlinkable to a person; it
keys the per-install rate limiter and, later, one-vote-per-install upserts.
It is only ever logged truncated (``log_safe``).
"""

import re
from typing import Annotated, Final

from fastapi import Header

from app.errors import BackendError

INSTALL_ID_HEADER: Final = "X-KetoClub-Install-Id"

_INSTALL_ID_PATTERN: Final = re.compile(r"^[0-9a-f]{32}$")

# How many leading characters of an install id a log line may carry.
_LOGGED_PREFIX_LENGTH: Final = 8


def is_valid_install_id(value: str) -> bool:
    """Whether ``value`` is exactly 32 lowercase hex characters."""
    return _INSTALL_ID_PATTERN.fullmatch(value) is not None


def log_safe(install_id: str) -> str:
    """The install id truncated to the prefix a log line may carry."""
    return install_id[:_LOGGED_PREFIX_LENGTH]


def require_install_id(
    install_id: Annotated[str | None, Header(alias=INSTALL_ID_HEADER)] = None,
) -> str:
    """FastAPI dependency: the request's install id, or 400 ``badResponse``.

    Missing and malformed are the same failure: the client sent a request
    this backend cannot attribute to an install.
    """
    if install_id is None or not is_valid_install_id(install_id):
        raise BackendError(400, "badResponse")
    return install_id

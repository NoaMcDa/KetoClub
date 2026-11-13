"""Refuse a request whose ``Host`` header names a host this server is not
(#271).

The backend listens on localhost and relies on CORS to keep web pages out.
DNS rebinding gets around CORS: a page on ``evil.example`` points its own
name at 127.0.0.1, and the browser then treats ``http://evil.example:8000``
as the page's own origin, so it may call ``/v1/chat`` on the server's Gemini
key, or ``/v1/website/fetch``, without any cross-origin check. The one thing
such a request cannot hide is its ``Host`` header, which still says
``evil.example``.

Starlette's ``TrustedHostMiddleware`` does the matching (``*.example.com``
patterns, ``*`` for any); this subclass only fixes two things for this
backend:

* the port is cut off correctly for a bracketed IPv6 literal, so
  ``[::1]:8000`` matches ``[::1]`` (Starlette cuts at the first colon), and
  names compare case-insensitively;
* a refusal is the backend's own ``{reason, status_code}`` body, 400
  ``invalidHost``, and never a redirect.
"""

from collections.abc import Sequence

from starlette.datastructures import Headers
from starlette.middleware.trustedhost import TrustedHostMiddleware
from starlette.responses import JSONResponse
from starlette.types import ASGIApp, Receive, Scope, Send


def host_of(header: str) -> str:
    """The host part of a ``Host`` header value, lower-cased, without port."""
    header = header.strip().lower()
    if header.startswith("["):
        end = header.find("]")
        return header if end == -1 else header[: end + 1]
    return header.split(":", 1)[0]


class AllowedHostsMiddleware(TrustedHostMiddleware):
    """``TrustedHostMiddleware`` with IPv6-aware port stripping and the
    backend's error body."""

    def __init__(self, app: ASGIApp, allowed_hosts: Sequence[str]) -> None:
        super().__init__(app, allowed_hosts=allowed_hosts, www_redirect=False)

    def allows(self, host: str) -> bool:
        """Whether ``host`` (no port) matches an allowed name or pattern."""
        return self.allow_any or any(
            host == pattern or (pattern.startswith("*") and host.endswith(pattern[1:]))
            for pattern in self.allowed_hosts
        )

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        # Only HTTP is checked: the backend has no WebSocket route, and the
        # lifespan scope carries no headers.
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return
        if self.allows(host_of(Headers(scope=scope).get("host", ""))):
            await self.app(scope, receive, send)
            return
        response = JSONResponse(
            {"reason": "invalidHost", "status_code": 400}, status_code=400
        )
        await response(scope, receive, send)

"""The upstream call to Wolt's public menu endpoint.

This module does one thing: an HTTP GET and a sealed result. It never parses
the payload. Turning Wolt's JSON into a menu belongs to `wolt_menu_mapper.dart`
in the Flutter app, which is already tested against a fixture; duplicating it
here would mean two implementations to keep in step.
"""

from dataclasses import dataclass

import httpx

# Must equal `browserUserAgent` in lib/utils/constants.dart. It is duplicated
# rather than shared because the two runtimes cannot share a constant, and it
# exists at all because a browser forbids a page from setting `User-Agent` —
# which is precisely why the web build needs this proxy. Change both together.
WOLT_USER_AGENT = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
    "AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/120.0.0.0 Safari/537.36"
)

MENU_PATH_TEMPLATE = "/v4/venues/slug/{slug}/menu/data"

# A slow upstream is not an unreachable one, so the two are timed separately
# and reported as different statuses.
WOLT_TIMEOUT = httpx.Timeout(connect=5.0, read=15.0, write=5.0, pool=5.0)


@dataclass(frozen=True)
class UpstreamResponse:
    """Wolt answered. The status may be any code, including 404 and 5xx."""

    status_code: int
    body: bytes
    content_type: str


@dataclass(frozen=True)
class UpstreamUnreachable:
    """Wolt could not be reached, or took longer than the read budget.

    Attributes:
        status_code: What this service answers with: 502 when the connection
            failed, 504 when it timed out. These two are the only statuses the
            proxy invents; every other status the caller sees is Wolt's own.
    """

    status_code: int


WoltResult = UpstreamResponse | UpstreamUnreachable


async def fetch_menu(
    client: httpx.AsyncClient,
    *,
    base_url: str,
    slug: str,
) -> WoltResult:
    """Fetches the menu for `slug` from `base_url`.

    The request headers are built from scratch: nothing from the browser that
    called this service is forwarded, so an `Origin`, a `Cookie` or an
    `Authorization` header cannot be relayed to Wolt by a caller.
    """
    url = base_url.rstrip("/") + MENU_PATH_TEMPLATE.format(slug=slug)
    try:
        response = await client.get(
            url,
            headers={
                "User-Agent": WOLT_USER_AGENT,
                "Accept": "application/json",
            },
            timeout=WOLT_TIMEOUT,
        )
    except httpx.TimeoutException:
        return UpstreamUnreachable(status_code=504)
    except httpx.HTTPError:
        return UpstreamUnreachable(status_code=502)

    return UpstreamResponse(
        status_code=response.status_code,
        body=response.content,
        content_type=response.headers.get("content-type", "application/json"),
    )

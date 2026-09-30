"""``POST /website/fetch``: one restaurant page, fetched politely (D19, #181).

The web build cannot read a restaurant's own site: browsers refuse the
cross-origin request, exactly as they do for Wolt (D11). So it asks this
route, which fetches the one URL server-side and hands back the document.
Phones fetch sites themselves with the same rules (D17). Unlike the Wolt and
10bis proxies the upstream host comes from the request, so this route is
fenced harder than they are:

- **Logged out, named.** No cookie, no credential, nothing of the inbound
  request is forwarded; every fetch sends ``WEBSITE_USER_AGENT``, which names
  KetoClub and a contact URL.
- **Public hosts only.** ``http``/``https`` on the default port; the host
  must resolve to globally routable addresses only (checked again on every
  redirect hop), so the route cannot reach this server's own network.
- **robots.txt is honoured** for ``ketoclubbot``, else ``*``; cached per host
  for ``WEBSITE_ROBOTS_TTL_SECONDS``. A 4xx robots.txt means no rules; a 5xx
  or an unreachable one means the site is not fetched (RFC 9309 §2.3.1.4).
- **AI opt-outs are honoured**: ``X-Robots-Tag: noai``, ``tdm-reservation:
  1`` and their ``<meta>`` forms.
- **Per-host and per-install rate limits**, and a size cap per kind.
- **Nothing is kept.** No response is cached or logged; a log line carries
  the host and the outcome only, never the path, the query or the body.

Every failure is a ``{reason, status_code}`` body with its own reason, which
the Dart client maps to a ``MenuFetchFailureReason`` one to one.
"""

import base64
import logging
from collections.abc import Awaitable, Callable
from typing import Annotated, Final
from urllib.parse import urljoin, urlsplit

import httpx
from fastapi import APIRouter, Depends, Request

from app.errors import BackendError
from app.schemas import WebsiteFetchRequest, WebsiteFetchResponse
from app.services.install_id import require_install_id
from app.services.rate_limit import RateLimiter
from app.services.website import (
    RobotsRules,
    decode_page,
    document_kind,
    header_reserves_ai,
    html_reserves_ai,
    is_public_address,
    looks_javascript_only,
    parse_robots,
    path_of,
)

router = APIRouter()

logger = logging.getLogger("ketoclub.website")

WEBSITE_TIMEOUT: Final = httpx.Timeout(15.0, connect=5.0)
_MAX_REDIRECTS: Final = 5
_ACCEPT: Final = "text/html,application/xhtml+xml,application/pdf;q=0.9,*/*;q=0.1"

HostResolver = Callable[[str], Awaitable[list[str]]]


@router.post("/website/fetch")
async def fetch_website(
    request: Request,
    install_id: Annotated[str, Depends(require_install_id)],
    body: WebsiteFetchRequest,
) -> WebsiteFetchResponse:
    """Fetch ``body.url`` (following up to five redirects) as HTML or PDF.

    The URL travels in the body rather than the query so the request log,
    which records the route path, never holds it.
    """
    install_limiter: RateLimiter = request.app.state.website_install_limiter
    if not install_limiter.allow(install_id):
        raise BackendError(429, "rateLimited")

    url = body.url.strip()
    for _ in range(_MAX_REDIRECTS + 1):
        host = _checked_host(url)
        try:
            await _require_public(request, host)
            await _require_robots_allow(request, url, host)
            _require_host_budget(request, host)
            response = await _fetch(request, url)
        except BackendError as error:
            _log(host, error.reason)
            raise
        if response is None:
            _log(host, "timeout")
            raise BackendError(504, "timeout")
        location = response.headers.get("location")
        if 300 <= response.status_code < 400 and location:
            await response.aclose()
            url = urljoin(url, location)
            continue
        try:
            result = await _read_document(request, url, response)
        except BackendError as error:
            _log(host, error.reason)
            raise
        finally:
            await response.aclose()
        _log(host, result.kind)
        return result
    raise BackendError(502, "upstreamStatus")


def _checked_host(url: str) -> str:
    """The lower-cased host of ``url``, or 400 ``invalidUrl``.

    Only ``http``/``https`` with a host, no credentials and the default port.
    """
    try:
        parts = urlsplit(url)
        port = parts.port
    except ValueError:
        raise BackendError(400, "invalidUrl") from None
    host = (parts.hostname or "").lower()
    if parts.scheme not in ("http", "https") or not host:
        raise BackendError(400, "invalidUrl")
    if parts.username or parts.password or port not in (None, 80, 443):
        raise BackendError(400, "invalidUrl")
    return host


async def _require_public(request: Request, host: str) -> None:
    resolve: HostResolver = request.app.state.resolve_host
    try:
        addresses = await resolve(host)
    except OSError:
        raise BackendError(502, "offline") from None
    if not addresses:
        raise BackendError(502, "offline")
    if not all(is_public_address(address) for address in addresses):
        raise BackendError(400, "invalidUrl")


async def _require_robots_allow(request: Request, url: str, host: str) -> None:
    scheme = urlsplit(url).scheme
    rules = await _robots_for(request, scheme, host)
    if not rules.allows(path_of(url)):
        raise BackendError(403, "disallowedByRobots")


async def _robots_for(request: Request, scheme: str, host: str) -> RobotsRules:
    """The robots rules for ``host``, from the in-memory cache or fetched."""
    settings = request.app.state.settings
    cache: dict[str, tuple[float, RobotsRules]] = request.app.state.robots_cache
    clock: Callable[[], float] = request.app.state.website_clock
    key = f"{scheme}://{host}"
    cached = cache.get(key)
    if cached is not None and clock() - cached[0] < settings.WEBSITE_ROBOTS_TTL_SECONDS:
        return cached[1]

    http_client: httpx.AsyncClient = request.app.state.http_client
    try:
        response = await http_client.get(
            f"{key}/robots.txt",
            headers=_headers(request, accept="text/plain"),
            timeout=WEBSITE_TIMEOUT,
            follow_redirects=False,
        )
    except httpx.TimeoutException:
        raise BackendError(504, "timeout") from None
    except httpx.HTTPError:
        raise BackendError(502, "offline") from None
    if response.status_code >= 500:
        raise BackendError(502, "offline")
    if 200 <= response.status_code < 300:
        rules = parse_robots(response.text[: settings.WEBSITE_MAX_ROBOTS_BYTES])
    else:
        # 3xx is not followed here (a redirect could point anywhere), and a
        # 4xx is "no robots.txt": both are read as no rules.
        rules = RobotsRules()
    cache[key] = (clock(), rules)
    return rules


def _require_host_budget(request: Request, host: str) -> None:
    limiter: RateLimiter = request.app.state.website_host_limiter
    if not limiter.allow(host):
        raise BackendError(429, "rateLimited")


async def _fetch(request: Request, url: str) -> httpx.Response | None:
    """Open a streamed GET of ``url``; None on a timeout."""
    http_client: httpx.AsyncClient = request.app.state.http_client
    outgoing = http_client.build_request(
        "GET", url, headers=_headers(request, accept=_ACCEPT), timeout=WEBSITE_TIMEOUT
    )
    try:
        return await http_client.send(outgoing, stream=True, follow_redirects=False)
    except httpx.TimeoutException:
        return None
    except httpx.HTTPError:
        raise BackendError(502, "offline") from None


async def _read_document(
    request: Request, url: str, response: httpx.Response
) -> WebsiteFetchResponse:
    """Turn a final (non-redirect) response into the route's answer."""
    settings = request.app.state.settings
    status = response.status_code
    if status in (404, 410):
        raise BackendError(404, "notFound")
    if not 200 <= status < 300:
        raise BackendError(502, "upstreamStatus")
    headers = {key.lower(): value for key, value in response.headers.items()}
    if header_reserves_ai(headers):
        raise BackendError(403, "aiReserved")

    content_type = headers.get("content-type", "")
    limit = max(settings.WEBSITE_MAX_HTML_BYTES, settings.WEBSITE_MAX_PDF_BYTES)
    declared = headers.get("content-length", "")
    if declared.isdigit() and int(declared) > limit:
        raise BackendError(413, "tooLarge")
    try:
        content = await _read_capped(response, limit)
    except httpx.TimeoutException:
        raise BackendError(504, "timeout") from None
    except httpx.HTTPError:
        raise BackendError(502, "offline") from None

    kind = document_kind(content_type, content[:5])
    if kind is None:
        raise BackendError(415, "unsupportedContent")
    cap = (
        settings.WEBSITE_MAX_PDF_BYTES
        if kind == "pdf"
        else settings.WEBSITE_MAX_HTML_BYTES
    )
    if len(content) > cap:
        raise BackendError(413, "tooLarge")
    if kind == "pdf":
        return WebsiteFetchResponse(
            kind="pdf",
            content_type="application/pdf",
            body=base64.b64encode(content).decode("ascii"),
            final_url=url,
        )

    page = decode_page(content, content_type)
    if html_reserves_ai(page):
        raise BackendError(403, "aiReserved")
    if looks_javascript_only(page):
        raise BackendError(422, "jsOnlyPage")
    return WebsiteFetchResponse(
        kind="html", content_type=content_type, body=page, final_url=url
    )


async def _read_capped(response: httpx.Response, limit: int) -> bytes:
    """The body, read until it ends or passes ``limit`` bytes (then 413)."""
    chunks: list[bytes] = []
    size = 0
    async for chunk in response.aiter_bytes():
        size += len(chunk)
        if size > limit:
            raise BackendError(413, "tooLarge")
        chunks.append(chunk)
    return b"".join(chunks)


def _headers(request: Request, *, accept: str) -> dict[str, str]:
    settings = request.app.state.settings
    return {
        "User-Agent": settings.WEBSITE_USER_AGENT,
        "Accept": accept,
        "Accept-Language": "he,en;q=0.8",
    }


def _log(host: str, outcome: str) -> None:
    """One line per fetch: the host and the outcome, never the path."""
    logger.info("website fetch host=%s outcome=%s", host, outcome)

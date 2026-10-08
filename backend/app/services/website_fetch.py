"""One polite fetch of a restaurant's page or PDF (D19, #181; shared by #334).

The I/O half of the website hygiene, moved here from
``app.routers.website`` so ``POST /v1/website/fetch`` and
``POST /v1/website-menu`` fetch every URL the same way. The pure half (robots
parsing, the AI opt-out signals, content sniffing, the public-address test)
stays in ``app.services.website``.

:func:`fetch_document` applies, in order, for every fetch:

- **The install's budget** (``website_install_limiter``), once per call, so
  the route is no open proxy: a link hop is a second call and a second spend.
- **Public hosts only.** ``http``/``https`` on the default port, no
  credentials; the host must resolve to globally routable addresses only,
  checked again on every redirect hop (at most five).
- **robots.txt** for ``ketoclubbot``, else ``*``, cached per host for
  ``WEBSITE_ROBOTS_TTL_SECONDS``. A 4xx robots.txt means no rules; a 5xx or
  an unreachable one means the site is not fetched (RFC 9309 §2.3.1.4).
- **The site's budget** (``website_host_limiter``), per hop, across installs.
- **Logged out, named.** Nothing of the inbound request is forwarded; every
  fetch sends ``WEBSITE_USER_AGENT``.
- **AI opt-outs**: ``X-Robots-Tag: noai`` and ``tdm-reservation: 1`` headers
  always; their ``<meta>`` forms and the JavaScript-only test only when the
  caller asks (``judge_page``): ``/v1/website-menu`` leaves those to the
  ported Dart reader (``app.website.adapter``), which takes JSON-LD before
  the JavaScript-only test exactly as the app does.
- **A size cap per kind**, and only HTML or a PDF accepted.

Every failure is a ``BackendError`` with its own reason; nothing is cached
and a log line carries the host and the outcome only, never the path, the
query or the body.
"""

import logging
from collections.abc import Awaitable, Callable
from dataclasses import dataclass
from typing import Final
from urllib.parse import urljoin, urlsplit

import httpx
from fastapi import Request

from app.errors import BackendError
from app.services.rate_limit import RateLimiter
from app.services.website import (
    DocumentKind,
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

logger = logging.getLogger("ketoclub.website")

WEBSITE_TIMEOUT: Final = httpx.Timeout(15.0, connect=5.0)
MAX_REDIRECTS: Final = 5
_ACCEPT: Final = "text/html,application/xhtml+xml,application/pdf;q=0.9,*/*;q=0.1"

HostResolver = Callable[[str], Awaitable[list[str]]]


@dataclass(frozen=True, slots=True)
class WebsiteDocument:
    """One fetched document.

    ``content`` is the raw body; ``page`` is its decoded text for ``html``
    and ``None`` for ``pdf``. ``final_url`` is the URL after redirects.
    """

    kind: DocumentKind
    content_type: str
    content: bytes
    page: str | None
    final_url: str


async def fetch_document(
    request: Request, url: str, install_id: str, *, judge_page: bool = True
) -> WebsiteDocument:
    """Fetch ``url`` (following up to five redirects) as HTML or a PDF.

    ``install_id`` keys the install budget and nothing else. With
    ``judge_page`` (``/v1/website/fetch``), an HTML page that opts out of AI
    use in its ``<meta>`` tags is 403 ``aiReserved`` and one that renders
    only with JavaScript is 422 ``jsOnlyPage``.
    """
    install_limiter: RateLimiter = request.app.state.website_install_limiter
    if not install_limiter.allow(install_id):
        raise BackendError(429, "rateLimited")

    for _ in range(MAX_REDIRECTS + 1):
        host = checked_host(url)
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
            document = await _read_document(
                request, url, response, judge_page=judge_page
            )
        except BackendError as error:
            _log(host, error.reason)
            raise
        finally:
            await response.aclose()
        _log(host, document.kind)
        return document
    raise BackendError(502, "upstreamStatus")


def checked_host(url: str) -> str:
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
    request: Request, url: str, response: httpx.Response, *, judge_page: bool
) -> WebsiteDocument:
    """Turn a final (non-redirect) response into a document, or an error."""
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
        return WebsiteDocument(
            kind="pdf",
            content_type="application/pdf",
            content=content,
            page=None,
            final_url=url,
        )

    page = decode_page(content, content_type)
    if judge_page:
        if html_reserves_ai(page):
            raise BackendError(403, "aiReserved")
        if looks_javascript_only(page):
            raise BackendError(422, "jsOnlyPage")
    return WebsiteDocument(
        kind="html",
        content_type=content_type,
        content=content,
        page=page,
        final_url=url,
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

"""Wolt upstream client: request headers, timeouts and the response cache.

``backend_plan.md`` §3.3, issue #95. The proxy route in
``app/routers/proxy.py`` is the only caller; this module has no FastAPI
imports so the request/response shaping stays in the router and the
upstream/caching mechanics stay here.

The cache functions (``read_cached_menu``/``write_cached_menu``) are shared
with ``app.services.tenbis`` (#122): they take a ``source`` so Wolt and
10bis rows in one ``menu_cache`` table cannot collide, rather than each
platform module duplicating the read/write logic.
"""

from collections.abc import Callable
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from typing import Literal

import httpx
from sqlalchemy import Engine
from sqlalchemy.orm import Session

from app.db import get_session
from app.models import MenuCache

# Duplicated intentionally: a browser cannot set its own `User-Agent` header,
# so the Dart client only sends this on native platforms (see
# `runsInBrowser` in `lib/services/menu/wolt/wolt_adapter.dart`) and relies
# on this proxy to send it for the web build instead. Keep this string
# identical to `browserUserAgent` in `lib/utils/constants.dart` if either
# changes.
WOLT_USER_AGENT = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
    "AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/120.0.0.0 Safari/537.36"
)

# connect 5s, read/write 15s, pool 5s (backend_plan.md §3.3's connect/read
# bounds; write and pool are not specified upstream and are set to match).
WOLT_TIMEOUT = httpx.Timeout(connect=5.0, read=15.0, write=15.0, pool=5.0)

# The two languages Wolt's web client accepts as `app-language`
# (phase2_discovery_research.md §2.2).
WoltLang = Literal["en", "he"]

# The `app-language` the menu proxy sends: the menu route carries no
# language, and the recorded assortment (test/fixtures/wolt_hamosad_menu.json)
# came back in the venue's own language with this value regardless. Keep
# identical to `woltDefaultAppLanguage` in `lib/utils/wolt_headers.dart`.
WOLT_MENU_LANG: WoltLang = "en"

# Every 2026 capture of a Wolt web-client request sends this literal value
# when analytics consent was never granted; this backend never asks for
# consent, so it is a constant rather than a setting.
_WOLT_SESSION_ID = "no-analytics-consent"

# The ``source`` the menu proxy writes into ``MenuCache`` rows (#122).
# Renamed from ``"wolt"`` when the route moved to the consumer-assortment
# endpoint (#168), so a row cached from the retired ``/v4`` endpoint — a
# zero-byte 200 — can never be served as an assortment.
SOURCE = "wolt-assortment"


def wolt_web_headers(
    *, lang: WoltLang, client_id: str, client_version: str
) -> dict[str, str]:
    """Build the Wolt web-client header set for one upstream request.

    Shared by the menu proxy (#168) and the two discovery routes (#123):
    the same set ``lib/utils/wolt_headers.dart`` sends from a phone. Built
    from scratch on every call, never copied from the inbound request:
    nothing of the browser's own request (``Origin``, ``Cookie``,
    ``Authorization``, the KetoClub install id) reaches Wolt
    (``backend_plan.md`` §3.3). A bare discovery request is reported to
    answer 410 "update the app" without the full web-client identity
    (``phase2_discovery_research.md`` §2.2), and the assortment endpoint was
    recorded with ``platform`` and ``app-language`` set, so this always
    sends ``platform``, the client version under both header names Wolt
    reads it from, ``app-language``, a per-process ``client_id`` (never the
    KetoClub install id — a separate uuid4, generated once at backend start)
    and the session-id placeholder.
    """
    return {
        "platform": "Web",
        "client-version": client_version,
        "clientversionnumber": client_version,
        "app-language": lang,
        "x-wolt-web-clientid": client_id,
        "w-wolt-session-id": _WOLT_SESSION_ID,
        "Accept": "application/json",
        "User-Agent": WOLT_USER_AGENT,
    }


def wolt_assortment_url(base_url: str, slug: str) -> str:
    """Build the upstream Wolt menu URL for ``slug`` under ``base_url``.

    The consumer-assortment endpoint wolt.com's own web app reads a menu
    from (#168). ``base_url`` is ``Settings.WOLT_CONSUMER_BASE_URL``: Wolt's
    older ``restaurant-api`` menu endpoint answers every anonymous caller
    with a zero-byte 200 and is no longer called.
    """
    return (
        f"{base_url}/consumer-api/consumer-assortment/v1/venues/slug/{slug}/assortment"
    )


# --- Discovery (#123) -------------------------------------------------------
#
# The two "pages" venue-search endpoints are a second, separate contract
# from the menu fetch above, with their own cache/rate-limit rows. Kept in
# this module rather than a new service file because they share the menu
# proxy's ``wolt_web_headers``, ``WOLT_TIMEOUT`` and cache functions — see
# ``phase2_discovery_research.md`` §2, §3.

# ``MenuCache.source`` for the two discovery routes, distinct from the menu
# proxy's ``SOURCE`` and ``"tenbis"`` so a discovery cache row can never
# collide with a menu cache row for what happens to be the same key string.
SOURCE_RESTAURANTS = "wolt-restaurants"
SOURCE_SEARCH = "wolt-search"


def wolt_restaurants_url(base_url: str) -> str:
    """Build the upstream "venues near a point" URL under ``base_url``.

    ``lat``/``lon`` are sent by the caller as query parameters, not baked
    into this string, so httpx encodes them rather than this module
    reimplementing float-to-query-string formatting.
    """
    return f"{base_url}/v1/pages/restaurants"


def wolt_search_url(base_url: str) -> str:
    """Build the upstream "search venues by name" URL under ``base_url``."""
    return f"{base_url}/v1/pages/search"


@dataclass(frozen=True)
class CachedMenuResponse:
    """A cached Wolt response, detached from its originating session."""

    status_code: int
    content_type: str
    body: str


def _run_in_session[T](engine: Engine, fn: Callable[[Session], T]) -> T:
    """Run ``fn`` over one session obtained from ``get_session``.

    ``get_session`` is written as a FastAPI dependency generator (commit on
    success, rollback on exception). Called directly like this — from a
    threadpool, not through ``Depends`` — driving it with the same
    next()/next() sequence as ``tests/test_db.py`` reproduces that same
    commit/rollback behaviour.
    """
    generator = get_session(engine)
    session = next(generator)
    try:
        result = fn(session)
    except Exception:
        generator.close()
        raise
    try:
        next(generator)
    except StopIteration:
        pass
    return result


def read_cached_menu(
    engine: Engine, source: str, slug: str, ttl_seconds: int
) -> CachedMenuResponse | None:
    """Return the cached response for ``(source, slug)`` if fresh.

    ``source`` (``"wolt"``, ``"tenbis"``, ...) plus ``slug`` is the table's
    primary key (#122), so identical ids from different platforms never
    collide. A missing row, or one older than ``ttl_seconds``, is a cache
    miss.
    """

    def _read(session: Session) -> CachedMenuResponse | None:
        row = session.get(MenuCache, (source, slug))
        if row is None:
            return None
        fetched_at = row.fetched_at
        if fetched_at.tzinfo is None:
            fetched_at = fetched_at.replace(tzinfo=UTC)
        if datetime.now(UTC) - fetched_at > timedelta(seconds=ttl_seconds):
            return None
        return CachedMenuResponse(
            status_code=row.status_code,
            content_type=row.content_type,
            body=row.body,
        )

    return _run_in_session(engine, _read)


def write_cached_menu(
    engine: Engine,
    source: str,
    slug: str,
    status_code: int,
    content_type: str,
    body: str,
) -> None:
    """Insert or replace the cached response for ``(source, slug)``.

    Only ever called for a 2xx upstream response (``backend_plan.md`` §3.3):
    a failed fetch is never cached.
    """

    def _write(session: Session) -> None:
        session.merge(
            MenuCache(
                source=source,
                slug=slug,
                status_code=status_code,
                content_type=content_type,
                body=body,
                fetched_at=datetime.now(UTC).replace(tzinfo=None),
            )
        )

    _run_in_session(engine, _write)

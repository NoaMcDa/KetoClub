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

# Built from scratch, never copied from the inbound request: nothing of the
# browser's own request (Origin, Cookie, Authorization, the install id)
# reaches Wolt (backend_plan.md §3.3).
WOLT_HEADERS: dict[str, str] = {
    "User-Agent": WOLT_USER_AGENT,
    "Accept": "application/json",
}

# connect 5s, read/write 15s, pool 5s (backend_plan.md §3.3's connect/read
# bounds; write and pool are not specified upstream and are set to match).
WOLT_TIMEOUT = httpx.Timeout(connect=5.0, read=15.0, write=15.0, pool=5.0)

# The ``source`` this platform writes into ``MenuCache`` rows (#122).
SOURCE = "wolt"


def wolt_menu_url(base_url: str, slug: str) -> str:
    """Build the upstream Wolt menu URL for ``slug`` under ``base_url``."""
    return f"{base_url}/v4/venues/slug/{slug}/menu/data"


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

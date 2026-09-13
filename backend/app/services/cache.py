"""Server-side cache for proxied menu bodies.

Caching is a courtesy to the restaurant platform and a speed-up for the app;
it is never required for correctness, so a failure to read or write the cache
must never fail a request.
"""

from dataclasses import dataclass
from datetime import datetime, timedelta

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import MenuCacheEntry


@dataclass(frozen=True)
class CachedBody:
    """A cached upstream response body and the content type it came with."""

    body: bytes
    content_type: str


def read_menu_cache(
    session: Session,
    *,
    source: str,
    slug: str,
    ttl_seconds: int,
    now: datetime,
) -> CachedBody | None:
    """Returns the cached body for `source`/`slug`, if one is still fresh.

    None when there is no entry, or when the entry is older than
    `ttl_seconds`. The boundary is exclusive, matching the app's own
    `menuCacheTtl`: an entry exactly at the limit is stale.
    """
    entry = session.scalar(
        select(MenuCacheEntry).where(
            MenuCacheEntry.source == source,
            MenuCacheEntry.slug == slug,
        )
    )
    if entry is None:
        return None
    if now - entry.fetched_at >= timedelta(seconds=ttl_seconds):
        return None
    return CachedBody(body=entry.body, content_type=entry.content_type)


def write_menu_cache(
    session: Session,
    *,
    source: str,
    slug: str,
    body: bytes,
    content_type: str,
    now: datetime,
) -> None:
    """Stores or replaces the cached body for `source`/`slug`."""
    entry = session.scalar(
        select(MenuCacheEntry).where(
            MenuCacheEntry.source == source,
            MenuCacheEntry.slug == slug,
        )
    )
    if entry is None:
        entry = MenuCacheEntry(
            source=source,
            slug=slug,
            body=body,
            content_type=content_type,
            fetched_at=now,
        )
        session.add(entry)
    else:
        entry.body = body
        entry.content_type = content_type
        entry.fetched_at = now
    session.commit()

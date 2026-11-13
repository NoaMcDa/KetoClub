"""Delete expired cache rows, so the database does not grow forever (#272).

Every cache read treats a row past its TTL as a miss, and a write replaces
only its own key, so a key never asked for again stayed in ``chat_cache``,
``menu_cache`` (menus and discovery lists) and ``analysis_cache`` for good.
``purge_expired`` deletes them: ``create_app``'s lifespan runs it at
startup and then every ``PURGE_INTERVAL_SECONDS``. ``stored_menus`` (D24)
is a store, not a cache, and is never purged here.
"""

from datetime import UTC, datetime, timedelta
from typing import Final

from sqlalchemy import Engine, delete
from sqlalchemy.orm import Session

from app.config import Settings
from app.models import AnalysisCache, ChatCache, MenuCache

PURGE_INTERVAL_SECONDS: Final = 3600.0


def purge_expired(engine: Engine, settings: Settings, now: datetime) -> int:
    """Delete every row older than its table's TTL; return how many went.

    ``menu_cache`` holds both menus and discovery lists, so its rows go only
    after the longer of the two TTLs. Timestamps are naive UTC.
    """
    moment = now.astimezone(UTC).replace(tzinfo=None) if now.tzinfo else now
    menu_ttl = max(
        settings.MENU_CACHE_TTL_SECONDS, settings.DISCOVERY_CACHE_TTL_SECONDS
    )
    statements = [
        delete(ChatCache).where(
            ChatCache.created_at
            < moment - timedelta(seconds=settings.CHAT_CACHE_TTL_SECONDS)
        ),
        delete(MenuCache).where(
            MenuCache.fetched_at < moment - timedelta(seconds=menu_ttl)
        ),
        delete(AnalysisCache).where(
            AnalysisCache.created_at
            < moment - timedelta(seconds=settings.ANALYSIS_CACHE_TTL_SECONDS)
        ),
    ]
    removed = 0
    with Session(engine) as session, session.begin():
        for statement in statements:
            result = session.execute(statement)
            removed += int(getattr(result, "rowcount", 0) or 0)
    return removed

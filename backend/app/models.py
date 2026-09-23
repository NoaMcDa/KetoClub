"""SQLAlchemy ORM models.

``menu_cache`` (#95) and ``chat_cache`` (#103) are the tables so far. Future
issues declare more tables here against ``app.db.Base`` — ``venues`` and
``ratings``/``dish_feedback`` (#105, #106), ``submissions`` (#107) — so one
``Base.metadata.create_all`` call in the lifespan creates every table.
"""

from datetime import datetime

from sqlalchemy import DateTime, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from app.db import Base

__all__ = ["Base", "ChatCache", "MenuCache"]


class MenuCache(Base):
    """A cached raw menu response, keyed by ``(source, slug)`` (#95, #122).

    ``source`` distinguishes which proxy route wrote the row (``"wolt"``,
    ``"tenbis"``) so a Wolt venue slug and a 10bis restaurant id that happen
    to be the same string cannot collide — the primary key is the pair, not
    ``slug`` alone. Only a 2xx upstream response is ever written here; a
    failed fetch is never cached (``backend_plan.md`` §3.3). ``fetched_at``
    is stored as a naive UTC timestamp — the proxy route treats a row older
    than ``Settings.MENU_CACHE_TTL_SECONDS`` as a miss and replaces it.
    """

    __tablename__ = "menu_cache"

    source: Mapped[str] = mapped_column(String, primary_key=True)
    slug: Mapped[str] = mapped_column(String, primary_key=True)
    status_code: Mapped[int] = mapped_column(Integer, nullable=False)
    content_type: Mapped[str] = mapped_column(String, nullable=False)
    body: Mapped[str] = mapped_column(Text, nullable=False)
    fetched_at: Mapped[datetime] = mapped_column(DateTime, nullable=False)


class ChatCache(Base):
    """A cached Gemini completion, keyed by request hash (issue #103).

    ``key`` is ``chat_cache.cache_key``'s sha256 hex digest over the
    canonical request (model, prompts and schema): identical menus produce
    identical prompts, so one completion serves every caller of that menu.
    Only a successful completion is ever written here — a ``BackendError``
    is never cached (``backend_plan.md`` §3.3's "only 2xx is cached" rule,
    carried over from ``MenuCache``). ``content`` and ``model`` are exactly
    what ``ChatResponse`` holds: prompt text and the model's own output,
    never an install id. ``created_at`` is stored as a naive UTC timestamp,
    the same convention as ``MenuCache.fetched_at``: the route treats a row
    older than ``Settings.CHAT_CACHE_TTL_SECONDS`` as a miss and replaces it.
    """

    __tablename__ = "chat_cache"

    key: Mapped[str] = mapped_column(String(64), primary_key=True)
    content: Mapped[str] = mapped_column(Text, nullable=False)
    model: Mapped[str] = mapped_column(String, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, nullable=False)

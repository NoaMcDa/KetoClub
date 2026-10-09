"""SQLAlchemy ORM models.

``menu_cache`` (#95), ``chat_cache`` (#103), ``stored_menus`` (#310) and
``analysis_cache`` (#333) are the tables so far. Future issues declare more
tables here against ``app.db.Base`` — ``venues`` and
``ratings``/``dish_feedback`` (#105, #106), ``submissions`` (#107) — so one
``Base.metadata.create_all`` call in the lifespan creates every table.

No table holds an install id (D12, #164): the id keys the in-memory rate
limiter and nothing else. ``stored_menus`` in particular is keyed by venue.
"""

from datetime import datetime

from sqlalchemy import DateTime, Float, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from app.db import Base

__all__ = ["AnalysisCache", "Base", "ChatCache", "MenuCache", "StoredMenu"]


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


class StoredMenu(Base):
    """One opened menu in the anonymous shared store (#310).

    Keyed by ``(source, platform_id)`` — the platform a menu came from
    (``"wolt"``, ``"tenbis"``, ``"tabit"``, ``"ontopo"``, ``"scan"``,
    ``"website"``) and that platform's own id for it — so a row describes a
    venue's menu, never who opened it. There is deliberately no install-id
    column: the id that ``POST /v1/menus`` requires keys the rate limiter
    only (D12, #164), and it never reaches this table or a log line beside
    its content.

    ``menu_json`` is the client's normalised menu as JSON text, replaced on
    every upload. ``analysis_json`` is the client's analysis, replaced only
    when an upload carries one; ``venue_name`` and ``city`` likewise keep
    their last non-null value. ``dish_count`` is counted from the menu's
    ``categories[*].dishes``; ``score`` is copied from a top-level numeric
    ``score`` in the analysis and is otherwise null — the backend computes
    neither verdicts nor scores. ``first_seen_at`` / ``last_seen_at`` are
    naive UTC timestamps (the ``MenuCache.fetched_at`` convention) and
    ``submission_count`` counts uploads, not distinct installs.
    """

    __tablename__ = "stored_menus"

    source: Mapped[str] = mapped_column(String(16), primary_key=True)
    platform_id: Mapped[str] = mapped_column(String(512), primary_key=True)
    venue_name: Mapped[str | None] = mapped_column(String(200), nullable=True)
    city: Mapped[str | None] = mapped_column(String(200), nullable=True)
    menu_json: Mapped[str] = mapped_column(Text, nullable=False)
    analysis_json: Mapped[str | None] = mapped_column(Text, nullable=True)
    dish_count: Mapped[int] = mapped_column(Integer, nullable=False)
    score: Mapped[float | None] = mapped_column(Float, nullable=True)
    first_seen_at: Mapped[datetime] = mapped_column(DateTime, nullable=False)
    last_seen_at: Mapped[datetime] = mapped_column(DateTime, nullable=False)
    submission_count: Mapped[int] = mapped_column(Integer, nullable=False)


class AnalysisCache(Base):
    """A complete LLM analysis of one menu, keyed by request hash (D25, #333).

    ``key`` is ``analysis_cache.cache_key``'s sha256 hex digest over the
    menu's dish-text fingerprint, the model, the parser's schema version and
    the options (net-carb limit, dietary constraints): every caller of the
    same menu under the same options shares one Gemini call. Only an
    analysis the language model made is ever written here, never a rules
    fallback. ``analysis_json`` is the Dart ``MenuAnalysed`` JSON, options
    snapshot included: dish ids, verdicts and the model's text, never an
    install id. ``created_at`` is a naive UTC timestamp, the
    ``MenuCache.fetched_at`` convention: a row older than
    ``Settings.ANALYSIS_CACHE_TTL_SECONDS`` is a miss and is replaced.
    """

    __tablename__ = "analysis_cache"

    key: Mapped[str] = mapped_column(String(64), primary_key=True)
    analysis_json: Mapped[str] = mapped_column(Text, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, nullable=False)

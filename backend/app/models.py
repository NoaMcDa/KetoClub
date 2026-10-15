"""SQLAlchemy ORM models.

``menu_cache`` (#95), ``chat_cache`` (#103), ``stored_menus`` (#310),
``analysis_cache`` (#333), ``dish_confirmations`` and ``confirmation_voters``
(ALG-14, #356) and ``allergen_matrices`` (ALG-16, #358) are the tables so
far. Future issues declare more
tables here against ``app.db.Base`` — ``venues`` and
``ratings``/``dish_feedback`` (#105, #106), ``submissions`` (#107) — so one
``Base.metadata.create_all`` call in the lifespan creates every table.

No table holds an install id (D12, #164): the id keys the in-memory rate
limiter and nothing else. ``stored_menus`` and ``allergen_matrices`` in
particular are keyed by venue. ``confirmation_voters`` holds a one-way digest
that cannot be joined back to an install or to a row (see its docstring),
never the id itself.
"""

from datetime import date, datetime

from sqlalchemy import Date, DateTime, Float, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from app.db import Base

__all__ = [
    "AllergenMatrix",
    "AnalysisCache",
    "Base",
    "ChatCache",
    "ConfirmationVoter",
    "DishConfirmation",
    "MenuCache",
    "StoredMenu",
]


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


class DishConfirmation(Base):
    """One community fact about one dish at one venue (ALG-14, #356).

    Keyed by the venue (``source``, ``platform_id``: the ``stored_menus``
    key), the dish's fingerprint, the restriction id and the polarity
    (``"present"``: staff confirmed the restriction's ingredient is in the
    dish, ``"absent"``: staff confirmed it is not). The row is a count and
    two dates and nothing else: **no install id column, no note column, and
    nothing profile-shaped** (the D24 rule, Banto C1). ``distinct_count`` is
    the number of different installs that confirmed this exact fact, which
    is what the ``>= 3`` threshold and the ``/v1/venue-menus`` counts read;
    ``submission_count`` counts every accepted post including repeats from
    an install already counted, and is never served. ``first_on`` and
    ``last_on`` are UTC calendar dates, deliberately not timestamps, so a
    row cannot be lined up with a request log by the second.
    """

    __tablename__ = "dish_confirmations"

    source: Mapped[str] = mapped_column(String(16), primary_key=True)
    platform_id: Mapped[str] = mapped_column(String(512), primary_key=True)
    dish_fingerprint: Mapped[str] = mapped_column(String(64), primary_key=True)
    restriction_id: Mapped[str] = mapped_column(String(64), primary_key=True)
    polarity: Mapped[str] = mapped_column(String(8), primary_key=True)
    distinct_count: Mapped[int] = mapped_column(Integer, nullable=False)
    submission_count: Mapped[int] = mapped_column(Integer, nullable=False)
    first_on: Mapped[date] = mapped_column(Date, nullable=False)
    last_on: Mapped[date] = mapped_column(Date, nullable=False)


class ConfirmationVoter(Base):
    """The bookkeeping that makes ``distinct_count`` distinct (ALG-14, #356).

    One row per ``(install, confirmed fact)`` that has been counted, holding
    only ``token``: ``HMAC-SHA256(pepper, install id | venue | dish |
    restriction | polarity)``. Three properties keep it from being a link
    between an install and anything:

    * **One-way.** The install id is a 128-bit random value and the digest
      is keyed with ``Settings.CONFIRMATION_PEPPER``, so a token cannot be
      turned back into an id, nor checked against a guessed one.
    * **Per fact.** The digest covers the fact it counts, so the same
      install has an unrelated token for every dish and venue: tokens
      cannot be grouped by install, and the table cannot be read as "what
      this install confirmed".
    * **Unjoinable.** The table has no foreign key, no timestamp and no
      other column, so a token cannot be tied to a ``dish_confirmations``
      row except by someone who already holds the install id, which the
      backend never keeps.

    A second post from the same install for the same fact recomputes the
    same token, finds it here and is not counted again.
    """

    __tablename__ = "confirmation_voters"

    token: Mapped[str] = mapped_column(String(64), primary_key=True)


class AllergenMatrix(Base):
    """A restaurant's allergen matrix for one venue and date (ALG-16, #358).

    Keyed by ``(source, platform_id, valid_from)``: the venue keying of
    ``stored_menus`` (a platform and its own id for the venue) plus the day
    the matrix starts to hold, so a venue keeps its successive matrices and
    importing one again for the same day replaces it. ``valid_until`` is the
    last day it holds, or null for "until replaced"; ``GET
    /v1/venue-menus`` answers the one with the latest ``valid_from`` that
    holds today (``app.services.allergen_matrix.current``).

    ``rows_json`` is the matrix itself, the wire form's ``rows``: one entry
    per dish by printed name (and aliases), each allergen column of the EU 14
    as ``contains``, ``may_contain`` or ``free``, a blank cell left out.
    ``matrix_source`` says where the restaurant's information was read
    (``restaurant``, ``printed``, ``website``) and ``entered_by`` who typed
    it in; ``entered_by`` is for the maintainer's audit and never leaves
    the server. Written only by the maintainer CLI
    (``tools/allergen_matrix.py``): there is no write route and no account.
    There is no install-id column, as for every table here.
    """

    __tablename__ = "allergen_matrices"

    source: Mapped[str] = mapped_column(String(16), primary_key=True)
    platform_id: Mapped[str] = mapped_column(String(512), primary_key=True)
    valid_from: Mapped[date] = mapped_column(Date, primary_key=True)
    valid_until: Mapped[date | None] = mapped_column(Date, nullable=True)
    matrix_source: Mapped[str] = mapped_column(String(32), nullable=False)
    entered_by: Mapped[str] = mapped_column(String(200), nullable=False)
    rows_json: Mapped[str] = mapped_column(Text, nullable=False)
    entered_at: Mapped[datetime] = mapped_column(DateTime, nullable=False)

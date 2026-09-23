"""Shared Gemini completion cache, keyed by request hash (issue #103).

Identical menus produce identical prompts, so one completion cached here
serves every caller who asks the same question — the OpenRouter/Gemini
free-tier quota (D6) goes much further. ``app/routers/proxy.py`` and
``app/services/wolt.py`` are the model for the read/write shape: sync
functions run over a session obtained from ``app.db.get_session``, called
from the async route through ``run_in_threadpool``.
"""

import hashlib
import json
from collections.abc import Callable
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta

from sqlalchemy import Engine
from sqlalchemy.orm import Session

from app.db import get_session
from app.models import ChatCache
from app.schemas import ChatRequest, ChatResponse


def cache_key(model: str, request: ChatRequest) -> str:
    """The sha256 hex digest of ``request``'s canonical JSON, under ``model``.

    Canonical means ``json.dumps`` with sorted keys and no whitespace, so the
    key is stable across dict key order — including inside a nested
    ``response_schema`` — and changes whenever the model, either prompt, the
    schema or its name changes.
    """
    payload = {
        "model": model,
        "system_prompt": request.system_prompt,
        "user_prompt": request.user_prompt,
        "response_schema": request.response_schema,
        "schema_name": request.schema_name,
    }
    canonical = json.dumps(
        payload, sort_keys=True, separators=(",", ":"), ensure_ascii=False
    )
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def _run_in_session[T](engine: Engine, fn: Callable[[Session], T]) -> T:
    """Run ``fn`` over one session obtained from ``get_session``.

    Duplicated from ``app.services.wolt`` rather than shared: the two
    services are independent (``backend_plan.md`` §3.3) and this is the only
    piece either needs from the other.
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


@dataclass(frozen=True)
class _CachedRow:
    """A cached row's fields, detached from its originating session."""

    content: str
    model: str


def read_cached(
    engine: Engine, key: str, ttl_seconds: int, now: datetime
) -> ChatResponse | None:
    """Return the cached response for ``key`` if it exists and is fresh.

    A missing row, or one older than ``ttl_seconds`` measured from ``now``,
    is a cache miss. ``now`` is passed in (rather than read here with
    ``datetime.now(UTC)``) so tests can move time without sleeping.
    """

    def _read(session: Session) -> _CachedRow | None:
        row = session.get(ChatCache, key)
        if row is None:
            return None
        created_at = row.created_at
        if created_at.tzinfo is None:
            created_at = created_at.replace(tzinfo=UTC)
        if now - created_at > timedelta(seconds=ttl_seconds):
            return None
        return _CachedRow(content=row.content, model=row.model)

    cached = _run_in_session(engine, _read)
    if cached is None:
        return None
    return ChatResponse(content=cached.content, model=cached.model)


def write_cached(
    engine: Engine, key: str, response: ChatResponse, now: datetime
) -> None:
    """Insert or replace the cached response for ``key``.

    Only ever called after a successful completion: a ``BackendError`` is
    never cached. ``session.merge`` upserts, so a row that has expired but
    was not yet evicted is simply replaced. ``now`` is stored naive, the same
    convention as ``MenuCache.fetched_at``: a tz-aware ``now`` (as
    ``datetime.now(UTC)`` gives) has its ``tzinfo`` dropped rather than being
    converted, so it is stored as the UTC wall-clock time it already is.
    """
    naive_now = now.replace(tzinfo=None) if now.tzinfo is not None else now

    def _write(session: Session) -> None:
        session.merge(
            ChatCache(
                key=key,
                content=response.content,
                model=response.model,
                created_at=naive_now,
            )
        )

    _run_in_session(engine, _write)

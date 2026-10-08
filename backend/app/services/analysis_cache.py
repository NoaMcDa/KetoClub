"""The D25 analysis cache: one complete LLM analysis per menu (#333).

A menu's dish text, under one model, one parser schema version and one set
of options, is classified once and the result serves every caller who asks
again, on any platform: ``backend_plan.md`` §3.3's "Analysis cache". Only an
analysis the language model made is ever written; a rules fallback never is,
so a Gemini outage cannot pin the rules' verdicts for a week. Scans (images)
never come here.

The read/write shape is ``app.services.chat_cache``'s: sync functions over a
session obtained from ``app.db.get_session``, called from the async service
through ``run_in_threadpool``. ``now`` is always passed in so tests move time
without sleeping, and timestamps are stored naive UTC.
"""

import hashlib
import json
from collections.abc import Callable
from datetime import UTC, datetime, timedelta

from pydantic import ValidationError
from sqlalchemy import Engine
from sqlalchemy.orm import Session

from app.db import get_session
from app.keto.fingerprint import fingerprint_hex
from app.keto.models import AnalysisOptionsSnapshot, Menu, MenuAnalysed, to_json
from app.models import AnalysisCache


def cache_key(
    menu: Menu, *, model: str, schema_version: int, options: AnalysisOptionsSnapshot
) -> str:
    """The sha256 hex digest of ``fingerprint|model|schemaVersion|
    netCarbLimitGrams|constraints``.

    ``fingerprint`` is the menu's dish-text fingerprint
    (``app.keto.fingerprint``, the one a scan is addressed by), so the same
    dishes are one key whichever platform or venue they came from.
    ``constraints`` is the list as compact JSON, in the order given, so no
    fragment's own punctuation can make two lists read alike.
    """
    constraints = json.dumps(
        list(options.dietary_constraints), ensure_ascii=False, separators=(",", ":")
    )
    material = "|".join(
        [
            fingerprint_hex(menu),
            model,
            str(schema_version),
            str(options.net_carb_limit_grams),
            constraints,
        ]
    )
    return hashlib.sha256(material.encode("utf-8")).hexdigest()


def _run_in_session[T](engine: Engine, fn: Callable[[Session], T]) -> T:
    """Run ``fn`` over one session obtained from ``get_session``.

    Duplicated from ``app.services.chat_cache`` rather than shared, for the
    reason given there: the services stay independent of one another.
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


def _naive_utc(moment: datetime) -> datetime:
    """``moment`` as a naive UTC timestamp; a naive input is taken as UTC."""
    if moment.tzinfo is None:
        return moment
    return moment.astimezone(UTC).replace(tzinfo=None)


def read_cached(
    engine: Engine, key: str, ttl_seconds: int, now: datetime
) -> MenuAnalysed | None:
    """The cached analysis for ``key`` if it exists, is fresh and still reads.

    A missing row, one older than ``ttl_seconds`` measured from ``now``, or
    one whose JSON no longer validates as a ``MenuAnalysed`` (a row written
    by an older backend) is a miss.
    """

    def _read(session: Session) -> str | None:
        row = session.get(AnalysisCache, key)
        if row is None:
            return None
        created_at = row.created_at
        if created_at.tzinfo is None:
            created_at = created_at.replace(tzinfo=UTC)
        if now - created_at > timedelta(seconds=ttl_seconds):
            return None
        return row.analysis_json

    text = _run_in_session(engine, _read)
    if text is None:
        return None
    try:
        return MenuAnalysed.model_validate_json(text)
    except ValidationError:
        return None


def write_cached(
    engine: Engine, key: str, analysis: MenuAnalysed, now: datetime
) -> None:
    """Insert or replace the cached analysis for ``key``.

    Only ever called with an analysis the language model made (an ``llm``
    engine): the caller never passes a rules fallback. ``session.merge``
    upserts, so an expired row is simply replaced.
    """
    text = json.dumps(
        to_json(analysis), ensure_ascii=False, separators=(",", ":"), allow_nan=False
    )
    stamp = _naive_utc(now)

    def _write(session: Session) -> None:
        session.merge(AnalysisCache(key=key, analysis_json=text, created_at=stamp))

    _run_in_session(engine, _write)

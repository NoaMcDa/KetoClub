"""The anonymous shared store of opened menus (#310).

One row per ``(source, platform_id)``: a venue's menu on one platform. An
upload inserts the row or refreshes it; nothing here ever sees who uploaded
it. The route requires an install id for rate limiting only and never passes
it in (D12, #164), so no signature below has a parameter that could carry
one.

The read/write shape is ``app.services.chat_cache``'s: sync functions over a
session obtained from ``app.db.get_session``, called from the async route
through ``run_in_threadpool``. Timestamps are stored naive UTC, the
``MenuCache.fetched_at`` convention, and ``now`` is always passed in so
tests move time without sleeping.
"""

import json
import math
from collections.abc import Callable
from datetime import UTC, datetime
from typing import Any

from sqlalchemy import Engine
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.db import get_session
from app.models import StoredMenu


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


def to_json(value: dict[str, Any]) -> str:
    """``value`` as compact JSON text, or ``ValueError`` for NaN/Infinity.

    Python's parser accepts ``NaN`` in a request body, but no JSON reader
    the app uses does, so such a menu is refused rather than stored in a
    form a later ``GET`` could not answer.
    """
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"), allow_nan=False)


def count_dishes(menu: dict[str, Any]) -> int:
    """The number of dishes across ``menu["categories"][*]["dishes"]``.

    Tolerant: a missing or mis-shaped ``categories`` list, a category that is
    not an object or a ``dishes`` that is not a list each count as zero
    rather than failing the upload.
    """
    categories = menu.get("categories")
    if not isinstance(categories, list):
        return 0
    total = 0
    for category in categories:
        if not isinstance(category, dict):
            continue
        dishes = category.get("dishes")
        if isinstance(dishes, list):
            total += len(dishes)
    return total


def score_of(analysis: dict[str, Any] | None) -> float | None:
    """A top-level finite numeric ``score`` in ``analysis``, else None.

    The backend computes no score of its own; it only keeps the one the
    client's analysis carries. ``True``/``False`` are not numbers here.
    """
    if analysis is None:
        return None
    score = analysis.get("score")
    if isinstance(score, bool) or not isinstance(score, int | float):
        return None
    as_float = float(score)
    return as_float if math.isfinite(as_float) else None


def _existing(session: Session, source: str, platform_id: str) -> StoredMenu | None:
    """The stored row for the key, if any. A seam for the insert-race test."""
    return session.get(StoredMenu, (source, platform_id))


def upsert(
    engine: Engine,
    *,
    source: str,
    platform_id: str,
    venue_name: str | None,
    city: str | None,
    menu: dict[str, Any],
    analysis: dict[str, Any] | None,
    now: datetime,
) -> tuple[bool, int]:
    """Insert or refresh the row for ``(source, platform_id)``.

    Returns ``(created, submission_count)``. A new row starts with
    ``first_seen_at = last_seen_at = now`` and a count of 1. An existing row
    keeps ``first_seen_at``, moves ``last_seen_at`` to ``now`` and counts one
    more upload; its ``menu_json`` and ``dish_count`` are always replaced,
    while ``venue_name``, ``city``, ``analysis_json`` and ``score`` are
    replaced only when this upload carries an analysis (or a name, a city).

    Two first uploads of one venue racing each other both see no row; the
    loser's insert fails the primary key and is retried once as an update.

    Raises ``ValueError`` when ``menu`` or ``analysis`` holds NaN/Infinity.
    """
    stamp = _naive_utc(now)
    menu_json = to_json(menu)
    analysis_json = None if analysis is None else to_json(analysis)
    dish_count = count_dishes(menu)
    score = score_of(analysis)

    def _write(session: Session) -> tuple[bool, int]:
        row = _existing(session, source, platform_id)
        if row is None:
            session.add(
                StoredMenu(
                    source=source,
                    platform_id=platform_id,
                    venue_name=venue_name,
                    city=city,
                    menu_json=menu_json,
                    analysis_json=analysis_json,
                    dish_count=dish_count,
                    score=score,
                    first_seen_at=stamp,
                    last_seen_at=stamp,
                    submission_count=1,
                )
            )
            session.flush()
            return True, 1
        row.menu_json = menu_json
        row.dish_count = dish_count
        if venue_name is not None:
            row.venue_name = venue_name
        if city is not None:
            row.city = city
        if analysis_json is not None:
            row.analysis_json = analysis_json
            row.score = score
        row.last_seen_at = stamp
        row.submission_count += 1
        count = row.submission_count
        session.flush()
        return False, count

    try:
        return _run_in_session(engine, _write)
    except IntegrityError:
        return _run_in_session(engine, _write)


def get(engine: Engine, source: str, platform_id: str) -> StoredMenu | None:
    """The stored row for ``(source, platform_id)``, detached, or None.

    The row is expunged before the session commits, so its loaded
    attributes stay readable after the session is gone.
    """

    def _read(session: Session) -> StoredMenu | None:
        row = _existing(session, source, platform_id)
        if row is not None:
            session.expunge(row)
        return row

    return _run_in_session(engine, _read)


def from_json(text: str) -> dict[str, Any]:
    """A stored ``menu_json``/``analysis_json`` back as an object.

    Only ever called on text ``to_json`` wrote, so it is an object; anything
    else (a hand-edited row) reads as an empty one rather than a 500.
    """
    value = json.loads(text)
    return value if isinstance(value, dict) else {}

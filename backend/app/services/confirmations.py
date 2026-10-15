"""Anonymous post-meal confirmations of what a dish contains (ALG-14, #356).

One ``dish_confirmations`` row per ``(venue, dish fingerprint, restriction id,
polarity)``: a count and two dates, never an install id and never a note (the
D24 rule). This module is the only code that writes the table, and nothing
here can see a sender: :func:`record` takes a ``token`` that
:func:`voter_token` made from the install id, and no signature has a
parameter that could carry the id itself.

**Distinct counting without storing who.** The threshold counts different
people, so a second post from one install must not count twice. The first
post of a fact inserts its token into ``confirmation_voters``; a later post
recomputes the same token, finds it and counts only as a repeat. The token is
``HMAC-SHA256(pepper, install id | venue | dish | restriction | polarity)``
(:func:`voter_token`), which is one-way, differs for every fact an install
confirms, and sits in a table with no other column. See
``app.models.ConfirmationVoter``.

Reads and writes follow ``app.services.menu_store``: sync functions over a
session from ``app.db.get_session``, called from the async route through
``run_in_threadpool``. Dates are UTC calendar dates and ``today`` is passed
in, so tests move time without sleeping.
"""

import hashlib
import hmac
import json
from collections.abc import Callable
from dataclasses import dataclass
from datetime import date
from typing import Final

from sqlalchemy import Engine, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.db import get_session
from app.models import ConfirmationVoter, DishConfirmation

MIN_DISTINCT_CONFIRMATIONS: Final = 3
"""A polarity's count is shown only once this many different installs have
confirmed the fact (ALG-14, "Abuse")."""

PRESENT: Final = "present"
ABSENT: Final = "absent"


@dataclass(frozen=True, slots=True)
class ConfirmationSummary:
    """The shown counts for one ``(dish fingerprint, restriction id)``.

    A polarity under the threshold is 0 here, never its real count.
    """

    dish_fingerprint: str
    restriction_id: str
    present: int
    absent: int
    first: date
    last: date


def _run_in_session[T](engine: Engine, fn: Callable[[Session], T]) -> T:
    """Run ``fn`` over one session obtained from ``get_session``.

    Duplicated from ``app.services.menu_store`` rather than shared, for the
    reason given in ``app.services.chat_cache``: the services stay
    independent of one another.
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


def voter_token(
    pepper: str,
    install_id: str,
    *,
    source: str,
    platform_id: str,
    dish_fingerprint: str,
    restriction_id: str,
    polarity: str,
) -> str:
    """The one-way token that marks "this install confirmed this fact".

    The fields are encoded as a JSON array, so no choice of strings can make
    two different facts encode alike. The same install gets an unrelated
    token for every fact, so tokens cannot be grouped by install.
    """
    message = json.dumps(
        [install_id, source, platform_id, dish_fingerprint, restriction_id, polarity],
        ensure_ascii=True,
        separators=(",", ":"),
    )
    return hmac.new(
        pepper.encode("utf-8"), message.encode("ascii"), hashlib.sha256
    ).hexdigest()


def record(
    engine: Engine,
    *,
    source: str,
    platform_id: str,
    dish_fingerprint: str,
    restriction_id: str,
    polarity: str,
    token: str,
    today: date,
) -> bool:
    """Count one confirmation; True when it was new, False for a repeat.

    A new ``token`` adds a voter, adds one to ``distinct_count`` and
    ``submission_count`` (creating the row at 1 and 1 when there is none) and
    moves ``last_on`` to ``today``. A token already seen only adds one to
    ``submission_count``: the fact is not counted twice.

    Two first posts of one token racing each other both see no voter; the
    loser's insert fails the primary key and is retried once as a repeat.
    """

    def _write(session: Session) -> bool:
        key = (source, platform_id, dish_fingerprint, restriction_id, polarity)
        row = session.get(DishConfirmation, key)
        if session.get(ConfirmationVoter, token) is not None:
            if row is not None:
                row.submission_count += 1
            return False
        session.add(ConfirmationVoter(token=token))
        if row is None:
            session.add(
                DishConfirmation(
                    source=source,
                    platform_id=platform_id,
                    dish_fingerprint=dish_fingerprint,
                    restriction_id=restriction_id,
                    polarity=polarity,
                    distinct_count=1,
                    submission_count=1,
                    first_on=today,
                    last_on=today,
                )
            )
        else:
            row.distinct_count += 1
            row.submission_count += 1
            row.last_on = max(row.last_on, today)
        session.flush()
        return True

    try:
        return _run_in_session(engine, _write)
    except IntegrityError:
        return _run_in_session(engine, _write)


def visible_for(
    engine: Engine, source: str, platform_id: str
) -> list[ConfirmationSummary]:
    """The venue's shown counts, ordered by fingerprint then restriction id.

    Only rows with at least :data:`MIN_DISTINCT_CONFIRMATIONS` distinct
    confirmations are read at all, so a smaller count cannot leak through
    this function: an entry whose other polarity is under the threshold
    reports 0 for it.
    """

    def _read(session: Session) -> list[ConfirmationSummary]:
        rows = session.scalars(
            select(DishConfirmation)
            .where(
                DishConfirmation.source == source,
                DishConfirmation.platform_id == platform_id,
                DishConfirmation.distinct_count >= MIN_DISTINCT_CONFIRMATIONS,
            )
            .order_by(
                DishConfirmation.dish_fingerprint,
                DishConfirmation.restriction_id,
                DishConfirmation.polarity,
            )
        ).all()
        grouped: dict[tuple[str, str], list[DishConfirmation]] = {}
        for row in rows:
            grouped.setdefault((row.dish_fingerprint, row.restriction_id), []).append(
                row
            )
        summaries: list[ConfirmationSummary] = []
        for (fingerprint, restriction_id), shown in grouped.items():
            counts = {row.polarity: row.distinct_count for row in shown}
            summaries.append(
                ConfirmationSummary(
                    dish_fingerprint=fingerprint,
                    restriction_id=restriction_id,
                    present=counts.get(PRESENT, 0),
                    absent=counts.get(ABSENT, 0),
                    first=min(row.first_on for row in shown),
                    last=max(row.last_on for row in shown),
                )
            )
        return summaries

    return _run_in_session(engine, _read)

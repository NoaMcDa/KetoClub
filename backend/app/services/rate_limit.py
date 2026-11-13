"""In-memory, per-install sliding-window rate limiter (backend_plan.md §3.4).

One process, one dict: good enough while the backend is local and runs a
single worker. #109 revisits this for a public host, where a shared store
and an abuse posture beyond a spoofable install id are needed.
"""

import time
from collections import deque
from collections.abc import Callable
from typing import Final

_MINUTE: Final = 60.0
_DAY: Final = 86400.0


SWEEP_EVERY: Final = 1024
"""How many checks pass between two sweeps of ids idle for a day."""

MAX_IDS: Final = 100_000
"""The most ids one limiter holds hits for at once."""


class RateLimiter:
    """At most ``per_minute`` hits in any 60 s and ``per_day`` in any 24 h.

    Both windows slide: each is measured back from the current ``clock()``
    reading, not from a calendar boundary. ``clock`` is injectable so tests
    move time without sleeping; it must be monotonic.

    The map of ids is bounded (#272): an id with no hit left in the last day
    is dropped (swept every ``SWEEP_EVERY`` checks), a refused id with no
    hit is never stored, and past ``max_ids`` the ids least recently let
    through are dropped first.
    """

    def __init__(
        self,
        per_minute: int,
        per_day: int,
        clock: Callable[[], float] = time.monotonic,
        max_ids: int = MAX_IDS,
    ) -> None:
        self._per_minute = per_minute
        self._per_day = per_day
        self._clock = clock
        self._max_ids = max_ids
        self._checks = 0
        # Hit timestamps per install id, oldest first. Pruned to the last day
        # on every check, so each deque holds at most ``per_day`` entries.
        self._hits: dict[str, deque[float]] = {}

    def allow(self, install_id: str) -> bool:
        """Record a hit for ``install_id`` and return True, or return False.

        A refused hit is not recorded, so a client that keeps retrying while
        limited does not push its own window further out.
        """
        now = self._clock()
        self._checks += 1
        if self._checks % SWEEP_EVERY == 0:
            self._sweep(now)
        hits = self._hits.pop(install_id, None) or deque()
        while hits and now - hits[0] >= _DAY:
            hits.popleft()
        # Re-inserted at the end: the dict's order is least recently seen
        # first. A refused id is put back only if it still has hits.
        if hits:
            self._hits[install_id] = hits

        if len(hits) >= self._per_day:
            return False

        in_last_minute = 0
        for stamp in reversed(hits):
            if now - stamp >= _MINUTE:
                break
            in_last_minute += 1
        if in_last_minute >= self._per_minute:
            return False

        hits.append(now)
        self._hits[install_id] = hits
        while len(self._hits) > self._max_ids:
            del self._hits[next(iter(self._hits))]
        return True

    def _sweep(self, now: float) -> None:
        """Drop every id whose newest hit is a day old or more."""
        for stale in [
            key
            for key, hits in self._hits.items()
            if not hits or now - hits[-1] >= _DAY
        ]:
            del self._hits[stale]

    def __len__(self) -> int:
        """How many ids the limiter holds hits for."""
        return len(self._hits)

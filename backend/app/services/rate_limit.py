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


class RateLimiter:
    """At most ``per_minute`` hits in any 60 s and ``per_day`` in any 24 h.

    Both windows slide: each is measured back from the current ``clock()``
    reading, not from a calendar boundary. ``clock`` is injectable so tests
    move time without sleeping; it must be monotonic.
    """

    def __init__(
        self,
        per_minute: int,
        per_day: int,
        clock: Callable[[], float] = time.monotonic,
    ) -> None:
        self._per_minute = per_minute
        self._per_day = per_day
        self._clock = clock
        # Hit timestamps per install id, oldest first. Pruned to the last day
        # on every check, so each deque holds at most ``per_day`` entries.
        self._hits: dict[str, deque[float]] = {}

    def allow(self, install_id: str) -> bool:
        """Record a hit for ``install_id`` and return True, or return False.

        A refused hit is not recorded, so a client that keeps retrying while
        limited does not push its own window further out.
        """
        now = self._clock()
        hits = self._hits.setdefault(install_id, deque())
        while hits and now - hits[0] >= _DAY:
            hits.popleft()

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
        return True

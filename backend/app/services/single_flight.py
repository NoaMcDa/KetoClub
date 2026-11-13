"""One upstream call per key at a time (#272).

Two identical ``/v1/chat`` requests that miss the shared cache together
used to call Gemini twice. ``KeyedLocks.hold(key)`` lets the first through
and makes the others wait; each then re-reads the cache, so the waiters are
answered by the first one's result. A key's lock lives only while someone
holds or waits for it, so the map never grows past the requests in flight.
"""

import asyncio
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager


class KeyedLocks:
    """An ``asyncio.Lock`` per key, created on demand and dropped when idle."""

    def __init__(self) -> None:
        self._locks: dict[str, tuple[asyncio.Lock, list[int]]] = {}

    @asynccontextmanager
    async def hold(self, key: str) -> AsyncIterator[None]:
        """Hold ``key``'s lock for the ``async with`` body."""
        entry = self._locks.get(key)
        if entry is None:
            entry = (asyncio.Lock(), [0])
            self._locks[key] = entry
        lock, users = entry
        users[0] += 1
        try:
            async with lock:
                yield
        finally:
            users[0] -= 1
            if users[0] == 0:
                del self._locks[key]

    def __len__(self) -> int:
        """How many keys are held or waited for right now."""
        return len(self._locks)

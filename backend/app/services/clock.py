"""The one source of the current time, so tests can pass their own.

Mirrors the Flutter side's `services/platform/clock.dart`: functions that care
about freshness take the time as a parameter rather than reading the wall clock
themselves, which is what makes cache expiry testable without sleeping.

Times are naive UTC throughout. SQLite does not preserve a timezone, so storing
aware datetimes would read back naive and compare wrongly; keeping one naive
UTC convention everywhere removes that whole class of bug.
"""

from datetime import UTC, datetime


def utc_now() -> datetime:
    """Returns the current UTC time, without a timezone attached."""
    return datetime.now(tz=UTC).replace(tzinfo=None)

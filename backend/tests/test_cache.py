"""The menu cache, unit-tested with an explicit clock.

Freshness is a boundary condition, and a boundary condition deserves a test
that names which side of it is fresh rather than a sleep.
"""

from datetime import datetime, timedelta

from sqlalchemy.orm import Session

from app.services.cache import read_menu_cache, write_menu_cache

NOW = datetime(2026, 9, 13, 12, 0, 0)
TTL = 3600


def _write(session: Session, *, body: bytes, at: datetime) -> None:
    write_menu_cache(
        session,
        source="wolt",
        slug="a-venue",
        body=body,
        content_type="application/json",
        now=at,
    )


def _read(session: Session, *, at: datetime) -> object | None:
    return read_menu_cache(
        session, source="wolt", slug="a-venue", ttl_seconds=TTL, now=at
    )


def test_an_absent_entry_reads_as_none(session: Session) -> None:
    assert _read(session, at=NOW) is None


def test_a_fresh_entry_reads_back_byte_for_byte(session: Session) -> None:
    _write(session, body=b'{"a": 1}', at=NOW)

    cached = _read(session, at=NOW + timedelta(seconds=TTL - 1))

    assert cached is not None
    assert cached.body == b'{"a": 1}'
    assert cached.content_type == "application/json"


def test_the_freshness_boundary_is_exclusive(session: Session) -> None:
    _write(session, body=b"{}", at=NOW)

    assert _read(session, at=NOW + timedelta(seconds=TTL)) is None


def test_a_second_write_replaces_the_first(session: Session) -> None:
    _write(session, body=b"old", at=NOW)
    _write(session, body=b"new", at=NOW + timedelta(seconds=10))

    cached = _read(session, at=NOW + timedelta(seconds=20))

    assert cached is not None
    assert cached.body == b"new"


def test_two_venues_do_not_share_an_entry(session: Session) -> None:
    _write(session, body=b"first", at=NOW)
    write_menu_cache(
        session,
        source="wolt",
        slug="another-venue",
        body=b"second",
        content_type="application/json",
        now=NOW,
    )

    cached = _read(session, at=NOW)

    assert cached is not None
    assert cached.body == b"first"

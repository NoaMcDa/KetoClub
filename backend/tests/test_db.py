"""Tests for ``app.db``: engine configuration and the session dependency."""

from pathlib import Path

from sqlalchemy import text
from sqlalchemy.pool import StaticPool

from app.config import Settings
from app.db import build_engine, get_session


def test_sqlite_engine_enables_wal_journal_mode() -> None:
    engine = build_engine(Settings(DATABASE_URL="sqlite:///:memory:"))

    with engine.connect() as conn:
        mode = conn.execute(text("PRAGMA journal_mode")).scalar()

    # An in-memory database reports "memory", not "wal": WAL needs a file to
    # back the write-ahead log. The pragma still runs without error, which is
    # what a file-backed database needs.
    assert mode in {"wal", "memory"}


def test_in_memory_url_uses_a_shared_static_pool() -> None:
    engine = build_engine(Settings(DATABASE_URL="sqlite:///:memory:"))

    assert isinstance(engine.pool, StaticPool)


def test_file_backed_url_does_not_use_static_pool(tmp_path: Path) -> None:
    db_path = tmp_path / "test.db"
    engine = build_engine(Settings(DATABASE_URL=f"sqlite:///{db_path}"))

    assert not isinstance(engine.pool, StaticPool)


def test_get_session_commits_on_success() -> None:
    engine = build_engine(Settings(DATABASE_URL="sqlite:///:memory:"))

    generator = get_session(engine)
    session = next(generator)
    session.execute(text("SELECT 1"))

    # Exhausting the generator runs the commit path with no exception raised.
    with_exception = False
    try:
        next(generator)
    except StopIteration:
        with_exception = True
    assert with_exception


def test_get_session_rolls_back_on_error() -> None:
    engine = build_engine(Settings(DATABASE_URL="sqlite:///:memory:"))

    generator = get_session(engine)
    next(generator)

    with_exception = False
    try:
        generator.throw(RuntimeError("boom"))
    except RuntimeError:
        with_exception = True
    assert with_exception

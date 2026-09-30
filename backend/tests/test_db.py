"""Tests for ``app.db``: engine configuration and the session dependency."""

from pathlib import Path

import pytest
from sqlalchemy import Engine, text
from sqlalchemy.orm import Session
from sqlalchemy.pool import StaticPool

from app.config import Settings
from app.db import build_engine, get_session


def _file_engine(tmp_path: Path) -> Engine:
    return build_engine(Settings(DATABASE_URL=f"sqlite:///{tmp_path / 'test.db'}"))


def _create_table(engine: Engine) -> None:
    with engine.begin() as conn:
        conn.execute(text("CREATE TABLE rows (id INTEGER PRIMARY KEY, v TEXT)"))


def _row_count(engine: Engine) -> int:
    with Session(engine) as session:
        return session.execute(text("SELECT COUNT(*) FROM rows")).scalar_one()


def test_sqlite_engine_enables_wal_journal_mode(tmp_path: Path) -> None:
    # A file-backed database is the only kind that can actually report "wal":
    # an in-memory one answers "memory" whether or not the listener ran.
    engine = _file_engine(tmp_path)

    with engine.connect() as conn:
        mode = conn.execute(text("PRAGMA journal_mode")).scalar()

    assert mode == "wal"


def test_in_memory_url_uses_a_shared_static_pool() -> None:
    engine = build_engine(Settings(DATABASE_URL="sqlite:///:memory:"))

    assert isinstance(engine.pool, StaticPool)


def test_file_backed_url_does_not_use_static_pool(tmp_path: Path) -> None:
    engine = _file_engine(tmp_path)

    assert not isinstance(engine.pool, StaticPool)


def test_get_session_commits_on_success(tmp_path: Path) -> None:
    engine = _file_engine(tmp_path)
    _create_table(engine)

    generator = get_session(engine)
    session = next(generator)
    session.execute(text("INSERT INTO rows (v) VALUES ('kept')"))
    with pytest.raises(StopIteration):
        next(generator)

    # A fresh session on a fresh connection sees the row only if it was
    # committed, not merely written inside the request's own transaction.
    assert _row_count(engine) == 1


def test_get_session_rolls_back_on_error(tmp_path: Path) -> None:
    engine = _file_engine(tmp_path)
    _create_table(engine)

    generator = get_session(engine)
    session = next(generator)
    session.execute(text("INSERT INTO rows (v) VALUES ('lost')"))
    with pytest.raises(RuntimeError, match="boom"):
        generator.throw(RuntimeError("boom"))

    assert _row_count(engine) == 0

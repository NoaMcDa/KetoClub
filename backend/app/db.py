"""Database engine and session factory.

Uses a SQLAlchemy 2 sync engine with:
- check_same_thread=False so a single SQLite file is shared across the
  threadpool workers that handle plain ``def`` routes.
- WAL journal mode for better read/write concurrency.
- A session-per-request dependency (``get_session``) for use with
  ``Depends`` in route handlers.

Postgres is an env-var swap later (set DATABASE_URL to a postgres:// URL and
remove the SQLite-specific connect_args).  Alembic arrives alongside it.
"""

from collections.abc import Generator
from typing import Any

from sqlalchemy import Engine, create_engine, event
from sqlalchemy.orm import DeclarativeBase, Session

from app.config import Settings


def build_engine(settings: Settings) -> Engine:
    """Create and return a configured SQLAlchemy engine.

    Called once from the lifespan context in ``main.py``; the result is stored
    on ``app.state`` so routes never rebuild it.  Tests pass an in-memory URL
    with ``StaticPool`` to avoid touching the filesystem.
    """
    connect_args: dict[str, Any] = {}
    if settings.DATABASE_URL.startswith("sqlite"):
        connect_args["check_same_thread"] = False

    engine = create_engine(settings.DATABASE_URL, connect_args=connect_args)

    # Enable WAL journal mode for SQLite.  WAL lets reads proceed while a
    # write is in progress, which matters even with a single worker because the
    # proxy and community routes may overlap.
    if settings.DATABASE_URL.startswith("sqlite"):

        @event.listens_for(engine, "connect")
        def set_wal(dbapi_conn: Any, _connection_record: Any) -> None:
            cursor = dbapi_conn.cursor()
            cursor.execute("PRAGMA journal_mode=WAL")
            cursor.close()

    return engine


def get_session(engine: Engine) -> Generator[Session, None, None]:
    """Yield a database session for the duration of one request.

    Intended for use as a FastAPI dependency via a closure:

        def _get_session() -> Generator[Session, None, None]:
            yield from get_session(app.state.engine)

        router.get(...)(lambda db=Depends(_get_session): ...)

    The session is committed on success and rolled back + closed on any
    exception, guaranteeing no partial writes escape the request boundary.
    """
    with Session(engine) as session:
        try:
            yield session
            session.commit()
        except Exception:
            session.rollback()
            raise


class Base(DeclarativeBase):
    """Shared declarative base for all ORM models."""

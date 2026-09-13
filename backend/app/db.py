"""Database engine, session factory and the declarative base.

Sessions are synchronous. Routes that touch the database are plain `def` so
Starlette runs them in a threadpool; the one `async def` route that writes
(the proxy's cache) goes through `run_in_threadpool` explicitly.
"""

from collections.abc import Iterator
from typing import Any

from fastapi import Request
from sqlalchemy import Engine, create_engine, event
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker
from sqlalchemy.pool import StaticPool


class Base(DeclarativeBase):
    """Declarative base shared by every ORM model."""


def _is_in_memory(database_url: str) -> bool:
    """Whether `database_url` names an in-memory SQLite database."""
    return database_url in {"sqlite://", "sqlite:///:memory:"}


def create_db_engine(database_url: str) -> Engine:
    """Builds an engine for `database_url`.

    SQLite needs three adjustments: `check_same_thread` off, because Starlette
    serves requests from a threadpool; write-ahead logging, so a read during a
    write does not block; and, for an in-memory database, a single shared
    connection, since the default pool would hand every caller its own empty
    database. The last one is what makes `sqlite://` usable in tests.
    """
    connect_args: dict[str, Any] = {}
    kwargs: dict[str, Any] = {}
    is_sqlite = database_url.startswith("sqlite")
    if is_sqlite:
        connect_args["check_same_thread"] = False
    if is_sqlite and _is_in_memory(database_url):
        kwargs["poolclass"] = StaticPool

    engine = create_engine(
        database_url, connect_args=connect_args, future=True, **kwargs
    )

    if is_sqlite:

        @event.listens_for(engine, "connect")
        # The DBAPI connection and the connection record are whatever the
        # driver hands back; SQLAlchemy publishes no protocol for either, so
        # `Any` is the honest annotation rather than a dodged one.
        def _set_sqlite_pragma(
            dbapi_connection: Any,  # noqa: ANN401
            _record: Any,  # noqa: ANN401
        ) -> None:
            cursor = dbapi_connection.cursor()
            cursor.execute("PRAGMA journal_mode=WAL")
            cursor.close()

    return engine


def create_session_factory(engine: Engine) -> sessionmaker[Session]:
    """Builds the session factory stored on the application state."""
    return sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)


def get_session(request: Request) -> Iterator[Session]:
    """Yields one session per request, closed when the request ends."""
    factory: sessionmaker[Session] = request.app.state.session_factory
    with factory() as session:
        yield session

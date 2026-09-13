"""ORM models.

Nothing here stores anything about a person. The menu cache holds a restaurant
platform's own response; when the chat cache arrives it will hold dish text and
model verdicts, never an install id alongside them (architecture.md §11).
"""

from datetime import datetime

from sqlalchemy import DateTime, LargeBinary, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.db import Base


class MenuCacheEntry(Base):
    """One upstream menu body, cached verbatim.

    The body is stored as received so the proxy can replay it byte for byte;
    parsing it is the Flutter mapper's job, not this service's.
    """

    __tablename__ = "menu_cache"
    __table_args__ = (
        UniqueConstraint("source", "slug", name="uq_menu_cache_source_slug"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    source: Mapped[str] = mapped_column(String(16))
    slug: Mapped[str] = mapped_column(String(128))
    body: Mapped[bytes] = mapped_column(LargeBinary)
    content_type: Mapped[str] = mapped_column(String(128))
    fetched_at: Mapped[datetime] = mapped_column(DateTime)

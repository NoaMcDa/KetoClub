"""SQLAlchemy ORM models.

``menu_cache`` (#95) is the first table. Future issues declare more tables
here against ``app.db.Base`` — ``chat_cache`` (#103), ``venues`` and
``ratings``/``dish_feedback`` (#105, #106), ``submissions`` (#107) — so one
``Base.metadata.create_all`` call in the lifespan creates every table.
"""

from datetime import datetime

from sqlalchemy import DateTime, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from app.db import Base

__all__ = ["Base", "MenuCache"]


class MenuCache(Base):
    """A cached raw Wolt menu response, keyed by venue slug (issue #95).

    Only a 2xx upstream response is ever written here; a failed fetch is
    never cached (``backend_plan.md`` §3.3). ``fetched_at`` is stored as a
    naive UTC timestamp — the proxy route treats a row older than
    ``Settings.MENU_CACHE_TTL_SECONDS`` as a miss and replaces it.
    """

    __tablename__ = "menu_cache"

    slug: Mapped[str] = mapped_column(String, primary_key=True)
    status_code: Mapped[int] = mapped_column(Integer, nullable=False)
    content_type: Mapped[str] = mapped_column(String, nullable=False)
    body: Mapped[str] = mapped_column(Text, nullable=False)
    fetched_at: Mapped[datetime] = mapped_column(DateTime, nullable=False)

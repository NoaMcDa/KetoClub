"""SQLAlchemy ORM models.

Empty for now: ``GET /v1/health`` (#94) needs no table. Future issues declare
their tables here against ``app.db.Base`` — ``menu_cache`` (#95),
``chat_cache`` (#103), ``venues`` and ``ratings``/``dish_feedback`` (#105,
#106), ``submissions`` (#107) — so one ``Base.metadata.create_all`` call in
the lifespan creates every table.
"""

from app.db import Base

__all__ = ["Base"]

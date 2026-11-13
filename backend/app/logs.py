"""One place that makes every ``ketoclub.*`` logger print (#467).

Uvicorn configures only its own loggers. Python's root logger stays at
WARNING with no handler, so an INFO line from ``ketoclub.classify``,
``ketoclub.scan``, ``ketoclub.website``, ``ketoclub.places`` or any other
module logger was dropped, and only the two loggers that attached their own
handler ever printed. ``configure_logging`` gives the shared ``ketoclub``
parent one stream handler at INFO, so every child prints through it; the
module loggers attach nothing of their own.

The records still propagate to the root logger, so pytest's ``caplog`` sees
them as before; a root handler (``uvicorn --log-config``) would print them a
second time, which is the configurer's choice.
"""

import logging
from typing import Final

PARENT: Final = "ketoclub"
_FORMAT: Final = "%(asctime)s %(name)s %(message)s"


class _KetoclubHandler(logging.StreamHandler):  # type: ignore[type-arg]
    """The handler ``configure_logging`` installs, told apart by its type so
    a second ``create_app`` never adds another."""


def configure_logging() -> logging.Logger:
    """Give the ``ketoclub`` logger level INFO and one stream handler.

    Idempotent: called by every ``create_app``, it installs the handler once.
    """
    logger = logging.getLogger(PARENT)
    logger.setLevel(logging.INFO)
    if not any(isinstance(handler, _KetoclubHandler) for handler in logger.handlers):
        handler = _KetoclubHandler()
        handler.setFormatter(logging.Formatter(_FORMAT))
        logger.addHandler(handler)
    return logger

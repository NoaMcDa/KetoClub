"""Every ``ketoclub.*`` logger prints under uvicorn (#467).

``caplog`` installs its own handler on the root logger, so it captures a
record whatever the app's own setup is; these tests look at the handler
``create_app`` installs instead, which is what a terminal running uvicorn
actually shows.
"""

import io
import logging
from collections.abc import Iterator

import pytest

from app.config import Settings
from app.logs import PARENT, configure_logging
from app.main import create_app

_MODULE_LOGGERS = (
    "ketoclub.chat",
    "ketoclub.classify",
    "ketoclub.menus",
    "ketoclub.places",
    "ketoclub.request",
    "ketoclub.scan",
    "ketoclub.venue_menus",
    "ketoclub.website",
    "ketoclub.website_menu",
    "ketoclub.errors",
)


@pytest.fixture
def printed(settings: Settings) -> Iterator[io.StringIO]:
    """What the app's own ``ketoclub`` handler writes, after ``create_app``."""
    create_app(settings=settings)
    handlers = [
        handler
        for handler in logging.getLogger(PARENT).handlers
        if isinstance(handler, logging.StreamHandler)
    ]
    assert len(handlers) == 1
    stream = io.StringIO()
    previous = handlers[0].setStream(stream)
    try:
        yield stream
    finally:
        handlers[0].setStream(previous)


@pytest.mark.parametrize("name", _MODULE_LOGGERS)
def test_an_info_line_from_every_module_logger_is_printed(
    printed: io.StringIO, name: str
) -> None:
    logging.getLogger(name).info("places outcome=timeout features=0 places=0")

    assert f"{name} places outcome=timeout" in printed.getvalue()


def test_no_module_logger_keeps_a_handler_of_its_own(settings: Settings) -> None:
    create_app(settings=settings)

    for name in _MODULE_LOGGERS:
        assert logging.getLogger(name).handlers == [], name


def test_configuring_twice_installs_one_handler(settings: Settings) -> None:
    create_app(settings=settings)
    create_app(settings=settings)
    configure_logging()

    assert len(logging.getLogger(PARENT).handlers) == 1
    assert logging.getLogger(PARENT).level == logging.INFO

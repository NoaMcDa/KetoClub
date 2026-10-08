"""Helpers shared by the D25 analysis route tests (#333).

Every upstream here is a respx route; nothing leaves the sandbox. Gemini's
host is the default ``GEMINI_BASE_URL``, Wolt's and 10bis's the default
``*_BASE_URL`` settings.
"""

import json
from collections.abc import Iterator
from contextlib import contextmanager
from pathlib import Path
from typing import Any

from fastapi.testclient import TestClient
from sqlalchemy import Engine, inspect, text

from app.config import Settings
from app.keto.models import Menu
from app.main import create_app

KEY = "test-gemini-key-for-d25-analysis-that-must-never-be-logged"
INSTALL_ID = "fedcba9876543210fedcba9876543210"
HEADERS = {"X-KetoClub-Install-Id": INSTALL_ID}
GEMINI_URL = (
    "https://generativelanguage.googleapis.com"
    "/v1beta/models/gemini-3.5-flash:generateContent"
)
MODEL_VERSION = "gemini-3.5-flash-001"

_GOLDEN = Path(__file__).parent / "fixtures" / "golden"


def golden(name: str) -> Any:
    """One golden fixture file, parsed."""
    return json.loads((_GOLDEN / name).read_text(encoding="utf-8"))


def golden_entry(name: str, entry: str) -> dict[str, Any]:
    """The entry named ``entry`` of a list-shaped golden file."""
    found: dict[str, Any] = next(e for e in golden(name) if e["name"] == entry)
    return found


def settings(**overrides: object) -> Settings:
    """Settings with a Gemini key and roomy limits, unless overridden."""
    fields: dict[str, object] = {
        "DATABASE_URL": "sqlite:///:memory:",
        "GEMINI_API_KEY": KEY,
        "ANALYSIS_RATE_LIMIT_PER_MINUTE": 100,
        "ANALYSIS_RATE_LIMIT_PER_DAY": 1000,
    }
    fields.update(overrides)
    return Settings(**fields)  # type: ignore[arg-type]


@contextmanager
def client(app_settings: Settings) -> Iterator[TestClient]:
    """A ``TestClient`` over an app built with ``app_settings``."""
    with TestClient(create_app(settings=app_settings)) as test_client:
        yield test_client


def gemini_answer(content: str) -> dict[str, Any]:
    """A Gemini ``generateContent`` 200 body whose one candidate says
    ``content``."""
    return {
        "candidates": [
            {"finishReason": "STOP", "content": {"parts": [{"text": content}]}}
        ],
        "modelVersion": MODEL_VERSION,
    }


def all_green_reply(menu: Menu) -> str:
    """A model reply placing every dish of ``menu`` as ``orderAsIs``."""
    return json.dumps(
        {
            "dishes": [
                {
                    "id": dish.id,
                    "name": dish.name,
                    "verdict": "orderAsIs",
                    "why": "Plain protein.",
                    "modification": None,
                    "net_carbs_estimate": 1,
                    "hidden_carbs": [],
                }
                for dish in menu.all_dishes()
            ]
        },
        ensure_ascii=False,
    )


def database_text(engine: Engine) -> str:
    """Every row of every table, as text: for "the install id is nowhere"."""
    dumped: list[str] = []
    with engine.connect() as connection:
        for table in inspect(engine).get_table_names():
            for row in connection.execute(text(f'SELECT * FROM "{table}"')):
                dumped.append(repr(tuple(row)))
    return "\n".join(dumped)

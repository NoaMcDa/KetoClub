"""Tests for ``app.services.menu_store`` (#310), with no HTTP at all."""

import json
from collections.abc import Iterator
from datetime import UTC, datetime, timedelta, timezone
from typing import Any

import pytest
from sqlalchemy import Engine, inspect
from sqlalchemy.orm import Session

from app.config import Settings
from app.db import build_engine
from app.models import Base, StoredMenu
from app.services import menu_store

_T0 = datetime(2026, 10, 8, 12, 0, tzinfo=UTC)
_MENU: dict[str, Any] = {
    "categories": [
        {"name": "Mains", "dishes": [{"name": "Steak"}, {"name": "Salmon"}]},
        {"name": "Salads", "dishes": [{"name": "Greek"}]},
    ]
}


@pytest.fixture
def engine() -> Iterator[Engine]:
    built = build_engine(Settings(DATABASE_URL="sqlite:///:memory:"))
    Base.metadata.create_all(built)
    yield built
    built.dispose()


def _upsert(engine: Engine, **overrides: Any) -> tuple[bool, int]:
    fields: dict[str, Any] = {
        "source": "wolt",
        "platform_id": "hamosad",
        "venue_name": "Hamosad",
        "city": "Tel Aviv",
        "menu": _MENU,
        "analysis": {"score": 72.5, "dishes": []},
        "now": _T0,
    }
    fields.update(overrides)
    return menu_store.upsert(engine, **fields)


def _row(engine: Engine, source: str = "wolt", key: str = "hamosad") -> StoredMenu:
    row = menu_store.get(engine, source, key)
    assert row is not None
    return row


def test_the_table_has_no_install_id_column(engine: Engine) -> None:
    columns = {c["name"] for c in inspect(engine).get_columns("stored_menus")}
    assert columns == {
        "source",
        "platform_id",
        "venue_name",
        "city",
        "menu_json",
        "analysis_json",
        "dish_count",
        "score",
        "first_seen_at",
        "last_seen_at",
        "submission_count",
    }
    assert not any("install" in name for name in columns)


def test_insert_stamps_both_times_and_counts_one(engine: Engine) -> None:
    assert _upsert(engine) == (True, 1)

    row = _row(engine)
    assert row.first_seen_at == row.last_seen_at == _T0.replace(tzinfo=None)
    assert row.submission_count == 1
    assert row.dish_count == 3
    assert row.score == 72.5
    assert row.venue_name == "Hamosad"
    assert row.city == "Tel Aviv"
    assert json.loads(row.menu_json) == _MENU


def test_update_keeps_first_seen_and_advances_last_seen(engine: Engine) -> None:
    _upsert(engine)
    later = _T0 + timedelta(hours=3)
    new_menu = {"categories": [{"dishes": [{"name": "Only"}]}]}

    assert _upsert(engine, menu=new_menu, now=later) == (False, 2)
    assert _upsert(engine, now=later + timedelta(minutes=1)) == (False, 3)

    row = _row(engine)
    assert row.first_seen_at == _T0.replace(tzinfo=None)
    assert row.last_seen_at == (later + timedelta(minutes=1)).replace(tzinfo=None)
    assert row.submission_count == 3


def test_menu_is_always_replaced(engine: Engine) -> None:
    _upsert(engine)
    new_menu = {"categories": [{"dishes": [{"name": "Only"}]}]}
    _upsert(engine, menu=new_menu)

    row = _row(engine)
    assert json.loads(row.menu_json) == new_menu
    assert row.dish_count == 1


def test_null_name_city_and_analysis_never_overwrite(engine: Engine) -> None:
    _upsert(engine)
    _upsert(engine, venue_name=None, city=None, analysis=None)

    row = _row(engine)
    assert row.venue_name == "Hamosad"
    assert row.city == "Tel Aviv"
    assert row.analysis_json is not None
    assert json.loads(row.analysis_json)["score"] == 72.5
    assert row.score == 72.5


def test_non_null_values_replace(engine: Engine) -> None:
    _upsert(engine)
    _upsert(engine, venue_name="Hamosad 2", city="Haifa", analysis={"score": 10})

    row = _row(engine)
    assert row.venue_name == "Hamosad 2"
    assert row.city == "Haifa"
    assert row.score == 10.0


def test_keys_are_the_pair_not_the_id_alone(engine: Engine) -> None:
    _upsert(engine)
    assert _upsert(engine, source="tenbis") == (True, 1)
    assert menu_store.get(engine, "scan", "hamosad") is None


def test_an_aware_non_utc_now_is_stored_as_utc(engine: Engine) -> None:
    plus_three = timezone(timedelta(hours=3))
    _upsert(engine, now=datetime(2026, 10, 8, 15, 0, tzinfo=plus_three))
    assert _row(engine).first_seen_at == datetime(2026, 10, 8, 12, 0)


def test_a_naive_now_is_taken_as_utc(engine: Engine) -> None:
    _upsert(engine, now=datetime(2026, 10, 8, 12, 0))
    assert _row(engine).first_seen_at == datetime(2026, 10, 8, 12, 0)


def test_a_racing_first_insert_is_retried_as_an_update(
    engine: Engine, monkeypatch: pytest.MonkeyPatch
) -> None:
    _upsert(engine)
    real = menu_store._existing
    calls = {"n": 0}

    def blind_once(session: Session, source: str, key: str) -> StoredMenu | None:
        calls["n"] += 1
        return None if calls["n"] == 1 else real(session, source, key)

    monkeypatch.setattr(menu_store, "_existing", blind_once)

    assert _upsert(engine) == (False, 2)


def test_nan_is_refused(engine: Engine) -> None:
    with pytest.raises(ValueError):
        _upsert(engine, menu={"categories": [], "x": float("nan")})
    assert menu_store.get(engine, "wolt", "hamosad") is None


@pytest.mark.parametrize(
    ("menu", "expected"),
    [
        ({}, 0),
        ({"categories": "nope"}, 0),
        ({"categories": ["nope", {"dishes": "nope"}, {"name": "empty"}]}, 0),
        ({"categories": [{"dishes": [1, 2]}, {"dishes": []}]}, 2),
    ],
)
def test_count_dishes_is_tolerant(menu: dict[str, Any], expected: int) -> None:
    assert menu_store.count_dishes(menu) == expected


@pytest.mark.parametrize(
    ("analysis", "expected"),
    [
        (None, None),
        ({}, None),
        ({"score": "80"}, None),
        ({"score": True}, None),
        ({"score": float("inf")}, None),
        ({"score": 80}, 80.0),
        ({"score": 61.5}, 61.5),
        ({"summary": {"score": 50}}, None),
    ],
)
def test_score_is_only_a_top_level_number(
    analysis: dict[str, Any] | None, expected: float | None
) -> None:
    assert menu_store.score_of(analysis) == expected


def test_from_json_reads_a_non_object_as_empty() -> None:
    assert menu_store.from_json("[1, 2]") == {}
    assert menu_store.from_json('{"a": 1}') == {"a": 1}

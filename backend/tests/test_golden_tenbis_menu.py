"""Replay of ``fixtures/golden/tenbis_menu.json`` through ``map_tenbis_menu``.

Each golden entry is one raw 10bis payload, the ref and clock it was mapped
with, and what the Dart ``TenBisMenuMapper`` answered (``null`` for a payload
it refuses). The Python mapper must answer the same, byte for byte once both
sides are written as canonical JSON (#323).
"""

import json
from pathlib import Path
from typing import Any

import pytest

from app.keto.models import VenueRef, to_json
from app.platforms._dart import dart_num_to_string
from app.platforms.tenbis_menu import map_tenbis_menu

_GOLDEN = Path(__file__).parent / "fixtures" / "golden" / "tenbis_menu.json"
_ENTRIES: list[dict[str, Any]] = json.loads(_GOLDEN.read_text(encoding="utf-8"))


def _canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, ensure_ascii=False)


def test_golden_is_not_empty() -> None:
    assert len(_ENTRIES) >= 5
    assert any(entry["menu"] is None for entry in _ENTRIES)
    assert any(entry["menu"] is not None for entry in _ENTRIES)


@pytest.mark.parametrize("entry", _ENTRIES, ids=[e["name"] for e in _ENTRIES])
def test_tenbis_menu_matches_golden(entry: dict[str, Any]) -> None:
    menu = map_tenbis_menu(
        entry["raw"],
        ref=VenueRef.model_validate(entry["ref"]),
        fetched_at=entry["fetchedAt"],
    )
    actual = None if menu is None else to_json(menu)
    assert _canonical(actual) == _canonical(entry["menu"])


@pytest.mark.parametrize("raw", [None, [], "menu", 7])
def test_non_object_payload_is_none(raw: object) -> None:
    ref = VenueRef(source="tenbis", platform_id="1")
    assert map_tenbis_menu(raw, ref=ref, fetched_at="2026-01-01T00:00:00.000Z") is None


@pytest.mark.parametrize(
    ("number", "text"),
    [
        (7, "7"),
        (-3, "-3"),
        (12.0, "12.0"),
        (12.5, "12.5"),
        (-0.0, "-0.0"),
        (0.000001, "0.000001"),
        (1e-7, "1e-7"),
        (1e16, "10000000000000000.0"),
        (1.5e20, "150000000000000000000.0"),
        (1e21, "1e+21"),
        (1.25e22, "1.25e+22"),
        (123456.789, "123456.789"),
    ],
)
def test_dart_number_to_string(number: float, text: str) -> None:
    assert dart_num_to_string(number) == text


def test_letterless_category_name_falls_back_to_a_hash_id() -> None:
    raw = {"categoriesList": [{"categoryName": "!!!", "dishList": []}]}
    ref = VenueRef(source="tenbis", platform_id="1")
    menu = map_tenbis_menu(raw, ref=ref, fetched_at="2026-01-01T00:00:00.000Z")
    assert menu is not None
    category_id = menu.categories[0].id
    assert category_id.startswith("cat_")
    assert int(category_id.removeprefix("cat_"), 16) > 0
    assert menu.categories[0].name == "!!!"


def test_dotted_capital_i_lowercases_to_plain_i_in_a_slug() -> None:
    raw = {"categoriesList": [{"categoryName": "İzmir", "dishList": []}]}
    ref = VenueRef(source="tenbis", platform_id="1")
    menu = map_tenbis_menu(raw, ref=ref, fetched_at="2026-01-01T00:00:00.000Z")
    assert menu is not None
    assert menu.categories[0].id == "cat_izmir"

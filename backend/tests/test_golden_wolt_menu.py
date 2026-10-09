"""Replay of ``fixtures/golden/wolt_menu.json`` through ``map_wolt_menu`` (#323).

Each golden entry is one raw Wolt payload, the ref and clock it was mapped
with, and what the Dart ``WoltMenuMapper`` answered (``null`` for a payload
it refuses). The Python mapper must answer the same, byte for byte once both
sides are written as canonical JSON.
"""

import json
from pathlib import Path
from typing import Any

import pytest

from app.keto.models import VenueRef, to_json
from app.platforms.wolt_menu import map_wolt_menu

_GOLDEN = Path(__file__).parent / "fixtures" / "golden" / "wolt_menu.json"
_ENTRIES: list[dict[str, Any]] = json.loads(_GOLDEN.read_text(encoding="utf-8"))


def _canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, ensure_ascii=False)


def test_golden_is_not_empty() -> None:
    assert len(_ENTRIES) >= 10
    assert any(entry["menu"] is None for entry in _ENTRIES)
    assert any(entry["menu"] is not None for entry in _ENTRIES)


@pytest.mark.parametrize("entry", _ENTRIES, ids=[e["name"] for e in _ENTRIES])
def test_wolt_menu_matches_golden(entry: dict[str, Any]) -> None:
    menu = map_wolt_menu(
        entry["raw"],
        ref=VenueRef.model_validate(entry["ref"]),
        fetched_at=entry["fetchedAt"],
    )
    actual = None if menu is None else to_json(menu)
    assert _canonical(actual) == _canonical(entry["menu"])


@pytest.mark.parametrize("raw", [None, [], "menu", 7])
def test_non_object_payload_is_none(raw: object) -> None:
    ref = VenueRef(source="wolt", platform_id="x")
    assert map_wolt_menu(raw, ref=ref, fetched_at="2026-01-01T00:00:00.000Z") is None

"""``app.keto.fingerprint`` replays the golden ``fingerprint.json`` (#322).

Each entry is a named menu (a platform fixture, a pasted or scanned menu, a
hand-built one), every dish's ``dishSearchText`` and the 8-hex-digit
32-bit FNV-1a fingerprint the Dart ``TextNormaliser.menuFingerprint`` gave.
"""

import json
from pathlib import Path
from typing import Any

import pytest

from app.keto.fingerprint import fingerprint_hex, fnv1a32, menu_fingerprint, scan_ref
from app.keto.models import Menu
from app.keto.normaliser import dish_search_text

_GOLDEN = Path(__file__).parent / "fixtures" / "golden" / "fingerprint.json"
_ENTRIES: list[dict[str, Any]] = json.loads(_GOLDEN.read_text(encoding="utf-8"))


@pytest.mark.parametrize("entry", _ENTRIES, ids=[entry["name"] for entry in _ENTRIES])
def test_every_golden_menu_fingerprints_as_dart_does(entry: dict[str, Any]) -> None:
    assert set(entry) == {"name", "menu", "searchTexts", "hex"}
    menu = Menu.model_validate(entry["menu"])
    assert [dish_search_text(dish) for dish in menu.all_dishes()] == entry[
        "searchTexts"
    ]
    assert fingerprint_hex(menu) == entry["hex"]
    assert menu_fingerprint(menu) == int(entry["hex"], 16)
    # A pasted or scanned menu is addressed by its own fingerprint (D23).
    if entry["name"].startswith(("pasted_", "scanned_")):
        assert scan_ref(menu) == menu.venue_ref


def test_the_corpus_covers_every_menu_family() -> None:
    names = [entry["name"] for entry in _ENTRIES]
    assert len(names) == 12
    for prefix in ("wolt_", "tenbis_", "pasted_", "scanned_", "english"):
        assert any(name.startswith(prefix) for name in names)


def test_fnv1a32_reads_utf16_code_units() -> None:
    # The FNV-1a test vectors, then an astral character (two units) and a
    # lone surrogate (one unit, carried through rather than an error).
    assert fnv1a32("") == 0x811C9DC5
    assert fnv1a32("a") == 0xE40C292C
    assert fnv1a32("foobar") == 0xBF9CF968
    by_units = 0x811C9DC5
    for unit in (0xD83C, 0xDF54):
        by_units = ((by_units ^ unit) * 16777619) & 0xFFFFFFFF
    assert fnv1a32("\U0001f354") == by_units
    assert 0 <= fnv1a32("\ud83c") <= 0xFFFFFFFF


def test_an_empty_menu_hashes_to_the_offset_basis() -> None:
    menu = Menu.model_validate(_ENTRIES[0]["menu"])
    empty = menu.model_copy(update={"categories": []})
    assert fingerprint_hex(empty) == "811c9dc5"

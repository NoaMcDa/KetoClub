"""Replay of ``fixtures/golden/text_menu.json`` through ``text_menu.parse``.

Each golden entry is a pasted text, the name Dart gave the uncategorised
section, and the ``Menu`` ``TextMenuSource.parse`` answered with a fixed
clock (``null`` when the text holds no dish). The Python port must answer the
same, once both sides are written as canonical JSON (#326).
"""

import json
import re
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

import pytest

from app.keto.models import to_json
from app.keto.text_menu import (
    PRICE_SUFFIX_SOURCE,
    WS,
    dart_iso8601,
    dart_upper_first,
    parse,
    starts_lowercase,
)
from app.keto.vocabulary import vocabulary

_GOLDEN = Path(__file__).parent / "fixtures" / "golden" / "text_menu.json"
_ENTRIES: list[dict[str, Any]] = json.loads(_GOLDEN.read_text(encoding="utf-8"))
_GOLDEN_NOW = datetime(2026, 1, 1, tzinfo=UTC)


def _canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, ensure_ascii=False)


def _entry_id(index: int, entry: dict[str, Any]) -> str:
    first = entry["text"].split("\n", 1)[0][:30]
    return f"{index + 1:02d}-{first}-{entry['uncategorisedName']}"


def test_golden_is_not_empty() -> None:
    assert len(_ENTRIES) >= 40
    assert any(entry["menu"] is None for entry in _ENTRIES)
    assert any(entry["menu"] is not None for entry in _ENTRIES)


@pytest.mark.parametrize(
    "entry",
    _ENTRIES,
    ids=[_entry_id(index, entry) for index, entry in enumerate(_ENTRIES)],
)
def test_text_menu_matches_golden(entry: dict[str, Any]) -> None:
    menu = parse(
        entry["text"], now=_GOLDEN_NOW, uncategorised_name=entry["uncategorisedName"]
    )
    actual = None if menu is None else to_json(menu)
    assert _canonical(actual) == _canonical(entry["menu"])


def test_the_clock_may_be_a_ready_made_string() -> None:
    menu = parse("Steak", now="2026-01-01T00:00:00.000Z")
    assert menu is not None
    assert menu.fetched_at == "2026-01-01T00:00:00.000Z"


def test_the_default_section_name_is_pasted_menu() -> None:
    menu = parse("Steak", now=_GOLDEN_NOW)
    assert menu is not None
    assert menu.categories[0].name == "Pasted menu"


def test_price_suffix_source_is_the_vocabulary_pattern_spelled_for_python() -> None:
    dart = vocabulary().pasted.pasted_price_suffix.pattern
    spelled = dart.replace(r"\s", WS).replace(r"\d", "[0-9]").removesuffix("$") + r"\Z"
    assert spelled == PRICE_SUFFIX_SOURCE
    re.compile(PRICE_SUFFIX_SOURCE)


@pytest.mark.parametrize(
    ("moment", "text"),
    [
        (datetime(2026, 1, 1, tzinfo=UTC), "2026-01-01T00:00:00.000Z"),
        (datetime(2026, 3, 4, 5, 6, 7, 8000, tzinfo=UTC), "2026-03-04T05:06:07.008Z"),
        (
            datetime(2026, 3, 4, 5, 6, 7, 8009, tzinfo=UTC),
            "2026-03-04T05:06:07.008009Z",
        ),
        (datetime(2026, 3, 4, 5, 6, 7), "2026-03-04T05:06:07.000"),
    ],
)
def test_dart_iso8601(moment: datetime, text: str) -> None:
    assert dart_iso8601(moment) == text


@pytest.mark.parametrize(
    ("text", "expected"),
    [
        ("steak", "Steak"),
        ("éclair", "Éclair"),
        ("борщ", "Борщ"),
        ("ßeta", "ßeta"),
        ("ᾳx", "ᾼx"),
        ("\U00010428x", "\U00010428x"),
        ("ა", "ა"),
        ("שניצל", "שניצל"),
        ("", ""),
    ],
)
def test_dart_upper_first_is_dart_s_one_to_one_code_unit_mapping(
    text: str, expected: str
) -> None:
    assert dart_upper_first(text) == expected


@pytest.mark.parametrize(
    ("text", "expected"),
    [("é", True), ("ζ", True), ("a", True), ("A", False), ("א", False), ("", False),
     ("1", False), ("ʕ", True), ("\U0001df1f", False)],
)  # fmt: skip
def test_starts_lowercase(text: str, expected: bool) -> None:
    assert starts_lowercase(text) is expected

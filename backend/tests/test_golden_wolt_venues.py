"""Replay of ``fixtures/golden/wolt_venues.json`` through ``map_wolt_venues``.

Each golden entry is one raw Wolt discovery page and what the Dart
``WoltVenueMapper`` answered (``null`` when the page has no ``sections``
list). The Python mapper must answer the same, byte for byte once both sides
are written as canonical JSON (#323).
"""

import json
from pathlib import Path
from typing import Any

import pytest

from app.keto.models import to_json
from app.platforms._dart import dart_https_url, dart_round
from app.platforms.wolt_venues import map_wolt_venues

_GOLDEN = Path(__file__).parent / "fixtures" / "golden" / "wolt_venues.json"
_ENTRIES: list[dict[str, Any]] = json.loads(_GOLDEN.read_text(encoding="utf-8"))


def _canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, ensure_ascii=False)


def test_golden_is_not_empty() -> None:
    assert len(_ENTRIES) >= 4
    assert any(entry["venues"] is None for entry in _ENTRIES)
    assert any(entry["venues"] for entry in _ENTRIES)


@pytest.mark.parametrize("entry", _ENTRIES, ids=[e["name"] for e in _ENTRIES])
def test_wolt_venues_match_golden(entry: dict[str, Any]) -> None:
    venues = map_wolt_venues(entry["raw"])
    actual = None if venues is None else [to_json(venue) for venue in venues]
    assert _canonical(actual) == _canonical(entry["venues"])


@pytest.mark.parametrize("raw", [None, [], "page", 7])
def test_non_object_page_is_none(raw: object) -> None:
    assert map_wolt_venues(raw) is None


@pytest.mark.parametrize(
    ("value", "rounded"),
    [(2.5, 3), (3.5, 4), (-0.5, -1), (-2.5, -3), (0.49999999999999994, 0), (7, 7)],
)
def test_dart_round_is_half_away_from_zero(value: float, rounded: int) -> None:
    assert dart_round(value) == rounded


@pytest.mark.parametrize(
    ("slug", "url"),
    [
        ("plain-slug", "https://wolt.com/en/isr/tel-aviv/restaurant/plain-slug"),
        ("a b", "https://wolt.com/en/isr/tel-aviv/restaurant/a%20b"),
        ("a?b#c", "https://wolt.com/en/isr/tel-aviv/restaurant/a%3Fb%23c"),
        ("100%", "https://wolt.com/en/isr/tel-aviv/restaurant/100%25"),
        ("a%2fb", "https://wolt.com/en/isr/tel-aviv/restaurant/a%2Fb"),
        ("a%41", "https://wolt.com/en/isr/tel-aviv/restaurant/aA"),
        ("..", "https://wolt.com/en/isr/tel-aviv/"),
    ],
)
def test_dart_uri_https_to_string(slug: str, url: str) -> None:
    assert dart_https_url("wolt.com", f"/en/isr/tel-aviv/restaurant/{slug}") == url

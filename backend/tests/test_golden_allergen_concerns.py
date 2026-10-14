"""``app.keto.rules`` and ``app.keto.heuristic`` replay the golden
``allergen_concerns.json`` (Banto; ALG-04b, related to #346).

Every ``dishes`` entry must give back exactly the Dart
``ClassificationRules.allergenFindings`` and ``allergenConcerns``, matched
text included; every ``heuristic`` entry is a golden menu classified with
``restrictionsRequested`` on, whose concerns ride on each dish.
"""

import json
from pathlib import Path
from typing import Any

import pytest

from app.keto.heuristic import classify_heuristic
from app.keto.models import (
    AnalysisOptionsSnapshot,
    Dish,
    DishOption,
    Menu,
    to_json,
)
from app.keto.rules import allergen_concerns, allergen_findings

_GOLDEN = Path(__file__).parent / "fixtures" / "golden" / "allergen_concerns.json"
_RAW: dict[str, Any] = json.loads(_GOLDEN.read_text(encoding="utf-8"))
_DISHES: list[dict[str, Any]] = _RAW["dishes"]
_HEURISTIC: list[dict[str, Any]] = _RAW["heuristic"]


def _canonical(value: object) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2)


def _dish(raw: dict[str, Any]) -> Dish:
    """The golden dish, built as the Dart exporter built it."""
    return Dish.model_construct(
        id=raw["id"],
        name=raw["name"],
        description=raw["description"],
        price=raw["price"],
        options=[
            DishOption.model_construct(name=option["name"], values=option["values"])
            for option in raw["options"]
        ],
        image_url=raw["imageUrl"],
        page=raw["page"],
    )


def test_the_golden_covers_every_source_and_tier() -> None:
    findings = [finding for entry in _DISHES for finding in entry["findings"]]
    assert {finding["source"] for finding in findings} == {
        "name",
        "description",
        "option",
        "hidden",
    }
    assert {finding["tier"] for finding in findings} == {"stated", "inferred"}
    assert {finding["certainty"] for finding in findings} == {
        "stated",
        "likely",
        "suspected",
    }


@pytest.mark.parametrize("entry", _DISHES, ids=[entry["name"] for entry in _DISHES])
def test_every_dish_finds_the_concerns_dart_found(entry: dict[str, Any]) -> None:
    dish = _dish(entry["dish"])
    assert [to_json(concern) for concern in allergen_findings(dish)] == entry[
        "findings"
    ]
    assert [to_json(concern) for concern in allergen_concerns(dish)] == entry[
        "concerns"
    ]


@pytest.mark.parametrize(
    "entry", _HEURISTIC, ids=[entry["name"] for entry in _HEURISTIC]
)
def test_the_heuristic_attaches_concerns_when_asked(entry: dict[str, Any]) -> None:
    menu = Menu.model_validate(entry["menu"])
    options = AnalysisOptionsSnapshot.model_validate(entry["options"])
    assert options.restrictions_requested
    analysis = classify_heuristic(
        menu, options, analysed_at=entry["analysis"]["analysedAt"]
    )
    assert _canonical(to_json(analysis)) == _canonical(entry["analysis"])
    assert any(dish.concerns for dish in analysis.dishes)


@pytest.mark.parametrize(
    "entry", _HEURISTIC, ids=[entry["name"] for entry in _HEURISTIC]
)
def test_the_heuristic_attaches_nothing_unless_asked(entry: dict[str, Any]) -> None:
    menu = Menu.model_validate(entry["menu"])
    options = AnalysisOptionsSnapshot.model_validate(
        {**entry["options"], "restrictionsRequested": False}
    )
    analysis = classify_heuristic(
        menu, options, analysed_at=entry["analysis"]["analysedAt"]
    )
    assert all(not dish.concerns for dish in analysis.dishes)
    assert "concerns" not in _canonical(to_json(analysis))


def test_a_matched_text_is_the_menus_own_spelling() -> None:
    dish = Dish.model_construct(
        id="d",
        name="סָלָט בַּטְּחִינָה",
        description="🥜 'Peanut' satay",
        price=10,
        options=[DishOption.model_construct(name="x", values=["ללא־שומשום"])],
        image_url=None,
        page=None,
    )
    texts = {
        concern.restriction_id: concern.matched_text
        for concern in allergen_concerns(dish)
    }
    assert texts["sesame"] == "בַּטְּחִינָה"
    assert texts["peanuts"] == "Peanut"

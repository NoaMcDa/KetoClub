"""``app.keto.rules`` replays the golden ``rules.json`` (#324, D25).

Every section is replayed entry by entry: ``texts`` through
:func:`~app.keto.rules.match`, ``dishes`` through
:func:`~app.keto.rules.match_dish` (with ``carbOnlyBase``,
``describesFilling`` and the four normaliser texts the entry also records),
``mentions`` through the three ``mentions_*`` checks and ``carbOnly`` through
:func:`~app.keto.rules.carb_only_base`.
"""

import json
from pathlib import Path
from typing import Any

import pytest

from app.keto.models import Dish, DishOption
from app.keto.normaliser import (
    dish_core_text,
    dish_option_rules_text,
    dish_rules_text,
    dish_search_text,
)
from app.keto.rules import (
    RuleMatch,
    carb_only_base,
    describes_filling,
    match,
    match_dish,
    mentions_dairy,
    mentions_plant,
    mentions_seed_oil,
)

_GOLDEN = Path(__file__).parent / "fixtures" / "golden" / "rules.json"
_RAW: dict[str, Any] = json.loads(_GOLDEN.read_text(encoding="utf-8"))
_TEXTS: list[dict[str, Any]] = _RAW["texts"]
_DISHES: list[dict[str, Any]] = _RAW["dishes"]
_MENTIONS: list[dict[str, Any]] = _RAW["mentions"]
_CARB_ONLY: list[dict[str, Any]] = _RAW["carbOnly"]


def _ids(entries: list[dict[str, Any]], key: str) -> list[str]:
    def label(entry: dict[str, Any]) -> str:
        value = entry[key]
        return str(value["name"] if isinstance(value, dict) else value)

    return [f"{index}:{label(entry)}" for index, entry in enumerate(entries)]


def _dish(raw: dict[str, Any]) -> Dish:
    """The golden dish, built without validation: the exporter built it
    with the Dart ``Dish`` constructor, which (unlike ``Dish.tryFrom``)
    accepts an empty name, and one entry has one."""
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


def _record(found: RuleMatch) -> dict[str, Any]:
    """``found`` in the golden's ``_match`` shape."""
    return {
        "kind": found.kind,
        "isNonKeto": found.is_non_keto,
        "baseLabel": found.base_label,
        "instructions": list(found.instructions),
    }


def test_the_golden_has_every_section() -> None:
    assert set(_RAW) == {"texts", "dishes", "mentions", "carbOnly"}
    assert _TEXTS and _DISHES and _MENTIONS and _CARB_ONLY


@pytest.mark.parametrize("entry", _TEXTS, ids=_ids(_TEXTS, "text"))
def test_every_golden_text_matches_as_dart_does(entry: dict[str, Any]) -> None:
    assert set(entry) == {"text", "match"}
    assert _record(match(entry["text"])) == entry["match"]


@pytest.mark.parametrize("entry", _DISHES, ids=_ids(_DISHES, "dish"))
def test_every_golden_dish_matches_as_dart_does(entry: dict[str, Any]) -> None:
    assert set(entry) == {
        "dish",
        "match",
        "carbOnlyBase",
        "describesFilling",
        "coreText",
        "rulesText",
        "optionRulesText",
        "searchText",
    }
    dish = _dish(entry["dish"])
    assert _record(match_dish(dish)) == entry["match"]
    assert carb_only_base(dish.name) == entry["carbOnlyBase"]
    assert describes_filling(dish) is entry["describesFilling"]
    assert dish_core_text(dish) == entry["coreText"]
    assert dish_rules_text(dish) == entry["rulesText"]
    assert dish_option_rules_text(dish) == entry["optionRulesText"]
    assert dish_search_text(dish) == entry["searchText"]


@pytest.mark.parametrize("entry", _MENTIONS, ids=_ids(_MENTIONS, "text"))
def test_every_golden_mention_is_found_as_dart_finds_it(
    entry: dict[str, Any],
) -> None:
    assert set(entry) == {"text", "seedOil", "dairy", "plant"}
    text = entry["text"]
    assert {
        "seedOil": mentions_seed_oil(text),
        "dairy": mentions_dairy(text),
        "plant": mentions_plant(text),
    } == {key: entry[key] for key in ("seedOil", "dairy", "plant")}


@pytest.mark.parametrize("entry", _CARB_ONLY, ids=_ids(_CARB_ONLY, "name"))
def test_every_golden_carb_only_name_is_labelled_as_dart_does(
    entry: dict[str, Any],
) -> None:
    assert set(entry) == {"name", "base"}
    assert carb_only_base(entry["name"]) == entry["base"]

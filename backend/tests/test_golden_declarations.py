"""``app.keto.declarations`` replays the golden ``declarations.json`` (ALG-09,
#351).

``rules``, ``guardsEn``, ``guardsHe``, ``kosherTags`` and
``kosherDeclaredTag`` pin the Python table equal to Dart's; ``cases`` replays
each hand-built dish under its heading to exactly the Dart declarations and
kosher flag; ``menus`` does the same for every dish of every golden menu
under its own category heading.
"""

import json
from pathlib import Path
from typing import Any, get_args

import pytest

from app.keto import declarations as dc
from app.keto.declarations import (
    DeclarationPolarity,
    DeclarationSource,
    declarations_in_text,
    declarations_of,
    declarations_of_tags,
    declares_kosher,
)
from app.keto.models import Dish, Menu, RestrictionIdName

_GOLDEN = Path(__file__).parent / "fixtures" / "golden" / "declarations.json"
_RAW: dict[str, Any] = json.loads(_GOLDEN.read_text(encoding="utf-8"))
_CASES: list[dict[str, Any]] = _RAW["cases"]
_MENUS: list[dict[str, Any]] = _RAW["menus"]


def _guards(guards: Any) -> dict[str, list[str]]:
    return {"before": list(guards.before), "after": list(guards.after)}


def test_the_golden_has_the_expected_sections() -> None:
    assert set(_RAW) == {
        "rules",
        "guardsEn",
        "guardsHe",
        "kosherTags",
        "kosherDeclaredTag",
        "cases",
        "menus",
    }
    assert len({case["name"] for case in _CASES}) == len(_CASES)


def test_the_table_is_the_dart_one() -> None:
    assert [rule.to_json() for rule in dc.DECLARATION_RULES] == _RAW["rules"]
    assert _guards(dc.DECLARATION_GUARDS_EN) == _RAW["guardsEn"]
    assert _guards(dc.DECLARATION_GUARDS_HE) == _RAW["guardsHe"]
    assert list(dc.KOSHER_TAGS) == _RAW["kosherTags"]
    assert dc.KOSHER_DECLARED_TAG == _RAW["kosherDeclaredTag"]


@pytest.mark.parametrize("case", _CASES, ids=[case["name"] for case in _CASES])
def test_every_case_reads_the_dart_declarations(case: dict[str, Any]) -> None:
    dish = Dish.model_validate(case["dish"])
    found = declarations_of(dish, heading=case["heading"])
    assert [declaration.to_json() for declaration in found] == case["declarations"]
    assert declares_kosher(dish) is case["declaresKosher"]


@pytest.mark.parametrize("entry", _MENUS, ids=[entry["name"] for entry in _MENUS])
def test_every_golden_menu_reads_the_dart_declarations(entry: dict[str, Any]) -> None:
    menu = Menu.model_validate(entry["menu"])
    read: dict[str, Any] = {}
    for category in menu.categories:
        for dish in category.dishes:
            read[dish.id] = [
                declaration.to_json()
                for declaration in declarations_of(dish, heading=category.name)
            ]
    assert read == entry["declarations"]
    assert [d.id for d in menu.all_dishes() if declares_kosher(d)] == entry["kosher"]


def test_every_rule_source_and_the_kosher_flag_are_exercised() -> None:
    rules = {
        declaration["rule"] for case in _CASES for declaration in case["declarations"]
    }
    sources = {
        declaration["source"] for case in _CASES for declaration in case["declarations"]
    }
    assert rules == {rule.id for rule in dc.DECLARATION_RULES}
    assert sources == {source.value for source in DeclarationSource}
    assert {case["declaresKosher"] for case in _CASES} == {True, False}
    assert any(entry["kosher"] for entry in _MENUS)


def test_every_rule_declares_an_absence_in_taxonomy_order() -> None:
    order = list(get_args(RestrictionIdName))
    for rule in dc.DECLARATION_RULES:
        assert rule.polarity is DeclarationPolarity.ABSENT
        assert list(rule.restrictions) == sorted(rule.restrictions, key=order.index)
        assert "keto" not in rule.restrictions


def test_a_tag_is_read_through_the_text_table_with_its_own_spelling() -> None:
    found = declarations_of_tags(["GLUTEN_FREE", "gluten-free"])
    assert [d.to_json() for d in found] == [
        {
            "rule": "glutenFree",
            "restrictionIds": ["gluten"],
            "polarity": "absent",
            "source": "platformTag",
            "matchedText": "GLUTEN_FREE",
        }
    ]
    # Kosher and halal (#342) are declared by a tag only, and one never
    # speaks for the other.
    assert [d.to_json() for d in declarations_of_tags(["kosher"])] == [
        {
            "rule": "kosher",
            "restrictionIds": ["kosher"],
            "polarity": "absent",
            "source": "platformTag",
            "matchedText": "kosher",
        }
    ]
    assert [d.rule for d in declarations_of_tags(["חלאל"])] == ["halal"]


def test_menu_text_never_declares_kosher_or_halal() -> None:
    found = declarations_in_text("Kosher halal steak", DeclarationSource.DISH_TEXT)
    assert found == []

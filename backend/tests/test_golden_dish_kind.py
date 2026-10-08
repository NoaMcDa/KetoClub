"""``app.keto.dish_kind`` replays the golden ``dish_kind.json`` (#322, D21).

``headings`` records ``categoryKindOf`` for each heading; ``menus`` records
``dishKindsOf`` (dish id → kind) for each named menu.
"""

import json
from pathlib import Path
from typing import Any

import pytest
from pydantic import ValidationError

from app.keto.dish_kind import DishKind, category_kind_of, dish_kind_of, dish_kinds_of
from app.keto.models import Dish, DishOption, Menu, MenuCategory, VenueRef

_GOLDEN = Path(__file__).parent / "fixtures" / "golden" / "dish_kind.json"
_RAW: dict[str, Any] = json.loads(_GOLDEN.read_text(encoding="utf-8"))
_HEADINGS: list[dict[str, Any]] = _RAW["headings"]
_MENUS: list[dict[str, Any]] = _RAW["menus"]

_BUILT_WITHOUT_VALIDATION = {"empty_name"}
"""Menus the exporter built with the Dart constructor around a value the
wire refuses (a dish with an empty name, which ``Dish.tryFrom`` and the
pydantic ``Dish`` both reject). ``dishKindOf`` still has to answer for it,
so the test builds it unvalidated, the way the Dart constructor did."""


def _construct_menu(raw: dict[str, Any]) -> Menu:
    """``raw`` as a ``Menu`` built field by field with no validation."""
    return Menu.model_construct(
        venue_ref=VenueRef.model_validate(raw["venueRef"]),
        currency=raw["currency"],
        fetched_at=raw["fetchedAt"],
        venue_name=raw["venueName"],
        categories=[
            MenuCategory.model_construct(
                id=category["id"],
                name=category["name"],
                dishes=[
                    Dish.model_construct(
                        id=dish["id"],
                        name=dish["name"],
                        description=dish["description"],
                        price=float(dish["price"]),
                        options=[DishOption.model_validate(o) for o in dish["options"]],
                        image_url=dish["imageUrl"],
                        page=dish["page"],
                    )
                    for dish in category["dishes"]
                ],
            )
            for category in raw["categories"]
        ],
    )


def _menu(entry: dict[str, Any]) -> Menu:
    if entry["name"] in _BUILT_WITHOUT_VALIDATION:
        with pytest.raises(ValidationError):
            Menu.model_validate(entry["menu"])
        return _construct_menu(entry["menu"])
    return Menu.model_validate(entry["menu"])


@pytest.mark.parametrize(
    "entry",
    _HEADINGS,
    ids=[f"{i:02d}-{ascii(e['heading'])[1:-1]}" for i, e in enumerate(_HEADINGS)],
)
def test_every_golden_heading_has_the_dart_kind(entry: dict[str, Any]) -> None:
    assert set(entry) == {"heading", "kind"}
    assert category_kind_of(entry["heading"]).value == entry["kind"]


@pytest.mark.parametrize("entry", _MENUS, ids=[entry["name"] for entry in _MENUS])
def test_every_golden_menu_has_the_dart_kinds(entry: dict[str, Any]) -> None:
    assert set(entry) == {"name", "menu", "kinds"}
    kinds = dish_kinds_of(_menu(entry))
    assert {dish_id: kind.value for dish_id, kind in kinds.items()} == entry["kinds"]


def test_every_kind_and_every_heading_outcome_is_exercised() -> None:
    from_headings = {entry["kind"] for entry in _HEADINGS}
    from_menus = {kind for entry in _MENUS for kind in entry["kinds"].values()}
    every = {kind.value for kind in DishKind}
    assert from_headings == every
    assert from_menus == every
    assert _BUILT_WITHOUT_VALIDATION <= {entry["name"] for entry in _MENUS}


def test_only_food_counts() -> None:
    assert [kind for kind in DishKind if kind.counts_toward_score] == [DishKind.FOOD]


def test_a_dish_listed_twice_takes_its_first_heading() -> None:
    cola = Dish(id="c", name="Cola", price=9.0, options=[])
    menu = Menu(
        venue_ref=VenueRef(source="scan", platform_id="x"),
        currency="ILS",
        fetched_at="2026-01-01T00:00:00.000Z",
        categories=[
            MenuCategory(id="a", name="Sauces", dishes=[cola]),
            MenuCategory(id="b", name="Mains", dishes=[cola]),
        ],
    )
    assert dish_kinds_of(menu) == {"c": DishKind.EXTRA}
    assert dish_kind_of(category="Mains", dish=cola) is DishKind.DRINK
    assert category_kind_of("   ") is DishKind.FOOD

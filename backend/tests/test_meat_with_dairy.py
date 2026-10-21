"""Kosher's meat-with-dairy rule in ``app.keto.rules`` (#342).

The Python twin of the rule table in
``test/utils/classification_rules_allergen_test.dart``; the golden
``allergen_concerns.json`` pins the same dishes against Dart byte for byte.
"""

import pytest

from app.keto.models import Dish, DishOption
from app.keto.rules import MEAT_WITH_DAIRY_JOINER, allergen_findings


def _dish(name: str, description: str = "", options: list[str] | None = None) -> Dish:
    return Dish.model_construct(
        id="d1",
        name=name,
        description=description,
        price=0,
        options=[DishOption.model_construct(name="Extras", values=options or [])],
        image_url=None,
        page=None,
    )


def _meat_with_dairy(dish: Dish) -> list[tuple[str, str, str | None]]:
    return [
        (c.certainty, c.source, c.matched_text)
        for c in allergen_findings(dish)
        if c.restriction_id == "kosher"
        and c.matched_text is not None
        and MEAT_WITH_DAIRY_JOINER in c.matched_text
    ]


@pytest.mark.parametrize(
    ("dish", "expected"),
    [
        (
            _dish("Ribeye steak", "Blue cheese butter"),
            [("stated", "description", "Ribeye + cheese")],
        ),
        (_dish("Chicken alfredo"), [("suspected", "hidden", "Chicken + alfredo")]),
        (
            _dish("Beef burger", options=["Cheddar"]),
            [("suspected", "option", "Beef + Cheddar")],
        ),
        (_dish("שניצל עוף", "ברוטב שמנת"), [("stated", "description", "שניצל + שמנת")]),
        (_dish("Salmon in cream sauce"), []),
        (_dish("Veggie burger", "With goat cheese"), []),
        (_dish("Chicken curry", "Coconut milk"), []),
        (_dish("Steak", "No cheese"), []),
        (_dish("Steak frites"), []),
    ],
)
def test_the_rule_table(dish: Dish, expected: list[tuple[str, str, str]]) -> None:
    assert _meat_with_dairy(dish) == expected

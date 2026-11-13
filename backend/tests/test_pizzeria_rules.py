"""The rule engine over a pizzeria's menu as Wolt lists it.

A Domino's venue on Wolt (``dominos-pizza-ashdod-city``) showed "29 dishes
as-is" on its Discovery card. Fourteen were pizzas the menu names by their
topping mix and describes by their toppings, so that only the option group
"בחרו סוג בצק" says "pizza"; the rest were dough sticks and fingers whose
description says "בצק", a cake and ice creams written in the construct form,
and dips counted as food. The dish shapes below are the real ones, trimmed.

The golden ``rules.json`` already pins the port to Dart on these shapes;
these tests say in Python what the behaviour is.
"""

import pytest

from app.keto.dish_kind import DishKind, category_kind_of, dish_kinds_of
from app.keto.heuristic import classify_heuristic
from app.keto.models import (
    AnalysisOptionsSnapshot,
    Dish,
    DishOption,
    Menu,
    MenuCategory,
    VenueRef,
)
from app.keto.rules import dough_choice_base, match, match_dish
from app.keto.score import VerdictCounts
from app.keto.vocabulary import vocabulary

_FAMILY_DOUGH = DishOption(
    name="בחרו סוג בצק - MIX",
    values=["בצק קלאסי", "בצק קלאסי דק", "צ׳יזי קראסט מוצרלה"],
)
_PERSONAL_DOUGH = DishOption(name="בצק - אישית", values=["בצק קלאסי"])


def _dish(
    name: str,
    description: str = "",
    options: list[DishOption] | None = None,
    dish_id: str = "d",
) -> Dish:
    return Dish(
        id=dish_id,
        name=name,
        description=description,
        price=40.0,
        options=options or [],
    )


def _skip(base: str) -> str:
    """The Hebrew option-base sentence for ``base``."""
    template = vocabulary().templates.option_base_modification_he
    return template.replace("{base}", base)


def test_a_pizza_named_by_its_topping_mix_is_red_through_its_choice_of_dough() -> None:
    pizza = _dish(
        "בקרנה MIX משפחתית",
        "פרוסות חזה בקר, כדורי בייבי מוצרלה, גבינת פרמז'ן גרנה פדנו",
        [_FAMILY_DOUGH],
    )

    found = match_dish(pizza)

    assert found.is_non_keto
    assert found.base_label == "בצק"
    assert found.instructions == ()
    assert dough_choice_base(pizza) == "בצק"


def test_a_personal_pizza_is_red_through_its_dough_group() -> None:
    pizza = _dish(
        "גריק MIX אישית",
        "קוביות עגבניות, בצל סגול, זיתי קלמטה וגבינה בולגרית",
        [_PERSONAL_DOUGH],
    )

    assert match_dish(pizza).kind == "red"


def test_a_gluten_free_dough_among_the_choices_rescues_nothing() -> None:
    pizza = _dish(
        "משפחתית יוונית",
        options=[DishOption(name="בחרו סוג בצק", values=["קלאסי", "בצק ללא גלוטן"])],
    )

    assert match_dish(pizza).kind == "red"


@pytest.mark.parametrize("values", [["בצק קלאסי", "בצק כרובית"], ["קלאסי", "כרובית"]])
def test_a_group_offering_a_cauliflower_dough_is_yellow_not_red(
    values: list[str],
) -> None:
    pizza = _dish(
        "משפחתית יוונית", options=[DishOption(name="בחרו סוג בצק", values=values)]
    )

    found = match_dish(pizza)

    assert dough_choice_base(pizza) is None
    assert found.kind == "yellow"
    assert found.instructions == (_skip("בצק"),)


def test_dough_offered_as_an_upsell_adds_nothing() -> None:
    # "Would you like something extra?" is an upsell (issue #475).
    salad = _dish(
        "סלט יווני",
        options=[DishOption(name="תרצו משהו נוסף?", values=["מקלות בצק"])],
    )

    assert dough_choice_base(salad) is None
    assert match_dish(salad).kind == "green"


@pytest.mark.parametrize(
    ("name", "description"),
    [
        ("אצבעות מוצרלה", "אצבעות בצק וגבינה 100% מוצרלה + דיפ עגבניות ושום"),
        ("מקלות דאבל דיפ מלוח", "8 מקלות בצק בחמאת שום ועשבי תיבול"),
        ("משפחתית יוונית עבה", "משפחתית מבצק עבה, עם עגבניות, פטה וזיתים"),
        ("Garlic knots", "Baked dough balls with garlic butter"),
    ],
)
def test_a_dish_whose_description_names_dough_is_red(
    name: str, description: str
) -> None:
    found = match_dish(_dish(name, description))

    assert found.kind == "red"
    assert found.base_label in {"בצק", "dough"}


@pytest.mark.parametrize(
    "text",
    [
        "קיש ללא בצק",
        "בצק כרובית עם מוצרלה",
        "בצק קמח שקדים",
        "Cauliflower dough with mozzarella",
        "Sourdough starter",
    ],
)
def test_a_crustless_dish_or_a_keto_dough_is_not_red(text: str) -> None:
    assert not match(text).is_non_keto


def test_a_removal_word_after_the_dough_rescues_nothing() -> None:
    assert match("פוקאצ׳ה מבצק ללא גלוטן").is_non_keto


@pytest.mark.parametrize(
    ("text", "label"),
    [
        ("עוגת שוקולד חמה", "עוגה"),
        ("עוגות הבית", "עוגה"),
        ("גלידת וניל משובחת", "גלידה"),
        ("גלידות בטעמים", "גלידה"),
    ],
)
def test_the_construct_forms_of_cake_and_ice_cream_are_red(
    text: str, label: str
) -> None:
    found = match(text)

    assert found.is_non_keto
    assert found.base_label == label


def test_a_dips_heading_is_extras_unless_a_food_word_sits_beside_it() -> None:
    assert category_kind_of("דיפים") is DishKind.EXTRA
    assert category_kind_of("דיפים ורטבים 🍯") is DishKind.EXTRA
    assert category_kind_of("נשנושים ודיפים") is DishKind.FOOD


def test_a_pizzeria_menu_counts_only_the_wings_as_order_as_is() -> None:
    menu = Menu(
        venue_ref=VenueRef(source="wolt", platform_id="dominos-pizza-ashdod-city"),
        currency="ILS",
        fetched_at="2026-11-11T00:00:00.000Z",
        categories=[
            MenuCategory(
                id="mix",
                name="🥓 Domino's Mix",
                dishes=[
                    _dish(
                        "בקרנה MIX משפחתית",
                        "פרוסות חזה בקר, כדורי בייבי מוצרלה",
                        [_FAMILY_DOUGH],
                        "mix-beef-family",
                    ),
                    _dish(
                        "גריק MIX אישית",
                        "קוביות עגבניות, בצל סגול, זיתי קלמטה",
                        [_PERSONAL_DOUGH],
                        "mix-greek-personal",
                    ),
                ],
            ),
            MenuCategory(
                id="sides",
                name="🌭 ליד הפיצה",
                dishes=[
                    _dish(
                        "אצבעות מוצרלה",
                        "אצבעות בצק וגבינה 100% מוצרלה",
                        dish_id="mozzarella-fingers",
                    ),
                    _dish(
                        "דומינו׳ס ווינגס",
                        "יחידות חצאי כנפיים מעולות ברוטב לבחירה",
                        [
                            DishOption(
                                name="בחרו רטבים לכנפיים",
                                values=["רוטב סוויט צ׳ילי אריזונה", "ללא רוטב"],
                            )
                        ],
                        "wings",
                    ),
                ],
            ),
            MenuCategory(
                id="dips",
                name="דיפים ורטבים 🍯",
                dishes=[
                    _dish("דיפ עגבניות שום", dish_id="dip-garlic"),
                    _dish("דיפ חריף", dish_id="dip-hot"),
                ],
            ),
            MenuCategory(
                id="desserts",
                name="קינוחים 🧁",
                dishes=[_dish("פונדנט שוקולד", "עוגת שוקולד חמה", dish_id="fondant")],
            ),
            MenuCategory(
                id="ice-cream",
                name="גלידות 🍦",
                dishes=[
                    _dish("פיינט וניל - 500 מ״ל", "גלידת וניל משובחת", dish_id="pint")
                ],
            ),
        ],
    )

    analysis = classify_heuristic(
        menu,
        AnalysisOptionsSnapshot(net_carb_limit_grams=6),
        analysed_at="2026-11-11T00:00:00.000Z",
    )
    counts = VerdictCounts.of(menu, analysis)
    verdicts = {dish.dish_id: dish.verdict for dish in analysis.dishes}
    kinds = dish_kinds_of(menu)

    # Before the fix all eight dishes were green and all eight were counted.
    assert (counts.green, counts.yellow, counts.red) == (1, 0, 5)
    assert verdicts["wings"] == "orderAsIs"
    assert kinds["dip-garlic"] is DishKind.EXTRA
    assert kinds["dip-hot"] is DishKind.EXTRA

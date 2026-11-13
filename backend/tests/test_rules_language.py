"""The waiter script is in the dish's language, whichever table fired (#279).

Israeli menus write English words inside Hebrew names ("המבורגר BBQ"); the
script is read aloud in that restaurant, so every carb-modifier trigger has a
counterpart in the other language's table, and a trigger from the other
table gives its counterpart's sentence. The golden ``rules.json`` and
``heuristic.json`` pin the port to Dart; these tests say it in Python.
"""

import re

from app.keto.models import Dish, DishOption
from app.keto.rules import is_hebrew_dish, match_dish
from app.keto.vocabulary import vocabulary

_HEBREW = re.compile("[֐-׿]")


def test_every_trigger_has_a_counterpart_in_the_other_table() -> None:
    vocab = vocabulary()
    en = dict(vocab.carb_modifiers_en)
    he = dict(vocab.carb_modifiers_he)
    assert set(vocab.carb_modifier_counterparts_en) == set(en)
    assert set(vocab.carb_modifier_counterparts_he) == set(he)
    assert set(vocab.carb_modifier_counterparts_en.values()) <= set(he)
    assert set(vocab.carb_modifier_counterparts_he.values()) <= set(en)


def test_an_english_trigger_in_a_hebrew_dish_asks_in_hebrew() -> None:
    he = dict(vocabulary().carb_modifiers_he)
    found = match_dish(Dish(id="d", name="המבורגר BBQ", price=10, options=[]))
    assert found.instructions == (he["המבורגר"], he["ברביקיו"])


def test_a_hebrew_option_of_an_english_dish_asks_in_english() -> None:
    steak = Dish(
        id="d",
        name="Steak",
        price=10,
        options=[DishOption(name="Sides", values=["צ'יפס"])],
    )
    found = match_dish(steak)
    assert found.instructions == (dict(vocabulary().carb_modifiers_en)["fries"],)
    assert not is_hebrew_dish(steak)
    assert not any(_HEBREW.search(sentence) for sentence in found.instructions)

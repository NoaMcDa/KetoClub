"""``app.keto.normaliser`` replays the golden ``normaliser.json`` (#322, D25).

Every entry records what the Dart ``TextNormaliser`` made of one input:
``normalise``, ``containsHebrew``, ``words`` (min length 1 and 3, counted
in UTF-16 code units) and ``isRemovalOptionValue``. The entries have no
``name``, so the test id is the entry's index and its input, escaped.
"""

import json
from pathlib import Path
from typing import Any

import pytest

from app.keto.dart_text import (
    dart_lower,
    dart_trim,
    from_utf16_units,
    utf16_len,
    utf16_slice,
    utf16_units,
)
from app.keto.models import Dish, DishOption
from app.keto.normaliser import (
    contains_hebrew,
    dish_core_text,
    dish_option_rules_text,
    dish_rules_text,
    dish_search_text,
    is_removal_option_value,
    normalise,
    words,
)
from app.keto.vocabulary import vocabulary

_GOLDEN = Path(__file__).parent / "fixtures" / "golden" / "normaliser.json"
_ENTRIES: list[dict[str, Any]] = json.loads(_GOLDEN.read_text(encoding="utf-8"))


def _id(index: int, entry: dict[str, Any]) -> str:
    return f"{index:04d}-{ascii(entry['in'])[1:-1][:48]}"


@pytest.mark.parametrize(
    "entry",
    _ENTRIES,
    ids=[_id(index, entry) for index, entry in enumerate(_ENTRIES)],
)
def test_every_golden_input_normalises_as_dart_does(entry: dict[str, Any]) -> None:
    text = entry["in"]
    assert set(entry) == {
        "in",
        "normalised",
        "containsHebrew",
        "words",
        "wordsMin3",
        "isRemovalOptionValue",
    }
    assert normalise(text) == entry["normalised"]
    assert contains_hebrew(text) is entry["containsHebrew"]
    assert words(text) == entry["words"]
    min_length = vocabulary().caps.min_overlap_word_length
    assert words(text, min_length=min_length) == entry["wordsMin3"]
    assert is_removal_option_value(text) is entry["isRemovalOptionValue"]


def test_normalise_is_not_idempotent_on_y_diaeresis_as_in_dart() -> None:
    # The Dart doc comment claims idempotence, but the fold runs before the
    # lowercase: ``Ÿ`` (outside Latin-1) lowercases to ``ÿ``, which only a
    # second pass folds. The port keeps the Dart behaviour, not the comment.
    assert normalise("\u0178") == "\u00ff"
    assert normalise(normalise("\u0178")) == "y"


def test_the_corpus_is_the_size_the_exporter_wrote() -> None:
    # The edge cases, the twelve quote marks, all of U+00A0–U+00FF and the
    # vocabulary: a truncated file would replay "green" with fewer cases.
    assert len(_ENTRIES) == 1210
    assert len({entry["in"] for entry in _ENTRIES}) == len(_ENTRIES)


# --- the dish texts -------------------------------------------------------------


def _dish(options: list[DishOption]) -> Dish:
    return Dish(
        id="d1",
        name="Burger",
        description="Beef patty, brioche BUN",
        price=58.0,
        options=options,
    )


def test_the_dish_texts_split_core_options_and_removals() -> None:
    dish = _dish(
        [
            DishOption(name="Side", values=["Potato purée", "", "No onions"]),
            DishOption(name="Sauce", values=["ללא אלף האיים", "Aioli"]),
        ]
    )
    assert dish_core_text(dish) == "burger beef patty brioche bun"
    assert dish_option_rules_text(dish) == "side potato puree sauce aioli"
    assert dish_rules_text(dish) == (
        "burger beef patty brioche bun side potato puree sauce aioli"
    )
    assert dish_search_text(dish) == (
        "burger beef patty brioche bun side potato puree no onions "
        "sauce ללא אלפ האיימ aioli"
    )


def test_a_dish_with_no_description_or_options_has_only_its_name() -> None:
    dish = Dish(id="d", name="Steak", price=0.0, options=[])
    assert dish_search_text(dish) == "steak"
    assert dish_option_rules_text(dish) == ""
    assert dish_rules_text(dish) == "steak"


@pytest.mark.parametrize(
    ("value", "removal"),
    [("No onions", True), ("without bun", True), ("  ", False), ("Nori", False)],
)
def test_a_removal_is_a_first_word_match(value: str, removal: bool) -> None:
    assert is_removal_option_value(value) is removal


# --- Dart string semantics --------------------------------------------------------


def test_utf16_lengths_and_units_count_surrogate_pairs() -> None:
    assert utf16_len("a\U0001f354b") == 4
    assert utf16_units("a\U0001f354") == [0x61, 0xD83C, 0xDF54]
    assert utf16_units("\ud83d") == [0xD83D]
    assert from_utf16_units([0xD83C, 0xDF54]) == "\U0001f354"


def test_utf16_slice_can_split_a_surrogate_pair_as_dart_does() -> None:
    assert utf16_slice("ab\U0001f354", 0, 3) == "ab\ud83c"
    assert utf16_slice("ab\U0001f354", 2) == "\U0001f354"


def test_dart_lower_is_one_to_one() -> None:
    assert dart_lower("İSTANBUL") == "istanbul"
    assert dart_lower("ΟΔΟΣ") == "οδοσ"
    assert dart_lower("Ÿ ẞ ǅ") == "ÿ ß ǆ"


def test_dart_trim_strips_the_bom_but_not_the_separators() -> None:
    assert dart_trim("﻿  why 　\n") == "why"
    assert dart_trim("\u001cwhy\u001f") == "\u001cwhy\u001f"
    assert dart_trim("﻿") == ""
    assert dart_trim("") == ""

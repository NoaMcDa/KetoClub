"""Text normalisation for the rule engine and menu fingerprints.

The Python twin of ``lib/utils/text_normaliser.dart`` (architecture.md D25,
``vocabulary_spec.md``). :func:`normalise` runs the same seven steps in the
same order, with the Dart quirks the golden corpus pins
(``tests/fixtures/golden/normaliser.json``):

1. Strip the bidi controls LRM, RLM, LRE, RLE, PDF, LRO, RLO, LRI, RLI, FSI,
   PDI.
2. Strip U+0591–U+05C7 (Hebrew points and teamim). The range also holds the
   maqaf U+05BE, paseq U+05C0, sof pasuq U+05C3 and nun hafukha U+05C6, so
   these are **deleted**, not spaced: ``חרדל־דבש`` becomes ``חרדלדבש``.
3. Delete the quote marks ``׳ ״ ' " ` ’ ” ʼ`` (only these: ``‘ “ ´ ′`` fall
   to step 6 and become spaces).
4. Fold Latin-1 Supplement diacritics with a hand-written table (no NFD:
   ``Ÿ``, ``ẞ`` and combining marks are left alone).
5. Lowercase one character at a time, the Dart way
   (:func:`app.keto.dart_text.dart_lower`).
6. Collapse every run of characters that is neither ``\\p{L}`` nor
   ``\\p{N}`` to one space (so ``_`` is a separator), then trim.
7. Fold Hebrew final letters to their medial forms.

Lengths are UTF-16 code units throughout (:func:`words`' ``min_length``).
"""

from typing import Final

import regex

from app.keto.dart_text import dart_lower, utf16_len
from app.keto.models import Dish
from app.keto.vocabulary import vocabulary

_BIDI_CONTROLS: Final = frozenset(
    chr(code)
    for code in (
        0x200E,
        0x200F,
        0x202A,
        0x202B,
        0x202C,
        0x202D,
        0x202E,
        0x2066,
        0x2067,
        0x2068,
        0x2069,
    )
)

_QUOTE_MARKS: Final = frozenset("׳״'\"`’”ʼ")
"""Geresh, gershayim, ASCII quote, double quote and backtick, the right
single and double smart quotes, and the modifier apostrophe."""

_NON_LETTER_OR_NUMBER_RUN: Final = regex.compile(r"[^\p{L}\p{N}]+")

_DIACRITIC_FOLD: Final[dict[str, str]] = {
    "À": "A",
    "Á": "A",
    "Â": "A",
    "Ã": "A",
    "Ä": "A",
    "Å": "A",
    "Æ": "AE",
    "Ç": "C",
    "È": "E",
    "É": "E",
    "Ê": "E",
    "Ë": "E",
    "Ì": "I",
    "Í": "I",
    "Î": "I",
    "Ï": "I",
    "Ð": "D",
    "Ñ": "N",
    "Ò": "O",
    "Ó": "O",
    "Ô": "O",
    "Õ": "O",
    "Ö": "O",
    "Ø": "O",
    "Ù": "U",
    "Ú": "U",
    "Û": "U",
    "Ü": "U",
    "Ý": "Y",
    "Þ": "TH",
    "à": "a",
    "á": "a",
    "â": "a",
    "ã": "a",
    "ä": "a",
    "å": "a",
    "æ": "ae",
    "ç": "c",
    "è": "e",
    "é": "e",
    "ê": "e",
    "ë": "e",
    "ì": "i",
    "í": "i",
    "î": "i",
    "ï": "i",
    "ð": "d",
    "ñ": "n",
    "ò": "o",
    "ó": "o",
    "ô": "o",
    "õ": "o",
    "ö": "o",
    "ø": "o",
    "ù": "u",
    "ú": "u",
    "û": "u",
    "ü": "u",
    "ý": "y",
    "þ": "th",
    "ÿ": "y",
}
"""The Dart ``_diacriticFold`` table, entry for entry: Latin-1 Supplement
only. ``ß``, ``×`` and ``÷`` are deliberately absent, as in Dart."""

_HEBREW_FINALS_FOLD: Final[dict[str, str]] = {
    "ך": "כ",
    "ם": "מ",
    "ן": "נ",
    "ף": "פ",
    "ץ": "צ",
}

_STEP_1_TO_4: Final[dict[int, str | None]] = {
    **{ord(char): None for char in _BIDI_CONTROLS},
    **{code: None for code in range(0x0591, 0x05C8)},
    **{ord(char): None for char in _QUOTE_MARKS},
    **{ord(char): folded for char, folded in _DIACRITIC_FOLD.items()},
}
"""Steps 1–4 as one ``str.translate`` table. The four steps touch disjoint
characters and none of them produces a character another one removes, so
applying them together is the same as applying them in order."""

_STEP_7: Final[dict[int, str]] = {
    ord(char): medial for char, medial in _HEBREW_FINALS_FOLD.items()
}


def normalise(raw: str) -> str:
    """``TextNormaliser.normalise``: the seven-step pipeline over ``raw``.

    Not quite idempotent, exactly as in Dart (whose doc comment claims it
    is): the fold runs before the lowercase, so a character outside Latin-1
    that lowercases *into* the fold table (``Ÿ`` to ``ÿ``, the Angstrom sign
    to ``å``) is folded only by a second pass.
    """
    text = raw.translate(_STEP_1_TO_4)
    text = dart_lower(text)
    text = _NON_LETTER_OR_NUMBER_RUN.sub(" ", text).strip(" ")
    return text.translate(_STEP_7)


def contains_hebrew(raw: str) -> bool:
    """``TextNormaliser.containsHebrew``: whether ``raw`` (untouched) holds a
    character in U+0590–U+05FF."""
    return any("֐" <= char <= "׿" for char in raw)


def words(raw: str, min_length: int = 1) -> list[str]:
    """``TextNormaliser.words``: the normalised words of ``raw`` at least
    ``min_length`` UTF-16 code units long, in order."""
    normalised = normalise(raw)
    if not normalised:
        return []
    return [word for word in normalised.split(" ") if utf16_len(word) >= min_length]


def _join(parts: list[str]) -> str:
    return " ".join(part for part in parts if part)


def dish_search_text(dish: Dish) -> str:
    """``TextNormaliser.dishSearchText``: the dish's name, description, every
    option name and every option value, each normalised, joined by single
    spaces with empty parts dropped. The input to :mod:`app.keto.fingerprint`.
    """
    parts = [normalise(dish.name), normalise(dish.description)]
    for option in dish.options:
        parts.append(normalise(option.name))
        parts.extend(normalise(value) for value in option.values)
    return _join(parts)


def dish_core_text(dish: Dish) -> str:
    """``TextNormaliser.dishCoreText``: the dish's own name and description,
    normalised, with no option text (issue #192)."""
    return _join([normalise(dish.name), normalise(dish.description)])


def dish_option_rules_text(dish: Dish) -> str:
    """``TextNormaliser.dishOptionRulesText``: every option name and each
    option value that is not a removal (:func:`is_removal_option_value`)."""
    parts: list[str] = []
    for option in dish.options:
        parts.append(normalise(option.name))
        parts.extend(
            normalise(value)
            for value in option.values
            if not is_removal_option_value(value)
        )
    return _join(parts)


def dish_rules_text(dish: Dish) -> str:
    """``TextNormaliser.dishRulesText``: what the rule engine reads,
    :func:`dish_core_text` plus :func:`dish_option_rules_text`."""
    return _join([dish_core_text(dish), dish_option_rules_text(dish)])


def is_removal_option_value(raw: str) -> bool:
    """``TextNormaliser.isRemovalOptionValue``: whether the first normalised
    word of ``raw`` is an option-removal word ("no", "without", "ללא", ...).
    A blank value is not a removal."""
    normalised = normalise(raw)
    if not normalised:
        return False
    first = normalised.split(" ")[0]
    vocab = vocabulary()
    return (
        first in vocab.option_removal_words_en or first in vocab.option_removal_words_he
    )

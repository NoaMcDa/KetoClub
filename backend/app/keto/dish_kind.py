"""What a menu line is: food, a drink, an extra or a notice (D21).

The Python twin of ``lib/utils/dish_kind.dart`` (architecture.md D21, D25).
Only food counts toward the keto score and the verdict counts
(:mod:`app.keto.score`); every kind is still classified and listed. The kind
is computed, never stored. Evidence is read in order — the category heading
first, the dish name second, never the description — and on doubt the
answer is food.
"""

import re
from collections.abc import Sequence
from dataclasses import dataclass
from enum import StrEnum
from functools import cache

from app.keto.models import Dish, Menu
from app.keto.normaliser import normalise
from app.keto.patterns import hebrew_trigger_pattern, latin_trigger_pattern
from app.keto.vocabulary import vocabulary


class DishKind(StrEnum):
    """Dart ``DishKind``; the value is the Dart enum ``name``."""

    FOOD = "food"
    DRINK = "drink"
    EXTRA = "extra"
    NOTICE = "notice"

    @property
    def counts_toward_score(self) -> bool:
        """Dart ``countsTowardScore``: true for :attr:`FOOD` only."""
        return self is DishKind.FOOD


@dataclass(frozen=True, slots=True)
class _WordList:
    """One compiled vocabulary list (Dart ``_Vocabulary``)."""

    patterns: tuple[re.Pattern[str], ...]

    @classmethod
    def of(
        cls, en: Sequence[str], he: Sequence[str], *, allow_hebrew_prefix: bool
    ) -> "_WordList":
        return cls(
            tuple(latin_trigger_pattern(normalise(word)) for word in en)
            + tuple(
                hebrew_trigger_pattern(
                    normalise(word), allow_prefix=allow_hebrew_prefix
                )
                for word in he
            )
        )

    def matches(self, normalised: str) -> bool:
        return any(pattern.search(normalised) for pattern in self.patterns)


@dataclass(frozen=True, slots=True)
class _Lists:
    drink_categories: _WordList
    extra_categories: _WordList
    food_categories: _WordList
    notices: _WordList
    drink_names: _WordList
    drink_name_guards: _WordList
    extra_names: _WordList
    plain_drink_names: _WordList
    drink_heading_guards: _WordList
    drink_heading_bases: tuple[tuple[re.Pattern[str], str], ...]


@cache
def _lists() -> _Lists:
    words = vocabulary().dish_kinds
    prefix = words.hebrew_prefix_allowed
    return _Lists(
        drink_categories=_WordList.of(
            words.drink_category_words_en,
            words.drink_category_words_he,
            allow_hebrew_prefix=prefix.drink_categories,
        ),
        extra_categories=_WordList.of(
            words.extra_category_words_en,
            words.extra_category_words_he,
            allow_hebrew_prefix=prefix.extra_categories,
        ),
        food_categories=_WordList.of(
            words.food_category_words_en,
            words.food_category_words_he,
            allow_hebrew_prefix=prefix.food_categories,
        ),
        notices=_WordList.of(
            words.notice_category_words_en,
            words.notice_category_words_he,
            allow_hebrew_prefix=prefix.notice,
        ),
        drink_names=_WordList.of(
            words.drink_name_triggers_en,
            words.drink_name_triggers_he,
            allow_hebrew_prefix=prefix.drink_names,
        ),
        drink_name_guards=_WordList.of(
            words.drink_name_guard_words_en,
            words.drink_name_guard_words_he,
            allow_hebrew_prefix=prefix.drink_name_guards,
        ),
        extra_names=_WordList.of(
            words.extra_name_words_en,
            words.extra_name_words_he,
            allow_hebrew_prefix=prefix.extra_names,
        ),
        plain_drink_names=_WordList.of(
            words.plain_drink_words_en,
            words.plain_drink_words_he,
            allow_hebrew_prefix=prefix.plain_drink_names,
        ),
        drink_heading_guards=_WordList.of(
            words.drink_heading_guard_words_en,
            words.drink_heading_guard_words_he,
            allow_hebrew_prefix=prefix.drink_heading_guards,
        ),
        drink_heading_bases=(
            *(
                (latin_trigger_pattern(normalise(word)), label)
                for word, label in words.drink_heading_bases_en.items()
            ),
            *(
                (
                    hebrew_trigger_pattern(
                        normalise(word), allow_prefix=prefix.drink_headings
                    ),
                    label,
                )
                for word, label in words.drink_heading_bases_he.items()
            ),
        ),
    )


def category_kind_of(category_name: str) -> DishKind:
    """Dart ``categoryKindOf``: the kind a heading alone implies, or food.

    A notice word wins; then a food word vetoes (the heading decides
    nothing); then a drink word, then an extras word.
    """
    heading = normalise(category_name)
    if not heading:
        return DishKind.FOOD
    lists = _lists()
    if lists.notices.matches(heading):
        return DishKind.NOTICE
    if lists.food_categories.matches(heading):
        return DishKind.FOOD
    if lists.drink_categories.matches(heading):
        return DishKind.DRINK
    if lists.extra_categories.matches(heading):
        return DishKind.EXTRA
    return DishKind.FOOD


def dish_kind_of(*, category: str, dish: Dish) -> DishKind:
    """Dart ``dishKindOf``: the heading decides when it can; otherwise the
    dish *name* (never the description): a notice word at a price of zero is
    a notice, a drink word with no ingredient guard is a drink, anything
    else is food."""
    from_heading = category_kind_of(category)
    if from_heading is not DishKind.FOOD:
        return from_heading
    name = normalise(dish.name)
    if not name:
        return DishKind.FOOD
    lists = _lists()
    if dish.price == 0 and lists.notices.matches(name):
        return DishKind.NOTICE
    if lists.extra_names.matches(name):
        return DishKind.EXTRA
    if lists.drink_names.matches(name) and not lists.drink_name_guards.matches(name):
        return DishKind.DRINK
    return DishKind.FOOD


def heading_drink_base(*, category: str, dish: Dish) -> str | None:
    """Dart ``headingDrinkBase``: the red base a drink takes from a beer,
    juice or shake heading (issue #474), or ``None`` for anything that is
    not a drink, a plain drink, a guarded name or another heading."""
    if dish_kind_of(category=category, dish=dish) is not DishKind.DRINK:
        return None
    heading = normalise(category)
    name = normalise(dish.name)
    lists = _lists()
    if lists.plain_drink_names.matches(name) or lists.drink_heading_guards.matches(
        name
    ):
        return None
    for pattern, label in lists.drink_heading_bases:
        if pattern.search(heading):
            return label
    return None


def dish_kinds_of(menu: Menu) -> dict[str, DishKind]:
    """Dart ``dishKindsOf``: every dish's kind by dish id, in menu order. A
    dish id listed under two categories takes the first one's heading."""
    kinds: dict[str, DishKind] = {}
    for category in menu.categories:
        for dish in category.dishes:
            if dish.id not in kinds:
                kinds[dish.id] = dish_kind_of(category=category.name, dish=dish)
    return kinds

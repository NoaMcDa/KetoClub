"""The rule engine's vocabulary matcher (architecture.md §6.2, D25, #324).

The Python twin of ``lib/utils/classification_rules.dart``. :func:`match`,
:func:`match_dish`, :func:`carb_only_base`, :func:`describes_filling` and the
three ``mentions_*`` checks run the bilingual vocabulary
(:mod:`app.keto.vocabulary`) over normalised dish text exactly as the Dart
``ClassificationRules`` does; the golden ``rules.json`` pins every result.

Behaviour the port keeps from Dart:

* **Tables are scanned in vocabulary order.** The English and then the
  Hebrew table, each in its ``constants.dart`` order (the vocabulary keeps
  ``nonKetoBases*`` as lists and ``carbModifiers*`` as ordered pairs). The
  first base found at the smallest offset wins a tie, so table order decides
  the label when two bases start at the same character.
* **Guards** (D-V1) look at the up-to-two words before a match and the
  up-to-two words after it, and test each normalised guard phrase against
  that window with space padding on both sides, so a two-word phrase must be
  literally adjacent.
* **Suppression** removes every occurrence whose key a fired, more specific
  trigger suppresses; the surviving sentences are deduplicated in first
  occurrence order, after a sort by match start.
* **Offsets.** Python match offsets count code points where Dart's count
  UTF-16 units. Every use of an offset here is either a slice of the same
  string (the guard windows) or an order comparison (the sort and the
  carb-only label), and a code-point offset preserves both, so no conversion
  is needed. The carb-only blanking replaces each matched code point with
  one space where Dart writes one space per unit; the leftover words, split
  on spaces with empty ones dropped, are the same either way.
* **The sort is stable here.** Dart's ``List.sort`` is an insertion sort
  (stable) up to 33 elements and a dual-pivot quicksort beyond. No dish in
  the golden corpus produces more than 33 occurrences; a dish that did, with
  two occurrences at one offset, could order its sentences differently.
* ``mentions_*`` normalise their argument, even when a caller passes text
  that is already normalised: :func:`app.keto.normaliser.normalise` is not
  idempotent (``Ÿ``), and Dart normalises twice on those paths too.
"""

import re
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from functools import cache
from typing import Final, Literal

from app.keto.dart_text import DART_WHITESPACE
from app.keto.models import Dish
from app.keto.normaliser import (
    contains_hebrew,
    dish_core_text,
    dish_option_rules_text,
    dish_rules_text,
    is_removal_option_value,
    normalise,
)
from app.keto.patterns import hebrew_trigger_pattern, latin_trigger_pattern
from app.keto.vocabulary import GuardWords, vocabulary

RuleKind = Literal["green", "yellow", "red"]
"""The verdict colour a :class:`RuleMatch` implies."""

_DART_WHITESPACE_CHARS: Final = "".join(sorted(DART_WHITESPACE))

_NO_GUARDS: Final[Mapping[str, GuardWords]] = {}
"""The seed-oil, plant and filling tables have no guards."""


@dataclass(frozen=True, slots=True)
class _Compiled:
    """A compiled trigger: its dictionary key (for guard, label and
    suppression lookups), its pattern, and its waiter sentence (empty for a
    base or a dietary trigger, which carry none)."""

    key: str
    pattern: re.Pattern[str]
    sentence: str = ""


@dataclass(frozen=True, slots=True)
class _Occurrence:
    """One surviving carb-modifier occurrence. ``end`` is exclusive."""

    start: int
    end: int
    key: str
    sentence: str


@dataclass(frozen=True, slots=True)
class RuleMatch:
    """Dart ``RuleMatch``: what the vocabulary found in one dish's text.

    ``base_label`` is set exactly when ``is_non_keto`` is true, and
    ``instructions`` is empty then.
    """

    is_non_keto: bool
    instructions: tuple[str, ...] = ()
    base_label: str | None = None

    @property
    def kind(self) -> RuleKind:
        """``red`` for a non-keto base, ``yellow`` with instructions,
        otherwise ``green``."""
        if self.is_non_keto:
            return "red"
        return "yellow" if self.instructions else "green"


# --- compiled tables ------------------------------------------------------------


def _latin(keys: Sequence[str]) -> tuple[_Compiled, ...]:
    return tuple(_Compiled(key, latin_trigger_pattern(normalise(key))) for key in keys)


def _hebrew(keys: Sequence[str], *, honour_no_prefix: bool) -> tuple[_Compiled, ...]:
    no_prefix = (
        set(vocabulary().no_prefix_hebrew_triggers) if honour_no_prefix else set()
    )
    return tuple(
        _Compiled(
            key,
            hebrew_trigger_pattern(normalise(key), allow_prefix=key not in no_prefix),
        )
        for key in keys
    )


@cache
def _bases_en() -> tuple[_Compiled, ...]:
    return _latin(vocabulary().non_keto_bases_en)


@cache
def _bases_he() -> tuple[_Compiled, ...]:
    return _hebrew(vocabulary().non_keto_bases_he, honour_no_prefix=True)


def _modifiers(
    pairs: Sequence[tuple[str, str]], compiled: tuple[_Compiled, ...]
) -> tuple[_Compiled, ...]:
    return tuple(
        _Compiled(entry.key, entry.pattern, sentence)
        for entry, (_, sentence) in zip(compiled, pairs, strict=True)
    )


@cache
def _carb_en() -> tuple[_Compiled, ...]:
    pairs = vocabulary().carb_modifiers_en
    return _modifiers(pairs, _latin([key for key, _ in pairs]))


@cache
def _carb_he() -> tuple[_Compiled, ...]:
    pairs = vocabulary().carb_modifiers_he
    return _modifiers(pairs, _hebrew([key for key, _ in pairs], honour_no_prefix=True))


@cache
def _seed_oil() -> tuple[tuple[_Compiled, ...], tuple[_Compiled, ...]]:
    vocab = vocabulary()
    return (
        _latin(vocab.seed_oil_triggers_en),
        _hebrew(vocab.seed_oil_triggers_he, honour_no_prefix=False),
    )


@cache
def _dairy() -> tuple[tuple[_Compiled, ...], tuple[_Compiled, ...]]:
    vocab = vocabulary()
    return (
        _latin(vocab.dairy_triggers_en),
        _hebrew(vocab.dairy_triggers_he, honour_no_prefix=False),
    )


@cache
def _plant() -> tuple[tuple[_Compiled, ...], tuple[_Compiled, ...]]:
    vocab = vocabulary()
    return (
        _latin(vocab.plant_triggers_en),
        _hebrew(vocab.plant_triggers_he, honour_no_prefix=False),
    )


@cache
def _filling_protein() -> tuple[tuple[_Compiled, ...], tuple[_Compiled, ...]]:
    vocab = vocabulary()
    return (
        _latin(vocab.filling_protein_triggers_en),
        _hebrew(vocab.filling_protein_triggers_he, honour_no_prefix=False),
    )


@cache
def _carb_only_qualifiers() -> frozenset[str]:
    vocab = vocabulary()
    return frozenset(
        normalise(word)
        for word in (*vocab.carb_only_qualifiers_en, *vocab.carb_only_qualifiers_he)
    )


@cache
def _normalised_phrase(phrase: str) -> str:
    return normalise(phrase)


# --- guards ---------------------------------------------------------------------


def _window_contains_any_phrase(
    window_words: Sequence[str], phrases: Sequence[str]
) -> bool:
    if not window_words or not phrases:
        return False
    window_text = f" {' '.join(window_words)} "
    return any(f" {_normalised_phrase(phrase)} " in window_text for phrase in phrases)


def _is_guarded(haystack: str, start: int, end: int, guard: GuardWords | None) -> bool:
    if guard is None:
        return False
    if guard.before:
        before_text = haystack[:start].rstrip(_DART_WHITESPACE_CHARS)
        if before_text:
            words = before_text.split(" ")
            if _window_contains_any_phrase(words[-2:], guard.before):
                return True
    if guard.after:
        after_text = haystack[end:].lstrip(_DART_WHITESPACE_CHARS)
        if after_text:
            words = after_text.split(" ")
            if _window_contains_any_phrase(words[:2], guard.after):
                return True
    return False


# --- scans ----------------------------------------------------------------------


def _first_unguarded_base_match(haystack: str) -> tuple[int, str] | None:
    """The earliest unguarded non-keto base in ``haystack`` as ``(start,
    label)``; at one start, the first table entry found wins."""
    vocab = vocabulary()
    best: tuple[int, str] | None = None
    for table, guards, labels in (
        (_bases_en(), vocab.keto_qualifier_guards_en, vocab.non_keto_base_labels_en),
        (_bases_he(), vocab.keto_qualifier_guards_he, vocab.non_keto_base_labels_he),
    ):
        for entry in table:
            for found in entry.pattern.finditer(haystack):
                if _is_guarded(
                    haystack, found.start(), found.end(), guards.get(entry.key)
                ):
                    continue
                if best is None or found.start() < best[0]:
                    best = (found.start(), labels.get(entry.key, entry.key))
    return best


def _any_unguarded_match(
    haystack: str,
    tables: Sequence[tuple[tuple[_Compiled, ...], Mapping[str, GuardWords]]],
) -> bool:
    for table, guards in tables:
        for entry in table:
            for found in entry.pattern.finditer(haystack):
                if not _is_guarded(
                    haystack, found.start(), found.end(), guards.get(entry.key)
                ):
                    return True
    return False


def _unguarded_modifier_occurrences(haystack: str) -> list[_Occurrence]:
    vocab = vocabulary()
    occurrences: list[_Occurrence] = []
    for table, guards in (
        (_carb_en(), vocab.keto_qualifier_guards_en),
        (_carb_he(), vocab.keto_qualifier_guards_he),
    ):
        for entry in table:
            for found in entry.pattern.finditer(haystack):
                if _is_guarded(
                    haystack, found.start(), found.end(), guards.get(entry.key)
                ):
                    continue
                occurrences.append(
                    _Occurrence(found.start(), found.end(), entry.key, entry.sentence)
                )
    occurrences.sort(key=lambda occurrence: occurrence.start)
    return occurrences


def _sentences_after_suppression(occurrences: Sequence[_Occurrence]) -> list[str]:
    suppresses = vocabulary().trigger_suppresses
    suppressed: set[str] = set()
    for key in {occurrence.key for occurrence in occurrences}:
        suppressed.update(suppresses.get(key, ()))
    sentences: dict[str, None] = {}
    for occurrence in occurrences:
        if occurrence.key not in suppressed:
            sentences.setdefault(occurrence.sentence, None)
    return list(sentences)


# --- public API -----------------------------------------------------------------


def match(raw_text: str) -> RuleMatch:
    """``ClassificationRules.match``: both vocabularies over ``raw_text``.

    A surviving non-keto base makes it red with no instructions; otherwise
    the unguarded, unsuppressed carb modifiers' sentences, deduplicated.
    """
    haystack = normalise(raw_text)
    base = _first_unguarded_base_match(haystack)
    if base is not None:
        return RuleMatch(is_non_keto=True, base_label=base[1])
    occurrences = _unguarded_modifier_occurrences(haystack)
    return RuleMatch(
        is_non_keto=False,
        instructions=tuple(_sentences_after_suppression(occurrences)),
    )


def match_dish(dish: Dish) -> RuleMatch:
    """``ClassificationRules.matchDish``: the vocabulary over one dish.

    1. A name that is only a starch or a bread (:func:`carb_only_base`) is
       red, unless the description or an option names a filling
       (:func:`describes_filling`).
    2. A non-keto base in the name or description is red.
    3. Carb modifiers are read from the rules text (options included,
       removals dropped). A non-keto base offered only as an option makes
       the dish yellow with ``optionBaseModification`` first.
    """
    carb_only = carb_only_base(dish.name)
    if carb_only is not None and not describes_filling(dish):
        return RuleMatch(is_non_keto=True, base_label=carb_only)

    base = _first_unguarded_base_match(dish_core_text(dish))
    if base is not None:
        return RuleMatch(is_non_keto=True, base_label=base[1])

    sentences = _sentences_after_suppression(
        _unguarded_modifier_occurrences(dish_rules_text(dish))
    )
    option_base = _first_unguarded_base_match(dish_option_rules_text(dish))
    if option_base is not None:
        label = option_base[1]
        templates = vocabulary().templates
        template = (
            templates.option_base_modification_he
            if contains_hebrew(label)
            else templates.option_base_modification_en
        )
        return RuleMatch(
            is_non_keto=False,
            instructions=(template.replace("{base}", label), *sentences),
        )
    return RuleMatch(is_non_keto=False, instructions=tuple(sentences))


def describes_filling(dish: Dish) -> bool:
    """``ClassificationRules.describesFilling``: whether the description or a
    non-removal option value names a protein, a plant or dairy. The name is
    never consulted."""
    parts = [normalise(dish.description)]
    for option in dish.options:
        for value in option.values:
            if is_removal_option_value(value):
                continue
            parts.append(normalise(value))
    text = " ".join(part for part in parts if part)
    if not text:
        return False
    protein_en, protein_he = _filling_protein()
    return (
        mentions_plant(text)
        or mentions_dairy(text)
        or _any_unguarded_match(
            text, [(protein_en, _NO_GUARDS), (protein_he, _NO_GUARDS)]
        )
    )


def carb_only_base(name: str) -> str | None:
    """``ClassificationRules.carbOnlyBase``: the carb trigger a dish ``name``
    consists of, when it is nothing but carb-only-eligible triggers and
    qualifier words; ``None`` otherwise.

    The label is the earliest trigger (at a tie, the longest), through
    ``carbOnlyBaseLabels`` when it has an entry there.
    """
    haystack = normalise(name)
    if not haystack:
        return None
    occurrences = _unguarded_modifier_occurrences(haystack)
    if not occurrences:
        return None
    eligible = vocabulary().carb_only_eligible_triggers
    if any(occurrence.key not in eligible for occurrence in occurrences):
        return None

    chars = list(haystack)
    for occurrence in occurrences:
        chars[occurrence.start : occurrence.end] = [" "] * (
            occurrence.end - occurrence.start
        )
    remainder = (word for word in "".join(chars).split(" ") if word)
    if not all(_is_carb_only_qualifier(word) for word in remainder):
        return None

    best = occurrences[0]
    for occurrence in occurrences:
        if occurrence.start < best.start or (
            occurrence.start == best.start and occurrence.end > best.end
        ):
            best = occurrence
    return vocabulary().carb_only_base_labels.get(best.key, best.key)


def _is_carb_only_qualifier(word: str) -> bool:
    """A leftover name word that is a qualifier as written, or after a
    leading ה/ו particle is stripped."""
    qualifiers = _carb_only_qualifiers()
    if word in qualifiers:
        return True
    # Dart counts ``length`` in UTF-16 units, but with a BMP first letter
    # "longer than one" holds in units exactly when it holds in code points.
    if len(word) > 1 and word[0] in "הו":
        return word[1:] in qualifiers
    return False


def mentions_seed_oil(raw_text: str) -> bool:
    """``ClassificationRules.mentionsSeedOil``: frying or a seed oil named
    in ``raw_text``, in either language."""
    en, he = _seed_oil()
    return _any_unguarded_match(
        normalise(raw_text), [(en, _NO_GUARDS), (he, _NO_GUARDS)]
    )


def mentions_dairy(raw_text: str) -> bool:
    """``ClassificationRules.mentionsDairy``: a dairy word in ``raw_text``
    that no plant word beside it rescues (``coconut cream``)."""
    vocab = vocabulary()
    en, he = _dairy()
    return _any_unguarded_match(
        normalise(raw_text), [(en, vocab.dairy_guards_en), (he, vocab.dairy_guards_he)]
    )


def mentions_plant(raw_text: str) -> bool:
    """``ClassificationRules.mentionsPlant``: a vegetable, salad, fruit,
    legume or other plant named in ``raw_text``."""
    en, he = _plant()
    return _any_unguarded_match(
        normalise(raw_text), [(en, _NO_GUARDS), (he, _NO_GUARDS)]
    )

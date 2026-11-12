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
  literally adjacent. A match is also cancelled when the normalised dish
  *name* (the whole text for :func:`match` and :func:`carb_only_base`)
  holds one of its ``ketoSubstituteNameWords*`` phrases anywhere, tested
  the same way (issue #273); the description is never read for those.
* **English bases match their regular plural** (``s``/``es``, issue #274)
  under their own key, so the singular's guard and label apply.
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
    is_add_on_option_group,
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


def _latin(keys: Sequence[str], *, allow_plural: bool = False) -> tuple[_Compiled, ...]:
    return tuple(
        _Compiled(key, latin_trigger_pattern(normalise(key), allow_plural=allow_plural))
        for key in keys
    )


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
    # Every English base also matches its regular plural (issue #274).
    return _latin(vocabulary().non_keto_bases_en, allow_plural=True)


@cache
def _bases_he() -> tuple[_Compiled, ...]:
    return _hebrew(vocabulary().non_keto_bases_he, honour_no_prefix=True)


@cache
def _dough_en() -> tuple[_Compiled, ...]:
    return _latin(vocabulary().dough_bases_en)


@cache
def _dough_he() -> tuple[_Compiled, ...]:
    # Dart compiles the dough table with ``_compileDietaryHe``: always the
    # permissive prefix, whatever ``noPrefixHebrewTriggers`` says.
    return _hebrew(vocabulary().dough_bases_he, honour_no_prefix=False)


@cache
def _choice_base_en() -> tuple[_Compiled, ...]:
    # The other bases of a choice-of-base group (issue #473), with the
    # regular plural like every English base.
    return _latin(vocabulary().choice_bases_en, allow_plural=True)


@cache
def _choice_base_he() -> tuple[_Compiled, ...]:
    return _hebrew(vocabulary().choice_bases_he, honour_no_prefix=False)


@cache
def _choice_words() -> tuple[_Compiled, ...]:
    vocab = vocabulary()
    return (
        *_latin(vocab.choice_group_words_en),
        *_hebrew(vocab.choice_group_words_he, honour_no_prefix=False),
    )


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
        for word in (
            *vocab.carb_only_qualifiers_en,
            *vocab.carb_only_qualifiers_he,
            *vocab.carb_only_toppings_en,
            *vocab.carb_only_toppings_he,
        )
    )


@cache
def _toppings() -> tuple[_Compiled, ...]:
    """The toppings :func:`describes_filling` blanks out (issue #273),
    English then Hebrew, in vocabulary order; Hebrew with the prefix."""
    vocab = vocabulary()
    return (
        *_latin(vocab.carb_only_toppings_en),
        *_hebrew(vocab.carb_only_toppings_he, honour_no_prefix=False),
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


def _is_name_guarded(name: str, key: str) -> bool:
    """Whether the normalised dish ``name`` holds, as whole words, a
    keto-substitute phrase ``ketoSubstituteNameWords*`` lists for ``key``
    (issue #273): the guard that reaches across the whole name."""
    vocab = vocabulary()
    phrases = vocab.keto_substitute_name_words_en.get(key)
    if phrases is None:
        phrases = vocab.keto_substitute_name_words_he.get(key)
    if phrases is None or not name:
        return False
    return _window_contains_any_phrase([name], phrases)


def _is_cancelled(
    haystack: str,
    name: str,
    start: int,
    end: int,
    key: str,
    guards: Mapping[str, GuardWords],
) -> bool:
    """The two-word-window guard (D-V1), or a keto substitute anywhere in
    the dish name (issue #273)."""
    return _is_guarded(haystack, start, end, guards.get(key)) or _is_name_guarded(
        name, key
    )


# --- scans ----------------------------------------------------------------------


def _first_unguarded_base_match(haystack: str, *, name: str) -> tuple[int, str] | None:
    """The earliest unguarded non-keto base in ``haystack`` as ``(start,
    label)``; at one start, the first table entry found wins. ``name`` is
    the normalised dish name the name-wide substitute guard reads."""
    vocab = vocabulary()
    best: tuple[int, str] | None = None
    for table, guards, labels in (
        (_bases_en(), vocab.keto_qualifier_guards_en, vocab.non_keto_base_labels_en),
        (_bases_he(), vocab.keto_qualifier_guards_he, vocab.non_keto_base_labels_he),
    ):
        for entry in table:
            for found in entry.pattern.finditer(haystack):
                if _is_cancelled(
                    haystack, name, found.start(), found.end(), entry.key, guards
                ):
                    continue
                if best is None or found.start() < best[0]:
                    best = (found.start(), labels.get(entry.key, entry.key))
    return best


def _unguarded_dough_label(haystack: str) -> str | None:
    """The label of the first dough word that survives its guards in
    ``haystack``, English table first; ``None`` when it names no dough or
    only a rescued one."""
    vocab = vocabulary()
    for table, guards, labels in (
        (_dough_en(), vocab.keto_qualifier_guards_en, vocab.non_keto_base_labels_en),
        (_dough_he(), vocab.keto_qualifier_guards_he, vocab.non_keto_base_labels_he),
    ):
        for entry in table:
            for found in entry.pattern.finditer(haystack):
                if not _is_guarded(
                    haystack, found.start(), found.end(), guards.get(entry.key)
                ):
                    return labels.get(entry.key, entry.key)
    return None


def _unguarded_choice_base_label(name: str) -> str | None:
    """The label of the first choice base (pasta, noodles; issue #473) that
    survives its guards in an option group's normalised ``name``, English
    table first, when the name also holds a choice word; ``None``
    otherwise."""
    if not any(word.pattern.search(name) for word in _choice_words()):
        return None
    vocab = vocabulary()
    for table, guards, labels in (
        (
            _choice_base_en(),
            vocab.keto_qualifier_guards_en,
            vocab.non_keto_base_labels_en,
        ),
        (
            _choice_base_he(),
            vocab.keto_qualifier_guards_he,
            vocab.non_keto_base_labels_he,
        ),
    ):
        for entry in table:
            for found in entry.pattern.finditer(name):
                if not _is_guarded(
                    name, found.start(), found.end(), guards.get(entry.key)
                ):
                    return labels.get(entry.key, entry.key)
    return None


def _names_rescued_dough(haystack: str) -> bool:
    """Whether a dough word in ``haystack`` is rescued by one of its
    guards: a cauliflower, almond or keto dough is named there; a pasta or
    noodle word rescued the same way counts too (issue #473)."""
    vocab = vocabulary()
    for table, guards in (
        (_dough_en(), vocab.keto_qualifier_guards_en),
        (_dough_he(), vocab.keto_qualifier_guards_he),
        (_choice_base_en(), vocab.keto_qualifier_guards_en),
        (_choice_base_he(), vocab.keto_qualifier_guards_he),
    ):
        for entry in table:
            for found in entry.pattern.finditer(haystack):
                if _is_guarded(
                    haystack, found.start(), found.end(), guards.get(entry.key)
                ):
                    return True
    return False


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


def _unguarded_modifier_occurrences(haystack: str, *, name: str) -> list[_Occurrence]:
    vocab = vocabulary()
    occurrences: list[_Occurrence] = []
    for table, guards in (
        (_carb_en(), vocab.keto_qualifier_guards_en),
        (_carb_he(), vocab.keto_qualifier_guards_he),
    ):
        for entry in table:
            for found in entry.pattern.finditer(haystack):
                if _is_cancelled(
                    haystack, name, found.start(), found.end(), entry.key, guards
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
    base = _first_unguarded_base_match(haystack, name=haystack)
    if base is not None:
        return RuleMatch(is_non_keto=True, base_label=base[1])
    occurrences = _unguarded_modifier_occurrences(haystack, name=haystack)
    return RuleMatch(
        is_non_keto=False,
        instructions=tuple(_sentences_after_suppression(occurrences)),
    )


def match_dish(dish: Dish) -> RuleMatch:
    """``ClassificationRules.matchDish``: the vocabulary over one dish.

    1. A name that is only a starch or a bread (:func:`carb_only_base`) is
       red, unless the description or an option names a filling
       (:func:`describes_filling`); a starch that is not a bread is rescued
       only by a protein (issue #276).
    2. A non-keto base in the name or description is red.
    3. A choice of dough among the options (:func:`dough_choice_base`) is
       red: the group asks which dough the dish is made of.
    4. Carb modifiers are read from the rules text (options included,
       removals dropped). A non-keto base offered only as an option makes
       the dish yellow with ``optionBaseModification`` first.
    """
    carb_only = carb_only_base(dish.name)
    if carb_only is not None and not (
        describes_filling(dish)
        if carb_only in vocabulary().carb_only_bread_triggers
        else _describes_protein(dish)
    ):
        return RuleMatch(is_non_keto=True, base_label=carb_only)

    name = normalise(dish.name)
    base = _first_unguarded_base_match(dish_core_text(dish), name=name)
    if base is not None:
        return RuleMatch(is_non_keto=True, base_label=base[1])

    dough = dough_choice_base(dish)
    if dough is not None:
        return RuleMatch(is_non_keto=True, base_label=dough)

    sentences = _sentences_after_suppression(
        _unguarded_modifier_occurrences(dish_rules_text(dish), name=name)
    )
    option_base = _first_unguarded_base_match(dish_option_rules_text(dish), name=name)
    # A choice of dough that reaches this line offers a rescued one; it is
    # steered around like any option base, even when the joined option text
    # reads as guarded.
    label = option_base[1] if option_base is not None else _first_dough_choice(dish)
    if label is not None:
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


def dough_choice_base(dish: Dish) -> str | None:
    """``ClassificationRules.doughChoiceBase``: the dough ``dish`` is built
    on when one of its option groups is a choice of dough.

    The group's **name** must hold an unguarded dough word ("בחרו סוג בצק -
    MIX", "Choose your dough"); its values are never what makes it one. A
    group that offers a rescued dough among its non-removal values ("בצק
    כרובית", or a bare "כרובית") is skipped, and :func:`match_dish` makes
    the dish a yellow instead; a dish with several dough groups is red as
    soon as one of them offers none.
    """
    for label, offers_rescued in _dough_choices(dish):
        if not offers_rescued:
            return label
    return None


def _dough_choices(dish: Dish) -> list[tuple[str, bool]]:
    """Dart ``_doughChoices``: every choice-of-dough option group of
    ``dish`` in option order, as ``(label, offers_rescued)``."""
    choices: list[tuple[str, bool]] = []
    for option in dish.options:
        # An upsell is never what the dish is made of (issue #475).
        if is_add_on_option_group(option.name):
            continue
        name = normalise(option.name)
        label = _unguarded_dough_label(name)
        if label is None:
            label = _unguarded_choice_base_label(name)
        if label is None:
            continue
        choices.append(
            (
                label,
                any(
                    not is_removal_option_value(value)
                    and _names_rescued_dough(f"{name} {normalise(value)}")
                    for value in option.values
                ),
            )
        )
    return choices


def _first_dough_choice(dish: Dish) -> str | None:
    """The label of ``dish``'s first choice-of-dough group, or ``None``."""
    choices = _dough_choices(dish)
    return choices[0][0] if choices else None


def _filling_text(dish: Dish) -> str:
    """Dart ``_fillingText``: the description and non-removal option values,
    normalised and joined, with every topping replaced by a space (issue
    #273): Dart's ``replaceAll`` with each topping pattern, in order."""
    parts = [normalise(dish.description)]
    for option in dish.options:
        if is_add_on_option_group(option.name):
            continue
        for value in option.values:
            if is_removal_option_value(value):
                continue
            parts.append(normalise(value))
    text = " ".join(part for part in parts if part)
    if not text:
        return text
    for topping in _toppings():
        text = topping.pattern.sub(" ", text)
    return text


def _describes_protein(dish: Dish) -> bool:
    """Dart ``_describesProtein``: whether the filling text names a protein,
    the one filling that rescues a starch named alone (issue #276)."""
    text = _filling_text(dish)
    if not text:
        return False
    protein_en, protein_he = _filling_protein()
    return _any_unguarded_match(
        text, [(protein_en, _NO_GUARDS), (protein_he, _NO_GUARDS)]
    )


def describes_filling(dish: Dish) -> bool:
    """``ClassificationRules.describesFilling``: whether the description or a
    non-removal option value names a protein, a plant or dairy. The name is
    never consulted."""
    text = _filling_text(dish)
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
    occurrences = _unguarded_modifier_occurrences(haystack, name=haystack)
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

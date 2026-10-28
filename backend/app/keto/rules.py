"""The rule engine's vocabulary matcher (architecture.md §6.2, D25, #324).

The Python twin of ``lib/utils/classification_rules.dart``. :func:`match`,
:func:`match_dish`, :func:`carb_only_base`, :func:`describes_filling` and the
three ``mentions_*`` checks run the bilingual vocabulary
(:mod:`app.keto.vocabulary`) over normalised dish text exactly as the Dart
``ClassificationRules`` does; the golden ``rules.json`` pins every result.
:func:`allergen_findings` and :func:`allergen_concerns` (Banto; ALG-04b) run
the allergen matcher (:mod:`app.keto.allergens`) over a dish's name,
description and non-removal option values; the golden
``allergen_concerns.json`` pins them, kosher's meat-with-dairy rule (#342)
included.

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
* **Hidden carbs** (issue #213 on the rules path): :func:`match` and
  :func:`match_dish` also return the dish's hidden-carb flags, from the
  ``hiddenCarbTriggers*`` tables, in the language of the text. The words
  either side of a trigger are read as the guards read them, with
  ``hiddenCarbWindowWords`` words for the guard phrases and the covering
  sweeteners; the occurrences are sorted by ``(start, -end)``, a total
  order, so the sort's stability never matters there.
* ``mentions_*`` normalise their argument, even when a caller passes text
  that is already normalised: :func:`app.keto.normaliser.normalise` is not
  idempotent (``Ÿ``), and Dart normalises twice on those paths too.
"""

import re
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from functools import cache
from typing import Final, Literal, cast

from app.keto.allergens import AllergenHit, allergens, find, find_with, match_text
from app.keto.dart_text import DART_WHITESPACE, utf16_len, utf16_slice
from app.keto.models import (
    Certainty,
    Concern,
    ConcernSource,
    Dish,
    HiddenCarb,
    HiddenCarbCertainty,
    RestrictionIdName,
)
from app.keto.normaliser import (
    contains_hebrew,
    dish_core_text,
    dish_option_rules_text,
    dish_rules_text,
    is_removal_option_value,
    normalise,
)
from app.keto.patterns import hebrew_trigger_pattern, latin_trigger_pattern
from app.keto.vocabulary import GuardWords, HiddenCarbTrigger, vocabulary

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
class _CompiledHidden:
    """A compiled hidden-carb trigger: its key (for its per-trigger guard),
    its pattern and its flag (issue #213 on the rules path)."""

    key: str
    pattern: re.Pattern[str]
    flag: HiddenCarbTrigger


@dataclass(frozen=True, slots=True)
class _HiddenOccurrence:
    """One unguarded hidden-carb occurrence. ``end`` is exclusive."""

    start: int
    end: int
    flag: HiddenCarbTrigger


@dataclass(frozen=True, slots=True)
class RuleMatch:
    """Dart ``RuleMatch``: what the vocabulary found in one dish's text.

    ``base_label`` is set exactly when ``is_non_keto`` is true, and
    ``instructions`` and ``hidden_carbs`` are empty then. ``hidden_carbs``
    never adds to ``instructions`` (so ``kind`` ignores it): the heuristic
    decides what a flag does to the verdict (§9.4 rule 5a).
    """

    is_non_keto: bool
    instructions: tuple[str, ...] = ()
    base_label: str | None = None
    hidden_carbs: tuple[HiddenCarb, ...] = ()

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
def _hidden_en() -> tuple[_CompiledHidden, ...]:
    """The English hidden-carb triggers, normalised at compile time."""
    return tuple(
        _CompiledHidden(key, latin_trigger_pattern(normalise(key)), flag)
        for key, flag in vocabulary().hidden_carb_triggers_en
    )


@cache
def _hidden_he() -> tuple[_CompiledHidden, ...]:
    """The Hebrew hidden-carb triggers, every one with the permissive
    prefix."""
    return tuple(
        _CompiledHidden(key, hebrew_trigger_pattern(normalise(key)), flag)
        for key, flag in vocabulary().hidden_carb_triggers_he
    )


@cache
def _hidden_guard_phrases(concern: str) -> tuple[str, ...]:
    """Dart ``_hiddenGuardPhrasesFor``: the guard phrases, both languages,
    that answer a flag of ``concern``. Only membership matters, so the
    golden's sorted key order is harmless."""
    vocab = vocabulary()
    phrases: list[str] = []
    for table in (
        vocab.hidden_carb_guard_phrases_en,
        vocab.hidden_carb_guard_phrases_he,
    ):
        for answers, words in table.items():
            if (
                answers == "any"
                or (answers == "sugar" and concern != "flour")
                or (answers == "flour" and concern != "sugar")
            ):
                phrases.extend(words)
    return tuple(phrases)


@cache
def _covering_modifiers() -> frozenset[str]:
    return frozenset(vocabulary().hidden_carb_covering_modifiers)


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


def is_guarded(haystack: str, start: int, end: int, guard: GuardWords | None) -> bool:
    """``ClassificationRules.isGuarded``: whether ``guard`` cancels the match
    spanning ``start``-``end`` (code-point offsets, ``end`` exclusive) in the
    normalised ``haystack``, with the D-V1 two-word window. Public for the
    allergen matcher (:mod:`app.keto.allergens`), as the Dart one is."""
    return _is_guarded(haystack, start, end, guard)


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


def _unsuppressed(occurrences: Sequence[_Occurrence]) -> list[_Occurrence]:
    """Dart ``_unsuppressed``: the occurrences ``triggerSuppresses`` leaves
    standing, in their order."""
    suppresses = vocabulary().trigger_suppresses
    suppressed: set[str] = set()
    for occurrence in occurrences:
        suppressed.update(suppresses.get(occurrence.key, ()))
    return [
        occurrence for occurrence in occurrences if occurrence.key not in suppressed
    ]


@dataclass(frozen=True, slots=True)
class _Window:
    """Dart ``_window``: up to ``count`` words either side of a match, and
    the offsets where that window starts and ends."""

    before: list[str]
    after: list[str]
    start: int
    end: int


def _window(haystack: str, start: int, end: int, count: int) -> _Window:
    """The words around ``haystack[start:end]``, read as ``_is_guarded``
    reads them. Offsets are code points throughout, which keeps every
    comparison Dart's UTF-16 offsets make (one string, order only)."""
    before: list[str] = []
    window_start = start
    before_text = haystack[:start].rstrip(_DART_WHITESPACE_CHARS)
    if before_text:
        before = before_text.split(" ")[-count:]
        window_start = len(before_text) - len(" ".join(before))
    after: list[str] = []
    window_end = end
    rest = haystack[end:]
    after_text = rest.lstrip(_DART_WHITESPACE_CHARS)
    if after_text:
        after = after_text.split(" ")[:count]
        window_end = end + len(rest) - len(after_text) + len(" ".join(after))
    return _Window(before, after, window_start, window_end)


def _hidden_carbs_in(
    haystack: str, *, modifiers: Sequence[_Occurrence], hebrew: bool
) -> tuple[HiddenCarb, ...]:
    """Dart ``_hiddenCarbsIn`` (issue #213 on the rules path, §9.4 rule 5a).

    Guards (per trigger, D-V1 window; guard phrases answering the flag's
    concern, ``hiddenCarbWindowWords`` either side) drop a trigger; of
    overlapping triggers the earliest, at one start the longest, is kept; a
    trigger a carb modifier overlaps, or a ``sugar`` one a covering
    sweetener sits in the window of, is covered; one flag per source; at
    most ``maxHiddenCarbsPerDish``, in text order.
    """
    vocab = vocabulary()
    count = vocab.caps.hidden_carb_window_words
    found: list[_HiddenOccurrence] = []
    for table, guards in (
        (_hidden_en(), vocab.hidden_carb_trigger_guards_en),
        (_hidden_he(), vocab.hidden_carb_trigger_guards_he),
    ):
        for entry in table:
            for hit in entry.pattern.finditer(haystack):
                if _is_guarded(haystack, hit.start(), hit.end(), guards.get(entry.key)):
                    continue
                window = _window(haystack, hit.start(), hit.end(), count)
                phrases = _hidden_guard_phrases(entry.flag.concern)
                if _window_contains_any_phrase(
                    window.before, phrases
                ) or _window_contains_any_phrase(window.after, phrases):
                    continue
                found.append(_HiddenOccurrence(hit.start(), hit.end(), entry.flag))
    found.sort(key=lambda occurrence: (occurrence.start, -occurrence.end))

    kept: list[_HiddenOccurrence] = []
    for occurrence in found:
        if not any(
            occurrence.start < other.end and other.start < occurrence.end
            for other in kept
        ):
            kept.append(occurrence)

    covering = _covering_modifiers()
    flags: list[HiddenCarb] = []
    sources: set[str] = set()
    for occurrence in kept:
        if len(flags) >= vocab.caps.max_hidden_carbs_per_dish:
            break
        flag = occurrence.flag
        window = _window(haystack, occurrence.start, occurrence.end, count)
        covered = any(
            (modifier.start < occurrence.end and occurrence.start < modifier.end)
            or (
                flag.concern == "sugar"
                and modifier.key in covering
                and modifier.start < window.end
                and window.start < modifier.end
            )
            for modifier in modifiers
        )
        if covered:
            continue
        source = flag.source_he if hebrew else flag.source_en
        if source in sources:
            continue
        sources.add(source)
        flags.append(
            HiddenCarb(
                source=source,
                certainty=cast(HiddenCarbCertainty, flag.certainty),
                waiter_question=flag.question_he if hebrew else flag.question_en,
            )
        )
    return tuple(flags)


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
        hidden_carbs=_hidden_carbs_in(
            haystack,
            modifiers=_unsuppressed(occurrences),
            hebrew=contains_hebrew(raw_text),
        ),
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

    A dish that is not red also carries its hidden-carb flags (issue #213),
    read from the same rules text and written in its language.
    """
    carb_only = carb_only_base(dish.name)
    if carb_only is not None and not describes_filling(dish):
        return RuleMatch(is_non_keto=True, base_label=carb_only)

    name = normalise(dish.name)
    base = _first_unguarded_base_match(dish_core_text(dish), name=name)
    if base is not None:
        return RuleMatch(is_non_keto=True, base_label=base[1])

    rules_text = dish_rules_text(dish)
    occurrences = _unguarded_modifier_occurrences(rules_text, name=name)
    sentences = _sentences_after_suppression(occurrences)
    hidden_carbs = _hidden_carbs_in(
        rules_text,
        modifiers=_unsuppressed(occurrences),
        hebrew=contains_hebrew(rules_text),
    )
    option_base = _first_unguarded_base_match(dish_option_rules_text(dish), name=name)
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
            hidden_carbs=hidden_carbs,
        )
    return RuleMatch(
        is_non_keto=False, instructions=tuple(sentences), hidden_carbs=hidden_carbs
    )


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
    # A topping named again is not a filling (issue #273): Dart's
    # ``replaceAll`` with each topping pattern, in order.
    for topping in _toppings():
        text = topping.pattern.sub(" ", text)
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


# --- the allergen pass (Banto; ALG-04b) ------------------------------------------

_MAQAF: Final = "־"
"""The Hebrew maqaf; the removal check reads it as a space, as the matcher
does."""

_CERTAINTY_RANK: Final[Mapping[str, int]] = {"stated": 0, "likely": 1, "suspected": 2}
"""Dart ``Certainty.index``: lower is surer."""


def _raw_slice(raw: str, start: int, end: int) -> str:
    """Dart ``_rawSlice``: the slice of ``raw`` that produced the UTF-16 span
    ``start``-``end`` of :func:`app.keto.allergens.match_text` of ``raw``.

    The match text of a prefix of ``raw`` is a prefix of the whole one and
    never shrinks as the prefix grows, so each end is a binary search for
    the shortest raw prefix (in code points, where Dart searches code units
    and steps back over a split surrogate pair) whose match text reaches it.
    """

    def shortest_prefix_reaching(length: int) -> int:
        low, high = 0, len(raw)
        while low < high:
            mid = (low + high) // 2
            if utf16_len(match_text(raw[:mid])) >= length:
                high = mid
            else:
                low = mid + 1
        return low

    raw_start = shortest_prefix_reaching(start + 1) - 1
    raw_end = shortest_prefix_reaching(end)
    if raw_start < 0 or raw_end <= raw_start:
        return utf16_slice(match_text(raw), start, end)
    return raw[raw_start:raw_end]


def _findings_in(
    raw: str, source: ConcernSource, hits: Sequence[AllergenHit]
) -> list[Concern]:
    """Dart ``_findingsIn``: one concern per allergen hit in ``hits``, read
    from ``raw``."""
    return [
        Concern(
            restriction_id=cast(RestrictionIdName, hit.id),
            source="hidden" if hit.hidden else source,
            certainty=cast(Certainty, hit.certainty),
            tier="inferred" if hit.hidden or hit.guarded else "stated",
            matched_text=_raw_slice(raw, hit.start, hit.end),
        )
        for hit in hits
    ]


MEAT_WITH_DAIRY_JOINER: Final = " + "
"""Dart ``meatWithDairyJoiner``: joins the meat and the dairy words of a
meat-with-dairy concern's matched text."""


@dataclass(frozen=True, slots=True)
class _SideHit:
    """Dart ``_SideHit``: one side of the meat-with-dairy rule."""

    hit: AllergenHit
    raw: str
    source: ConcernSource


def _surest(hits: Sequence[_SideHit]) -> _SideHit | None:
    """Dart ``_surest``: the surest hit, the earliest at a tie."""
    best: _SideHit | None = None
    for candidate in hits:
        if (
            best is None
            or _CERTAINTY_RANK[candidate.hit.certainty]
            < _CERTAINTY_RANK[best.hit.certainty]
        ):
            best = candidate
    return best


def _overlaps(a: AllergenHit, b: AllergenHit) -> bool:
    return a.start < b.end and b.start < a.end


def _meat_with_dairy(
    meat: Sequence[_SideHit], dairy: Sequence[_SideHit]
) -> Concern | None:
    """Dart ``_meatWithDairy``: kosher's meat-with-dairy concern (#342)."""
    meat_in_dish = _surest([side for side in meat if side.source != "option"])
    dairy_in_dish = _surest([side for side in dairy if side.source != "option"])
    meat_side = meat_in_dish or _surest(meat)
    dairy_side = dairy_in_dish or _surest(dairy)
    if meat_side is None or dairy_side is None:
        return None
    in_option = meat_in_dish is None or dairy_in_dish is None
    stated = (
        not in_option
        and meat_side.hit.certainty == "stated"
        and dairy_side.hit.certainty == "stated"
    )
    source: ConcernSource
    if in_option:
        source = "option"
    elif dairy_side.hit.hidden:
        source = "hidden"
    else:
        source = dairy_side.source
    return Concern(
        restriction_id="kosher",
        source=source,
        certainty="stated" if stated else "suspected",
        tier="stated" if stated else "inferred",
        matched_text=(
            _raw_slice(meat_side.raw, meat_side.hit.start, meat_side.hit.end)
            + MEAT_WITH_DAIRY_JOINER
            + _raw_slice(dairy_side.raw, dairy_side.hit.start, dairy_side.hit.end)
        ),
    )


def allergen_findings(dish: Dish) -> list[Concern]:
    """``ClassificationRules.allergenFindings``: one concern per allergen hit
    in the dish's name, then description, then each non-removal option value
    (a maqaf read as a space for the removal check), each part matched on
    its own; option group names are not read. Then at most one kosher
    meat-with-dairy concern (#342): an unguarded meat word and an unguarded
    stated or likely Milk word that do not overlap."""
    parts: list[tuple[str, ConcernSource]] = [
        (dish.name, "name"),
        (dish.description, "description"),
    ]
    for option in dish.options:
        for value in option.values:
            if is_removal_option_value(value.replace(_MAQAF, " ")):
                continue
            parts.append((value, "option"))
    findings: list[Concern] = []
    meat: list[_SideHit] = []
    dairy: list[_SideHit] = []
    meat_vocabulary = allergens().meat_with_dairy
    for raw, source in parts:
        hits = find(raw)
        findings.extend(_findings_in(raw, source, hits))
        meat_hits = find_with(raw, meat_vocabulary)
        meat.extend(_SideHit(hit, raw, source) for hit in meat_hits if not hit.guarded)
        dairy.extend(
            _SideHit(hit, raw, source)
            for hit in hits
            if hit.id == "milk"
            and not hit.guarded
            and hit.certainty != "suspected"
            and not any(_overlaps(hit, other) for other in meat_hits)
        )
    combined = _meat_with_dairy(meat, dairy)
    if combined is not None:
        findings.append(combined)
    return findings


def allergen_concerns(dish: Dish) -> list[Concern]:
    """``ClassificationRules.allergenConcerns``: :func:`allergen_findings`
    reduced to one concern per restriction, in taxonomy order, keeping the
    surest finding (stated > likely > suspected), the earliest at a tie."""
    best: dict[str, Concern] = {}
    for finding in allergen_findings(dish):
        kept = best.get(finding.restriction_id)
        if (
            kept is None
            or _CERTAINTY_RANK[finding.certainty] < _CERTAINTY_RANK[kept.certainty]
        ):
            best[finding.restriction_id] = finding
    order = {
        restriction.id: index for index, restriction in enumerate(allergens().taxonomy)
    }
    return [best[rid] for rid in sorted(best, key=order.__getitem__)]

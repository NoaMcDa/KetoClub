"""The restriction taxonomy, the allergen vocabulary and the allergen matcher
(Banto; ALG-01, issue #343; architecture.md D26).

The Python twin of ``lib/models/restriction.dart`` and
``lib/utils/allergens/``. ``allergens.json`` beside this module is a
byte-for-byte copy of the golden ``tests/fixtures/golden/allergens.json``,
which ``tool/golden/golden_export.dart`` writes from the Dart taxonomy and
vocabulary registry; a test asserts the two files are identical.

:func:`allergens` parses the file once (cached) into frozen dataclasses.
:func:`find` and :func:`find_in_dish` run every restriction's vocabulary over
a text or a dish exactly as the Dart ``AllergenMatcher`` does, and report
every trigger for every restriction, whatever anyone's profile (C1). There
are no severity levels: a restriction is strict when its kind is
``allergen`` or ``autoimmune`` (:attr:`Restriction.is_strict`).

Behaviour the port keeps from Dart:

* **Compilation.** Each term is normalised once
  (:func:`app.keto.normaliser.normalise`); a term that normalises to nothing
  is skipped. English terms compile with :func:`latin_trigger_pattern`
  (``re.ASCII`` word boundary), Hebrew ones with
  :func:`hebrew_trigger_pattern`, with no permissive prefix when the term,
  as written, is in ``noPrefixHe``.
* **Maqaf (ALG-04a).** The Hebrew maqaf U+05BE becomes a space before the
  text is normalised (:func:`match_text`, :func:`dish_match_text`): the
  normaliser deletes it as a Hebrew point, which glues "חמאת־בוטנים" into
  one word. Length-preserving; the keto normaliser is untouched.
* **Guards (ALG-04a).** A guard lowers, never cancels: a guarded trigger is
  reported as ``suspected`` with ``guarded`` set. English guards apply to
  English triggers and Hebrew guards to Hebrew ones; a trigger's guards are
  its restriction's plus its own ``termGuards``. A guard counts only in the
  slot adjacent to the match (:func:`_is_adjacent_guarded`), never in the
  keto engine's two-word window (:func:`app.keto.rules.is_guarded`, which
  this module no longer calls). A Hebrew guard's first word may carry one or
  two prefix letters ``בהוכלמש`` before the trigger, and only ``ה`` after
  it.
* **Order.** Hits sort by start, then the restriction's taxonomy position,
  then the order they were found in (direct English, direct Hebrew, hidden
  English, hidden Hebrew, each as listed; a trigger's matches left to right).
* **Offsets.** :class:`AllergenHit` offsets are Dart's: UTF-16 code units of
  the normalised text. Python matches in code points, so each offset is
  converted with :func:`app.keto.dart_text.utf16_len`; the sort runs on code
  points first, which orders the same way.
"""

import json
import re
from collections.abc import Mapping, Sequence
from dataclasses import dataclass, field
from functools import cache
from pathlib import Path
from types import MappingProxyType
from typing import Any, Final

from app.keto.dart_text import utf16_len
from app.keto.models import Dish
from app.keto.normaliser import dish_rules_text, normalise
from app.keto.patterns import hebrew_trigger_pattern, latin_trigger_pattern

ALLERGENS_PATH: Final = Path(__file__).with_name("allergens.json")
"""The packaged copy of the golden ``allergens.json``."""


# --- typed readers --------------------------------------------------------------


def _obj(value: Any, where: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ValueError(f"{where}: expected an object")
    return value


def _list(value: Any, where: str) -> list[Any]:
    if not isinstance(value, list):
        raise ValueError(f"{where}: expected a list")
    return value


def _str(value: Any, where: str) -> str:
    if not isinstance(value, str):
        raise ValueError(f"{where}: expected a string")
    return value


def _bool(value: Any, where: str) -> bool:
    if not isinstance(value, bool):
        raise ValueError(f"{where}: expected a boolean")
    return value


def _strs(value: Any, where: str) -> tuple[str, ...]:
    return tuple(_str(item, f"{where}[]") for item in _list(value, where))


# --- the model ------------------------------------------------------------------


@dataclass(frozen=True, slots=True)
class Restriction:
    """Dart ``Restriction``: one taxonomy entry. ``jurisdictions`` is in the
    Dart ``Jurisdiction`` order; ``is_strict`` is derived from ``kind`` in
    Dart and checked against it here."""

    id: str
    kind: str
    is_strict: bool
    jurisdictions: tuple[str, ...]
    name_en: str
    name_he: str
    source: str


@dataclass(frozen=True, slots=True)
class HiddenTrigger:
    """Dart ``HiddenTrigger``: a hidden-source term with its own certainty."""

    term: str
    certainty: str
    source: str


@dataclass(frozen=True, slots=True)
class AllergenGuards:
    """Dart ``AllergenGuards``: phrases that lower a trigger from the words
    just before or just after it, per language."""

    before_en: tuple[str, ...] = ()
    after_en: tuple[str, ...] = ()
    before_he: tuple[str, ...] = ()
    after_he: tuple[str, ...] = ()


@dataclass(frozen=True, slots=True)
class RestrictionVocabulary:
    """Dart ``RestrictionVocabulary``: one restriction's triggers."""

    direct_en: tuple[str, ...] = ()
    direct_he: tuple[str, ...] = ()
    hidden_en: tuple[HiddenTrigger, ...] = ()
    hidden_he: tuple[HiddenTrigger, ...] = ()
    guards: AllergenGuards = AllergenGuards()
    term_guards: Mapping[str, AllergenGuards] = field(
        default_factory=lambda: MappingProxyType({})
    )
    no_prefix_he: tuple[str, ...] = ()
    sources: tuple[str, ...] = ()


@dataclass(frozen=True, slots=True)
class Allergens:
    """Every value in ``allergens.json`` the matcher needs, typed."""

    taxonomy: tuple[Restriction, ...]
    strict_kinds: frozenset[str]
    jurisdictions: tuple[str, ...]
    certainties: tuple[str, ...]
    vocabulary: Mapping[str, RestrictionVocabulary]


@dataclass(frozen=True, slots=True)
class AllergenHit:
    """Dart ``AllergenHit``. ``start``/``end`` are UTF-16 code units of the
    text the matcher read (:func:`match_text` or :func:`dish_match_text`);
    ``end`` is exclusive. ``guarded`` hits are always ``suspected``.
    ``hidden`` is set when the trigger came from a hidden list (ALG-04b); it
    is not in ``allergens.json``, and ``allergen_concerns.json`` pins it."""

    id: str
    term: str
    certainty: str
    start: int
    end: int
    guarded: bool = False
    hidden: bool = False


# --- parsing --------------------------------------------------------------------


def _terms(value: Any, where: str) -> tuple[str, ...]:
    return tuple(
        _str(_obj(item, where)["term"], f"{where}.term") for item in _list(value, where)
    )


def _hidden(value: Any, where: str) -> tuple[HiddenTrigger, ...]:
    triggers: list[HiddenTrigger] = []
    for item in _list(value, where):
        entry = _obj(item, where)
        triggers.append(
            HiddenTrigger(
                term=_str(entry["term"], f"{where}.term"),
                certainty=_str(entry["certainty"], f"{where}.certainty"),
                source=_str(entry["source"], f"{where}.source"),
            )
        )
    return tuple(triggers)


def _guards(value: Any, where: str) -> AllergenGuards:
    guards = _obj(value, where)
    return AllergenGuards(
        before_en=_strs(guards["beforeEn"], f"{where}.beforeEn"),
        after_en=_strs(guards["afterEn"], f"{where}.afterEn"),
        before_he=_strs(guards["beforeHe"], f"{where}.beforeHe"),
        after_he=_strs(guards["afterHe"], f"{where}.afterHe"),
    )


def parse_restriction_vocabularies(raw: Any) -> Mapping[str, RestrictionVocabulary]:
    """A registry as the exporter writes one, ``{id: entry}``, typed."""
    registry: dict[str, RestrictionVocabulary] = {}
    for key, value in _obj(raw, "vocabulary").items():
        entry = _obj(value, key)
        term_guards = _obj(entry["termGuards"], f"{key}.termGuards")
        registry[key] = RestrictionVocabulary(
            direct_en=_terms(entry["directEn"], f"{key}.directEn"),
            direct_he=_terms(entry["directHe"], f"{key}.directHe"),
            hidden_en=_hidden(entry["hiddenEn"], f"{key}.hiddenEn"),
            hidden_he=_hidden(entry["hiddenHe"], f"{key}.hiddenHe"),
            guards=_guards(entry["guards"], f"{key}.guards"),
            term_guards=MappingProxyType(
                {
                    term: _guards(guards, f"{key}.termGuards.{term}")
                    for term, guards in term_guards.items()
                }
            ),
            no_prefix_he=_strs(entry["noPrefixHe"], f"{key}.noPrefixHe"),
            sources=_strs(entry["sources"], f"{key}.sources"),
        )
    return MappingProxyType(registry)


def parse_allergens(raw: Any) -> Allergens:
    """The :class:`Allergens` in ``raw``, the decoded ``allergens.json``.

    Raises ``ValueError`` (or ``KeyError``) when a key is missing, has the
    wrong type, or a taxonomy entry's strictness disagrees with its kind: the
    file is checked in, so that is a build error.
    """
    root = _obj(raw, "allergens")
    strict_kinds = frozenset(
        _str(kind["name"], "kinds.name")
        for kind in (_obj(item, "kinds") for item in _list(root["kinds"], "kinds"))
        if _bool(kind["isStrict"], "kinds.isStrict")
    )
    taxonomy: list[Restriction] = []
    for item in _list(root["taxonomy"], "taxonomy"):
        entry = _obj(item, "taxonomy")
        restriction = Restriction(
            id=_str(entry["id"], "taxonomy.id"),
            kind=_str(entry["kind"], "taxonomy.kind"),
            is_strict=_bool(entry["isStrict"], "taxonomy.isStrict"),
            jurisdictions=_strs(entry["jurisdictions"], "taxonomy.jurisdictions"),
            name_en=_str(entry["nameEn"], "taxonomy.nameEn"),
            name_he=_str(entry["nameHe"], "taxonomy.nameHe"),
            source=_str(entry["source"], "taxonomy.source"),
        )
        if restriction.is_strict != (restriction.kind in strict_kinds):
            raise ValueError(f"taxonomy.{restriction.id}: strictness is not its kind's")
        taxonomy.append(restriction)
    return Allergens(
        taxonomy=tuple(taxonomy),
        strict_kinds=strict_kinds,
        jurisdictions=_strs(root["jurisdictions"], "jurisdictions"),
        certainties=_strs(root["certainties"], "certainties"),
        vocabulary=parse_restriction_vocabularies(root["vocabulary"]),
    )


@cache
def allergens() -> Allergens:
    """The packaged taxonomy and vocabulary, parsed once and shared."""
    return parse_allergens(json.loads(ALLERGENS_PATH.read_text(encoding="utf-8")))


# --- the matcher ---------------------------------------------------------------

_Phrase = tuple[str, ...]
"""One guard phrase, normalised and split into its words."""


@dataclass(frozen=True, slots=True)
class _CompiledTrigger:
    term: str
    pattern: re.Pattern[str]
    certainty: str
    before: tuple[_Phrase, ...]
    after: tuple[_Phrase, ...]
    hebrew: bool
    hidden: bool = False


@dataclass(frozen=True, slots=True)
class _CompiledRestriction:
    id: str
    order: int
    triggers: tuple[_CompiledTrigger, ...]


def _phrases(phrases: Sequence[str]) -> tuple[_Phrase, ...]:
    """``phrases`` normalised and split; one that normalises to nothing is
    dropped."""
    return tuple(
        tuple(normalised.split(" "))
        for normalised in (match_text(phrase) for phrase in phrases)
        if normalised
    )


def _compile_trigger(
    term: str,
    certainty: str,
    entry: RestrictionVocabulary,
    *,
    hebrew: bool,
    no_prefix: frozenset[str],
    hidden: bool = False,
) -> _CompiledTrigger | None:
    """``term`` compiled with its guards (the restriction's, then the
    term's own), or None when it normalises to nothing."""
    normalised = match_text(term)
    if not normalised:
        return None
    pattern = (
        hebrew_trigger_pattern(normalised, allow_prefix=term not in no_prefix)
        if hebrew
        else latin_trigger_pattern(normalised)
    )
    own = entry.term_guards.get(term, AllergenGuards())
    glob = entry.guards
    if hebrew:
        before = _phrases((*glob.before_he, *own.before_he))
        after = _phrases((*glob.after_he, *own.after_he))
    else:
        before = _phrases((*glob.before_en, *own.before_en))
        after = _phrases((*glob.after_en, *own.after_en))
    return _CompiledTrigger(term, pattern, certainty, before, after, hebrew, hidden)


def _compile(
    vocabulary: Mapping[str, RestrictionVocabulary],
) -> tuple[_CompiledRestriction, ...]:
    compiled: list[_CompiledRestriction] = []
    for order, restriction in enumerate(allergens().taxonomy):
        entry = vocabulary.get(restriction.id)
        if entry is None:
            continue
        no_prefix = frozenset(entry.no_prefix_he)
        candidates = (
            *(
                _compile_trigger(t, "stated", entry, hebrew=False, no_prefix=no_prefix)
                for t in entry.direct_en
            ),
            *(
                _compile_trigger(t, "stated", entry, hebrew=True, no_prefix=no_prefix)
                for t in entry.direct_he
            ),
            *(
                _compile_trigger(
                    t.term,
                    t.certainty,
                    entry,
                    hebrew=False,
                    no_prefix=no_prefix,
                    hidden=True,
                )
                for t in entry.hidden_en
            ),
            *(
                _compile_trigger(
                    t.term,
                    t.certainty,
                    entry,
                    hebrew=True,
                    no_prefix=no_prefix,
                    hidden=True,
                )
                for t in entry.hidden_he
            ),
        )
        compiled.append(
            _CompiledRestriction(
                id=restriction.id,
                order=order,
                triggers=tuple(t for t in candidates if t is not None),
            )
        )
    return tuple(compiled)


_COMPILED: dict[
    int, tuple[Mapping[str, RestrictionVocabulary], tuple[_CompiledRestriction, ...]]
] = {}
"""Dart ``_compiledCache``: every vocabulary compiled so far, keyed on the
mapping's identity (the mapping is kept alive beside its compiled form, so
an id is never reused while it is cached)."""


def _compiled(
    vocabulary: Mapping[str, RestrictionVocabulary],
) -> tuple[_CompiledRestriction, ...]:
    """``vocabulary`` compiled once per mapping instance."""
    entry = _COMPILED.get(id(vocabulary))
    if entry is not None and entry[0] is vocabulary:
        return entry[1]
    compiled = _compile(vocabulary)
    _COMPILED[id(vocabulary)] = (vocabulary, compiled)
    return compiled


def _registry() -> tuple[_CompiledRestriction, ...]:
    return _compiled(allergens().vocabulary)


_HEBREW_BEFORE_PREFIX: Final = re.compile(r"[בהוכלמש]{1,2}")
"""Dart ``_hebrewBeforePrefix``: one or two grammatical prefix letters a
Hebrew guard's first word may carry before its trigger (``fullmatch``)."""

_HEBREW_AFTER_PREFIX: Final = re.compile(r"ה")
"""Dart ``_hebrewAfterPrefix``: only the article ה after a trigger."""


def _is_phrase(
    words: Sequence[str], phrase: _Phrase, prefix: re.Pattern[str] | None
) -> bool:
    """Dart ``_isPhrase``: ``words`` is ``phrase`` word for word, the first
    word allowed a prefix that ``prefix`` fully matches."""
    for index, guard in enumerate(phrase):
        word = words[index]
        if word == guard:
            continue
        if index > 0 or prefix is None or not word.endswith(guard):
            return False
        if prefix.fullmatch(word[: len(word) - len(guard)]) is None:
            return False
    return True


def _is_adjacent_guarded(
    haystack: str, start: int, end: int, trigger: _CompiledTrigger
) -> bool:
    """Dart ``_isAdjacentGuarded``: a ``before`` phrase ends on the word just
    before ``start``, or an ``after`` phrase starts on the word just after
    ``end`` (code-point offsets). The haystack is normalised, so its only
    whitespace is single ASCII spaces."""
    if trigger.before:
        before_text = haystack[:start].rstrip(" ")
        if before_text:
            words = before_text.split(" ")
            prefix = _HEBREW_BEFORE_PREFIX if trigger.hebrew else None
            for phrase in trigger.before:
                if len(phrase) <= len(words) and _is_phrase(
                    words[len(words) - len(phrase) :], phrase, prefix
                ):
                    return True
    if trigger.after:
        after_text = haystack[end:].lstrip(" ")
        if after_text:
            words = after_text.split(" ")
            prefix = _HEBREW_AFTER_PREFIX if trigger.hebrew else None
            for phrase in trigger.after:
                if len(phrase) <= len(words) and _is_phrase(
                    words[: len(phrase)], phrase, prefix
                ):
                    return True
    return False


def _find_in(
    haystack: str, compiled: Sequence[_CompiledRestriction]
) -> list[AllergenHit]:
    if not haystack:
        return []
    found: list[tuple[int, int, int, str, str, str, int, bool, bool]] = []
    for restriction in compiled:
        for trigger in restriction.triggers:
            for match in trigger.pattern.finditer(haystack):
                guarded = _is_adjacent_guarded(
                    haystack, match.start(), match.end(), trigger
                )
                found.append(
                    (
                        match.start(),
                        restriction.order,
                        len(found),
                        restriction.id,
                        trigger.term,
                        "suspected" if guarded else trigger.certainty,
                        match.end(),
                        guarded,
                        trigger.hidden,
                    )
                )
    found.sort(key=lambda item: (item[0], item[1], item[2]))
    return [
        AllergenHit(
            id=hit_id,
            term=term,
            certainty=certainty,
            start=utf16_len(haystack[:start]),
            end=utf16_len(haystack[:end]),
            guarded=guarded,
            hidden=hidden,
        )
        for start, _, _, hit_id, term, certainty, end, guarded, hidden in found
    ]


_MAQAF: Final = "\u05be"
"""The Hebrew maqaf, a hyphen that joins two words."""


def _space_maqaf(raw: str) -> str:
    return raw.replace(_MAQAF, " ")


def _space_maqaf_in_dish(dish: Dish) -> Dish:
    """``dish`` with every maqaf in its name, description, option names and
    option values a space (not validated again: the shape is unchanged)."""
    return dish.model_copy(
        update={
            "name": _space_maqaf(dish.name),
            "description": _space_maqaf(dish.description),
            "options": [
                option.model_copy(
                    update={
                        "name": _space_maqaf(option.name),
                        "values": [_space_maqaf(value) for value in option.values],
                    }
                )
                for option in dish.options
            ],
        }
    )


def match_text(raw_text: str) -> str:
    """``AllergenMatcher.matchText``: ``raw_text`` with every maqaf a space,
    normalised; what :func:`find` reads and its offsets index."""
    return normalise(_space_maqaf(raw_text))


def dish_match_text(dish: Dish) -> str:
    """``AllergenMatcher.dishMatchText``: :func:`dish_rules_text` of ``dish``
    with every maqaf a space; what :func:`find_in_dish` reads."""
    return dish_rules_text(_space_maqaf_in_dish(dish))


def find_with(
    raw_text: str, vocabulary: Mapping[str, RestrictionVocabulary]
) -> list[AllergenHit]:
    """``AllergenMatcher.findWith``: :func:`find` over ``vocabulary``."""
    return _find_in(match_text(raw_text), _compiled(vocabulary))


def find_in_dish_with(
    dish: Dish, vocabulary: Mapping[str, RestrictionVocabulary]
) -> list[AllergenHit]:
    """``AllergenMatcher.findInDishWith``: :func:`find_in_dish` over
    ``vocabulary``."""
    return _find_in(dish_match_text(dish), _compiled(vocabulary))


def find(raw_text: str) -> list[AllergenHit]:
    """``AllergenMatcher.find``: every trigger in ``raw_text``, both
    languages, for every restriction, a guarded one lowered. Offsets index
    :func:`match_text`."""
    return _find_in(match_text(raw_text), _registry())


def find_in_dish(dish: Dish) -> list[AllergenHit]:
    """``AllergenMatcher.findInDish``: every trigger in the dish's name,
    description, option names and non-removal option values. Offsets index
    :func:`dish_match_text`."""
    return _find_in(dish_match_text(dish), _registry())

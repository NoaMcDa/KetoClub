"""Platform and restaurant declarations as evidence (Banto; ALG-09, #351;
architecture.md D26).

The Python twin of ``lib/utils/allergens/declarations.dart``, whose doc
comment holds the rules. A declaration is what the platform or the
restaurant says about a dish: a declared tag (Wolt ``dietary_preferences``,
10bis ``kosher``) or free text such as "טבעוני", "ללא גלוטן", "gluten-free"
or 🌱 in the dish's name, description or category heading.
:func:`declarations_of` reads them all; the device's profile evaluator
lowers the matching concerns (never below ``suspected`` for a strict entry).
Nothing on the server consults it yet (D26 C1 keeps the profile on the
device); the port exists so the golden pins the table on both sides.

The rules, guards and kosher tags below are byte-for-byte Dart's; the golden
``declarations.json`` carries them and a test asserts they are equal.

Behaviour the port keeps from Dart:

* **Compilation.** Each term is normalised once; English terms compile with
  :func:`latin_trigger_pattern`, Hebrew ones with
  :func:`hebrew_trigger_pattern` (permissive prefix); a guard cancels a match
  through :func:`app.keto.rules.is_guarded`'s two-word window.
* **Symbols** (🌱, 🌾) are matched on the raw text, which normalisation
  would strip.
* **Order.** Tags first (one declaration per rule, the first tag that makes
  it, with the tag as the matched text), then the dish's name and
  description, then the heading; within each, rule order.
"""

import re
from collections.abc import Sequence
from dataclasses import dataclass
from enum import StrEnum
from functools import cache
from typing import Any, Final

from app.keto.models import Dish
from app.keto.normaliser import normalise
from app.keto.patterns import hebrew_trigger_pattern, latin_trigger_pattern
from app.keto.rules import is_guarded
from app.keto.vocabulary import GuardWords

KOSHER_DECLARED_TAG: Final = "kosher"
"""The declared tag a 10bis dish flagged ``kosher: true`` carries."""

KOSHER_TAGS: Final = ("kosher", "כשר")
"""The normalised declared tags that mean "kosher"."""


class DeclarationPolarity(StrEnum):
    """Dart ``DeclarationPolarity``; the value is the Dart enum ``name``."""

    ABSENT = "absent"
    PRESENT = "present"


class DeclarationSource(StrEnum):
    """Dart ``DeclarationSource``; the value is the Dart enum ``name``."""

    PLATFORM_TAG = "platformTag"
    DISH_TEXT = "dishText"
    HEADING = "heading"


@dataclass(frozen=True, slots=True)
class DeclarationRule:
    """Dart ``DeclarationRule``: ``restrictions`` holds ``RestrictionId``
    names in taxonomy order."""

    id: str
    en: tuple[str, ...]
    he: tuple[str, ...]
    restrictions: tuple[str, ...]
    symbols: tuple[str, ...] = ()
    polarity: DeclarationPolarity = DeclarationPolarity.ABSENT

    def to_json(self) -> dict[str, Any]:
        """The rule as the golden corpus writes it."""
        return {
            "id": self.id,
            "en": list(self.en),
            "he": list(self.he),
            "symbols": list(self.symbols),
            "restrictions": list(self.restrictions),
            "polarity": self.polarity.value,
        }


@dataclass(frozen=True, slots=True)
class Declaration:
    """Dart ``Declaration``."""

    rule: str
    restriction_ids: tuple[str, ...]
    polarity: DeclarationPolarity
    source: DeclarationSource
    matched_text: str

    def to_json(self) -> dict[str, Any]:
        """Dart ``Declaration.toJson``."""
        return {
            "rule": self.rule,
            "restrictionIds": list(self.restriction_ids),
            "polarity": self.polarity.value,
            "source": self.source.value,
            "matchedText": self.matched_text,
        }


# --- the table (Dart's, verbatim) --------------------------------------------------

DECLARATION_RULES: Final = (
    DeclarationRule(
        id="vegan",
        en=("vegan", "plant based"),
        he=("טבעוני", "טבעונית", "טבעוניים", "טבעוניות"),
        symbols=("🌱",),
        restrictions=(
            "milk",
            "lactose",
            "eggs",
            "fish",
            "crustaceans",
            "molluscs",
            "vegan",
            "vegetarian",
        ),
    ),
    DeclarationRule(
        id="vegetarian",
        en=("vegetarian",),
        he=("צמחוני", "צמחונית", "צמחוניים", "צמחוניות"),
        restrictions=("fish", "crustaceans", "molluscs", "vegetarian"),
    ),
    DeclarationRule(
        id="glutenFree",
        en=("gluten free", "without gluten", "gf"),
        he=(
            "ללא גלוטן",
            "נטול גלוטן",
            "נטולת גלוטן",
            "נטולי גלוטן",
            "נטולות גלוטן",
            "בלי גלוטן",
        ),
        symbols=("🌾",),
        restrictions=("gluten",),
    ),
    DeclarationRule(
        id="dairyFree",
        en=("dairy free", "milk free", "without dairy"),
        he=(
            "ללא חלב",
            "ללא מוצרי חלב",
            "נטול חלב",
            "נטולת חלב",
            "נטול מוצרי חלב",
            "בלי חלב",
        ),
        restrictions=("milk", "lactose"),
    ),
    DeclarationRule(
        id="lactoseFree",
        en=("lactose free",),
        he=("ללא לקטוז", "נטול לקטוז", "נטולת לקטוז"),
        restrictions=("lactose",),
    ),
    DeclarationRule(
        id="eggFree",
        en=("egg free", "eggless", "without eggs"),
        he=("ללא ביצים", "ללא ביצה", "נטול ביצים", "בלי ביצים"),
        restrictions=("eggs",),
    ),
)

DECLARATION_GUARDS_EN: Final = GuardWords(
    before=("not", "non", "no", "can", "made", "optional", "ask"),
    after=(
        "option",
        "options",
        "optional",
        "available",
        "on request",
        "upon request",
        "version",
        "alternative",
        "substitute",
    ),
)
DECLARATION_GUARDS_HE: Final = GuardWords(
    before=("לא", "ניתן", "אפשר", "אפשרות", "באפשרות", "יש", "לבקש"),
    after=(
        "לפי בקשה",
        "בהזמנה",
        "בתוספת",
        "באפשרות",
        "בתיאום",
        "לבקשה",
        "אופציה",
    ),
)


@dataclass(frozen=True, slots=True)
class _Term:
    term: str
    pattern: re.Pattern[str]
    hebrew: bool


@cache
def _compiled() -> tuple[tuple[DeclarationRule, tuple[_Term, ...]], ...]:
    return tuple(
        (
            rule,
            tuple(
                _Term(term, latin_trigger_pattern(normalise(term)), False)
                for term in rule.en
            )
            + tuple(
                _Term(term, hebrew_trigger_pattern(normalise(term)), True)
                for term in rule.he
            ),
        )
        for rule in DECLARATION_RULES
    )


def declarations_of(dish: Dish, *, heading: str | None = None) -> list[Declaration]:
    """Dart ``Declarations.of``: the dish's tags, its name and description,
    then ``heading``."""
    found = declarations_of_tags(dish.declared_tags)
    found += declarations_in_text(
        f"{dish.name} {dish.description}", DeclarationSource.DISH_TEXT
    )
    if heading is not None:
        found += declarations_in_text(heading, DeclarationSource.HEADING)
    return found


def declarations_of_tags(tags: Sequence[str]) -> list[Declaration]:
    """Dart ``Declarations.ofTags``: each tag through the text table, one
    declaration per rule, the tag itself as the matched text."""
    found: list[Declaration] = []
    for tag in tags:
        for declaration in declarations_in_text(tag, DeclarationSource.PLATFORM_TAG):
            if any(kept.rule == declaration.rule for kept in found):
                continue
            found.append(
                Declaration(
                    rule=declaration.rule,
                    restriction_ids=declaration.restriction_ids,
                    polarity=declaration.polarity,
                    source=DeclarationSource.PLATFORM_TAG,
                    matched_text=tag,
                )
            )
    return found


def declarations_in_text(raw: str, source: DeclarationSource) -> list[Declaration]:
    """Dart ``Declarations.inText``: per rule, its first unguarded English
    then Hebrew term, else its first symbol the raw text holds."""
    haystack = normalise(raw)
    found: list[Declaration] = []
    for rule, terms in _compiled():
        matched = _first_term(haystack, terms)
        if matched is None:
            matched = next((s for s in rule.symbols if s in raw), None)
        if matched is None:
            continue
        found.append(
            Declaration(
                rule=rule.id,
                restriction_ids=rule.restrictions,
                polarity=rule.polarity,
                source=source,
                matched_text=matched,
            )
        )
    return found


def declares_kosher(dish: Dish) -> bool:
    """Dart ``Declarations.declaresKosher``."""
    return any(normalise(tag) in KOSHER_TAGS for tag in dish.declared_tags)


def _first_term(haystack: str, terms: tuple[_Term, ...]) -> str | None:
    for term in terms:
        guards = DECLARATION_GUARDS_HE if term.hebrew else DECLARATION_GUARDS_EN
        for found in term.pattern.finditer(haystack):
            if not is_guarded(haystack, found.start(), found.end(), guards):
                return term.term
    return None

"""Kitchen cross-contact signals (Banto; ALG-07, issue #349; architecture.md D26).

The Python twin of ``lib/utils/allergens/kitchen_signals.dart``. A pure,
rules-only pass over a whole menu: :func:`kitchen_signals` reports what the
menu reveals about its kitchen (a fryer, a wok, a grill that cooks meat and
fish, flour, nuts, sesame) as :class:`KitchenSignal` values, each with the
restrictions it threatens, up to three dish names as evidence and one
bilingual question for the staff. A signal never changes a verdict and its
questions never reassure.

The term lists, guards, threat table and questions below are byte-for-byte
Dart's; the golden ``kitchen_signals.json`` carries them under
``vocabulary`` and a test asserts they are equal. The nuts, sesame and
seafood facts come from the allergen matcher (:mod:`app.keto.allergens`),
never from a list here.

Behaviour the port keeps from Dart:

* **Compilation.** Each term is normalised once; English terms compile with
  :func:`latin_trigger_pattern`, Hebrew ones with
  :func:`hebrew_trigger_pattern` with the permissive prefix except for the
  words in :data:`NO_PREFIX_HE`; a guard cancels a match through
  :func:`app.keto.rules.is_guarded`.
* **What is read.** A dish's rules text (:func:`app.keto.normaliser
  .dish_rules_text`) and its category heading, separately: a dish shows a
  kind when its own text or its heading does.
* **Order.** Signals come in :class:`KitchenSignalKind` order; evidence is
  distinct dish names, first occurrence kept, in menu order, at most
  :data:`EVIDENCE_CAP`.
"""

import re
from collections.abc import Callable, Iterable, Mapping, Sequence
from dataclasses import dataclass
from enum import StrEnum
from functools import cache
from typing import Any, Final

from app.keto.allergens import (
    AllergenHit,
    RestrictionVocabulary,
    find,
    find_in_dish,
    find_in_dish_with,
    find_with,
)
from app.keto.models import Dish, Menu
from app.keto.normaliser import dish_rules_text, normalise
from app.keto.patterns import hebrew_trigger_pattern, latin_trigger_pattern
from app.keto.rules import is_guarded
from app.keto.vocabulary import GuardWords


class KitchenSignalKind(StrEnum):
    """Dart ``KitchenSignalKind``; the value is the Dart enum ``name``. The
    declaration order is the order :func:`kitchen_signals` reports in."""

    FRYER = "fryer"
    WOK = "wok"
    SHARED_GRILL = "sharedGrill"
    BAKERY = "bakery"
    NUTS = "nuts"
    SESAME = "sesame"


EVIDENCE_CAP: Final = 3
"""The most dish names a :class:`KitchenSignal` carries as evidence."""


@dataclass(frozen=True, slots=True)
class KitchenSignal:
    """Dart ``KitchenSignal``: ``threatens`` holds ``RestrictionId`` names in
    taxonomy order; ``evidence`` is up to :data:`EVIDENCE_CAP` dish names."""

    kind: KitchenSignalKind
    threatens: tuple[str, ...]
    evidence: tuple[str, ...]
    question_en: str
    question_he: str

    def to_json(self) -> dict[str, Any]:
        """The signal as the golden corpus writes it."""
        return {
            "kind": self.kind.value,
            "threatens": list(self.threatens),
            "evidence": list(self.evidence),
            "questionEn": self.question_en,
            "questionHe": self.question_he,
        }


# --- the term lists (Dart's, verbatim) ------------------------------------------

FRIED_EN: Final = (
    "fried",
    "fries",
    "chips",
    "schnitzel",
    "tempura",
    "battered",
    "breaded",
    "crumbed",
    "fritters",
    "falafel",
    "onion rings",
    "nuggets",
    "katsu",
    "chicken tenders",
)
FRIED_HE: Final = (
    "מטוגן",
    "מטוגנת",
    "מטוגנים",
    "מטוגנות",
    "צ'יפס",
    "שניצל",
    "שניצלים",
    "טמפורה",
    "פלאפל",
    "בציפוי",
    "בבלילה",
    "נאגטס",
    "טבעות בצל",
)
FRIED_GUARDS_EN: Final = {
    "fried": GuardWords(before=("stir", "pan", "air"), after=("rice",)),
    "chips": GuardWords(before=("chocolate", "choc"), after=()),
}
FRIED_GUARDS_HE: Final = {
    "מטוגן": GuardWords(before=("אורז",), after=()),
}
WOK_EN: Final = (
    "wok",
    "stir fry",
    "stir fried",
    "pad thai",
    "pad see ew",
    "chow mein",
    "lo mein",
    "kung pao",
    "yakisoba",
    "fried rice",
)
WOK_HE: Final = (
    "ווק",
    "מוקפץ",
    "מוקפצת",
    "מוקפצים",
    "מוקפצות",
    "פאד תאי",
    "צ'או מיין",
    "לו מיין",
    "קונג פאו",
    "יאקיסובה",
    "אורז מטוגן",
)
WOK_GUARDS_HE: Final = {
    "מוקפץ": GuardWords(before=("צ'יפס",), after=()),
}
GRILL_EN: Final = (
    "grill",
    "grilled",
    "chargrilled",
    "charcoal",
    "plancha",
    "mangal",
    "open fire",
)
GRILL_HE: Final = ("גריל", "על האש", "מנגל", "פחמים", "פלנצ'ה")
MEAT_EN: Final = (
    "steak",
    "beef",
    "burger",
    "hamburger",
    "chicken",
    "lamb",
    "kebab",
    "kebabs",
    "ribs",
    "entrecote",
    "ribeye",
    "rib eye",
    "sirloin",
    "sausage",
    "merguez",
    "brisket",
    "turkey",
    "pork",
    "wings",
)
MEAT_HE: Final = (
    "סטייק",
    "סטקים",
    "בקר",
    "בשר",
    "עוף",
    "כבש",
    "קבב",
    "שיפוד",
    "שיפודים",
    "אנטריקוט",
    "המבורגר",
    "נקניקיה",
    "נקניקיות",
    "מרגז",
    "הודו",
    "צלעות",
    "פרגית",
    "פרגיות",
    "כנפיים",
    "אסאדו",
    "בריסקט",
)
_PLANT_BEFORE: Final = ("vegan", "veggie", "vegetarian", "plant based", "beyond")
MEAT_GUARDS_EN: Final = {
    "burger": GuardWords(before=_PLANT_BEFORE, after=()),
    "hamburger": GuardWords(before=_PLANT_BEFORE, after=()),
}
MEAT_GUARDS_HE: Final = {
    "המבורגר": GuardWords(before=(), after=("טבעוני", "טבעונית", "צמחוני", "צמחונית")),
    "בשר": GuardWords(before=("ללא", "בלי"), after=("טבעוני", "צמחי")),
}
BAKERY_EN: Final = (
    "bread",
    "baguette",
    "focaccia",
    "ciabatta",
    "sourdough",
    "challah",
    "bagel",
    "croissant",
    "pastry",
    "pastries",
    "pizza",
    "cake",
    "muffin",
    "scone",
    "danish",
    "brioche",
    "toast",
    "dough",
    "bourekas",
    "burekas",
    "borekas",
    "khachapuri",
    "malawach",
    "jachnun",
    "manakish",
    "cookie",
    "cookies",
    "brownie",
    "waffle",
    "waffles",
    "pancake",
    "pancakes",
)
BAKERY_HE: Final = (
    "לחם",
    "חלה",
    "בגט",
    "פוקאצ'ה",
    "צ'יאבטה",
    "מאפה",
    "מאפים",
    "מאפי",
    "פיצה",
    "פיצות",
    "בורקס",
    "בורקסים",
    "קרואסון",
    "קרואסונים",
    "בייגל",
    "עוגה",
    "עוגות",
    "עוגת",
    "עוגיה",
    "עוגיות",
    "מאפין",
    "פנקייק",
    "פנקייקים",
    "ופל",
    "ופלים",
    "חצ'פורי",
    "מלוואח",
    "ג'חנון",
    "מנאקיש",
    "בריוש",
    "טוסט",
    "דניש",
    "סקונס",
    "בצק",
)
NO_PREFIX_HE: Final = frozenset({"חלה"})
"""Hebrew terms compiled with no permissive prefix letter."""

_SEAFOOD: Final = ("fish", "crustaceans", "molluscs")
"""The seafood restrictions a fried or grilled dish can carry, taxonomy order."""

FRYER_BASE: Final = ("wheat", "gluten")
"""What a fryer always threatens; seafood is added when a fried dish names it."""

THREATENS: Final = {
    KitchenSignalKind.FRYER: FRYER_BASE,
    KitchenSignalKind.WOK: (
        "peanuts",
        "soy",
        "wheat",
        "gluten",
        "crustaceans",
        "molluscs",
        "sesame",
    ),
    KitchenSignalKind.SHARED_GRILL: _SEAFOOD,
    KitchenSignalKind.BAKERY: ("milk", "eggs", "wheat", "gluten", "sesame"),
    KitchenSignalKind.NUTS: ("peanuts", "treeNuts"),
    KitchenSignalKind.SESAME: ("sesame",),
}
"""What each kind threatens, in taxonomy order, except a fryer's seafood."""

QUESTIONS: Final = {
    KitchenSignalKind.FRYER: (
        "Do the fried dishes share a fryer or frying oil with breaded or "
        "battered ones?",
        "האם המנות המטוגנות מטוגנות באותו שמן או באותה מטגנת עם מנות בציפוי או בבלילה?",
    ),
    KitchenSignalKind.WOK: (
        "Is the wok shared between dishes, and is it cleaned between orders?",
        "האם אותו ווק משמש למנות שונות, והאם מנקים אותו בין הזמנות?",
    ),
    KitchenSignalKind.SHARED_GRILL: (
        "Are meat and fish cooked on the same grill, and is it cleaned between orders?",
        "האם בשר ודגים מבושלים על אותו גריל, והאם מנקים אותו בין הזמנות?",
    ),
    KitchenSignalKind.BAKERY: (
        "Is flour or bread handled on the surfaces where other dishes are prepared?",
        "האם מכינים מנות אחרות על אותם משטחים שבהם עובדים עם קמח או לחם?",
    ),
    KitchenSignalKind.NUTS: (
        "Are nuts used in this kitchen, and can my dish be prepared with no "
        "contact with them?",
        "האם משתמשים באגוזים במטבח הזה, ואפשר להכין את המנה שלי בלי מגע איתם?",
    ),
    KitchenSignalKind.SESAME: (
        "Are sesame or tahini used on shared surfaces or utensils, and can my "
        "dish be prepared without them?",
        "האם משתמשים בשומשום או בטחינה על משטחים או כלים משותפים, ואפשר "
        "להכין את המנה שלי בלעדיהם?",
    ),
}
"""The standard question for each kind, English then Hebrew."""


# --- compiling and matching -----------------------------------------------------


@dataclass(frozen=True, slots=True)
class _Compiled:
    pattern: re.Pattern[str]
    guard: GuardWords | None


def _compile_en(
    terms: Iterable[str], guards: Mapping[str, GuardWords] | None = None
) -> tuple[_Compiled, ...]:
    table = guards or {}
    return tuple(
        _Compiled(latin_trigger_pattern(normalise(term)), table.get(term))
        for term in terms
    )


def _compile_he(
    terms: Iterable[str], guards: Mapping[str, GuardWords] | None = None
) -> tuple[_Compiled, ...]:
    table = guards or {}
    return tuple(
        _Compiled(
            hebrew_trigger_pattern(
                normalise(term), allow_prefix=term not in NO_PREFIX_HE
            ),
            table.get(term),
        )
        for term in terms
    )


def _any(haystack: str, compiled: Sequence[_Compiled]) -> bool:
    """Whether any of ``compiled`` has an unguarded match in ``haystack``."""
    if not haystack:
        return False
    return any(
        not is_guarded(haystack, match.start(), match.end(), entry.guard)
        for entry in compiled
        for match in entry.pattern.finditer(haystack)
    )


@cache
def _fried() -> tuple[_Compiled, ...]:
    return _compile_en(FRIED_EN, FRIED_GUARDS_EN) + _compile_he(
        FRIED_HE, FRIED_GUARDS_HE
    )


@cache
def _wok() -> tuple[_Compiled, ...]:
    return _compile_en(WOK_EN) + _compile_he(WOK_HE, WOK_GUARDS_HE)


@cache
def _grill() -> tuple[_Compiled, ...]:
    return _compile_en(GRILL_EN) + _compile_he(GRILL_HE)


@cache
def _meat() -> tuple[_Compiled, ...]:
    return _compile_en(MEAT_EN, MEAT_GUARDS_EN) + _compile_he(MEAT_HE, MEAT_GUARDS_HE)


@cache
def _bakery() -> tuple[_Compiled, ...]:
    return _compile_en(BAKERY_EN) + _compile_he(BAKERY_HE)


@dataclass(frozen=True, slots=True)
class _Flags:
    """What one piece of text (a dish or a heading) shows."""

    fried: bool
    wok: bool
    grill: bool
    meat: bool
    bakery: bool
    nuts: bool
    sesame: bool
    seafood: frozenset[str]

    def union(self, other: "_Flags") -> "_Flags":
        return _Flags(
            fried=self.fried or other.fried,
            wok=self.wok or other.wok,
            grill=self.grill or other.grill,
            meat=self.meat or other.meat,
            bakery=self.bakery or other.bakery,
            nuts=self.nuts or other.nuts,
            sesame=self.sesame or other.sesame,
            seafood=self.seafood | other.seafood,
        )


def _flags_of(haystack: str, hits: Sequence[AllergenHit]) -> _Flags:
    # A guarded hit ("almond-free") is no evidence that the kitchen handles
    # the allergen, so only unguarded hits count (ALG-04a).
    ids = {hit.id for hit in hits if not hit.guarded}
    return _Flags(
        fried=_any(haystack, _fried()),
        wok=_any(haystack, _wok()),
        grill=_any(haystack, _grill()),
        meat=_any(haystack, _meat()),
        bakery=_any(haystack, _bakery()),
        nuts="peanuts" in ids or "treeNuts" in ids,
        sesame="sesame" in ids,
        seafood=frozenset(i for i in _SEAFOOD if i in ids),
    )


@dataclass(frozen=True, slots=True)
class _Seen:
    """A dish, its position in the menu and what it shows (its own text plus
    its category heading)."""

    index: int
    dish: Dish
    flags: _Flags


def _names(seen: Iterable[_Seen]) -> tuple[str, ...]:
    """Up to :data:`EVIDENCE_CAP` distinct names, first occurrence kept."""
    names: list[str] = []
    for entry in seen:
        if len(names) == EVIDENCE_CAP:
            break
        if entry.dish.name not in names:
            names.append(entry.dish.name)
    return tuple(names)


def _grill_evidence(meat: list[_Seen], fish: list[_Seen]) -> list[_Seen]:
    """The first meat dish and the first fish dish (they are why the grill is
    shared), then more grilled dishes in menu order up to the cap, all in menu
    order."""
    meat_indexes = {entry.index for entry in meat}
    on_grill = sorted(
        [*meat, *(entry for entry in fish if entry.index not in meat_indexes)],
        key=lambda entry: entry.index,
    )
    picked = {meat[0].index, fish[0].index}
    for entry in on_grill:
        if len(picked) == EVIDENCE_CAP:
            break
        picked.add(entry.index)
    return [entry for entry in on_grill if entry.index in picked]


def _read(
    menu: Menu,
    find_in_text: Callable[[str], list[AllergenHit]],
    find_in_a_dish: Callable[[Dish], list[AllergenHit]],
) -> list[KitchenSignal]:
    seen: list[_Seen] = []
    for category in menu.categories:
        heading = _flags_of(normalise(category.name), find_in_text(category.name))
        for dish in category.dishes:
            own = _flags_of(dish_rules_text(dish), find_in_a_dish(dish))
            seen.append(_Seen(len(seen), dish, own.union(heading)))

    def where(test: Callable[[_Flags], bool]) -> list[_Seen]:
        return [entry for entry in seen if test(entry.flags)]

    fried = where(lambda flags: flags.fried)
    wok = where(lambda flags: flags.wok)
    bakery = where(lambda flags: flags.bakery)
    nuts = where(lambda flags: flags.nuts)
    sesame = where(lambda flags: flags.sesame)
    grilled_meat = where(lambda flags: flags.grill and flags.meat)
    grilled_fish = where(lambda flags: flags.grill and "fish" in flags.seafood)
    fried_seafood = {i for entry in fried for i in entry.flags.seafood}

    def signal(
        kind: KitchenSignalKind,
        evidence: Iterable[_Seen],
        threatens: Sequence[str] | None = None,
    ) -> KitchenSignal:
        question_en, question_he = QUESTIONS[kind]
        return KitchenSignal(
            kind=kind,
            threatens=tuple(THREATENS[kind] if threatens is None else threatens),
            evidence=_names(evidence),
            question_en=question_en,
            question_he=question_he,
        )

    signals: list[KitchenSignal] = []
    if fried:
        signals.append(
            signal(
                KitchenSignalKind.FRYER,
                fried,
                [*FRYER_BASE, *(i for i in _SEAFOOD if i in fried_seafood)],
            )
        )
    if wok:
        signals.append(signal(KitchenSignalKind.WOK, wok))
    if grilled_meat and grilled_fish:
        signals.append(
            signal(
                KitchenSignalKind.SHARED_GRILL,
                _grill_evidence(grilled_meat, grilled_fish),
            )
        )
    if bakery:
        signals.append(signal(KitchenSignalKind.BAKERY, bakery))
    if nuts:
        signals.append(signal(KitchenSignalKind.NUTS, nuts))
    if sesame:
        signals.append(signal(KitchenSignalKind.SESAME, sesame))
    return signals


def kitchen_signals(menu: Menu) -> list[KitchenSignal]:
    """``KitchenSignals.of``: every signal ``menu`` shows, in
    :class:`KitchenSignalKind` order; an empty list when it shows none."""
    return _read(menu, find, find_in_dish)


def kitchen_signals_with(
    menu: Menu, vocabulary: Mapping[str, RestrictionVocabulary]
) -> list[KitchenSignal]:
    """``KitchenSignals.ofWith``: :func:`kitchen_signals` over ``vocabulary``
    instead of the packaged allergen vocabulary."""
    return _read(
        menu,
        lambda text: find_with(text, vocabulary),
        lambda dish: find_in_dish_with(dish, vocabulary),
    )

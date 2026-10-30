"""Parses an LLM reply into a menu analysis (architecture.md §9.4, D25).

The Python twin of ``MenuResponseParser`` in
``lib/services/classifier/menu_response_parser.dart``. The reply is untrusted
input shaped by menu text a restaurant typed (§9, §11): every rule exists to
make a wrong green rare and visible, never to trust a field the model sent.
A test replays the golden ``parser.json`` through :func:`parse` and
:func:`parse_scanned` and compares the results with the Dart ones.

Dart behaviour reproduced on purpose (``parity_quirks`` 6-8):

* **Lengths are UTF-16 code units.** The 300-unit caps on ``why``,
  ``modification`` and a hidden carb's ``source``/``waiter_question`` count
  an astral character as two, and the ``why`` cut never splits a surrogate
  pair (it backs off one unit instead).
* **Trimming is Dart's** (:func:`~app.keto.dart_text.dart_trim`): it strips a
  leading BOM, so a reply starting with U+FEFF still parses and a ``why`` of
  only U+FEFF is blank, but it keeps U+001C-U+001F, which Python's
  ``strip`` would remove.
* **JSON is Dart's** ``jsonDecode``: ``NaN``/``Infinity`` literals are a
  ``badResponse``, as are trailing content and prose around a fence.

Static, pure and total: every input yields an :class:`Analysed` (or
:class:`ScannedRead`) or a :class:`Failed`, and nothing raises. The output
models are built with ``model_construct``: the rules here are the validation
(they are Dart's), and pydantic's own checks differ from Dart's in two
places a hostile reply can reach (``HiddenCarb`` blanks use Python
``strip``; a lone surrogate an escaped reply can carry is not a valid
pydantic string), so validating again could raise where Dart does not.
"""

import json
import math
import re
from collections.abc import Mapping
from dataclasses import dataclass
from typing import Any, Final, Literal, TypeGuard, get_args

from app.keto.dart_text import dart_trim, utf16_len, utf16_slice, utf16_units
from app.keto.fingerprint import scan_ref
from app.keto.models import (
    AnalysedDish,
    Certainty,
    ComponentRole,
    Dish,
    ExtractedIngredient,
    HiddenCarb,
    LlmEngine,
    Menu,
    MenuAnalysed,
    MenuCategory,
    RulesEngine,
    VenueRef,
)
from app.keto.normaliser import contains_hebrew, dish_rules_text, normalise, words
from app.keto.vocabulary import vocabulary

SCHEMA_VERSION: Final[int] = vocabulary().caps.parser_schema_version
"""``MenuResponseParser.schemaVersion``, stamped on every analysis."""

ParseFailureReason = Literal["badResponse", "noDishesFound"]
"""The two ``MenuAnalysisFailureReason`` names the parser can return."""

_VERDICTS: Final = frozenset({"orderAsIs", "modifiable", "nonKeto"})
_CERTAINTIES: Final = frozenset({"suspected", "likely"})
_INGREDIENT_CERTAINTIES: Final = frozenset(get_args(Certainty))
_COMPONENT_ROLES: Final = frozenset(get_args(ComponentRole))

MAX_INGREDIENTS_PER_DISH: Final = 40
"""Dart ``maxIngredientsPerDish`` (ALG-03)."""

MAX_INGREDIENT_NAME_LENGTH: Final = 100
"""Dart ``maxIngredientNameLength``, in UTF-16 code units (ALG-03)."""

MAX_TRANSCRIBED_DESCRIPTION_LENGTH: Final = 1000
"""Dart ``maxTranscribedDescriptionLength``, in UTF-16 code units."""

_JS_WHITESPACE: Final = "\t\n\u000b\u000c\r    -     　﻿"
"""JavaScript's ``\\s`` (which Dart's ``RegExp`` uses): unlike Python's, it
holds U+FEFF and not U+001C-U+001F or U+0085."""

_FENCED_JSON: Final = re.compile(
    rf"^```(?:[jJ][sS][oO][nN])?[{_JS_WHITESPACE}]*\n?([\s\S]*?)\n?```\Z"
)
"""Dart ``_fencedJson``: a whole reply in a markdown fence, with or without
a ``json`` tag in any case. ``\\Z`` because Dart's ``$`` (no multiline) never
matches before a final newline; the tag is spelled out because Python's
``IGNORECASE`` would let ``ſ`` match ``s``, which Dart's does not."""


@dataclass(frozen=True, slots=True)
class Analysed:
    """``MenuAnalysed``: the reply placed (possibly with nothing placed)."""

    analysis: MenuAnalysed


@dataclass(frozen=True, slots=True)
class ScannedRead:
    """``ScannedMenuRead``: the transcribed menu and its analysis."""

    menu: Menu
    analysis: MenuAnalysed


@dataclass(frozen=True, slots=True)
class Failed:
    """``MenuAnalysisFailed`` / ``ScannedMenuFailed``."""

    reason: ParseFailureReason


ParseResult = Analysed | Failed
"""What :func:`parse` returns."""

ScannedParseResult = ScannedRead | Failed
"""What :func:`parse_scanned` returns."""

Engine = LlmEngine | RulesEngine


def _reject_constant(name: str) -> Any:
    raise ValueError(f"{name} is not JSON")


def _decode(body: str) -> dict[str, Any] | None:
    """Dart ``_decode``: trim, strip a whole-reply fence, ``jsonDecode``;
    ``None`` when that fails or the root is not an object (rules 1-2)."""
    trimmed = dart_trim(body)
    fence = _FENCED_JSON.match(trimmed)
    unfenced = dart_trim(fence.group(1)) if fence else trimmed
    try:
        decoded = json.loads(unfenced, parse_constant=_reject_constant)
    except (ValueError, RecursionError):
        return None
    return decoded if isinstance(decoded, dict) else None


def _dishes_of(body: str) -> list[Any] | None:
    """The reply's ``dishes`` list, or ``None`` for a ``badResponse``."""
    decoded = _decode(body)
    if decoded is None:
        return None
    raw_dishes = decoded.get("dishes")
    if not isinstance(raw_dishes, list):
        return None
    if len(raw_dishes) > vocabulary().caps.max_analysed_dishes:
        return None
    return raw_dishes


def _is_number(value: object) -> TypeGuard[int | float]:
    """Dart ``is num``: an int or a double, never a bool."""
    return isinstance(value, int | float) and not isinstance(value, bool)


def _to_double(value: int | float) -> float:
    """Dart ``num.toDouble``; an int too large for a double is infinite, as
    Dart's ``jsonDecode`` reads such a literal."""
    try:
        return float(value)
    except OverflowError:
        return math.inf if value > 0 else -math.inf


def _truncated(text: str, max_length: int) -> str:
    """Dart ``_truncated``: at most ``max_length`` UTF-16 units, backing off
    one unit rather than ending on a high surrogate."""
    if utf16_len(text) <= max_length:
        return text
    last = utf16_units(text)[max_length - 1]
    end = max_length - 1 if 0xD800 <= last <= 0xDBFF else max_length
    return utf16_slice(text, 0, end)


def _parse_hidden_carbs(raw: object) -> list[HiddenCarb]:
    """Dart ``_parseHiddenCarbs`` (rule 5a): well-formed flags only, at most
    ``maxHiddenCarbsPerDish``. Lengths are checked on the untrimmed text."""
    if not isinstance(raw, list):
        return []
    caps = vocabulary().caps
    result: list[HiddenCarb] = []
    for entry in raw:
        if len(result) >= caps.max_hidden_carbs_per_dish:
            break
        if not isinstance(entry, dict):
            continue
        source = entry.get("source")
        certainty = entry.get("certainty")
        question = entry.get("waiter_question")
        if not isinstance(source, str) or not dart_trim(source):
            continue
        if utf16_len(source) > caps.max_why_length:
            continue
        if not isinstance(certainty, str) or certainty not in _CERTAINTIES:
            continue
        if not isinstance(question, str) or not dart_trim(question):
            continue
        if utf16_len(question) > caps.max_why_length:
            continue
        result.append(
            HiddenCarb.model_construct(
                source=dart_trim(source),
                certainty=certainty,
                waiter_question=dart_trim(question),
            )
        )
    return result


def _parse_ingredients(raw: object, dish: Dish) -> list[ExtractedIngredient]:
    """Dart ``_parseIngredients`` (ALG-03): well-formed entries only, a
    missing or unknown role read as ``unknown``, an ingredient whose
    normalised name is not a substring of ``dish``'s rules text capped at
    ``suspected``, the first of names that normalise alike, at most
    :data:`MAX_INGREDIENTS_PER_DISH`. The name is Dart-trimmed before its
    length is checked."""
    if not isinstance(raw, list):
        return []
    dish_text = dish_rules_text(dish)
    seen: set[str] = set()
    result: list[ExtractedIngredient] = []
    for entry in raw:
        if len(result) >= MAX_INGREDIENTS_PER_DISH:
            break
        if not isinstance(entry, dict):
            continue
        raw_name = entry.get("name")
        if not isinstance(raw_name, str):
            continue
        name = dart_trim(raw_name)
        if not name or utf16_len(name) > MAX_INGREDIENT_NAME_LENGTH:
            continue
        certainty = entry.get("certainty")
        if not isinstance(certainty, str) or certainty not in _INGREDIENT_CERTAINTIES:
            continue
        raw_role = entry.get("role")
        role = (
            raw_role
            if isinstance(raw_role, str) and raw_role in _COMPONENT_ROLES
            else "unknown"
        )
        normalised = normalise(name)
        key = normalised or name
        if key in seen:
            continue
        seen.add(key)
        supported = bool(normalised) and normalised in dish_text
        result.append(
            ExtractedIngredient.model_construct(
                name=name,
                certainty=certainty if supported else "suspected",
                role=role,
            )
        )
    return result


def extraction_missing(dish: Dish, analysed: AnalysedDish, *, extract: bool) -> bool:
    """Dart ``MenuResponseParser.extractionMissing`` (ALG-03): with
    extraction requested, a dish with a description whose verdict kept no
    ingredient. Computed, never stored; the verdict stands and the rules
    pass is that dish's only source of concerns."""
    return extract and not analysed.ingredients and dart_trim(dish.description) != ""


def _judge(
    raw_dish: dict[str, Any],
    matched: Dish,
    *,
    net_carb_limit_grams: int,
    extract: bool,
    dishes: list[AnalysedDish],
    unclassified: list[str],
) -> None:
    """Dart ``_judge``: rules 4-6, #57's net-carb post-rule and #213's
    hidden-carb rule (rule 5a); places ``raw_dish`` under ``matched``'s id and name or
    demotes ``matched``'s name to ``unclassified``. With ``extract`` the
    placed dish carries :func:`_parse_ingredients` of its ``ingredients``,
    whatever its verdict."""
    caps = vocabulary().caps
    verdict = raw_dish.get("verdict")
    if not isinstance(verdict, str) or verdict not in _VERDICTS:
        unclassified.append(matched.name)
        return

    raw_why = raw_dish.get("why")
    why = dart_trim(raw_why) if isinstance(raw_why, str) else ""
    if not why:
        unclassified.append(matched.name)
        return

    raw_modification = raw_dish.get("modification")
    modification = (
        dart_trim(raw_modification) if isinstance(raw_modification, str) else None
    )
    has_usable_modification = (
        modification is not None
        and modification != ""
        and utf16_len(modification) <= caps.max_modification_length
    )

    raw_net_carbs = raw_dish.get("net_carbs_estimate")
    net_carbs = _to_double(raw_net_carbs) if _is_number(raw_net_carbs) else None

    final_verdict = verdict
    if (
        verdict == "orderAsIs"
        and net_carbs is not None
        and net_carbs > net_carb_limit_grams
    ):
        final_verdict = "modifiable"

    hidden_carbs = (
        []
        if verdict == "nonKeto"
        else _parse_hidden_carbs(raw_dish.get("hidden_carbs"))
    )
    # Rule 5a only for a dish still green: the flag is then its only reason
    # to be yellow. A yellow the model sent (or #57 made) keeps rule 5 as
    # written, hidden carbs or not (#277).
    hidden_carb_yellow = final_verdict == "orderAsIs" and bool(hidden_carbs)
    if hidden_carb_yellow:
        final_verdict = "modifiable"

    final_modification: str | None = None
    if final_verdict == "modifiable":
        if has_usable_modification:
            final_modification = modification
        elif hidden_carb_yellow:
            final_modification = hidden_carbs[0].waiter_question
        else:
            unclassified.append(matched.name)
            return

    dishes.append(
        AnalysedDish.model_construct(
            dish_id=matched.id,
            name=matched.name,
            verdict=final_verdict,
            why=_truncated(why, caps.max_why_length),
            modification=final_modification,
            # Infinity passes the post-rule above as in Dart, but no JSON
            # (Dart's or ours) can carry it, so it is stored as no estimate.
            net_carbs_estimate=(
                net_carbs
                if net_carbs is not None and math.isfinite(net_carbs)
                else None
            ),
            hidden_carbs=[] if final_verdict == "nonKeto" else hidden_carbs,
            ingredients=(
                _parse_ingredients(raw_dish.get("ingredients"), matched)
                if extract
                else []
            ),
            concerns=[],
        )
    )


def _content_words(name: str) -> set[str]:
    """Dart ``_contentWords``: the distinct normalised words of
    ``minOverlapWordLength``+ UTF-16 units not in ``nameStopWords``."""
    stop_words = vocabulary().provenance.name_stop_words
    return {
        word
        for word in words(name, vocabulary().caps.min_overlap_word_length)
        if word not in stop_words
    }


def _find_source_dish(
    source: Menu, *, prompt_ids: Mapping[str, str], dish_id: str, name: str
) -> Dish | None:
    """Dart ``_findSourceDish`` (rule 3, #277): a matching id always wins,
    a key of ``prompt_ids`` (the short ids the prompt sent) first, read as
    the dish whose own id it maps to, then a dish's own id; only a missing
    or unknown id falls back to ``name``, first by an exact normalised name
    (the first in menu order), then by the unique best Jaccard overlap of
    content words at or over the threshold, in integers as Dart counts it.
    A tie for the best is ambiguous: no match."""
    all_dishes = source.all_dishes()
    if dish_id:
        mapped = prompt_ids.get(dish_id)
        if mapped is not None:
            for dish in all_dishes:
                if dish.id == mapped:
                    return dish
        for dish in all_dishes:
            if dish.id == dish_id:
                return dish
    normalised_name = normalise(name)
    if not normalised_name:
        return None
    for dish in all_dishes:
        if normalise(dish.name) == normalised_name:
            return dish
    name_words = _content_words(name)
    if not name_words:
        return None
    provenance = vocabulary().provenance
    best: Dish | None = None
    best_shared = 0
    best_union = 1
    tied = False
    for dish in all_dishes:
        dish_words = _content_words(dish.name)
        shared = len(dish_words & name_words)
        if shared == 0:
            continue
        union = len(name_words) + len(dish_words) - shared
        if (
            shared * provenance.name_overlap_denominator
            < union * provenance.name_overlap_numerator
        ):
            continue
        compare = shared * best_union - best_shared * union
        if best is None or compare > 0:
            best, best_shared, best_union, tied = dish, shared, union, False
        elif compare == 0:
            tied = True
    return None if tied else best


def _analysis(
    dishes: list[AnalysedDish],
    unclassified: list[str],
    engine: Engine,
    analysed_at: str,
) -> MenuAnalysed:
    return MenuAnalysed.model_construct(
        dishes=dishes,
        unclassified=unclassified,
        engine=engine,
        analysed_at=analysed_at,
        options=None,
        schema_version=SCHEMA_VERSION,
    )


def parse(
    body: str,
    *,
    source: Menu,
    engine: Engine,
    net_carb_limit_grams: int,
    analysed_at: str,
    extract: bool = False,
    prompt_ids: Mapping[str, str] | None = None,
) -> ParseResult:
    """``MenuResponseParser.parse``: ``body``, the raw reply, against
    ``source``, the menu it was computed from (§9.4 rules 1-8).

    ``prompt_ids`` is ``prompt.prompt_ids(source)``, the short ids the
    request numbered ``source``'s dishes with: a reply's ``id`` is read
    through it before it is compared with the dishes' own ids.

    With ``extract`` (ALG-03) each placed dish carries its ingredients;
    without it ``ingredients`` is never read. A model-sent ``concerns`` is
    never read (D26 C1).

    ``analysed_at`` is the Dart ``toIso8601String()`` text, kept verbatim.
    The analysis carries no ``options`` snapshot: as in Dart, the caller
    stamps that.
    """
    raw_dishes = _dishes_of(body)
    if raw_dishes is None:
        return Failed("badResponse")

    resolved_source_ids: set[str] = set()
    dishes: list[AnalysedDish] = []
    unclassified: list[str] = []
    for raw_dish in raw_dishes:
        if not isinstance(raw_dish, dict):
            continue
        raw_id = raw_dish.get("id")
        raw_name = raw_dish.get("name")
        model_id = raw_id if isinstance(raw_id, str) else ""
        model_name = raw_name if isinstance(raw_name, str) else ""
        if not model_id and not model_name:
            continue
        matched = _find_source_dish(
            source, prompt_ids=prompt_ids or {}, dish_id=model_id, name=model_name
        )
        if matched is None:
            # An invention: never a verdict, but flagged by the model's name.
            if model_name:
                unclassified.append(model_name)
            continue
        # A second element for a dish already judged is dropped (#277).
        if matched.id in resolved_source_ids:
            continue
        resolved_source_ids.add(matched.id)
        _judge(
            raw_dish,
            matched,
            net_carb_limit_grams=net_carb_limit_grams,
            extract=extract,
            dishes=dishes,
            unclassified=unclassified,
        )

    # Rule 7: a source dish no element matched was skipped by the model.
    for dish in source.all_dishes():
        if dish.id not in resolved_source_ids:
            unclassified.append(dish.name)

    if not dishes and not unclassified:
        return Failed("noDishesFound")
    return Analysed(_analysis(dishes, unclassified, engine, analysed_at))


def _page(raw: object, page_count: int | None) -> int | None:
    """Dart ``_page``: an integral number in ``1..page_count`` (``2.0``
    reads as 2), else ``None``; always ``None`` without a page count."""
    if page_count is None or not _is_number(raw):
        return None
    if isinstance(raw, float) and not (math.isfinite(raw) and raw.is_integer()):
        return None
    page = int(raw)
    return page if 1 <= page <= page_count else None


def parse_scanned(
    body: str,
    *,
    engine: Engine,
    analysed_at: str,
    net_carb_limit_grams: int,
    page_count: int | None,
    extract: bool = False,
) -> ScannedParseResult:
    """``MenuResponseParser.parseScanned``: a vision reply read as both the
    transcribed menu and its analysis.

    An element without a non-blank string ``name`` is dropped; of elements
    whose names normalise alike (the trimmed name itself when it normalises
    to nothing) the first is kept. Kept elements become dishes ``v1``, ``v2``…
    with no description, price ``0.0``, no options and a page from
    :func:`_page`, in one ``scanned`` category named in Hebrew when any dish
    name holds Hebrew. The menu is addressed ``scan/<fingerprint>`` and
    fetched at ``analysed_at``; the analysis carries no ``options``.

    With ``extract`` (ALG-03) a dish's description is its element's string
    ``description``, Dart-trimmed and cut at
    :data:`MAX_TRANSCRIBED_DESCRIPTION_LENGTH` like ``why``, and each placed
    dish carries its ingredients.
    """
    raw_dishes = _dishes_of(body)
    if raw_dishes is None:
        return Failed("badResponse")

    scanned = vocabulary().scanned
    seen_names: set[str] = set()
    transcribed: list[Dish] = []
    dishes: list[AnalysedDish] = []
    unclassified: list[str] = []
    for raw_dish in raw_dishes:
        if not isinstance(raw_dish, dict):
            continue
        raw_name = raw_dish.get("name")
        name = dart_trim(raw_name) if isinstance(raw_name, str) else ""
        if not name:
            continue
        key = normalise(name) or name
        if key in seen_names:
            continue
        seen_names.add(key)
        raw_description = raw_dish.get("description")
        description = (
            _truncated(dart_trim(raw_description), MAX_TRANSCRIBED_DESCRIPTION_LENGTH)
            if extract and isinstance(raw_description, str)
            else ""
        )
        dish = Dish.model_construct(
            id=f"{scanned.scanned_dish_id_prefix}{len(transcribed) + 1}",
            name=name,
            description=description,
            price=0.0,
            options=[],
            image_url=None,
            page=_page(raw_dish.get("page"), page_count),
        )
        transcribed.append(dish)
        _judge(
            raw_dish,
            dish,
            net_carb_limit_grams=net_carb_limit_grams,
            extract=extract,
            dishes=dishes,
            unclassified=unclassified,
        )

    if not transcribed:
        return Failed("noDishesFound")
    is_hebrew = any(contains_hebrew(dish.name) for dish in transcribed)
    categories = [
        MenuCategory.model_construct(
            id=scanned.scanned_category_id,
            name=(
                scanned.scanned_category_name_he
                if is_hebrew
                else scanned.scanned_category_name_en
            ),
            dishes=transcribed,
        )
    ]

    def menu_at(ref: VenueRef) -> Menu:
        return Menu.model_construct(
            venue_ref=ref,
            currency=scanned.scanned_menu_currency,
            fetched_at=analysed_at,
            categories=categories,
            venue_name=None,
        )

    # The paste scheme: fingerprint a provisional menu, address the real one.
    provisional = menu_at(VenueRef(source="scan", platform_id="pending"))
    return ScannedRead(
        menu=menu_at(scan_ref(provisional)),
        analysis=_analysis(dishes, unclassified, engine, analysed_at),
    )

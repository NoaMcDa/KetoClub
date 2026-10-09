"""The keto vocabulary, read from ``vocabulary.json`` (architecture.md D25).

``vocabulary.json`` beside this module is a byte-for-byte copy of the golden
``tests/fixtures/golden/vocabulary.json``, which the Dart exporter
(``tool/golden/golden_export.dart``) writes from ``lib/utils/constants.dart``
and the private values it reads back from the Dart code. A test asserts the
two files are identical, so the Python port can never drift from the Dart
vocabulary without that test failing.

:func:`vocabulary` parses the file once (cached) into frozen dataclasses with
typed accessors. Every list is a ``tuple`` and every map a read-only
``Mapping``, so nothing downstream can mutate the shared value.

**Key order.** The golden files sort every object's keys, so a ``Mapping``
here iterates in sorted (UTF-16 code unit) order, not the Dart
``constants.dart`` insertion order. Where that order matters to the rule
engine the exporter wrote an ordered list of pairs instead
(``carbModifiersEn``/``carbModifiersHe``), kept here as a tuple of pairs.
"""

import json
from collections.abc import Mapping
from dataclasses import dataclass
from functools import cache
from pathlib import Path
from types import MappingProxyType
from typing import Any, Final

VOCABULARY_PATH: Final = Path(__file__).with_name("vocabulary.json")
"""The packaged copy of the golden vocabulary."""


# --- typed readers --------------------------------------------------------------


def _obj(value: Any, where: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ValueError(f"{where}: expected an object")
    return value


def _str(value: Any, where: str) -> str:
    if not isinstance(value, str):
        raise ValueError(f"{where}: expected a string")
    return value


def _int(value: Any, where: str) -> int:
    if not isinstance(value, int) or isinstance(value, bool):
        raise ValueError(f"{where}: expected an integer")
    return value


def _float(value: Any, where: str) -> float:
    if not isinstance(value, int | float) or isinstance(value, bool):
        raise ValueError(f"{where}: expected a number")
    return float(value)


def _bool(value: Any, where: str) -> bool:
    if not isinstance(value, bool):
        raise ValueError(f"{where}: expected a boolean")
    return value


def _strs(value: Any, where: str) -> tuple[str, ...]:
    if not isinstance(value, list):
        raise ValueError(f"{where}: expected a list")
    return tuple(_str(item, f"{where}[]") for item in value)


def _str_map(value: Any, where: str) -> Mapping[str, str]:
    raw = _obj(value, where)
    return MappingProxyType(
        {key: _str(item, f"{where}.{key}") for key, item in raw.items()}
    )


def _strs_map(value: Any, where: str) -> Mapping[str, tuple[str, ...]]:
    raw = _obj(value, where)
    return MappingProxyType(
        {key: _strs(item, f"{where}.{key}") for key, item in raw.items()}
    )


def _pairs(value: Any, where: str) -> tuple[tuple[str, str], ...]:
    if not isinstance(value, list):
        raise ValueError(f"{where}: expected a list of pairs")
    pairs: list[tuple[str, str]] = []
    for item in value:
        if not isinstance(item, list) or len(item) != 2:
            raise ValueError(f"{where}: expected a [key, value] pair")
        pairs.append((_str(item[0], where), _str(item[1], where)))
    return tuple(pairs)


# --- the sections -----------------------------------------------------------------


@dataclass(frozen=True, slots=True)
class GuardWords:
    """Dart ``GuardWords``: words that, within two words of a trigger,
    rescue it (``before`` the trigger or ``after`` it)."""

    before: tuple[str, ...]
    after: tuple[str, ...]


def _guards(value: Any, where: str) -> Mapping[str, GuardWords]:
    raw = _obj(value, where)
    return MappingProxyType(
        {
            key: GuardWords(
                before=_strs(_obj(item, where)["before"], f"{where}.{key}.before"),
                after=_strs(_obj(item, where)["after"], f"{where}.{key}.after"),
            )
            for key, item in raw.items()
        }
    )


@dataclass(frozen=True, slots=True)
class HebrewPrefixAllowed:
    """Which ``dish_kind`` vocabularies match Hebrew with the permissive
    prefix (private to ``utils/dish_kind.dart``)."""

    drink_categories: bool
    extra_categories: bool
    food_categories: bool
    notice: bool
    drink_names: bool
    drink_name_guards: bool


@dataclass(frozen=True, slots=True)
class DishKindWords:
    """The D21 dish-kind vocabularies (``constants.dart``)."""

    drink_category_words_en: tuple[str, ...]
    drink_category_words_he: tuple[str, ...]
    extra_category_words_en: tuple[str, ...]
    extra_category_words_he: tuple[str, ...]
    food_category_words_en: tuple[str, ...]
    food_category_words_he: tuple[str, ...]
    notice_category_words_en: tuple[str, ...]
    notice_category_words_he: tuple[str, ...]
    yellow_drink_triggers_en: tuple[str, ...]
    yellow_drink_triggers_he: tuple[str, ...]
    plain_drink_words_en: tuple[str, ...]
    plain_drink_words_he: tuple[str, ...]
    drink_name_triggers_en: tuple[str, ...]
    drink_name_triggers_he: tuple[str, ...]
    drink_name_guard_words_en: tuple[str, ...]
    drink_name_guard_words_he: tuple[str, ...]
    hebrew_prefix_allowed: HebrewPrefixAllowed


@dataclass(frozen=True, slots=True)
class Templates:
    """The heuristic's bilingual ``why``/modification templates."""

    green_why_en: str
    green_why_he: str
    yellow_why_en: str
    yellow_why_he: str
    red_why_en: str
    red_why_he: str
    dietary_rule_why_en: str
    dietary_rule_why_he: str
    seed_oil_free_modification_en: str
    seed_oil_free_modification_he: str
    dairy_free_modification_en: str
    dairy_free_modification_he: str
    carnivore_only_modification_en: str
    carnivore_only_modification_he: str
    option_base_modification_en: str
    option_base_modification_he: str


@dataclass(frozen=True, slots=True)
class PromptText:
    """The system prompt's parts, as the Dart ``MenuAnalysisPrompt`` builds
    them (``rolePreamble``, ``outputRules`` and ``dietaryConstraintsPreamble``
    were cut out of its real output)."""

    prompt_verdict_definitions_template: str
    prompt_keto_rules_template: str
    seed_oil_free_prompt_fragment: str
    dairy_free_prompt_fragment: str
    carnivore_only_prompt_fragment: str
    net_carb_limit_placeholder: str
    role_preamble: str
    output_rules: str
    dietary_constraints_preamble: str
    schema_name: str


@dataclass(frozen=True, slots=True)
class Caps:
    """Numeric limits (``constants.dart`` and two Dart literals)."""

    max_analysed_dishes: int
    max_why_length: int
    max_modification_length: int
    min_overlap_word_length: int
    default_net_carb_limit_grams: int
    min_net_carb_limit_grams: int
    max_net_carb_limit_grams: int
    max_hidden_carbs_per_dish: int
    parser_schema_version: int
    max_scan_pages: int
    max_scan_page_bytes: int


@dataclass(frozen=True, slots=True)
class ScannedConstants:
    """The shape a scanned menu is built in (D15)."""

    scanned_category_id: str
    scanned_category_name_en: str
    scanned_category_name_he: str
    scanned_dish_id_prefix: str
    scanned_menu_currency: str


@dataclass(frozen=True, slots=True)
class RegexSource:
    """A Dart ``RegExp`` as its source text and flags."""

    pattern: str
    case_sensitive: bool
    unicode: bool


@dataclass(frozen=True, slots=True)
class PastedConstants:
    """The pasted-menu reader's constants (D18)."""

    pasted_header_max_words: int
    pasted_price_suffix: RegexSource


@dataclass(frozen=True, slots=True)
class WebsiteConstants:
    """The website-menu locator's constants (D19)."""

    website_category_name_en: str
    website_category_name_he: str
    menu_words: tuple[str, ...]
    min_priced_lines: int
    js_only_text_chars: int
    js_only_noscript_text_chars: int


@dataclass(frozen=True, slots=True)
class KetoScoreWeights:
    """The keto score's yellow weights, read back from the Dart formula."""

    yellow: float
    hidden_carb_yellow: float


@dataclass(frozen=True, slots=True)
class HebrewPatternExample:
    """``hebrewTriggerPattern``'s source text for one trigger, three ways."""

    trigger: str
    with_prefix: str
    without_prefix: str
    with_inflection: str


@dataclass(frozen=True, slots=True)
class LatinPatternExample:
    """``latinTriggerPattern``'s source text and flags for one trigger."""

    trigger: str
    pattern: str
    case_sensitive: bool
    unicode: bool


@dataclass(frozen=True, slots=True)
class Vocabulary:
    """Every value in ``vocabulary.json``, typed."""

    carb_modifiers_en: tuple[tuple[str, str], ...]
    carb_modifiers_he: tuple[tuple[str, str], ...]
    non_keto_drink_bases_en: tuple[str, ...]
    non_keto_drink_bases_he: tuple[str, ...]
    non_keto_bases_en: tuple[str, ...]
    non_keto_bases_he: tuple[str, ...]
    non_keto_base_labels_en: Mapping[str, str]
    non_keto_base_labels_he: Mapping[str, str]
    carb_only_base_labels: Mapping[str, str]
    carb_only_eligible_triggers: tuple[str, ...]
    carb_only_qualifiers_en: tuple[str, ...]
    carb_only_qualifiers_he: tuple[str, ...]
    filling_protein_triggers_en: tuple[str, ...]
    filling_protein_triggers_he: tuple[str, ...]
    seed_oil_triggers_en: tuple[str, ...]
    seed_oil_triggers_he: tuple[str, ...]
    dairy_triggers_en: tuple[str, ...]
    dairy_triggers_he: tuple[str, ...]
    plant_triggers_en: tuple[str, ...]
    plant_triggers_he: tuple[str, ...]
    trigger_suppresses: Mapping[str, tuple[str, ...]]
    keto_qualifier_guards_en: Mapping[str, GuardWords]
    keto_qualifier_guards_he: Mapping[str, GuardWords]
    dairy_guards_en: Mapping[str, GuardWords]
    dairy_guards_he: Mapping[str, GuardWords]
    option_removal_words_en: tuple[str, ...]
    option_removal_words_he: tuple[str, ...]
    no_prefix_hebrew_triggers: tuple[str, ...]
    hebrew_trigger_pattern_example: HebrewPatternExample
    latin_trigger_pattern_example: LatinPatternExample
    dish_kinds: DishKindWords
    templates: Templates
    prompt: PromptText
    caps: Caps
    scanned: ScannedConstants
    pasted: PastedConstants
    website: WebsiteConstants
    keto_score_weights: KetoScoreWeights


def parse_vocabulary(raw: Any) -> Vocabulary:
    """The :class:`Vocabulary` in ``raw``, the decoded ``vocabulary.json``.

    Raises ``ValueError`` (or ``KeyError``) when a key is missing or has the
    wrong type: the file is checked in, so that is a build error.
    """
    root = _obj(raw, "vocabulary")
    kinds = _obj(root["dishKinds"], "dishKinds")
    prefix = _obj(kinds["hebrewPrefixAllowed"], "hebrewPrefixAllowed")
    templates = _obj(root["templates"], "templates")
    prompt = _obj(root["prompt"], "prompt")
    caps = _obj(root["caps"], "caps")
    scanned = _obj(root["scanned"], "scanned")
    pasted = _obj(root["pasted"], "pasted")
    suffix = _obj(pasted["pastedPriceSuffix"], "pastedPriceSuffix")
    website = _obj(root["website"], "website")
    weights = _obj(root["ketoScoreWeights"], "ketoScoreWeights")
    he_example = _obj(root["hebrewTriggerPatternExample"], "hebrewExample")
    latin_example = _obj(root["latinTriggerPatternExample"], "latinExample")

    def strs(key: str) -> tuple[str, ...]:
        return _strs(root[key], key)

    def kind_strs(key: str) -> tuple[str, ...]:
        return _strs(kinds[key], f"dishKinds.{key}")

    def template(key: str) -> str:
        return _str(templates[key], f"templates.{key}")

    def prompt_text(key: str) -> str:
        return _str(prompt[key], f"prompt.{key}")

    def cap(key: str) -> int:
        return _int(caps[key], f"caps.{key}")

    return Vocabulary(
        carb_modifiers_en=_pairs(root["carbModifiersEn"], "carbModifiersEn"),
        carb_modifiers_he=_pairs(root["carbModifiersHe"], "carbModifiersHe"),
        non_keto_drink_bases_en=strs("nonKetoDrinkBasesEn"),
        non_keto_drink_bases_he=strs("nonKetoDrinkBasesHe"),
        non_keto_bases_en=strs("nonKetoBasesEn"),
        non_keto_bases_he=strs("nonKetoBasesHe"),
        non_keto_base_labels_en=_str_map(root["nonKetoBaseLabelsEn"], "labelsEn"),
        non_keto_base_labels_he=_str_map(root["nonKetoBaseLabelsHe"], "labelsHe"),
        carb_only_base_labels=_str_map(root["carbOnlyBaseLabels"], "carbOnlyLabels"),
        carb_only_eligible_triggers=strs("carbOnlyEligibleTriggers"),
        carb_only_qualifiers_en=strs("carbOnlyQualifiersEn"),
        carb_only_qualifiers_he=strs("carbOnlyQualifiersHe"),
        filling_protein_triggers_en=strs("fillingProteinTriggersEn"),
        filling_protein_triggers_he=strs("fillingProteinTriggersHe"),
        seed_oil_triggers_en=strs("seedOilTriggersEn"),
        seed_oil_triggers_he=strs("seedOilTriggersHe"),
        dairy_triggers_en=strs("dairyTriggersEn"),
        dairy_triggers_he=strs("dairyTriggersHe"),
        plant_triggers_en=strs("plantTriggersEn"),
        plant_triggers_he=strs("plantTriggersHe"),
        trigger_suppresses=_strs_map(root["triggerSuppresses"], "triggerSuppresses"),
        keto_qualifier_guards_en=_guards(root["ketoQualifierGuardsEn"], "kqgEn"),
        keto_qualifier_guards_he=_guards(root["ketoQualifierGuardsHe"], "kqgHe"),
        dairy_guards_en=_guards(root["dairyGuardsEn"], "dairyGuardsEn"),
        dairy_guards_he=_guards(root["dairyGuardsHe"], "dairyGuardsHe"),
        option_removal_words_en=strs("optionRemovalWordsEn"),
        option_removal_words_he=strs("optionRemovalWordsHe"),
        no_prefix_hebrew_triggers=strs("noPrefixHebrewTriggers"),
        hebrew_trigger_pattern_example=HebrewPatternExample(
            trigger=_str(he_example["trigger"], "trigger"),
            with_prefix=_str(he_example["withPrefix"], "withPrefix"),
            without_prefix=_str(he_example["withoutPrefix"], "withoutPrefix"),
            with_inflection=_str(he_example["withInflection"], "withInflection"),
        ),
        latin_trigger_pattern_example=LatinPatternExample(
            trigger=_str(latin_example["trigger"], "trigger"),
            pattern=_str(latin_example["pattern"], "pattern"),
            case_sensitive=_bool(latin_example["caseSensitive"], "caseSensitive"),
            unicode=_bool(latin_example["unicode"], "unicode"),
        ),
        dish_kinds=DishKindWords(
            drink_category_words_en=kind_strs("drinkCategoryWordsEn"),
            drink_category_words_he=kind_strs("drinkCategoryWordsHe"),
            extra_category_words_en=kind_strs("extraCategoryWordsEn"),
            extra_category_words_he=kind_strs("extraCategoryWordsHe"),
            food_category_words_en=kind_strs("foodCategoryWordsEn"),
            food_category_words_he=kind_strs("foodCategoryWordsHe"),
            notice_category_words_en=kind_strs("noticeCategoryWordsEn"),
            notice_category_words_he=kind_strs("noticeCategoryWordsHe"),
            yellow_drink_triggers_en=kind_strs("yellowDrinkTriggersEn"),
            yellow_drink_triggers_he=kind_strs("yellowDrinkTriggersHe"),
            plain_drink_words_en=kind_strs("plainDrinkWordsEn"),
            plain_drink_words_he=kind_strs("plainDrinkWordsHe"),
            drink_name_triggers_en=kind_strs("drinkNameTriggersEn"),
            drink_name_triggers_he=kind_strs("drinkNameTriggersHe"),
            drink_name_guard_words_en=kind_strs("drinkNameGuardWordsEn"),
            drink_name_guard_words_he=kind_strs("drinkNameGuardWordsHe"),
            hebrew_prefix_allowed=HebrewPrefixAllowed(
                drink_categories=_bool(prefix["drinkCategories"], "drinkCategories"),
                extra_categories=_bool(prefix["extraCategories"], "extraCategories"),
                food_categories=_bool(prefix["foodCategories"], "foodCategories"),
                notice=_bool(prefix["notice"], "notice"),
                drink_names=_bool(prefix["drinkNames"], "drinkNames"),
                drink_name_guards=_bool(prefix["drinkNameGuards"], "drinkNameGuards"),
            ),
        ),
        templates=Templates(
            green_why_en=template("greenWhyEn"),
            green_why_he=template("greenWhyHe"),
            yellow_why_en=template("yellowWhyEn"),
            yellow_why_he=template("yellowWhyHe"),
            red_why_en=template("redWhyEn"),
            red_why_he=template("redWhyHe"),
            dietary_rule_why_en=template("dietaryRuleWhyEn"),
            dietary_rule_why_he=template("dietaryRuleWhyHe"),
            seed_oil_free_modification_en=template("seedOilFreeModificationEn"),
            seed_oil_free_modification_he=template("seedOilFreeModificationHe"),
            dairy_free_modification_en=template("dairyFreeModificationEn"),
            dairy_free_modification_he=template("dairyFreeModificationHe"),
            carnivore_only_modification_en=template("carnivoreOnlyModificationEn"),
            carnivore_only_modification_he=template("carnivoreOnlyModificationHe"),
            option_base_modification_en=template("optionBaseModificationEn"),
            option_base_modification_he=template("optionBaseModificationHe"),
        ),
        prompt=PromptText(
            prompt_verdict_definitions_template=prompt_text(
                "promptVerdictDefinitionsTemplate"
            ),
            prompt_keto_rules_template=prompt_text("promptKetoRulesTemplate"),
            seed_oil_free_prompt_fragment=prompt_text("seedOilFreePromptFragment"),
            dairy_free_prompt_fragment=prompt_text("dairyFreePromptFragment"),
            carnivore_only_prompt_fragment=prompt_text("carnivoreOnlyPromptFragment"),
            net_carb_limit_placeholder=prompt_text("netCarbLimitPlaceholder"),
            role_preamble=prompt_text("rolePreamble"),
            output_rules=prompt_text("outputRules"),
            dietary_constraints_preamble=prompt_text("dietaryConstraintsPreamble"),
            schema_name=prompt_text("schemaName"),
        ),
        caps=Caps(
            max_analysed_dishes=cap("maxAnalysedDishes"),
            max_why_length=cap("maxWhyLength"),
            max_modification_length=cap("maxModificationLength"),
            min_overlap_word_length=cap("minOverlapWordLength"),
            default_net_carb_limit_grams=cap("defaultNetCarbLimitGrams"),
            min_net_carb_limit_grams=cap("minNetCarbLimitGrams"),
            max_net_carb_limit_grams=cap("maxNetCarbLimitGrams"),
            max_hidden_carbs_per_dish=cap("maxHiddenCarbsPerDish"),
            parser_schema_version=cap("parserSchemaVersion"),
            max_scan_pages=cap("maxScanPages"),
            max_scan_page_bytes=cap("maxScanPageBytes"),
        ),
        scanned=ScannedConstants(
            scanned_category_id=_str(scanned["scannedCategoryId"], "id"),
            scanned_category_name_en=_str(scanned["scannedCategoryNameEn"], "en"),
            scanned_category_name_he=_str(scanned["scannedCategoryNameHe"], "he"),
            scanned_dish_id_prefix=_str(scanned["scannedDishIdPrefix"], "prefix"),
            scanned_menu_currency=_str(scanned["scannedMenuCurrency"], "currency"),
        ),
        pasted=PastedConstants(
            pasted_header_max_words=_int(
                pasted["pastedHeaderMaxWords"], "pastedHeaderMaxWords"
            ),
            pasted_price_suffix=RegexSource(
                pattern=_str(suffix["pattern"], "pattern"),
                case_sensitive=_bool(suffix["caseSensitive"], "caseSensitive"),
                unicode=_bool(suffix["unicode"], "unicode"),
            ),
        ),
        website=WebsiteConstants(
            website_category_name_en=_str(website["websiteCategoryNameEn"], "en"),
            website_category_name_he=_str(website["websiteCategoryNameHe"], "he"),
            menu_words=_strs(website["menuWords"], "menuWords"),
            min_priced_lines=_int(website["minPricedLines"], "minPricedLines"),
            js_only_text_chars=_int(website["jsOnlyTextChars"], "jsOnlyTextChars"),
            js_only_noscript_text_chars=_int(
                website["jsOnlyNoscriptTextChars"], "jsOnlyNoscriptTextChars"
            ),
        ),
        keto_score_weights=KetoScoreWeights(
            yellow=_float(weights["yellow"], "yellow"),
            hidden_carb_yellow=_float(weights["hiddenCarbYellow"], "hiddenCarbYellow"),
        ),
    )


@cache
def vocabulary() -> Vocabulary:
    """The packaged vocabulary, parsed once and shared."""
    return parse_vocabulary(json.loads(VOCABULARY_PATH.read_text(encoding="utf-8")))

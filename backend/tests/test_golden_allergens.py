"""``app.keto.allergens`` replays the golden ``allergens.json`` (ALG-01, #343).

The packaged ``app/keto/allergens.json`` must be the golden file byte for
byte; the taxonomy must load; every vocabulary term must normalise and
compile to the pattern source Dart wrote; and every ``matcherCases`` and
``fixture`` entry must replay to exactly the Dart hits — the fixture
vocabulary pins the matcher's rules before the real vocabulary is filled.
"""

import json
from pathlib import Path
from typing import Any

import pytest

from app.keto.allergens import (
    ALLERGENS_PATH,
    AllergenGuards,
    AllergenHit,
    RestrictionVocabulary,
    allergens,
    dish_match_text,
    find,
    find_in_dish,
    find_in_dish_with,
    find_with,
    match_text,
    parse_allergens,
    parse_restriction_vocabularies,
)
from app.keto.models import Dish, DishOption
from app.keto.normaliser import dish_rules_text, normalise
from app.keto.patterns import hebrew_trigger_source, latin_trigger_source

_GOLDEN = Path(__file__).parent / "fixtures" / "golden" / "allergens.json"
_RAW: dict[str, Any] = json.loads(_GOLDEN.read_text(encoding="utf-8"))
_CASES: dict[str, Any] = _RAW["matcherCases"]
_FIXTURE_CASES: dict[str, Any] = _RAW["fixture"]["cases"]
_FIXTURE = parse_restriction_vocabularies(_RAW["fixture"]["vocabulary"])

_IDS = [
    "peanuts",
    "treeNuts",
    "milk",
    "lactose",
    "eggs",
    "soy",
    "wheat",
    "gluten",
    "fish",
    "crustaceans",
    "molluscs",
    "sesame",
    "celery",
    "mustard",
    "lupin",
    "sulphites",
    "legumes",
    "alphaGal",
    "fodmap",
    "histamine",
    "vegan",
    "vegetarian",
    "glp1",
    "kosher",
    "halal",
    "buckwheat",
    "kiwi",
    "peach",
    "apple",
    "banana",
    "orange",
    "beef",
    "pork",
    "chicken",
    "gelatin",
    "yam",
    "corn",
    "sunflower",
    "flax",
    "chickpea",
    "lentil",
    "pea",
    "fenugreek",
    "fava",
    "nightshades",
    "msg",
    "caffeine",
    "salicylates",
    "oralAllergy",
    "pescatarian",
    "paleo",
    "whole30",
    "aip",
    "jain",
    "keto",
    "custom",
]


def _dish(raw: dict[str, Any]) -> Dish:
    """The golden dish, built as the Dart exporter built it."""
    return Dish.model_construct(
        id=raw["id"],
        name=raw["name"],
        description=raw["description"],
        price=raw["price"],
        options=[
            DishOption.model_construct(name=option["name"], values=option["values"])
            for option in raw["options"]
        ],
        image_url=raw["imageUrl"],
        page=raw["page"],
    )


def _record(hits: list[AllergenHit]) -> list[dict[str, Any]]:
    return [
        {
            "id": hit.id,
            "term": hit.term,
            "certainty": hit.certainty,
            "start": hit.start,
            "end": hit.end,
            "guarded": hit.guarded,
        }
        for hit in hits
    ]


# --- the file and the taxonomy -------------------------------------------------


def test_the_packaged_allergens_file_is_the_golden_file_byte_for_byte() -> None:
    assert ALLERGENS_PATH.read_bytes() == _GOLDEN.read_bytes()


def test_the_golden_has_every_section() -> None:
    assert set(_RAW) == {
        "taxonomy",
        "kinds",
        "jurisdictions",
        "certainties",
        "vocabulary",
        "meatWithDairy",
        "matcherCases",
        "fixture",
    }


def test_the_taxonomy_loads_with_every_id_in_order() -> None:
    loaded = allergens()
    assert [entry.id for entry in loaded.taxonomy] == _IDS
    assert set(loaded.vocabulary) == set(_IDS)
    assert loaded.certainties == ("stated", "likely", "suspected")
    assert loaded.jurisdictions == ("us", "eu", "uk", "ca", "anz", "jp", "il")


def test_strictness_is_derived_from_the_kind() -> None:
    loaded = allergens()
    assert loaded.strict_kinds == {"allergen", "autoimmune", "medical"}
    by_id = {entry.id: entry for entry in loaded.taxonomy}
    assert by_id["gluten"].kind == "autoimmune" and by_id["gluten"].is_strict
    assert by_id["lactose"].kind == "intolerance" and not by_id["lactose"].is_strict
    assert not by_id["keto"].is_strict
    assert by_id["fava"].kind == "medical" and by_id["fava"].is_strict
    assert by_id["nightshades"].kind == "intolerance"
    assert not by_id["nightshades"].is_strict
    assert by_id["buckwheat"].jurisdictions == ("jp",)
    assert {"us", "eu"} <= set(by_id["sesame"].jurisdictions)


def test_every_taxonomy_value_round_trips() -> None:
    loaded = allergens()
    assert [
        {
            "id": entry.id,
            "kind": entry.kind,
            "isStrict": entry.is_strict,
            "jurisdictions": list(entry.jurisdictions),
            "nameEn": entry.name_en,
            "nameHe": entry.name_he,
            "source": entry.source,
        }
        for entry in loaded.taxonomy
    ] == _RAW["taxonomy"]


def test_a_strictness_that_disagrees_with_the_kind_is_refused() -> None:
    broken = json.loads(json.dumps(_RAW))
    broken["taxonomy"][0]["isStrict"] = False
    with pytest.raises(ValueError, match="strictness"):
        parse_allergens(broken)


@pytest.mark.parametrize(
    ("mutate", "message"),
    [
        (lambda raw: raw.update(taxonomy={}), "expected a list"),
        (lambda raw: raw.update(vocabulary=[]), "expected an object"),
        (lambda raw: raw["taxonomy"][0].update(id=1), "expected a string"),
        (lambda raw: raw["kinds"][0].update(isStrict="yes"), "expected a boolean"),
    ],
)
def test_a_malformed_file_is_refused(mutate: Any, message: str) -> None:
    broken = json.loads(json.dumps(_RAW))
    mutate(broken)
    with pytest.raises(ValueError, match=message):
        parse_allergens(broken)


# --- the vocabulary -------------------------------------------------------------


def _vocabulary_terms() -> list[tuple[str, str, dict[str, Any], bool, list[str]]]:
    rows: list[tuple[str, str, dict[str, Any], bool, list[str]]] = []
    for section, registry in (
        ("registry", _RAW["vocabulary"]),
        ("fixture", _RAW["fixture"]["vocabulary"]),
    ):
        for rid, entry in registry.items():
            for key, hebrew in (
                ("directEn", False),
                ("directHe", True),
                ("hiddenEn", False),
                ("hiddenHe", True),
            ):
                for term in entry[key]:
                    rows.append((section, rid, term, hebrew, entry["noPrefixHe"]))
    return rows


_TERMS = _vocabulary_terms()


def test_the_fixture_vocabulary_has_terms_to_check() -> None:
    assert any(section == "fixture" for section, *_ in _TERMS)


@pytest.mark.parametrize(
    ("section", "rid", "term", "hebrew", "no_prefix"),
    _TERMS,
    ids=[f"{row[0]}:{row[1]}:{row[2]['term']}" for row in _TERMS],
)
def test_every_term_normalises_and_compiles_as_dart_did(
    section: str, rid: str, term: dict[str, Any], hebrew: bool, no_prefix: list[str]
) -> None:
    normalised = match_text(term["term"])
    assert normalised == term["normalised"]
    if not normalised:
        assert term["pattern"] is None
    elif hebrew:
        assert term["pattern"] == hebrew_trigger_source(
            normalised, allow_prefix=term["term"] not in no_prefix
        )
    else:
        assert term["pattern"] == latin_trigger_source(normalised)


def test_the_fixture_vocabulary_loads_every_field() -> None:
    wheat = _FIXTURE["wheat"]
    assert wheat.no_prefix_he == ("חיטה",)
    assert wheat.hidden_en[0].term == "soy sauce"
    assert wheat.hidden_en[0].certainty == "likely"
    assert wheat.guards.before_en == ("gluten free",)
    assert wheat.term_guards["flour"].before_en == ("rice",)
    assert _FIXTURE["sesame"].sources == ("11 §11", "12 §1.1")
    assert _FIXTURE["sesame"].term_guards == {}


# --- the matcher, replayed ------------------------------------------------------


def _text_ids(cases: list[dict[str, Any]]) -> list[str]:
    return [f"{index}:{case['text']}" for index, case in enumerate(cases)]


@pytest.mark.parametrize("case", _CASES["texts"], ids=_text_ids(_CASES["texts"]))
def test_every_registry_text_replays(case: dict[str, Any]) -> None:
    assert normalise(case["text"]) == case["normalised"]
    assert match_text(case["text"]) == case["matchText"]
    assert _record(find(case["text"])) == case["hits"]


@pytest.mark.parametrize("case", _CASES["dishes"])
def test_every_registry_dish_replays(case: dict[str, Any]) -> None:
    dish = _dish(case["dish"])
    assert dish_rules_text(dish) == case["rulesText"]
    assert dish_match_text(dish) == case["matchText"]
    assert _record(find_in_dish(dish)) == case["hits"]


@pytest.mark.parametrize(
    "case", _FIXTURE_CASES["texts"], ids=_text_ids(_FIXTURE_CASES["texts"])
)
def test_every_fixture_text_replays(case: dict[str, Any]) -> None:
    assert normalise(case["text"]) == case["normalised"]
    assert match_text(case["text"]) == case["matchText"]
    assert _record(find_with(case["text"], _FIXTURE)) == case["hits"]


@pytest.mark.parametrize("case", _FIXTURE_CASES["dishes"])
def test_every_fixture_dish_replays(case: dict[str, Any]) -> None:
    dish = _dish(case["dish"])
    assert dish_rules_text(dish) == case["rulesText"]
    assert dish_match_text(dish) == case["matchText"]
    assert _record(find_in_dish_with(dish, _FIXTURE)) == case["hits"]


def test_the_fixture_cases_find_something() -> None:
    assert sum(len(case["hits"]) for case in _FIXTURE_CASES["texts"]) > 0


def test_the_fixture_cases_hold_guarded_hits_and_maqaf_texts() -> None:
    hits = [hit for case in _FIXTURE_CASES["texts"] for hit in case["hits"]]
    assert any(hit["guarded"] for hit in hits)
    assert all(hit["certainty"] == "suspected" for hit in hits if hit["guarded"])
    assert any(
        case["matchText"] != case["normalised"] for case in _FIXTURE_CASES["texts"]
    )


# --- the matcher, directly ------------------------------------------------------

_SESAME = RestrictionVocabulary(
    direct_en=("sesame",),
    direct_he=("טחינה",),
    guards=AllergenGuards(after_en=("free",), before_he=("ללא",)),
)


def _found(text: str, vocab: dict[str, RestrictionVocabulary]) -> list[str]:
    return [
        f"{hit.id}:{hit.term}:{hit.certainty}{':guarded' if hit.guarded else ''}"
        for hit in find_with(text, vocab)
    ]


def test_a_guard_lowers_a_hit_in_its_own_language_only() -> None:
    vocab = {"sesame": _SESAME}
    assert _found("sesame-free bun", vocab) == ["sesame:sesame:suspected:guarded"]
    assert _found("חומוס ללא טחינה", vocab) == ["sesame:טחינה:suspected:guarded"]
    assert _found("טחינה free", vocab) == ["sesame:טחינה:stated"]


_ADJACENT = {
    "sesame": RestrictionVocabulary(
        direct_en=("sesame", "tahini"),
        direct_he=("שומשום", "טחינה"),
        guards=AllergenGuards(
            before_en=("no",), after_en=("free",), before_he=("ללא",)
        ),
    ),
    "milk": RestrictionVocabulary(
        direct_en=("milk",),
        direct_he=("חלב",),
        guards=AllergenGuards(before_en=("dairy free",), after_he=("שקדים",)),
        term_guards={"milk": AllergenGuards(before_en=("coconut",))},
    ),
    "treeNuts": RestrictionVocabulary(direct_en=("almond milk",)),
    "wheat": RestrictionVocabulary(
        direct_en=("flour",),
        term_guards={"flour": AllergenGuards(before_en=("rice",))},
    ),
    "peanuts": RestrictionVocabulary(direct_he=("חמאת בוטנים",)),
}


@pytest.mark.parametrize(
    ("text", "expected"),
    [
        # A guard lowers, never cancels.
        ("Hummus, no tahini", ["sesame:tahini:suspected:guarded"]),
        ("dairy-free milk", ["milk:milk:suspected:guarded"]),
        # Only the adjacent slot counts.
        (
            "no sesame or tahini",
            ["sesame:sesame:suspected:guarded", "sesame:tahini:stated"],
        ),
        ("no big tahini", ["sesame:tahini:stated"]),
        ("tahini big free", ["sesame:tahini:stated"]),
        (
            "sesame free tahini",
            ["sesame:sesame:suspected:guarded", "sesame:tahini:stated"],
        ),
        ("dairy big free milk", ["milk:milk:stated"]),
        # Hebrew prefix letters on the guard.
        ("חומוס וללא טחינה", ["sesame:טחינה:suspected:guarded"]),
        ("חומוס אללא טחינה", ["sesame:טחינה:stated"]),
        ("חלב השקדים", ["milk:חלב:suspected:guarded"]),
        ("חלב ושקדים", ["milk:חלב:stated"]),
        # Per-term guards.
        ("rice flour bun", ["wheat:flour:suspected:guarded"]),
        ("coconut milk", ["milk:milk:suspected:guarded"]),
        (
            "almond milk",
            ["treeNuts:almond milk:stated", "milk:milk:stated"],
        ),
        # The maqaf joins words.
        ("חמאת־בוטנים", ["peanuts:חמאת בוטנים:stated"]),
        ("טחינה־ללא", ["sesame:טחינה:stated"]),
    ],
)
def test_the_alg_04a_rules(text: str, expected: list[str]) -> None:
    assert _found(text, _ADJACENT) == expected


def test_a_term_guard_applies_to_its_own_term_only() -> None:
    vocab = {
        "milk": RestrictionVocabulary(
            direct_en=("milk", "cream"),
            term_guards={"milk": AllergenGuards(before_en=("coconut",))},
        )
    }
    assert _found("coconut cream", vocab) == ["milk:cream:stated"]


def test_the_maqaf_is_a_space_only_for_the_allergen_matcher() -> None:
    assert normalise("חמאת־בוטנים") == "חמאתבוטנימ"
    assert match_text("חמאת־בוטנים") == "חמאת בוטנימ"
    assert len(match_text("a־b")) == len("a b")


def test_offsets_are_utf16_units_of_the_normalised_text() -> None:
    # An astral character before the trigger is one code point but two
    # UTF-16 units, so the Dart offset is one more than the Python one.
    hits = find_with("\U0001d400 sesame", {"sesame": _SESAME})
    normalised = normalise("\U0001d400 sesame")
    assert normalised.index("sesame") == 2
    assert [(hit.start, hit.end) for hit in hits] == [(3, 9)]


def test_a_vocabulary_without_the_id_or_with_an_empty_term_finds_nothing() -> None:
    assert find_with("sesame", {}) == []
    assert find_with("!!", {"mustard": RestrictionVocabulary(direct_en=("!!",))}) == []
    assert find_with("", {"sesame": _SESAME}) == []


def test_find_in_dish_reads_a_maqaf_as_a_space() -> None:
    dish = Dish(
        id="d",
        name="טוסט",
        price=10,
        options=[DishOption(name="שינויים", values=["ללא־טחינה", "שומשום"])],
    )
    hits = find_in_dish_with(dish, {"sesame": _SESAME})
    assert hits == []
    assert dish_match_text(dish) == "טוסט שינויימ שומשומ"


def test_find_in_dish_skips_a_removal_value() -> None:
    dish = Dish(
        id="d",
        name="Hummus",
        price=10,
        options=[DishOption(name="Changes", values=["No sesame", "Add sesame"])],
    )
    hits = find_in_dish_with(dish, {"sesame": _SESAME})
    assert len(hits) == 1
    assert dish_rules_text(dish)[hits[0].start : hits[0].end] == "sesame"

"""Tests for Banto's wire additions to ``app.keto.models`` (D26 W2-0, #345).

The Python twin of ``test/models/concern_test.dart`` and the W2-0 groups of
``test/models/analysis_test.dart``: ``Concern`` and ``ExtractedIngredient``
read tolerantly and round-trip, and ``AnalysedDish.ingredients``/``concerns``
and ``AnalysisOptionsSnapshot.restrictionsRequested`` are written only when
non-empty or true (C2, C3), so a keto analysis is the same bytes as before.
"""

import json
from typing import Any, get_args

import pytest
from pydantic import ValidationError

from app.keto.allergens import allergens
from app.keto.models import (
    AnalysedDish,
    AnalysisOptionsSnapshot,
    Certainty,
    ComponentRole,
    Concern,
    ConcernSource,
    EvidenceTier,
    ExtractedIngredient,
    RestrictionIdName,
    to_json,
)


def _dart_encode(value: Any) -> str:
    """``value`` as Dart's ``jsonEncode`` writes it: compact, UTF-8 as-is."""
    return json.dumps(value, separators=(",", ":"), ensure_ascii=False)


_KETO_DISH = (
    '{"dishId":"d1","name":"Salad with tahini","verdict":"orderAsIs",'
    '"why":"Greens and tahini","modification":null,"netCarbsEstimate":null,'
    '"hiddenCarbs":[]}'
)
_INGREDIENT: dict[str, Any] = {"name": "tahini", "certainty": "stated", "role": "sauce"}
_CONCERN: dict[str, Any] = {
    "restrictionId": "sesame",
    "source": "description",
    "certainty": "stated",
    "tier": "stated",
    "matchedText": "טחינה",
    "waiterQuestion": None,
}


def _dish(**overrides: Any) -> dict[str, Any]:
    raw: dict[str, Any] = json.loads(_KETO_DISH)
    raw.update(overrides)
    return raw


# --- the enums -------------------------------------------------------------------


def test_the_enum_names_are_pinned_in_dart_order() -> None:
    assert get_args(ConcernSource) == (
        "name",
        "description",
        "option",
        "hidden",
        "model",
        "kitchen",
        "matrix",
    )
    assert get_args(Certainty) == ("stated", "likely", "suspected")
    assert get_args(EvidenceTier) == (
        "declared",
        "stated",
        "inferred",
        "suspected",
        "confirmed",
        "denied",
    )
    assert get_args(ComponentRole) == (
        "base",
        "protein",
        "side",
        "sauce",
        "garnish",
        "option",
        "unknown",
    )


def test_restriction_ids_and_certainties_match_the_allergens_golden() -> None:
    golden = allergens()
    assert get_args(RestrictionIdName) == tuple(r.id for r in golden.taxonomy)
    assert get_args(Certainty) == golden.certainties


# --- Concern ---------------------------------------------------------------------


def test_a_concern_round_trips_byte_for_byte_with_every_key() -> None:
    text = _dart_encode(_CONCERN)
    assert _dart_encode(to_json(Concern.model_validate(json.loads(text)))) == text


@pytest.mark.parametrize("key", ["restrictionId", "source", "certainty", "tier"])
def test_a_concern_with_a_missing_or_unknown_enum_is_refused(key: str) -> None:
    missing = dict(_CONCERN)
    del missing[key]
    for raw in (missing, {**_CONCERN, key: "zzz"}, {**_CONCERN, key: 1}):
        with pytest.raises(ValidationError):
            Concern.model_validate(raw)


@pytest.mark.parametrize("value", [None, 3, ""])
def test_a_concern_reads_malformed_optional_text_as_null(value: object) -> None:
    concern = Concern.model_validate(
        {**_CONCERN, "matchedText": value, "waiterQuestion": value}
    )
    assert (concern.matched_text, concern.waiter_question) == (None, None)
    absent = dict(_CONCERN)
    del absent["matchedText"]
    del absent["waiterQuestion"]
    assert Concern.model_validate(absent).matched_text is None


# --- ExtractedIngredient ---------------------------------------------------------


def test_an_ingredient_round_trips_byte_for_byte() -> None:
    text = _dart_encode(_INGREDIENT)
    model = ExtractedIngredient.model_validate(json.loads(text))
    assert _dart_encode(to_json(model)) == text


@pytest.mark.parametrize("value", [None, 3, "", "  "])
def test_an_ingredient_without_a_name_is_refused(value: object) -> None:
    with pytest.raises(ValidationError):
        ExtractedIngredient.model_validate({**_INGREDIENT, "name": value})


@pytest.mark.parametrize("value", [None, "certain", 2])
def test_an_ingredient_with_an_unknown_certainty_is_refused(value: object) -> None:
    with pytest.raises(ValidationError):
        ExtractedIngredient.model_validate({**_INGREDIENT, "certainty": value})


@pytest.mark.parametrize("value", [None, "topping", 5])
def test_an_unknown_or_missing_role_reads_as_unknown(value: object) -> None:
    raw = {**_INGREDIENT, "role": value}
    assert ExtractedIngredient.model_validate(raw).role == "unknown"
    absent = dict(_INGREDIENT)
    del absent["role"]
    assert ExtractedIngredient.model_validate(absent).role == "unknown"


# --- AnalysedDish ----------------------------------------------------------------


def test_a_keto_dish_writes_no_ingredients_or_concerns() -> None:
    dish = AnalysedDish.model_validate(json.loads(_KETO_DISH))
    assert (dish.ingredients, dish.concerns) == ([], [])
    assert _dart_encode(to_json(dish)) == _KETO_DISH
    assert "ingredients" not in dish.model_dump()


def test_a_banto_dish_writes_both_after_hidden_carbs_and_round_trips() -> None:
    text = _dart_encode(_dish(ingredients=[_INGREDIENT], concerns=[_CONCERN]))
    dish = AnalysedDish.model_validate(json.loads(text))
    written = to_json(dish)
    assert list(written)[7:] == ["ingredients", "concerns"]
    assert _dart_encode(written) == text


def test_only_the_non_empty_list_is_written() -> None:
    written = to_json(AnalysedDish.model_validate(_dish(concerns=[_CONCERN])))
    assert "ingredients" not in written
    assert written["concerns"] == [_CONCERN]


@pytest.mark.parametrize("value", [None, "tahini", 3, {}])
def test_a_null_or_non_list_reads_as_empty(value: object) -> None:
    dish = AnalysedDish.model_validate(_dish(ingredients=value, concerns=value))
    assert (dish.ingredients, dish.concerns) == ([], [])


def test_malformed_and_unknown_entries_are_dropped() -> None:
    dish = AnalysedDish.model_validate(
        _dish(
            ingredients=[
                "tahini",
                {"name": "tahini", "certainty": "certain"},
                _INGREDIENT,
                ExtractedIngredient.model_validate(_INGREDIENT),
            ],
            concerns=[7, {**_CONCERN, "restrictionId": "kiwi"}, _CONCERN],
        )
    )
    assert [to_json(i) for i in dish.ingredients] == [_INGREDIENT, _INGREDIENT]
    assert [to_json(c) for c in dish.concerns] == [_CONCERN]


# --- AnalysisOptionsSnapshot -----------------------------------------------------


def test_a_keto_snapshot_writes_no_restrictions_key() -> None:
    text = '{"netCarbLimitGrams":6,"dietaryConstraints":["dairy-free"]}'
    snapshot = AnalysisOptionsSnapshot.model_validate(json.loads(text))
    assert snapshot.restrictions_requested is False
    assert _dart_encode(to_json(snapshot)) == text
    assert "restrictions_requested" not in snapshot.model_dump()


def test_a_snapshot_with_restrictions_writes_true_and_round_trips() -> None:
    text = (
        '{"netCarbLimitGrams":6,"dietaryConstraints":[],"restrictionsRequested":true}'
    )
    snapshot = AnalysisOptionsSnapshot.model_validate(json.loads(text))
    assert snapshot.restrictions_requested is True
    assert _dart_encode(to_json(snapshot)) == text
    assert snapshot != AnalysisOptionsSnapshot(net_carb_limit_grams=6)


@pytest.mark.parametrize("value", [None, False, "true", 1])
def test_anything_but_true_reads_as_false(value: object) -> None:
    snapshot = AnalysisOptionsSnapshot.model_validate(
        {"netCarbLimitGrams": 6, "restrictionsRequested": value}
    )
    assert snapshot == AnalysisOptionsSnapshot(net_carb_limit_grams=6)

"""``app.keto.kitchen_signals`` replays the golden ``kitchen_signals.json``
(ALG-07, #349).

``vocabulary`` pins the Python term lists, guards, threat table and questions
equal to Dart's; ``cases`` replays every menu to exactly the Dart signals
under ``fixtureVocabulary``, a small nuts, sesame and seafood vocabulary the
golden carries so it does not move when the real allergen vocabulary does.
"""

import json
from pathlib import Path
from typing import Any

import pytest

from app.keto import kitchen_signals as ks
from app.keto.allergens import parse_restriction_vocabularies
from app.keto.kitchen_signals import (
    KitchenSignalKind,
    kitchen_signals,
    kitchen_signals_with,
)
from app.keto.models import Menu

_GOLDEN = Path(__file__).parent / "fixtures" / "golden" / "kitchen_signals.json"
_RAW: dict[str, Any] = json.loads(_GOLDEN.read_text(encoding="utf-8"))
_VOCABULARY: dict[str, Any] = _RAW["vocabulary"]
_FIXTURE = parse_restriction_vocabularies(_RAW["fixtureVocabulary"])
_CASES: list[dict[str, Any]] = _RAW["cases"]


def _guards(table: dict[str, Any]) -> dict[str, Any]:
    return {
        key: {"before": list(value.before), "after": list(value.after)}
        for key, value in table.items()
    }


def test_the_golden_has_the_expected_sections() -> None:
    assert set(_RAW) == {"vocabulary", "fixtureVocabulary", "cases"}
    assert len({case["name"] for case in _CASES}) == len(_CASES)


def test_the_term_lists_are_the_dart_ones() -> None:
    assert list(ks.FRIED_EN) == _VOCABULARY["friedEn"]
    assert list(ks.FRIED_HE) == _VOCABULARY["friedHe"]
    assert _guards(ks.FRIED_GUARDS_EN) == _VOCABULARY["friedGuardsEn"]
    assert _guards(ks.FRIED_GUARDS_HE) == _VOCABULARY["friedGuardsHe"]
    assert list(ks.WOK_EN) == _VOCABULARY["wokEn"]
    assert list(ks.WOK_HE) == _VOCABULARY["wokHe"]
    assert _guards(ks.WOK_GUARDS_HE) == _VOCABULARY["wokGuardsHe"]
    assert list(ks.GRILL_EN) == _VOCABULARY["grillEn"]
    assert list(ks.GRILL_HE) == _VOCABULARY["grillHe"]
    assert list(ks.MEAT_EN) == _VOCABULARY["meatEn"]
    assert list(ks.MEAT_HE) == _VOCABULARY["meatHe"]
    assert _guards(ks.MEAT_GUARDS_EN) == _VOCABULARY["meatGuardsEn"]
    assert _guards(ks.MEAT_GUARDS_HE) == _VOCABULARY["meatGuardsHe"]
    assert list(ks.BAKERY_EN) == _VOCABULARY["bakeryEn"]
    assert list(ks.BAKERY_HE) == _VOCABULARY["bakeryHe"]
    assert sorted(ks.NO_PREFIX_HE) == sorted(_VOCABULARY["noPrefixHe"])
    assert ks.EVIDENCE_CAP == _VOCABULARY["evidenceCap"]
    assert list(ks.FRYER_BASE) == _VOCABULARY["fryerBase"]


def test_the_threat_table_and_questions_are_the_dart_ones() -> None:
    assert {kind.value: list(ids) for kind, ids in ks.THREATENS.items()} == (
        _VOCABULARY["threatens"]
    )
    assert {
        kind.value: {"en": en, "he": he} for kind, (en, he) in ks.QUESTIONS.items()
    } == _VOCABULARY["questions"]


@pytest.mark.parametrize("case", _CASES, ids=[case["name"] for case in _CASES])
def test_every_golden_menu_has_the_dart_signals(case: dict[str, Any]) -> None:
    menu = Menu.model_validate(case["menu"])
    signals = kitchen_signals_with(menu, _FIXTURE)
    assert [signal.to_json() for signal in signals] == case["signals"]


def test_every_kind_is_exercised() -> None:
    seen = {s["kind"] for case in _CASES for s in case["signals"]}
    assert seen == {kind.value for kind in KitchenSignalKind}


def test_signals_come_in_kind_order() -> None:
    order = [kind.value for kind in KitchenSignalKind]
    for case in _CASES:
        kinds = [s["kind"] for s in case["signals"]]
        assert kinds == sorted(kinds, key=order.index)


def test_evidence_is_capped_and_distinct() -> None:
    for case in _CASES:
        for signal in case["signals"]:
            assert 1 <= len(signal["evidence"]) <= ks.EVIDENCE_CAP
            assert len(set(signal["evidence"])) == len(signal["evidence"])


def test_the_packaged_vocabulary_runs_without_error() -> None:
    # The real vocabulary may be empty or full; this pins only that the
    # public entry point answers for every golden menu.
    for case in _CASES:
        assert isinstance(kitchen_signals(Menu.model_validate(case["menu"])), list)

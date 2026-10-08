"""``app.keto.score`` replays the golden ``score.json`` (#322, D13, D21).

``formula`` records ``ketoScore`` over a grid of counts (and a few large
ones); ``menus`` records ``VerdictCounts.of`` (food only) and its score for
each named menu and analysis.
"""

import json
from pathlib import Path
from typing import Any

import pytest

from app.keto.models import Menu, MenuAnalysed
from app.keto.score import VerdictCounts, dart_to_fixed_1, keto_score

_GOLDEN = Path(__file__).parent / "fixtures" / "golden" / "score.json"
_RAW: dict[str, Any] = json.loads(_GOLDEN.read_text(encoding="utf-8"))
_FORMULA: list[dict[str, Any]] = _RAW["formula"]
_MENUS: list[dict[str, Any]] = _RAW["menus"]
_COUNT_KEYS = {"green", "yellow", "hiddenCarbYellow", "red", "score"}


def _formula_id(entry: dict[str, Any]) -> str:
    return (
        f"g{entry['green']}-y{entry['yellow']}-h{entry['hiddenCarbYellow']}"
        f"-r{entry['red']}"
    )


@pytest.mark.parametrize("entry", _FORMULA, ids=[_formula_id(e) for e in _FORMULA])
def test_every_golden_count_scores_as_dart_does(entry: dict[str, Any]) -> None:
    assert set(entry) == _COUNT_KEYS
    score = keto_score(
        green_count=entry["green"],
        hidden_carb_yellow_count=entry["hiddenCarbYellow"],
        other_yellow_count=entry["yellow"] - entry["hiddenCarbYellow"],
        red_count=entry["red"],
    )
    assert score == entry["score"]
    assert type(score) is type(entry["score"])


@pytest.mark.parametrize("entry", _MENUS, ids=[entry["name"] for entry in _MENUS])
def test_every_golden_analysis_counts_food_as_dart_does(
    entry: dict[str, Any],
) -> None:
    assert set(entry) == {"name", "menu", "analysis", "counts"}
    counts = VerdictCounts.of(
        Menu.model_validate(entry["menu"]),
        MenuAnalysed.model_validate(entry["analysis"]),
    )
    assert set(entry["counts"]) == _COUNT_KEYS
    assert {
        "green": counts.green,
        "yellow": counts.yellow,
        "hiddenCarbYellow": counts.hidden_carb_yellow,
        "red": counts.red,
        "score": counts.score,
    } == entry["counts"]
    assert counts.total == counts.green + counts.yellow + counts.red


def test_the_corpus_holds_ties_python_round_would_get_wrong() -> None:
    # 1.25 and 6.25 are exact doubles: Dart's toStringAsFixed(1) rounds them
    # up, Python's round() to even. The corpus must keep such a case.
    ties = [entry for entry in _FORMULA if entry["score"] in (1.3, 6.3)]
    assert any(round(entry["score"] - 0.05, 1) != entry["score"] for entry in ties)
    assert len(_MENUS) >= 30


@pytest.mark.parametrize(
    ("value", "fixed"),
    [
        (1.25, 1.3),
        (6.25, 6.3),
        (0.15, 0.1),  # really 0.1499999…: no tie, rounds down as in Dart
        (0.05, 0.1),  # really 0.05000000000000000277: rounds up
        (9.95, 9.9),  # really 9.9499999…
        (10.0, 10.0),
        (0.0, 0.0),
    ],
)
def test_dart_to_fixed_1_rounds_the_exact_binary_value(
    value: float, fixed: float
) -> None:
    assert dart_to_fixed_1(value) == fixed


def test_no_placed_dish_scores_none_never_zero() -> None:
    assert VerdictCounts.ZERO.score is None
    assert VerdictCounts.ZERO.total == 0
    assert (
        keto_score(
            green_count=0, hidden_carb_yellow_count=0, other_yellow_count=0, red_count=1
        )
        == 0.0
    )


def test_hidden_carb_yellows_are_yellows() -> None:
    with pytest.raises(ValueError):
        VerdictCounts(green=0, yellow=1, hidden_carb_yellow=2, red=0)
    counts = VerdictCounts(green=1, yellow=3, hidden_carb_yellow=1, red=0)
    assert counts.other_yellow == 2

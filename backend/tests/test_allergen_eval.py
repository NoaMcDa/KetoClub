"""The pure scoring behind ``tools/allergen_eval.py`` (ALG-10).

No network and no model: these tests feed the scoring functions hand-made
findings, labels and model replies.
"""

import json
from datetime import UTC, datetime
from typing import Any

import pytest

from app.keto.models import Menu
from tools import allergen_eval as ev


def _dish(
    name: str,
    labels: dict[str, str],
    *,
    description: str = "",
    options: tuple[tuple[str, tuple[str, ...]], ...] = (),
    menu: str = "m.json",
    index: int = 0,
) -> ev.CorpusDish:
    return ev.CorpusDish(
        menu=menu,
        index=index,
        name=name,
        description=description,
        options=options,
        labels={
            restriction_id: {"label": label, "evidence": "x", "source": "11 §0"}
            for restriction_id, label in labels.items()
        },
    )


def test_surer_prefers_the_stronger_certainty_and_treats_none_as_weakest() -> None:
    assert ev.surer("stated", "likely") == "stated"
    assert ev.surer("suspected", "likely") == "likely"
    assert ev.surer("likely", "likely") == "likely"
    assert ev.surer(None, "suspected") == "suspected"
    assert ev.surer("stated", None) == "stated"
    assert ev.surer(None, None) is None


def test_weaker_prefers_the_weaker_certainty() -> None:
    assert ev.weaker("stated", "likely") == "likely"
    assert ev.weaker("suspected", "stated") == "suspected"
    assert ev.weaker("likely", "likely") == "likely"


@pytest.mark.parametrize(
    ("found", "label", "expected"),
    [
        ("stated", "contains", True),
        ("likely", "contains", True),
        ("suspected", "contains", False),
        (None, "contains", False),
        ("stated", "may_contain", True),
        ("likely", "may_contain", True),
        ("suspected", "may_contain", True),
        (None, "may_contain", False),
    ],
)
def test_meets_holds_contains_to_likely_and_may_contain_to_suspected(
    found: str | None, label: str, expected: bool
) -> None:
    assert ev.meets(found, label) is expected


def test_merge_keeps_the_surest_certainty_per_restriction() -> None:
    merged = ev.merge(
        {"sesame": "suspected", "milk": "stated"},
        {"sesame": "likely", "eggs": "suspected"},
        {},
    )
    assert merged == {"sesame": "likely", "milk": "stated", "eggs": "suspected"}


def test_rules_findings_reads_the_dish_text() -> None:
    dish = _dish("Hummus with tahini", {}).to_dish()
    assert ev.rules_findings(dish)["sesame"] in {"stated", "likely"}


def test_model_findings_runs_the_matcher_on_ingredient_names() -> None:
    found = ev.model_findings(
        [
            {"name": "tahini", "certainty": "stated", "role": "sauce"},
            {"name": "butter", "certainty": "suspected", "role": "base"},
        ]
    )
    assert found["sesame"] == "stated"
    assert found["milk"] == "suspected"


def test_model_findings_cuts_a_hit_to_the_ingredients_certainty() -> None:
    found = ev.model_findings([{"name": "tahini", "certainty": "suspected"}])
    assert found == {"sesame": "suspected"}


def test_model_findings_skips_anything_malformed() -> None:
    assert ev.model_findings(None) == {}
    assert ev.model_findings("tahini") == {}
    assert (
        ev.model_findings(
            [
                "tahini",
                {"name": 7, "certainty": "stated"},
                {"name": "tahini", "certainty": "certain"},
                {"name": "tahini"},
            ]
        )
        == {}
    )


def test_find_misses_lists_only_strict_labels_the_findings_do_not_meet() -> None:
    dishes = [
        _dish(
            "A",
            {
                "sesame": "contains",
                "milk": "may_contain",
                "eggs": "free",
                "vegan": "contains",
            },
        ),
        _dish("B", {"sesame": "contains", "fish": "contains"}, index=1),
    ]
    findings = [
        {"sesame": "suspected", "milk": "suspected", "eggs": "stated"},
        {"sesame": "likely"},
    ]
    misses = ev.find_misses(dishes, findings)
    assert [(m.restriction_id, m.dish, m.label, m.found) for m in misses] == [
        ("sesame", "A", "contains", "suspected"),
        ("fish", "B", "contains", None),
    ]
    assert misses[0].key == "sesame|m.json|A"
    assert str(misses[1]) == "fish  m.json  'B'  contains  found: nothing"


def test_find_misses_needs_one_finding_set_per_dish() -> None:
    with pytest.raises(ValueError, match="zip"):
        ev.find_misses([_dish("A", {})], [])


def test_tally_counts_recall_and_both_kinds_of_false_positive() -> None:
    dishes = [
        _dish("A", {"sesame": "contains"}),
        _dish("B", {"sesame": "contains"}, index=1),
        _dish("C", {"sesame": "may_contain"}, index=2),
        _dish("D", {"sesame": "free"}, index=3),
        _dish("E", {}, index=4),
        _dish("F", {"sesame": "free"}, index=5),
    ]
    findings = [
        {"sesame": "stated"},
        {"sesame": "suspected"},
        {"sesame": "suspected"},
        {"sesame": "likely"},
        {"sesame": "suspected"},
        {},
    ]
    count = ev.tally(dishes, findings, ["sesame"])["sesame"]
    assert (count.contains, count.contains_hit) == (2, 1)
    assert (count.may_contain, count.may_contain_hit) == (1, 1)
    assert count.fp_free == 1
    assert count.fp_unlabelled == 1


def test_percent_and_the_recall_table() -> None:
    assert ev.percent(1, 3) == "33.3%"
    assert ev.percent(0, 0) == "-"
    dishes = [_dish("A", {"sesame": "contains"})]
    table = ev.recall_table(ev.tally(dishes, [{"sesame": "stated"}], ["sesame"]))
    assert "sesame" in table
    assert "1/1" in table
    assert "100.0%" in table
    assert "all strict" in table


def test_strict_ids_are_the_allergens_and_celiac_disease() -> None:
    ids = ev.strict_ids()
    assert "peanuts" in ids
    assert "gluten" in ids
    assert {"lactose", "vegan", "vegetarian", "keto"}.isdisjoint(ids)


def test_entry_key_joins_id_menu_and_dish() -> None:
    assert ev.entry_key({"id": "soy", "menu": "m.json", "dish": "X"}) == "soy|m.json|X"


def test_the_corpus_loads_in_file_order_with_labels() -> None:
    dishes = ev.load_corpus()
    assert dishes[0].menu <= dishes[-1].menu
    assert all(isinstance(dish.labels, dict) for dish in dishes)
    sample = next(dish for dish in dishes if dish.labels)
    assert sample.to_dish().name == sample.name


def _menu(*names: str) -> Menu:
    dishes = [_dish(name, {}, index=i) for i, name in enumerate(names)]
    return ev._corpus_menu("m.json", dishes)


def test_the_corpus_menu_holds_one_dish_per_corpus_dish() -> None:
    menu = _menu("A", "B")
    assert [dish.id for dish in menu.all_dishes()] == ["m.json#0", "m.json#1"]


def test_ingredients_by_dish_keys_ingredients_by_menu_position() -> None:
    menu = _menu("A", "B")
    body = json.dumps(
        {
            "dishes": [
                {"id": "m.json#1", "ingredients": [{"name": "tahini"}]},
                {"id": "m.json#0", "ingredients": []},
                {"id": "invented", "ingredients": [{"name": "x"}]},
                {"id": "m.json#0"},
                "not a dish",
            ]
        }
    )
    assert ev.ingredients_by_dish(body, menu) == {1: [{"name": "tahini"}], 0: []}


@pytest.mark.parametrize("body", ["", "not json", "[]", '{"dishes": 3}', "null"])
def test_ingredients_by_dish_reads_a_bad_reply_as_nothing(body: str) -> None:
    assert ev.ingredients_by_dish(body, _menu("A")) == {}


def test_render_report_has_a_section_per_source_and_the_run_facts() -> None:
    dishes = [_dish("A", {"sesame": "contains"}), _dish("B", {}, index=1)]
    rules: list[dict[str, str]] = [{"sesame": "stated"}, {}]
    model: list[dict[str, str]] = [{}, {"sesame": "suspected"}]
    report = ev.render_report(
        dishes=dishes,
        rules=rules,
        model=model,
        model_id="some-model",
        failed_menus=["x.json"],
        when=datetime(2026, 10, 13, 9, 30, tzinfo=UTC),
    )
    assert "## Rules alone" in report
    assert "## Model alone" in report
    assert "## Merged (rules and model)" in report
    assert "2026-10-13 09:30 UTC" in report
    assert "`some-model`" in report
    assert "x.json" in report
    assert "| sesame | 1/1 | 100.0% |" in report


def test_the_report_marks_a_run_with_no_failed_menu() -> None:
    kwargs: dict[str, Any] = {
        "dishes": [_dish("A", {})],
        "rules": [{}],
        "model": [{}],
        "model_id": "m",
        "when": datetime(2026, 1, 1, tzinfo=UTC),
    }
    report = ev.render_report(failed_menus=[], **kwargs)
    assert "did not answer for: none" in report


def test_extraction_support_is_a_boolean() -> None:
    assert isinstance(ev.extraction_supported(), bool)


_PAGE = (
    "# Allergen evaluation: the last result\n\n"
    "**Status: not yet run.** Nothing here is a measurement.\n\n"
    "## What is measured\n\nText.\n\n## Last result\n\nNot yet run.\n"
)


def test_update_page_rewrites_the_status_and_the_last_result() -> None:
    when = datetime(2026, 10, 13, 9, 30, tzinfo=UTC)
    updated = ev.update_page(_PAGE, "Run: today.\n\n| table |\n", when)
    assert "**Status: last run 2026-10-13.**" in updated
    assert "Status: not yet run" not in updated
    assert "## What is measured\n\nText.\n\n## Last result\n\nRun: today." in updated
    assert updated.endswith("| table |\n")


def test_update_page_is_stable_when_run_twice() -> None:
    when = datetime(2026, 10, 13, tzinfo=UTC)
    once = ev.update_page(_PAGE, "Run: a.\n", when)
    assert ev.update_page(once, "Run: a.\n", when) == once


def test_update_page_adds_a_missing_heading() -> None:
    when = datetime(2026, 10, 13, tzinfo=UTC)
    updated = ev.update_page("# Title\n", "Run: a.\n", when)
    assert updated == "# Title\n\n## Last result\n\nRun: a.\n"

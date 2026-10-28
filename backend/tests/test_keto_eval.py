"""``tools/keto_eval.py``: the scoring, the merge, and the run against a
mocked model.

No network: Gemini is a respx route (the conftest blocks anything else),
the corpus is the hand-made fixture under ``fixtures/keto_eval/``, and the
model name is a placeholder set in the environment.
"""

import asyncio
import dataclasses
import json
from collections.abc import Callable, Iterator
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

import httpx
import pytest
import respx

from app.config import Settings
from tools import keto_eval as ev

FIXTURE = Path(__file__).parent / "fixtures" / "keto_eval" / "menus"
KEY = "test-key-for-the-keto-eval-that-must-never-be-recorded"
MODEL = "placeholder-model"
GEMINI_URL = (
    f"https://generativelanguage.googleapis.com/v1beta/models/{MODEL}:generateContent"
)
WHEN = datetime(2026, 10, 28, 9, 30, tzinfo=UTC)


def _dish(
    expected: str,
    *,
    id: str = "d1",
    acceptable: tuple[str, ...] = (),
    carbs: tuple[tuple[str, str], ...] = (),
    language: str = "en",
    menu: str = "m",
) -> ev.CorpusDish:
    return ev.CorpusDish(
        menu=menu,
        id=id,
        name=f"Dish {id}",
        description="",
        options=(),
        expected=expected,
        acceptable=frozenset(acceptable),
        hidden_carbs=tuple(ev.ExpectedCarb(s, c) for s, c in carbs),
        language=language,
    )


def _menu(*dishes: ev.CorpusDish, id: str = "m", language: str = "en") -> ev.CorpusMenu:
    return ev.CorpusMenu(
        id=id, name=id, source="test", language=language, categories=(("C", dishes),)
    )


def _settings() -> Settings:
    return Settings(
        DATABASE_URL="sqlite:///:memory:", GEMINI_API_KEY=KEY, GEMINI_MODEL=MODEL
    )


def _gemini_body(content: str, **extra: Any) -> dict[str, Any]:
    return {
        "candidates": [
            {"finishReason": "STOP", "content": {"parts": [{"text": content}]}}
        ],
        "modelVersion": f"{MODEL}-001",
        **extra,
    }


def _sent_prompt(request: httpx.Request) -> str:
    text: str = json.loads(request.content)["contents"][0]["parts"][0]["text"]
    return text


def _reply_for(prompt_text: str, verdict: str = "orderAsIs") -> str:
    """Every dish line of ``prompt_text`` placed as ``verdict``."""
    dishes = []
    for line in prompt_text.split("\n"):
        dish_id, _category, name, *_ = line.split(" | ")
        dishes.append(
            {
                "id": dish_id,
                "name": name,
                "verdict": verdict,
                "why": "Test reason.",
                "modification": "Ask for salad." if verdict == "modifiable" else None,
                "net_carbs_estimate": 2,
                "hidden_carbs": [],
            }
        )
    return json.dumps({"dishes": dishes}, ensure_ascii=False)


def _answering(
    failures: dict[int, httpx.Response | Exception] | None = None,
) -> Callable[[httpx.Request], httpx.Response]:
    calls = {"n": 0}

    def answer(request: httpx.Request) -> httpx.Response:
        calls["n"] += 1
        failure = (failures or {}).get(calls["n"])
        if isinstance(failure, Exception):
            raise failure
        if failure is not None:
            return failure
        usage = {"promptTokenCount": 100, "candidatesTokenCount": 40}
        return httpx.Response(
            200,
            json=_gemini_body(_reply_for(_sent_prompt(request)), usageMetadata=usage),
        )

    return answer


@pytest.fixture
def gemini() -> Iterator[respx.MockRouter]:
    with respx.mock(assert_all_called=False) as router:
        yield router


# --- the corpus ------------------------------------------------------------------


def test_the_fixture_corpus_loads_in_file_order() -> None:
    menus = ev.load_corpus(FIXTURE)
    assert [menu.id for menu in menus] == ["eval_en_bistro", "eval_he_grill"]
    assert [menu.language for menu in menus] == ["en", "he"]
    he = menus[1]
    assert [name for name, _ in he.categories] == ["עיקריות", "מהגריל"]
    salmon = he.dishes[1]
    assert salmon.key == "eval_he_grill/he-02"
    assert salmon.acceptable == {"modifiable"}
    assert salmon.hidden_carbs == (
        ev.ExpectedCarb("sweet soy sauce (רוטב סויה)", "suspected", "מוקפצים"),
    )
    assert menus[0].dishes[4].hidden_carbs[0].term is None
    assert he.dishes[3].options == (("תוספת", ("אורז", "סלט")),)


def test_the_corpus_menu_holds_every_dish_under_its_key() -> None:
    menu = ev.load_corpus(FIXTURE)[1].to_menu()
    assert [category.name for category in menu.categories] == ["עיקריות", "מהגריל"]
    assert menu.all_dishes()[0].id == "eval_he_grill/he-01"
    assert menu.all_dishes()[0].price == 0


def test_a_missing_corpus_is_empty(tmp_path: Path) -> None:
    assert ev.load_corpus(tmp_path / "absent") == []
    assert ev.load_corpus(tmp_path) == []


def test_a_flat_menu_reads_as_one_category(tmp_path: Path) -> None:
    path = tmp_path / "flat.json"
    path.write_text(
        json.dumps({"dishes": [{"id": "1", "name": "Steak", "expected": "orderAsIs"}]}),
        encoding="utf-8",
    )
    menu = ev.load_menu(path)
    assert (menu.id, menu.language) == ("flat", "unknown")
    assert menu.categories[0][0] == "flat"
    assert menu.dishes[0].description == ""
    assert menu.dishes[0].hidden_carbs == ()


@pytest.mark.parametrize(
    "dish",
    [
        {"id": "1", "name": "X", "expected": "green"},
        {"id": "1", "name": "X", "expected": "orderAsIs", "acceptable": ["red"]},
    ],
)
def test_a_label_that_is_not_a_verdict_fails_loudly(
    tmp_path: Path, dish: dict[str, Any]
) -> None:
    path = tmp_path / "bad.json"
    path.write_text(json.dumps({"id": "bad", "dishes": [dish]}), encoding="utf-8")
    with pytest.raises(ValueError, match="bad/1"):
        ev.load_menu(path)


def test_select_menus_by_id_or_file_name() -> None:
    menus = ev.load_corpus(FIXTURE)
    assert ev.select_menus(menus, "") == menus
    assert [m.id for m in ev.select_menus(menus, " eval_he_grill.json ,")] == [
        "eval_he_grill"
    ]
    with pytest.raises(ValueError, match="nope"):
        ev.select_menus(menus, "eval_en_bistro,nope")


# --- verdicts --------------------------------------------------------------------


def test_rules_verdicts_run_the_ported_heuristic() -> None:
    rules = ev.rules_verdicts(ev.load_corpus(FIXTURE)[0])
    assert rules["eval_en_bistro/en-01"].verdict == "modifiable"
    assert rules["eval_en_bistro/en-02"].verdict == "orderAsIs"
    assert rules["eval_en_bistro/en-03"].verdict == "nonKeto"
    assert rules["eval_en_bistro/en-05"].verdict == "orderAsIs"  # the known gap


def _reply(*dishes: dict[str, Any]) -> str:
    return json.dumps({"dishes": list(dishes)})


def _raw(dish_id: str, verdict: str, **fields: Any) -> dict[str, Any]:
    return {
        "id": dish_id,
        "name": "",
        "verdict": verdict,
        "why": "Because.",
        "modification": None,
        "net_carbs_estimate": None,
        "hidden_carbs": [],
        **fields,
    }


def test_model_verdicts_read_the_reply_as_the_parser_does() -> None:
    corpus = ev.load_corpus(FIXTURE)[0]
    menu = corpus.to_menu()
    carb = {"source": "sugar", "certainty": "likely", "waiter_question": "Sugar?"}
    got = ev.model_verdicts(
        _reply(
            _raw("eval_en_bistro/en-01", "modifiable", modification="No mash."),
            _raw(
                "eval_en_bistro/en-02",
                "orderAsIs",
                net_carbs_estimate=9,
                modification="Dressing on the side.",
            ),
            _raw("eval_en_bistro/en-03", "nonKeto"),
            _raw("eval_en_bistro/en-04", "modifiable"),  # no instruction
            _raw("eval_en_bistro/en-05", "orderAsIs", hidden_carbs=[carb]),
            _raw("invented", "orderAsIs", name="Pizza of the house"),
        ),
        menu,
    )
    assert got is not None
    assert got["eval_en_bistro/en-01"] == ev.Got("modifiable")
    assert got["eval_en_bistro/en-02"].verdict == "modifiable"  # over 6 g
    assert got["eval_en_bistro/en-03"] == ev.Got("nonKeto")
    assert "eval_en_bistro/en-04" not in got  # demoted to unclassified
    assert got["eval_en_bistro/en-05"] == ev.Got(
        "modifiable", (ev.Flag("sugar", "Sugar?"),)
    )
    assert "eval_en_bistro/en-06" not in got  # skipped
    assert len(got) == 4


@pytest.mark.parametrize("reply", ["", "not json", "[]", '{"dishes": 3}'])
def test_an_unusable_reply_has_no_verdicts(reply: str) -> None:
    assert ev.model_verdicts(reply, ev.load_corpus(FIXTURE)[0].to_menu()) is None


def test_merge_never_upgrades_a_rules_yellow_or_red_to_green() -> None:
    rules = {
        "a": ev.Got("modifiable", (ev.Flag("rice"),)),
        "b": ev.Got("nonKeto"),
        "c": ev.Got("orderAsIs"),
        "d": ev.Got("nonKeto"),
        "e": ev.Got("modifiable"),
    }
    model = {
        "a": ev.Got("orderAsIs", (ev.Flag("Rice", "Rice?"), ev.Flag("honey"))),
        "b": ev.Got("orderAsIs"),
        "c": ev.Got("nonKeto"),
        "d": ev.Got("modifiable"),
        "f": ev.Got("orderAsIs"),
    }
    merged = ev.merge(rules, model)
    assert merged["a"] == ev.Got("modifiable", (ev.Flag("rice"), ev.Flag("honey")))
    assert merged["b"] == ev.Got("nonKeto")
    assert merged["c"] == ev.Got("nonKeto")
    assert merged["d"] == ev.Got("modifiable")  # a downgrade from red stands
    assert merged["e"] == ev.Got("modifiable")  # the model did not place it
    assert merged["f"] == ev.Got("orderAsIs")
    assert list(merged) == ["a", "b", "c", "d", "e", "f"]


# --- the metrics -----------------------------------------------------------------


@pytest.mark.parametrize(
    ("expected", "flagged", "match"),
    [
        ("sugar", "Sugar", True),
        ("sugar", "brown sugar", True),
        ("brown sugar", "sugar", True),
        ("sugar", "sugarcane", True),
        ("rice", "sugar", False),
        ("רוטב סויה", "סויה", True),
        ("sweet marinade (מרינדה מתוקה)", "Sweet marinade", True),
        ("sweet marinade (מרינדה מתוקה)", "מרינדה מתוקה", True),
        ("honey", "", False),
    ],
)
def test_the_source_fallback_is_normalised_containment(
    expected: str, flagged: str, match: bool
) -> None:
    assert ev.texts_match(expected, flagged) is match
    assert ev.ExpectedCarb(expected, "likely").matched_by(ev.Flag(flagged)) is match


def test_a_label_with_a_term_is_matched_by_the_term_alone() -> None:
    carb = ev.ExpectedCarb("house sauce (רוטב הבית)", "suspected", "רוטב הבית")
    # The flag's source contains the term, or the term contains the source.
    assert carb.matched_by(ev.Flag("רוטב הבית המתוק"))
    assert carb.matched_by(ev.Flag("רוטב"))
    # The waiter question contains the term.
    assert carb.matched_by(ev.Flag("sugar", "יש סוכר ברוטב הבית?"))
    # The English source is not consulted once there is a term.
    assert not carb.matched_by(ev.Flag("House sauce"))
    assert not carb.matched_by(ev.Flag("sugar", "Is there sugar?"))
    assert not carb.matched_by(ev.Flag("", ""))
    assert not ev.ExpectedCarb("x", "likely", "!!").matched_by(ev.Flag("x"))


def test_a_label_without_a_term_falls_back_to_its_source() -> None:
    implied = ev.ExpectedCarb("bread binder in minced kebab", "suspected")
    assert implied.matched_by(ev.Flag("Bread binder"))
    assert not implied.matched_by(ev.Flag("sugar", "bread binder in minced kebab?"))


def test_score_counts_every_metric() -> None:
    dishes = [
        _dish("orderAsIs", id="1"),  # correct
        _dish("orderAsIs", id="2"),  # false red
        _dish("modifiable", id="3"),  # false green
        _dish("modifiable", id="4", acceptable=("orderAsIs",)),  # green accepted
        _dish("nonKeto", id="5"),  # false green
        _dish("nonKeto", id="6"),  # unclassified
        _dish("modifiable", id="7", acceptable=("nonKeto",)),  # red accepted
        _dish("modifiable", id="8"),  # false red
    ]
    got = {
        "m/1": ev.Got("orderAsIs"),
        "m/2": ev.Got("nonKeto"),
        "m/3": ev.Got("orderAsIs"),
        "m/4": ev.Got("orderAsIs"),
        "m/5": ev.Got("orderAsIs"),
        "m/7": ev.Got("nonKeto"),
        "m/8": ev.Got("nonKeto"),
    }
    result = ev.score(dishes, got)
    assert (result.dishes, result.correct, result.unclassified) == (8, 3, 1)
    assert result.accuracy == pytest.approx(3 / 8)
    assert (result.false_green, result.non_green) == (2, 6)
    assert result.false_green_rate == pytest.approx(2 / 6)
    assert (result.false_red, result.non_red) == (2, 6)
    assert result.false_red_rate == pytest.approx(2 / 6)


def test_score_counts_hidden_carb_recall_and_precision() -> None:
    dishes = [
        _dish("modifiable", id="1", carbs=(("sugar", "likely"), ("flour", "likely"))),
        _dish("orderAsIs", id="2", carbs=(("soy sauce", "suspected"),)),
        _dish("orderAsIs", id="3"),
    ]
    got = {
        "m/1": ev.Got("modifiable", (ev.Flag("brown sugar"), ev.Flag("starch"))),
        "m/2": ev.Got("modifiable", (ev.Flag("Soy Sauce"),)),
        "m/3": ev.Got("modifiable", (ev.Flag("honey"),)),
    }
    result = ev.score(dishes, got)
    assert (result.carbs_found, result.carbs_expected) == (2, 3)
    assert (result.carbs_flagged_matched, result.carbs_flagged) == (2, 4)
    assert result.carb_recall == pytest.approx(2 / 3)
    assert result.carb_precision == pytest.approx(0.5)
    assert result.carbs_by_certainty == {"likely": [1, 2], "suspected": [1, 1]}


def test_an_empty_slice_has_no_rates() -> None:
    result = ev.score([], {})
    assert result.accuracy is None
    assert result.false_green_rate is None
    assert result.false_red_rate is None
    assert result.carb_recall is None
    assert result.carb_precision is None
    assert ev.percent(None) == "-"
    assert ev.percent(1 / 3) == "33.3%"


# --- the gate --------------------------------------------------------------------


def test_find_misses_names_every_dish_the_labels_do_not_accept() -> None:
    menu = _menu(
        _dish("modifiable", id="1"),
        _dish("orderAsIs", id="2", acceptable=("modifiable",)),
        _dish("nonKeto", id="3"),
        _dish("orderAsIs", id="4"),
        _dish("nonKeto", id="5", acceptable=("modifiable",)),
    )
    got = {
        "m/1": ev.Got("orderAsIs"),
        "m/2": ev.Got("modifiable"),
        "m/4": ev.Got("nonKeto"),
        "m/5": ev.Got("orderAsIs"),
    }
    misses = ev.find_misses([menu], got)
    assert [(m.dish, m.expected, m.got) for m in misses] == [
        ("1", "modifiable", "orderAsIs"),
        ("3", "nonKeto", "unclassified"),
        ("4", "orderAsIs", "nonKeto"),
        ("5", "nonKeto", "orderAsIs"),
    ]
    assert [m.dish for m in ev.false_greens(misses)] == ["1", "5"]
    assert misses[0].key == ("m", "1")
    assert str(misses[0]) == "m  1  'Dish 1'  expected modifiable, got orderAsIs"
    assert misses[0].entry("sweet dressing") == {
        "menu": "m",
        "dish": "1",
        "expected": "modifiable",
        "got": "orderAsIs",
        "reason": "sweet dressing",
    }
    assert misses[0].entry()["reason"] == "TODO"


def test_a_green_the_labels_accept_is_not_a_false_green() -> None:
    menu = _menu(_dish("modifiable", id="1", acceptable=("orderAsIs",)))
    assert ev.find_misses([menu], {"m/1": ev.Got("orderAsIs")}) == []


def test_the_gate_holds_false_greens_only_and_can_only_shrink() -> None:
    misses = [
        ev.Miss("m", "1", "A", "modifiable", "orderAsIs"),  # listed
        ev.Miss("m", "2", "B", "nonKeto", "modifiable"),  # not a false green
        ev.Miss("m", "3", "C", "nonKeto", "orderAsIs"),  # unlisted
        ev.Miss("m", "4", "D", "modifiable", "orderAsIs"),  # expected changed
    ]
    known = [
        misses[0].entry("listed"),
        {**misses[1].entry("now yellow"), "got": "orderAsIs"},
        ev.Miss("m", "9", "E", "nonKeto", "orderAsIs").entry("fixed since"),
        {**misses[3].entry("relabelled"), "expected": "nonKeto"},
    ]
    assert ev.unlisted_false_greens(misses, known) == [misses[2]]
    assert [e["dish"] for e in ev.stale_known_misses(misses, known)] == [
        "2",
        "9",
        "4",
    ]
    exact = [m.entry("x") for m in ev.false_greens(misses)]
    assert ev.unlisted_false_greens(misses, exact) == []
    assert ev.stale_known_misses(misses, exact) == []


def test_regenerate_keeps_reasons_and_marks_new_entries_todo() -> None:
    misses = [
        ev.Miss("m", "1", "A", "modifiable", "orderAsIs"),
        ev.Miss("m", "2", "B", "nonKeto", "modifiable"),
        ev.Miss("m", "3", "C", "nonKeto", "orderAsIs"),
    ]
    existing = [misses[0].entry("sweet dressing"), {**misses[2].entry("x")}]
    existing[1]["dish"] = "gone"
    assert ev.regenerate_known_misses(misses, existing) == [
        misses[0].entry("sweet dressing"),
        misses[2].entry("TODO"),
    ]


def test_encode_known_misses_writes_the_dart_shape() -> None:
    entry = ev.Miss("il_x", "d1", "סלט", "modifiable", "orderAsIs").entry("טעם")
    assert ev.encode_known_misses([]) == "[]\n"
    assert ev.encode_known_misses([entry]) == (
        "[\n"
        "  {\n"
        '    "menu": "il_x",\n'
        '    "dish": "d1",\n'
        '    "expected": "modifiable",\n'
        '    "got": "orderAsIs",\n'
        '    "reason": "טעם"\n'
        "  }\n"
        "]\n"
    )
    assert list(entry) == list(ev.KNOWN_MISS_FIELDS)


def test_load_known_misses(tmp_path: Path) -> None:
    assert ev.load_known_misses(tmp_path / "absent.json") == []
    path = tmp_path / "known.json"
    entry = ev.Miss("m", "1", "A", "modifiable", "orderAsIs").entry("why")
    path.write_text(json.dumps([entry]), encoding="utf-8")
    assert ev.load_known_misses(path) == [entry]
    path.write_text(json.dumps({"misses": []}), encoding="utf-8")
    with pytest.raises(ValueError, match="JSON list"):
        ev.load_known_misses(path)


# --- the report ------------------------------------------------------------------


def _results(model: ev.Verdicts | None, runs: list[ev.MenuRun]) -> ev.Results:
    menus = ev.load_corpus(FIXTURE)
    rules: ev.Verdicts = {}
    for menu in menus:
        rules.update(ev.rules_verdicts(menu))
    return ev.Results(
        menus=menus,
        rules=rules,
        model=model,
        runs=runs,
        when=WHEN,
        model_id=None if model is None else MODEL,
        commit="abc1234",
        corpus="backend/tests/fixtures/keto_eval/menus",
    )


def test_a_rules_only_report_has_the_rules_tables_and_no_model() -> None:
    report = ev.report_markdown(_results(None, []))
    assert "2026-10-28 09:30 UTC" in report
    assert "`abc1234`" in report
    assert "**not yet run**" in report
    assert "**unreviewed**" in report
    assert "| Rules | 11 | 10/11 (90.9%) | **1/7 (14.3%)** |" in report
    assert "| en: Rules | 6 |" in report
    assert "| he: Rules | 5 |" in report
    assert "### Hidden carbs" in report
    assert "| eval_en_bistro | Coleslaw | modifiable | orderAsIs |" in report
    assert "| Model |" not in report
    assert "### Model run per menu" not in report


def test_a_model_report_compares_rules_model_and_merged() -> None:
    menus = ev.load_corpus(FIXTURE)
    model = {dish.key: ev.Got(dish.expected) for dish in ev.all_dishes(menus)}
    model["eval_en_bistro/en-05"] = ev.Got("modifiable", (ev.Flag("Sugar"),))
    del model["eval_he_grill/he-05"]
    runs = [
        ev.MenuRun(
            "eval_en_bistro",
            batches=1,
            latency_seconds=2.25,
            tokens={"prompt": 100, "output": 40},
        ),
        ev.MenuRun("eval_he_grill", batches=1, failures=[(1, "timeout")]),
    ]
    report = ev.report_markdown(_results(model, runs))
    assert f"`{MODEL}`" in report
    assert "Menus with a failed batch: eval_he_grill." in report
    assert "| Model | 11 | 10/11 (90.9%) | **0/7 (0.0%)** |" in report
    assert "| Merged | 11 | 11/11 (100.0%) | **0/7 (0.0%)** |" in report
    assert "| eval_en_bistro | 6 | 1 | 2.2 | 100 | 40 | none |" in report
    assert "| eval_he_grill | 5 | 1 | 0.0 | - | - | batch 1: timeout |" in report
    assert "| Model | 3 | 1 | 1/2 (50.0%) | 0/1 (0.0%) | 1 | 1 | 100.0% |" in report
    assert (
        "| eval_en_bistro | Coleslaw | modifiable | orderAsIs | modifiable | "
        "modifiable |"
    ) in report


def test_a_report_with_no_false_green_says_so() -> None:
    menus = ev.load_corpus(FIXTURE)
    perfect = {dish.key: ev.Got(dish.expected) for dish in ev.all_dishes(menus)}
    results = ev.Results(
        menus=menus,
        rules=perfect,
        model=None,
        runs=[],
        when=WHEN,
        model_id=None,
        commit="x",
        corpus="c",
    )
    assert ev.report_markdown(results).endswith("### False greens\n\nNone.\n")


_PAGE = (
    "# Keto evaluation\n\n"
    "**Status: not yet run.** Nothing here.\n\n"
    "## What is measured\n\nText.\n\n## Last result\n\nNot yet run.\n"
)


def test_update_page_for_a_rules_only_run_keeps_not_yet_run() -> None:
    results = _results(None, [])
    updated = ev.update_page(_PAGE, "Rules table.\n", results)
    assert "**Status: not yet run.**" in updated
    assert "which is not the keto corpus" in updated
    assert "## What is measured\n\nText.\n\n## Last result\n\nRules table." in updated
    assert updated.endswith("Rules table.\n")


def test_update_page_for_a_model_run_names_its_date() -> None:
    results = _results({}, [])
    updated = ev.update_page(_PAGE, "Run.\n", results)
    assert "**Status: last run 2026-10-28.**" in updated
    assert "not yet run" not in updated
    assert ev.update_page(updated, "Run.\n", results) == updated


def test_update_page_on_the_corpus_and_without_a_heading() -> None:
    results = _results(None, [])
    on_corpus = dataclasses.replace(results, corpus=ev._label(ev.CORPUS_DIR))
    assert "not the keto corpus" not in ev.update_page(_PAGE, "R.\n", on_corpus)
    assert ev.update_page("# Title\n", "R.\n", results) == (
        "# Title\n\n## Last result\n\nR.\n"
    )


def test_the_committed_page_has_the_status_and_the_heading() -> None:
    page = ev.REPORT_PATH.read_text(encoding="utf-8")
    assert "**Status:" in page
    assert "## Last result\n" in page
    assert "unreviewed" in page


# --- recording -------------------------------------------------------------------


def test_redact_replaces_a_secret_everywhere() -> None:
    value = {"a": [f"x{KEY}y", 3, None], KEY: {"b": KEY}}
    assert ev.redact(value, [KEY, ""]) == {
        "a": ["x[redacted]y", 3, None],
        "[redacted]": {"b": "[redacted]"},
    }


def test_write_recordings_saves_bodies_and_never_the_key(tmp_path: Path) -> None:
    run = ev.MenuRun(
        "eval_en_bistro",
        replies=[
            {
                "batch": 1,
                "failure": "badResponse",
                "attempts": [
                    {"status": 400, "body": {"error": {"message": f"bad key {KEY}"}}}
                ],
            }
        ],
    )
    (path,) = ev.write_recordings([run], MODEL, [KEY], tmp_path / "rec")
    assert path.name == "eval_en_bistro.json"
    saved = path.read_text(encoding="utf-8")
    assert KEY not in saved
    assert "[redacted]" in saved
    assert json.loads(saved)["model"] == MODEL


# --- the run against a mocked model ----------------------------------------------


def _run(
    menus: list[ev.CorpusMenu], *, timeout: float = 30.0, delay: float = 0.0
) -> list[ev.MenuRun]:
    return asyncio.run(ev.evaluate(menus, _settings(), timeout=timeout, delay=delay))


def test_evaluate_sends_the_real_prompt_and_reads_every_reply(
    gemini: respx.MockRouter,
) -> None:
    route = gemini.post(GEMINI_URL).mock(side_effect=_answering())
    menus = ev.load_corpus(FIXTURE)
    runs = _run(menus, delay=0.001)
    assert route.call_count == 2
    sent = json.loads(route.calls[0].request.content)
    assert sent["system_instruction"]["parts"][0]["text"] == ev.prompt.system_prompt(
        ev.OPTIONS
    )
    assert _sent_prompt(route.calls[0].request) == ev.prompt.user_prompt(
        menus[0].to_menu()
    )
    schema = sent["generationConfig"]["responseSchema"]
    assert "ingredients" not in json.dumps(schema)
    assert route.calls[0].request.headers["x-goog-api-key"] == KEY
    assert [run.failures for run in runs] == [[], []]
    assert runs[0].tokens == {"prompt": 100, "output": 40}
    assert runs[0].latency_seconds >= 0
    assert set(runs[0].verdicts) == {dish.key for dish in menus[0].dishes}
    assert runs[0].replies[0]["attempts"][0]["status"] == 200


def test_a_large_menu_is_sent_in_batches(gemini: respx.MockRouter) -> None:
    route = gemini.post(GEMINI_URL).mock(side_effect=_answering())
    big = _menu(*(_dish("orderAsIs", id=str(i)) for i in range(130)), id="big")
    (run,) = _run([big])
    assert route.call_count == 2
    assert run.batches == 2
    assert [len(_sent_prompt(c.request).split("\n")) for c in route.calls] == [65, 65]
    assert len(run.verdicts) == 130
    assert run.tokens == {"prompt": 200, "output": 80}


def test_a_failed_batch_is_recorded_and_the_run_goes_on(
    gemini: respx.MockRouter,
) -> None:
    route = gemini.post(GEMINI_URL).mock(
        side_effect=_answering({1: httpx.Response(429, json={"error": {}})})
    )
    big = _menu(*(_dish("orderAsIs", id=str(i)) for i in range(130)), id="big")
    small = _menu(_dish("orderAsIs", id="x", menu="small"), id="small")
    runs = _run([big, small])
    assert route.call_count == 3
    assert runs[0].failures == [(1, "rateLimited")]
    assert len(runs[0].verdicts) == 65
    assert runs[0].replies[0]["failure"] == "rateLimited"
    assert runs[1].failures == []
    assert set(runs[1].verdicts) == {"small/x"}


@pytest.mark.parametrize(
    ("answer", "reason"),
    [
        (httpx.ReadTimeout("slow"), "timeout"),
        (httpx.ConnectError("down"), "offline"),
        (httpx.Response(500), "badResponse"),
        (httpx.Response(200, json=_gemini_body("not json at all")), "badResponse"),
        (httpx.Response(403), "notConfigured"),
    ],
)
def test_every_failure_is_named(
    gemini: respx.MockRouter, answer: httpx.Response | Exception, reason: str
) -> None:
    gemini.post(GEMINI_URL).mock(side_effect=_answering({1: answer}))
    (run,) = _run([_menu(_dish("orderAsIs"))])
    assert run.failures == [(1, reason)]
    assert run.verdicts == {}


def test_the_timeout_flag_bounds_each_request(gemini: respx.MockRouter) -> None:
    async def slow(request: httpx.Request) -> httpx.Response:
        await asyncio.sleep(5)
        return httpx.Response(200)  # pragma: no cover - cancelled first

    gemini.post(GEMINI_URL).mock(side_effect=slow)
    (run,) = _run([_menu(_dish("orderAsIs"))], timeout=0.05)
    assert run.failures == [(1, "timeout")]


def test_usage_of_reads_only_integer_counters() -> None:
    body = {
        "usageMetadata": {
            "promptTokenCount": 5,
            "candidatesTokenCount": True,
            "totalTokenCount": "9",
            "thoughtsTokenCount": 0,
        }
    }
    assert ev.usage_of(body) == {"prompt": 5, "thoughts": 0}
    assert ev.usage_of("text") == {}
    assert ev.usage_of({"usageMetadata": []}) == {}


def test_the_tap_keeps_a_body_that_is_not_json() -> None:
    tap = ev.Tap()
    asyncio.run(tap(httpx.Response(502, text="gateway")))
    assert tap.bodies == [(502, "gateway")]


def test_current_commit_outside_a_checkout_is_unknown(tmp_path: Path) -> None:
    assert ev.current_commit(tmp_path) == "unknown"
    assert ev.current_commit(tmp_path / "absent") == "unknown"
    assert ev.current_commit() != ""


# --- main ------------------------------------------------------------------------


def test_main_without_a_key_exits_with_a_clear_message(
    monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    monkeypatch.delenv("GEMINI_API_KEY", raising=False)
    assert ev.main(["--corpus", str(FIXTURE)]) == 1
    assert "GEMINI_API_KEY is not set" in capsys.readouterr().err
    monkeypatch.setenv("GEMINI_API_KEY", "   ")
    assert ev.main(["--corpus", str(FIXTURE)]) == 1


def test_main_rules_only_needs_no_key_and_sends_nothing(
    monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    monkeypatch.delenv("GEMINI_API_KEY", raising=False)
    assert ev.main(["--rules-only", "--no-write", "--corpus", str(FIXTURE)]) == 0
    out = capsys.readouterr().out
    assert "| Rules | 11 |" in out
    assert "| Model |" not in out


def test_main_names_a_bad_menu_and_an_empty_corpus(
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
    tmp_path: Path,
) -> None:
    monkeypatch.delenv("GEMINI_API_KEY", raising=False)
    argv = ["--rules-only", "--no-write", "--corpus", str(FIXTURE)]
    assert ev.main([*argv, "--menus", "nope"]) == 2
    assert "no such corpus menu: nope" in capsys.readouterr().err
    assert ev.main(["--rules-only", "--corpus", str(tmp_path)]) == 1
    assert "no corpus menus" in capsys.readouterr().err


def test_main_runs_the_model_writes_the_page_and_records(
    gemini: respx.MockRouter,
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    gemini.post(GEMINI_URL).mock(side_effect=_answering())
    monkeypatch.setenv("GEMINI_API_KEY", KEY)
    monkeypatch.setenv("GEMINI_MODEL", MODEL)
    page = tmp_path / "KETO_EVAL.md"
    page.write_text(_PAGE, encoding="utf-8")
    monkeypatch.setattr(ev, "REPORT_PATH", page)
    monkeypatch.setattr(ev, "RECORD_DIR", tmp_path / "rec")
    argv = ["--corpus", str(FIXTURE), "--record", "--delay", "0"]
    assert ev.main([*argv, "--menus", "eval_he_grill"]) == 0
    written = page.read_text(encoding="utf-8")
    assert "**Status: last run" in written
    assert f"Model: `{MODEL}`" in written
    assert "| Merged | 5 |" in written
    (recorded,) = sorted((tmp_path / "rec").iterdir())
    assert recorded.name == "eval_he_grill.json"
    saved = recorded.read_text(encoding="utf-8").lower()
    assert KEY.lower() not in saved
    assert "x-goog-api-key" not in saved
    assert "authorization" not in saved
    assert json.loads(saved)["batches"][0]["attempts"][0]["status"] == 200


def test_main_exits_1_when_a_request_failed(
    gemini: respx.MockRouter,
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    gemini.post(GEMINI_URL).mock(
        side_effect=_answering({1: httpx.Response(429, json={})})
    )
    monkeypatch.setenv("GEMINI_API_KEY", KEY)
    monkeypatch.setenv("GEMINI_MODEL", MODEL)
    argv = ["--corpus", str(FIXTURE), "--no-write", "--delay", "0"]
    assert ev.main([*argv, "--menus", "eval_en_bistro"]) == 1
    captured = capsys.readouterr()
    assert "batch 1 failed: rateLimited" in captured.err
    assert "batch 1: rateLimited" in captured.out


def test_the_fixture_gate_finds_the_one_rules_gap() -> None:
    menus = ev.load_corpus(FIXTURE)
    rules: ev.Verdicts = {}
    for menu in menus:
        rules.update(ev.rules_verdicts(menu))
    misses = ev.find_misses(menus, rules)
    assert [(m.menu, m.dish, m.expected, m.got) for m in misses] == [
        ("eval_en_bistro", "en-05", "modifiable", "orderAsIs")
    ]
    known = [misses[0].entry("a deli coleslaw dressing is sweetened")]
    assert ev.unlisted_false_greens(misses, known) == []
    assert ev.stale_known_misses(misses, known) == []
    assert ev.unlisted_false_greens(misses, []) == misses

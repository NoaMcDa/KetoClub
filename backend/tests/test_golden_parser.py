"""``app.keto.parser`` replays the golden ``parser.json`` (#325, D25).

``text`` entries are a reply parsed against a source menu
(``MenuResponseParser.parse``); ``scanned`` entries are a vision reply read
as a transcription (``parseScanned``). Every Dart result is compared with
ours as canonical JSON. A few direct cases below pin what the corpus cannot
hold (a value Dart's ``jsonEncode`` could not write).
"""

import json
from pathlib import Path
from typing import Any

import pytest

from app.keto.models import LlmEngine, Menu, to_json
from app.keto.parser import (
    SCHEMA_VERSION,
    Analysed,
    Failed,
    ScannedRead,
    extraction_missing,
    parse,
    parse_scanned,
)
from app.keto.prompt import prompt_ids

_GOLDEN = Path(__file__).parent / "fixtures" / "golden" / "parser.json"
_RAW: dict[str, Any] = json.loads(_GOLDEN.read_text(encoding="utf-8"))
_TEXT: list[dict[str, Any]] = _RAW["text"]
_SCANNED: list[dict[str, Any]] = _RAW["scanned"]
_EXTRACT_TEXT: list[dict[str, Any]] = _RAW["extractText"]
_EXTRACT_SCANNED: list[dict[str, Any]] = _RAW["extractScanned"]
_PROMPT_ID_TEXT: list[dict[str, Any]] = _RAW["promptIdText"]
_ENGINE = LlmEngine(model="golden-model")
_NOW = "2026-01-01T00:00:00.000Z"


def _canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, ensure_ascii=False)


@pytest.mark.parametrize("entry", _TEXT, ids=[e["name"] for e in _TEXT])
def test_every_golden_text_reply_parses_as_dart_does(entry: dict[str, Any]) -> None:
    assert set(entry) == {"name", "reply", "sourceMenu", "netCarbLimitGrams", "result"}
    result = parse(
        entry["reply"],
        source=Menu.model_validate(entry["sourceMenu"]),
        engine=_ENGINE,
        net_carb_limit_grams=entry["netCarbLimitGrams"],
        analysed_at=_NOW,
    )
    match result:
        case Analysed(analysis=analysis):
            actual: dict[str, Any] = {"analysed": to_json(analysis)}
        case Failed(reason=reason):
            actual = {"failed": reason}
    assert _canonical(actual) == _canonical(entry["result"])


@pytest.mark.parametrize(
    "entry", _PROMPT_ID_TEXT, ids=[e["name"] for e in _PROMPT_ID_TEXT]
)
def test_every_golden_prompt_id_reply_parses_as_dart_does(
    entry: dict[str, Any],
) -> None:
    assert set(entry) == {
        "name",
        "reply",
        "sourceMenu",
        "netCarbLimitGrams",
        "promptIds",
        "result",
    }
    source = Menu.model_validate(entry["sourceMenu"])
    # The ids the golden parsed through are the ones the server's prompt
    # sends for this menu.
    assert prompt_ids(source) == entry["promptIds"]
    result = parse(
        entry["reply"],
        source=source,
        prompt_ids=entry["promptIds"],
        engine=_ENGINE,
        net_carb_limit_grams=entry["netCarbLimitGrams"],
        analysed_at=_NOW,
    )
    match result:
        case Analysed(analysis=analysis):
            actual: dict[str, Any] = {"analysed": to_json(analysis)}
        case Failed(reason=reason):
            actual = {"failed": reason}
    assert _canonical(actual) == _canonical(entry["result"])


def test_the_prompt_id_corpus_places_two_dishes_of_one_name() -> None:
    by_name = {entry["name"]: entry for entry in _PROMPT_ID_TEXT}
    placed = by_name["hand_prompt_ids_place_every_dish"]["result"]["analysed"]
    assert [d["dishId"] for d in placed["dishes"]] == [
        "65b0c1f2a3d4e5f60718293a",
        "65b0c1f2a3d4e5f60718293b",
        "65b0c1f2a3d4e5f6071829ff",
        "1",
    ]
    assert placed["unclassified"] == []
    # The recorded reply's shape: prefixes match no id, so the names place
    # the first dish only and its namesake is lost.
    prefixes = by_name["hand_prompt_ids_prefixes_fall_to_names"]["result"]
    assert [d["dishId"] for d in prefixes["analysed"]["dishes"]] == [
        "65b0c1f2a3d4e5f60718293a",
        "65b0c1f2a3d4e5f6071829ff",
    ]


@pytest.mark.parametrize("entry", _SCANNED, ids=[e["name"] for e in _SCANNED])
def test_every_golden_scanned_reply_parses_as_dart_does(
    entry: dict[str, Any],
) -> None:
    assert set(entry) == {"name", "reply", "pageCount", "netCarbLimitGrams", "result"}
    result = parse_scanned(
        entry["reply"],
        engine=_ENGINE,
        analysed_at=_NOW,
        net_carb_limit_grams=entry["netCarbLimitGrams"],
        page_count=entry["pageCount"],
    )
    match result:
        case ScannedRead(menu=menu, analysis=analysis):
            actual: dict[str, Any] = {
                "menu": to_json(menu),
                "analysis": to_json(analysis),
            }
        case Failed(reason=reason):
            actual = {"failed": reason}
    assert _canonical(actual) == _canonical(entry["result"])


def _missing(menu: Menu, analysis: Any) -> list[str]:
    """The ids whose extraction is missing, as the golden lists them."""
    by_id = {dish.id: dish for dish in menu.all_dishes()}
    return [
        verdict.dish_id
        for verdict in analysis.dishes
        if extraction_missing(by_id[verdict.dish_id], verdict, extract=True)
    ]


@pytest.mark.parametrize("entry", _EXTRACT_TEXT, ids=[e["name"] for e in _EXTRACT_TEXT])
def test_every_golden_extracting_text_reply_parses_as_dart_does(
    entry: dict[str, Any],
) -> None:
    assert set(entry) == {
        "name",
        "reply",
        "sourceMenu",
        "netCarbLimitGrams",
        "result",
        "extractionMissing",
    }
    source = Menu.model_validate(entry["sourceMenu"])
    result = parse(
        entry["reply"],
        source=source,
        engine=_ENGINE,
        net_carb_limit_grams=entry["netCarbLimitGrams"],
        analysed_at=_NOW,
        extract=True,
    )
    assert isinstance(result, Analysed)
    assert _canonical({"analysed": to_json(result.analysis)}) == _canonical(
        entry["result"]
    )
    assert _missing(source, result.analysis) == entry["extractionMissing"]


@pytest.mark.parametrize(
    "entry", _EXTRACT_SCANNED, ids=[e["name"] for e in _EXTRACT_SCANNED]
)
def test_every_golden_extracting_scanned_reply_parses_as_dart_does(
    entry: dict[str, Any],
) -> None:
    result = parse_scanned(
        entry["reply"],
        engine=_ENGINE,
        analysed_at=_NOW,
        net_carb_limit_grams=entry["netCarbLimitGrams"],
        page_count=entry["pageCount"],
        extract=True,
    )
    assert isinstance(result, ScannedRead)
    actual = {"menu": to_json(result.menu), "analysis": to_json(result.analysis)}
    assert _canonical(actual) == _canonical(entry["result"])
    assert _missing(result.menu, result.analysis) == entry["extractionMissing"]


def test_the_extracting_corpus_reaches_every_parser_rule() -> None:
    dishes = [
        dish
        for entry in _EXTRACT_TEXT
        for dish in entry["result"]["analysed"]["dishes"]
    ]
    certainties = {i["certainty"] for d in dishes for i in d.get("ingredients", [])}
    roles = {i["role"] for d in dishes for i in d.get("ingredients", [])}
    assert certainties == {"stated", "likely", "suspected"}
    assert "unknown" in roles
    assert all("concerns" not in dish for dish in dishes)
    assert any(entry["extractionMissing"] for entry in _EXTRACT_TEXT)
    assert any(entry["extractionMissing"] for entry in _EXTRACT_SCANNED)


def test_without_extract_the_ingredients_are_never_read() -> None:
    for entry in _EXTRACT_TEXT:
        result = parse(
            entry["reply"],
            source=Menu.model_validate(entry["sourceMenu"]),
            engine=_ENGINE,
            net_carb_limit_grams=entry["netCarbLimitGrams"],
            analysed_at=_NOW,
        )
        assert isinstance(result, Analysed)
        assert all(not dish.ingredients for dish in result.analysis.dishes)


def test_the_corpus_reaches_both_outcomes_of_both_parsers() -> None:
    assert {tuple(sorted(e["result"])) for e in _TEXT} == {
        ("analysed",),
        ("failed",),
    }
    assert {tuple(sorted(e["result"])) for e in _SCANNED} == {
        ("analysis", "menu"),
        ("failed",),
    }
    assert {e["result"].get("failed") for e in _TEXT} >= {
        "badResponse",
        "noDishesFound",
    }
    assert SCHEMA_VERSION == 1


# --- what the corpus cannot hold -------------------------------------------------


def _steak_menu() -> Menu:
    return Menu.model_validate(
        {
            "venueRef": {"source": "wolt", "platformId": "v"},
            "currency": "ILS",
            "fetchedAt": _NOW,
            "categories": [
                {
                    "id": "c",
                    "name": "Mains",
                    "dishes": [
                        {"id": "s", "name": "Steak", "price": 1.0, "options": []}
                    ],
                }
            ],
        }
    )


def _reply(**dish: object) -> str:
    return json.dumps({"dishes": [{"id": "s", "name": "Steak", **dish}]})


def _only_dish(body: str) -> dict[str, Any]:
    result = parse(
        body,
        source=_steak_menu(),
        engine=_ENGINE,
        net_carb_limit_grams=6,
        analysed_at=_NOW,
    )
    assert isinstance(result, Analysed)
    dumped = to_json(result.analysis)
    assert len(dumped["dishes"]) == 1
    dish: dict[str, Any] = dumped["dishes"][0]
    return dish


def test_an_infinite_estimate_demotes_a_green_but_is_not_stored() -> None:
    # 1e400 decodes to Infinity in Dart and Python alike: over the limit, so
    # the green is not kept, but no JSON can carry the figure itself.
    body = _reply(verdict="orderAsIs", why="w", modification="m").replace(
        '"modification"', '"net_carbs_estimate": 1e400, "modification"'
    )
    dish = _only_dish(body)
    assert dish["verdict"] == "modifiable"
    assert dish["netCarbsEstimate"] is None


def test_a_hidden_carb_of_separator_characters_is_kept_as_dart_keeps_it() -> None:
    # Dart's trim keeps U+001C; the flag is not blank, so it demotes the green.
    dish = _only_dish(
        _reply(
            verdict="orderAsIs",
            why="w",
            hidden_carbs=[
                {"source": "\u001c", "certainty": "likely", "waiter_question": "q?"}
            ],
        )
    )
    assert dish["verdict"] == "modifiable"
    assert dish["modification"] == "q?"
    assert dish["hiddenCarbs"][0]["source"] == "\u001c"


def test_a_lone_surrogate_in_the_reply_never_raises() -> None:
    body = (
        '{"dishes": [{"id": "s", "name": "x", "verdict": "orderAsIs",'
        ' "why": "\\ud800"}]}'
    )
    assert _only_dish(body)["why"] == "\ud800"
    scanned = parse_scanned(
        '{"dishes": [{"name": "\\ud800 Steak", "verdict": "orderAsIs", "why": "w"}]}',
        engine=_ENGINE,
        analysed_at=_NOW,
        net_carb_limit_grams=6,
        page_count=None,
    )
    assert isinstance(scanned, ScannedRead)


@pytest.mark.parametrize(
    "body",
    ["", "{", '{"dishes": [Infinity]}', '{"dishes": -Infinity}', "[" * 100_000],
)
def test_malformed_json_is_a_bad_response(body: str) -> None:
    result = parse(
        body,
        source=_steak_menu(),
        engine=_ENGINE,
        net_carb_limit_grams=6,
        analysed_at=_NOW,
    )
    assert result == Failed("badResponse")

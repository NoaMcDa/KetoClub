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
    parse,
    parse_scanned,
)

_GOLDEN = Path(__file__).parent / "fixtures" / "golden" / "parser.json"
_RAW: dict[str, Any] = json.loads(_GOLDEN.read_text(encoding="utf-8"))
_TEXT: list[dict[str, Any]] = _RAW["text"]
_SCANNED: list[dict[str, Any]] = _RAW["scanned"]
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

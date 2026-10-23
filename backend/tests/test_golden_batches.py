"""``app.keto.batching`` replays the golden ``batches.json`` (#188, D25).

Every entry is one menu split under one ``(maxDishes, maxChars)`` pair by the
Dart ``MenuAnalysisPrompt.batches``: each batch as its categories' ids with
their dish ids, and its user prompt's length in UTF-16 code units. The file
also carries the Dart constants, which must equal the Python ones the server
batches with.
"""

import json
from pathlib import Path
from typing import Any

import pytest

from app.keto.batching import (
    ANALYSIS_BATCH_MAX_DISHES,
    ANALYSIS_BATCH_MAX_DISHES_EXTRACT,
    batch_max_dishes,
    split_batches,
)
from app.keto.dart_text import utf16_len
from app.keto.models import Menu
from app.keto.prompt import user_prompt
from app.schemas import USER_PROMPT_MAX_CHARS, ChatRequest

_RAW: dict[str, Any] = json.loads(
    (Path(__file__).parent / "fixtures" / "golden" / "batches.json").read_text(
        encoding="utf-8"
    )
)
_MENUS: dict[str, Menu] = {
    name: Menu.model_validate(raw) for name, raw in _RAW["menus"].items()
}
_ENTRIES: list[dict[str, Any]] = _RAW["entries"]


def test_the_limits_are_the_dart_constants() -> None:
    assert _RAW["userPromptMaxChars"] == USER_PROMPT_MAX_CHARS
    assert _RAW["maxDishes"] == ANALYSIS_BATCH_MAX_DISHES
    assert _RAW["maxDishesExtract"] == ANALYSIS_BATCH_MAX_DISHES_EXTRACT
    assert batch_max_dishes(extract=False) == ANALYSIS_BATCH_MAX_DISHES
    assert batch_max_dishes(extract=True) == ANALYSIS_BATCH_MAX_DISHES_EXTRACT


def test_the_chat_route_enforces_the_budget_the_split_uses() -> None:
    field = ChatRequest.model_fields["user_prompt"]
    assert any(
        getattr(meta, "max_length", None) == USER_PROMPT_MAX_CHARS
        for meta in field.metadata
    )


@pytest.mark.parametrize("entry", _ENTRIES, ids=[e["name"] for e in _ENTRIES])
def test_every_golden_split_is_reproduced(entry: dict[str, Any]) -> None:
    menu = _MENUS[entry["menu"]]

    batches = split_batches(
        menu, max_dishes=entry["maxDishes"], max_chars=entry["maxChars"]
    )

    assert [
        {
            "categories": [
                {"id": category.id, "dishIds": [dish.id for dish in category.dishes]}
                for category in batch.categories
            ],
            "userPromptLength": utf16_len(user_prompt(batch)),
        }
        for batch in batches
    ] == entry["batches"]
    for batch in batches:
        assert batch.venue_ref == menu.venue_ref
        assert batch.venue_name == menu.venue_name
        assert batch.fetched_at == menu.fetched_at
        assert batch.currency == menu.currency


def test_the_corpus_splits_on_both_limits() -> None:
    names = {entry["name"] for entry in _ENTRIES}
    assert {"large/defaults", "large/extract", "large/chars300"} <= names
    by_name = {entry["name"]: entry for entry in _ENTRIES}
    assert len(by_name["large/defaults"]["batches"]) == 3
    assert len(by_name["wolt_hamosad/defaults"]["batches"]) == 1


def test_a_menu_that_fits_is_returned_itself() -> None:
    menu = _MENUS["english"]

    batches = split_batches(
        menu, max_dishes=ANALYSIS_BATCH_MAX_DISHES, max_chars=USER_PROMPT_MAX_CHARS
    )

    assert len(batches) == 1
    assert batches[0] is menu

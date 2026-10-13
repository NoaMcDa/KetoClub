"""``app.keto.prompt`` replays the golden ``prompt.json`` (#325, D25).

Every entry is one menu under one option set, with the Dart
``MenuAnalysisPrompt`` output for it. The system prompt is the backend chat
cache's key (D12), so it is compared as an exact string, not loosely.
"""

import json
from pathlib import Path
from typing import Any

import pytest

from app.keto.models import AnalysisOptionsSnapshot, Menu
from app.keto.prompt import (
    SCHEMA_NAME,
    response_schema,
    system_prompt,
    user_prompt,
    vision_preamble,
    vision_response_schema,
    vision_system_prompt,
    vision_user_prompt,
)

_FIXTURES = Path(__file__).parent / "fixtures"
_RAW: dict[str, Any] = json.loads(
    (_FIXTURES / "golden" / "prompt.json").read_text(encoding="utf-8")
)
_ENTRIES: list[dict[str, Any]] = _RAW["entries"]
_ENTRY_KEYS = {
    "name",
    "menu",
    "options",
    "systemPrompt",
    "userPrompt",
    "visionPreamble1",
    "visionPreamble3",
    "visionUserPrompt1",
    "visionUserPrompt3",
    "visionSystemPrompt1",
    "visionSystemPrompt3",
}


def _canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, ensure_ascii=False)


@pytest.mark.parametrize("entry", _ENTRIES, ids=[e["name"] for e in _ENTRIES])
def test_every_golden_prompt_is_built_byte_for_byte(entry: dict[str, Any]) -> None:
    assert set(entry) == _ENTRY_KEYS
    menu = Menu.model_validate(entry["menu"])
    options = AnalysisOptionsSnapshot.model_validate(entry["options"])

    assert system_prompt(options) == entry["systemPrompt"]
    assert user_prompt(menu) == entry["userPrompt"]
    assert vision_preamble(1) == entry["visionPreamble1"]
    assert vision_preamble(3) == entry["visionPreamble3"]
    assert vision_user_prompt(1) == entry["visionUserPrompt1"]
    assert vision_user_prompt(3) == entry["visionUserPrompt3"]
    assert vision_system_prompt(1, options) == entry["visionSystemPrompt1"]
    assert vision_system_prompt(3, options) == entry["visionSystemPrompt3"]


def test_the_default_prompt_is_the_golden_defaults_prompt() -> None:
    defaults = [e for e in _ENTRIES if e["name"].endswith("/defaults")]
    assert defaults
    for entry in defaults:
        assert system_prompt() == entry["systemPrompt"]
        assert vision_system_prompt(3) == entry["visionSystemPrompt3"]
    assert not system_prompt().endswith("\n")


def test_the_corpus_covers_every_option_shape() -> None:
    constraint_counts = {len(e["options"]["dietaryConstraints"]) for e in _ENTRIES}
    limits = {e["options"]["netCarbLimitGrams"] for e in _ENTRIES}
    assert constraint_counts >= {0, 1, 2, 3}
    assert len(limits) >= 3


def test_the_schemas_and_name_match_the_golden() -> None:
    assert SCHEMA_NAME == _RAW["schemaName"]
    assert _canonical(response_schema()) == _canonical(_RAW["schema"])
    assert _canonical(vision_response_schema()) == _canonical(_RAW["visionSchema"])
    assert _canonical(response_schema(extract=True)) == _canonical(
        _RAW["extractSchema"]
    )
    assert _canonical(vision_response_schema(extract=True)) == _canonical(
        _RAW["extractVisionSchema"]
    )


def test_the_extracting_schemas_keep_the_required_order() -> None:
    # ``required`` is a list: canonical JSON keeps its order, so it is
    # compared as the golden lists it (ALG-03).
    text = response_schema(extract=True)["properties"]["dishes"]["items"]
    vision = vision_response_schema(extract=True)["properties"]["dishes"]["items"]
    golden_text = _RAW["extractSchema"]["properties"]["dishes"]["items"]
    golden_vision = _RAW["extractVisionSchema"]["properties"]["dishes"]["items"]
    assert text["required"] == golden_text["required"]
    assert vision["required"] == golden_vision["required"]
    assert text["required"][-1] == "ingredients"
    assert vision["required"][-2:] == ["page", "description"]


def test_the_corpus_has_extracting_entries_and_keto_ones_without_it() -> None:
    extracting = [e for e in _ENTRIES if e["name"].endswith("/restrictions")]
    assert extracting
    for entry in extracting:
        assert entry["options"]["restrictionsRequested"] is True
        keto = next(
            e
            for e in _ENTRIES
            if e["name"] == entry["name"].replace("/restrictions", "/defaults")
        )
        assert entry["systemPrompt"].startswith(keto["systemPrompt"] + "\n\n")
    for entry in _ENTRIES:
        if entry not in extracting:
            assert "restrictionsRequested" not in entry["options"]
            assert '"ingredients"' not in entry["systemPrompt"]


def test_the_response_schema_is_the_checked_in_schema_file() -> None:
    checked_in = json.loads(
        (_FIXTURES / "menu_analysis_schema.json").read_text(encoding="utf-8")
    )
    assert response_schema() == checked_in


def test_the_vision_schema_does_not_change_the_text_schema() -> None:
    vision = vision_response_schema()
    item = vision["properties"]["dishes"]["items"]
    assert item["required"][-1] == "page"
    assert "page" not in response_schema()["properties"]["dishes"]["items"]["required"]

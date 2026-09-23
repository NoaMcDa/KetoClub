"""Tests for ``app.services.gemini.to_gemini_schema``.

The fixture is the exact output of the Dart
``MenuAnalysisPrompt.responseSchema()``
(``lib/services/classifier/menu_analysis_prompt.dart``), the one schema the
app actually sends.
"""

import copy
import json
from pathlib import Path

from app.services.gemini import to_gemini_schema

_FIXTURE = Path(__file__).parent / "fixtures" / "menu_analysis_schema.json"


def _menu_analysis_schema() -> dict[str, object]:
    loaded: dict[str, object] = json.loads(_FIXTURE.read_text(encoding="utf-8"))
    return loaded


def _keys_anywhere(value: object) -> set[str]:
    if isinstance(value, dict):
        keys = set(value)
        for sub in value.values():
            keys |= _keys_anywhere(sub)
        return keys
    if isinstance(value, list):
        found: set[str] = set()
        for sub in value:
            found |= _keys_anywhere(sub)
        return found
    return set()


def _dish_properties(converted: dict[str, object]) -> dict[str, object]:
    properties = converted["properties"]
    assert isinstance(properties, dict)
    dishes = properties["dishes"]
    assert isinstance(dishes, dict)
    items = dishes["items"]
    assert isinstance(items, dict)
    dish_properties = items["properties"]
    assert isinstance(dish_properties, dict)
    return dish_properties


def test_no_additional_properties_remains_anywhere() -> None:
    converted = to_gemini_schema(_menu_analysis_schema())

    assert "additionalProperties" not in _keys_anywhere(converted)


def test_nullable_unions_become_a_type_and_nullable() -> None:
    dish = _dish_properties(to_gemini_schema(_menu_analysis_schema()))

    assert dish["modification"] == {"type": "string", "nullable": True}
    assert dish["net_carbs_estimate"] == {"type": "number", "nullable": True}


def test_enum_required_and_plain_types_survive() -> None:
    converted = to_gemini_schema(_menu_analysis_schema())
    dish = _dish_properties(converted)

    assert dish["verdict"] == {
        "type": "string",
        "enum": ["orderAsIs", "modifiable", "nonKeto"],
    }
    assert dish["id"] == {"type": "string"}
    assert converted["required"] == ["dishes"]
    assert converted["type"] == "object"


def test_whole_menu_analysis_schema_converts_exactly() -> None:
    converted = to_gemini_schema(_menu_analysis_schema())

    assert converted == {
        "type": "object",
        "required": ["dishes"],
        "properties": {
            "dishes": {
                "type": "array",
                "items": {
                    "type": "object",
                    "required": [
                        "id",
                        "name",
                        "verdict",
                        "why",
                        "modification",
                        "net_carbs_estimate",
                    ],
                    "properties": {
                        "id": {"type": "string"},
                        "name": {"type": "string"},
                        "verdict": {
                            "type": "string",
                            "enum": ["orderAsIs", "modifiable", "nonKeto"],
                        },
                        "why": {"type": "string"},
                        "modification": {"type": "string", "nullable": True},
                        "net_carbs_estimate": {"type": "number", "nullable": True},
                    },
                },
            }
        },
    }


def test_null_first_union_is_handled() -> None:
    converted = to_gemini_schema({"type": ["null", "integer"]})

    assert converted == {"type": "integer", "nullable": True}


def test_single_element_type_list_is_unwrapped_without_nullable() -> None:
    assert to_gemini_schema({"type": ["string"]}) == {"type": "string"}


def test_multi_type_union_is_left_for_upstream_to_judge() -> None:
    converted = to_gemini_schema({"type": ["string", "number", "null"]})

    assert converted == {"type": ["string", "number", "null"]}


def test_description_is_kept() -> None:
    converted = to_gemini_schema({"type": "string", "description": "A dish id."})

    assert converted == {"type": "string", "description": "A dish id."}


def test_input_is_never_mutated() -> None:
    schema = _menu_analysis_schema()
    before = copy.deepcopy(schema)

    converted = to_gemini_schema(schema)
    required = converted["required"]
    assert isinstance(required, list)
    required.append("mutated")

    assert schema == before

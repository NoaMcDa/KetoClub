"""``app.keto.vocabulary`` replays the golden ``vocabulary.json`` (#322, D25).

The packaged ``app/keto/vocabulary.json`` must be the golden file byte for
byte, and every value the loader types must write back to exactly the
golden value: nothing dropped, renamed or coerced.
"""

import json
from collections.abc import Mapping
from dataclasses import fields, is_dataclass
from pathlib import Path
from typing import Any

import pytest

from app.keto.normaliser import normalise
from app.keto.patterns import (
    dart_regexp_escape,
    hebrew_trigger_pattern,
    hebrew_trigger_source,
    latin_trigger_pattern,
    latin_trigger_source,
)
from app.keto.score import keto_score
from app.keto.vocabulary import VOCABULARY_PATH, parse_vocabulary, vocabulary

_GOLDEN = Path(__file__).parent / "fixtures" / "golden" / "vocabulary.json"
_RAW: dict[str, Any] = json.loads(_GOLDEN.read_text(encoding="utf-8"))


def _camel(name: str) -> str:
    head, *rest = name.split("_")
    return head + "".join(part.capitalize() for part in rest)


def _as_json(value: Any) -> Any:
    """A loaded vocabulary value back in the golden file's JSON shape."""
    if is_dataclass(value) and not isinstance(value, type):
        return {
            _camel(field.name): _as_json(getattr(value, field.name))
            for field in fields(value)
        }
    if isinstance(value, Mapping):
        return {key: _as_json(item) for key, item in value.items()}
    if isinstance(value, tuple):
        return [_as_json(item) for item in value]
    return value


def test_the_packaged_vocabulary_is_the_golden_file_byte_for_byte() -> None:
    assert VOCABULARY_PATH.read_bytes() == _GOLDEN.read_bytes()


@pytest.mark.parametrize("key", sorted(_RAW))
def test_every_section_loads_to_exactly_the_golden_value(key: str) -> None:
    loaded = _as_json(vocabulary())
    assert set(loaded) == set(_RAW)
    assert loaded[key] == _RAW[key]
    # Floats stay floats and ints stay ints (``0.5`` is not ``0``).
    assert json.dumps(loaded[key], sort_keys=True) == json.dumps(
        _RAW[key], sort_keys=True
    )


def test_the_vocabulary_is_loaded_once_and_frozen() -> None:
    assert vocabulary() is vocabulary()
    with pytest.raises(AttributeError):
        vocabulary().caps.max_why_length = 1  # type: ignore[misc]
    with pytest.raises(TypeError):
        vocabulary().trigger_suppresses["x"] = ()  # type: ignore[index]


def test_ordered_pairs_keep_the_dart_order() -> None:
    first_key, first_sentence = vocabulary().carb_modifiers_en[0]
    assert [first_key, first_sentence] == _RAW["carbModifiersEn"][0]


def test_the_trigger_pattern_sources_are_the_dart_sources() -> None:
    he = vocabulary().hebrew_trigger_pattern_example
    assert hebrew_trigger_source(he.trigger) == he.with_prefix
    assert hebrew_trigger_source(he.trigger, allow_prefix=False) == he.without_prefix
    assert (
        hebrew_trigger_source(he.trigger, allow_inflection=True) == he.with_inflection
    )
    latin = vocabulary().latin_trigger_pattern_example
    assert latin_trigger_source(latin.trigger) == latin.pattern
    assert latin.case_sensitive is False
    assert latin.unicode is False


def test_dart_regexp_escape_escapes_exactly_the_dart_set() -> None:
    assert dart_regexp_escape("a$()*+.?[\\]^{|}-/b") == (
        "a\\$\\(\\)\\*\\+\\.\\?\\[\\\\\\]\\^\\{\\|\\}-/b"
    )
    assert dart_regexp_escape("פסטה sweet") == "פסטה sweet"


@pytest.mark.parametrize(
    ("text", "matches"),
    [
        ("big pasta bowl", True),
        ("BIG PASTA", True),
        ("pastas", False),
        ("pasta_salad", False),
        ("ßpasta", True),
        ("פסטהpasta", True),
        ("\U0001d401pasta", True),
    ],
)
def test_the_latin_boundary_is_ascii_only(text: str, matches: bool) -> None:
    assert bool(latin_trigger_pattern("pasta").search(text)) is matches


@pytest.mark.parametrize(
    ("text", "allow_prefix", "matches"),
    [
        ("פסטה", True, True),
        ("הפסטה", True, True),
        ("ובהפסטה", True, False),
        ("הפסטה", False, False),
        ("פסטהי", True, False),
        ("pastaפסטה", False, True),
    ],
)
def test_the_hebrew_boundary_is_the_letter_range(
    text: str, allow_prefix: bool, matches: bool
) -> None:
    pattern = hebrew_trigger_pattern(normalise("פסטה"), allow_prefix=allow_prefix)
    assert bool(pattern.search(text)) is matches


def test_the_score_weights_are_the_formula_weights() -> None:
    weights = vocabulary().keto_score_weights
    one_yellow = keto_score(
        green_count=0, hidden_carb_yellow_count=0, other_yellow_count=1, red_count=0
    )
    one_hidden = keto_score(
        green_count=0, hidden_carb_yellow_count=1, other_yellow_count=0, red_count=0
    )
    assert one_yellow is not None and one_hidden is not None
    assert one_yellow / 10 == weights.yellow
    assert one_hidden / 10 == weights.hidden_carb_yellow


def _without(raw: dict[str, Any], *path: str) -> dict[str, Any]:
    copy: dict[str, Any] = json.loads(json.dumps(raw))
    node = copy
    for key in path[:-1]:
        node = node[key]
    del node[path[-1]]
    return copy


def _with(raw: dict[str, Any], value: Any, *path: str) -> dict[str, Any]:
    copy: dict[str, Any] = json.loads(json.dumps(raw))
    node = copy
    for key in path[:-1]:
        node = node[key]
    node[path[-1]] = value
    return copy


@pytest.mark.parametrize(
    "broken",
    [
        pytest.param([], id="not-an-object"),
        pytest.param(_without(_RAW, "caps"), id="missing-section"),
        pytest.param(_with(_RAW, "6", "caps", "maxWhyLength"), id="string-int"),
        pytest.param(_with(_RAW, True, "caps", "maxWhyLength"), id="bool-int"),
        pytest.param(_with(_RAW, "x", "nonKetoBasesEn"), id="string-list"),
        pytest.param(_with(_RAW, [1], "nonKetoBasesEn"), id="int-in-list"),
        pytest.param(_with(_RAW, [["a"]], "carbModifiersEn"), id="short-pair"),
        pytest.param(_with(_RAW, {}, "carbModifiersEn"), id="pairs-not-list"),
        pytest.param(
            _with(_RAW, "no", "dishKinds", "hebrewPrefixAllowed", "notice"),
            id="string-bool",
        ),
        pytest.param(_with(_RAW, "0.5", "ketoScoreWeights", "yellow"), id="str-num"),
    ],
)
def test_a_malformed_vocabulary_is_refused(broken: Any) -> None:
    with pytest.raises((ValueError, KeyError)):
        parse_vocabulary(broken)

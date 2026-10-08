"""``app.keto.heuristic`` replays the golden ``heuristic.json`` (#324, D25).

Each entry is one menu classified under one of the exporter's four option
sets, at the exporter's fixed clock. The whole analysis must come back equal
to the golden, key for key.
"""

import json
from pathlib import Path
from typing import Any

import pytest

from app.keto.heuristic import classify_heuristic
from app.keto.models import AnalysisOptionsSnapshot, Menu, to_json

_GOLDEN = Path(__file__).parent / "fixtures" / "golden" / "heuristic.json"
_ENTRIES: list[dict[str, Any]] = json.loads(_GOLDEN.read_text(encoding="utf-8"))


def _canonical(value: object) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2)


def test_the_golden_covers_every_option_set() -> None:
    names = {entry["name"].split("/")[1] for entry in _ENTRIES}
    assert names == {
        "defaults",
        "seedOilFree_dairyFree",
        "carnivoreOnly_limit10",
        "allRules_limit2",
    }


@pytest.mark.parametrize("entry", _ENTRIES, ids=[entry["name"] for entry in _ENTRIES])
def test_every_golden_menu_classifies_as_dart_does(entry: dict[str, Any]) -> None:
    assert set(entry) == {"name", "menu", "options", "analysis"}
    menu = Menu.model_validate(entry["menu"])
    options = AnalysisOptionsSnapshot.model_validate(entry["options"])
    analysis = classify_heuristic(
        menu, options, analysed_at=entry["analysis"]["analysedAt"]
    )
    assert _canonical(to_json(analysis)) == _canonical(entry["analysis"])

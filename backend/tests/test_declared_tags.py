"""``Dish.declaredTags`` through the wire model and both platform mappers
(Banto, ALG-09, #351): the Python halves of the Dart mapper and model tests.

The goldens pin the recorded fixtures (every Wolt item carries an empty
``dietary_preferences``; the synthetic 10bis dish ``1003`` is ``kosher``);
these cases pin the tolerant reads the fixtures do not reach.
"""

from typing import Any

from app.keto.models import Dish, VenueRef, to_json
from app.platforms.tenbis_menu import map_tenbis_menu
from app.platforms.wolt_menu import map_wolt_menu

_FETCHED_AT = "2026-01-01T00:00:00.000Z"


def _wolt(item: dict[str, Any]) -> Dish:
    raw = {
        "categories": [{"id": "c", "name": "Mains", "item_ids": ["i1"]}],
        "items": [{"id": "i1", "name": "Bowl", "price": 4200, **item}],
        "options": [],
    }
    menu = map_wolt_menu(
        raw,
        ref=VenueRef(source="wolt", platform_id="v"),
        fetched_at=_FETCHED_AT,
    )
    assert menu is not None
    return menu.all_dishes()[0]


def _tenbis(dish: dict[str, Any]) -> Dish:
    raw = {
        "categoriesList": [
            {
                "categoryName": "Mains",
                "dishList": [{"dishId": 1, "dishName": "Bowl", "price": 42, **dish}],
            }
        ]
    }
    menu = map_tenbis_menu(
        raw,
        ref=VenueRef(source="tenbis", platform_id="1"),
        fetched_at=_FETCHED_AT,
    )
    assert menu is not None
    return menu.all_dishes()[0]


def test_wolt_dietary_preferences_are_kept_raw() -> None:
    dish = _wolt({"dietary_preferences": ["VEGAN", "GLUTEN_FREE"]})
    assert dish.declared_tags == ["VEGAN", "GLUTEN_FREE"]
    assert to_json(dish)["declaredTags"] == ["VEGAN", "GLUTEN_FREE"]


def test_wolt_dietary_preferences_are_read_tolerantly() -> None:
    dish = _wolt(
        {
            "dietary_preferences": [
                {"id": "vegan", "name": "Vegan"},
                {"name": "Gluten free"},
                {"id": "  ", "name": "Dairy free"},
                "vegan",
                "",
                "  ",
                7,
                None,
                {"label": "ignored"},
            ]
        }
    )
    assert dish.declared_tags == ["vegan", "Gluten free", "Dairy free"]


def test_wolt_absent_or_malformed_dietary_preferences_are_no_tags() -> None:
    for item in ({}, {"dietary_preferences": None}, {"dietary_preferences": "VEGAN"}):
        dish = _wolt(item)
        assert dish.declared_tags == []
        assert "declaredTags" not in to_json(dish)


def test_tenbis_kosher_true_is_the_one_tag() -> None:
    assert _tenbis({"kosher": True}).declared_tags == ["kosher"]
    for value in (False, None, 1, "true"):
        assert _tenbis({"kosher": value}).declared_tags == []
    assert _tenbis({}).declared_tags == []


def test_the_wire_model_reads_tags_tolerantly_and_omits_none() -> None:
    base = {"id": "d", "name": "Bowl", "price": 1.0, "options": []}
    assert Dish.model_validate(base).declared_tags == []
    assert Dish.model_validate({**base, "declaredTags": "vegan"}).declared_tags == []
    tolerant = Dish.model_validate({**base, "declaredTags": ["vegan", 3, " ", ""]})
    assert tolerant.declared_tags == ["vegan"]
    written = to_json(Dish.model_validate({**base, "declaredTags": ["kosher"]}))
    assert list(written) == [
        "id",
        "name",
        "description",
        "price",
        "options",
        "imageUrl",
        "page",
        "declaredTags",
    ]
    assert "declaredTags" not in to_json(Dish.model_validate(base))

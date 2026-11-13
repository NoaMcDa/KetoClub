"""10bis ``NextApi/GetRestaurantMenu`` payload to ``Menu`` (D25, #323, #468).

Python twin of Dart ``TenBisMenuMapper`` (``lib/services/menu/tenbis/
tenbis_menu_mapper.dart``), whose doc comment holds the rules. Pure and never
raising: any shape the mapper does not know answers ``None``, and
``tenbis_menu_not_found`` tells 10bis's two "no such restaurant" answers
apart from that.

The menu sits in an envelope (``{Errors, Success, Data: {resId,
categoriesList}}``) and is nested (``categoriesList`` -> ``dishList`` ->
``choices`` -> ``subs``). A category id is ``cat_`` plus its numeric
``categoryID``, or a slug of its name without one; a ``dishId`` or
``categoryID`` number is written as Dart's ``toString`` writes it (``12.0``
stays ``"12.0"``); ``dishPrice`` is already in shekels. The payload names no
currency (``ILS``) and no restaurant (``venue_name`` is ``None``).
"""

import re

from pydantic import ValidationError

from app.keto.models import Dish, DishOption, Menu, MenuCategory, VenueRef
from app.platforms._dart import dart_num_to_string, dart_string_hash, is_num

_CURRENCY = "ILS"
"""10bis is Israel-only and its payload names no currency."""

_DASH_RUNS = re.compile(r"-+")
_EDGE_DASHES = re.compile(r"^-|-$")


def tenbis_menu_not_found(raw: object) -> bool:
    """Whether ``raw`` is 10bis saying it has no such restaurant: an explicit
    ``Success: false`` (a malformed id), or a ``Data`` whose
    ``categoriesList`` is null (an id no restaurant has). Dart
    ``TenBisMenuMapper.isNotFound``; both answers come with a 200."""
    if not isinstance(raw, dict):
        return False
    if raw.get("Success") is False:
        return True
    data = raw.get("Data")
    return (
        isinstance(data, dict)
        and "categoriesList" in data
        and data["categoriesList"] is None
    )


def map_tenbis_menu(raw: object, *, ref: VenueRef, fetched_at: str) -> Menu | None:
    """``raw`` as a ``Menu`` for ``ref`` stamped ``fetched_at`` (the Dart
    ``toIso8601String`` text), or ``None`` when it is not a payload this
    mapper knows."""
    try:
        return _try_build_menu(raw, ref, fetched_at)
    except (ValidationError, OverflowError):
        # A value the wire model refuses (an infinite price, say) is a shape
        # drift like any other; Dart would carry the infinity through.
        return None


def _try_build_menu(raw: object, ref: VenueRef, fetched_at: str) -> Menu | None:
    if not isinstance(raw, dict) or tenbis_menu_not_found(raw):
        return None
    data = raw.get("Data")
    if not isinstance(data, dict):
        return None
    raw_categories = data.get("categoriesList")
    if not isinstance(raw_categories, list):
        return None

    used_dish_ids: set[str] = set()
    categories: list[MenuCategory] = []
    for raw_category in raw_categories:
        category = _try_build_category(raw_category, used_dish_ids)
        if category is None:
            return None
        categories.append(category)

    return Menu(
        venue_ref=ref,
        currency=_CURRENCY,
        fetched_at=fetched_at,
        categories=categories,
        venue_name=None,
    )


def _try_build_category(raw: object, used_dish_ids: set[str]) -> MenuCategory | None:
    """One ``categoriesList[]`` entry; the first category to use a dish id
    keeps it."""
    if not isinstance(raw, dict):
        return None
    category_name = raw.get("categoryName")
    raw_dishes = raw.get("dishList")
    if not isinstance(category_name, str) or not category_name:
        return None
    if not isinstance(raw_dishes, list):
        return None

    dishes: list[Dish] = []
    for raw_dish in raw_dishes:
        dish = _try_build_dish(raw_dish)
        if dish is None:
            return None
        if dish.id in used_dish_ids:
            continue
        used_dish_ids.add(dish.id)
        dishes.append(dish)
    category_id = raw.get("categoryID")
    return MenuCategory(
        id=f"cat_{dart_num_to_string(category_id)}"
        if is_num(category_id)
        else _slugify_category_name(category_name),
        name=category_name,
        dishes=dishes,
    )


def _try_build_dish(raw: object) -> Dish | None:
    """One ``dishList[]`` entry; ``dishPrice`` is read as-is, never divided."""
    if not isinstance(raw, dict):
        return None
    dish_id = _try_read_dish_id(raw.get("dishId"))
    name = raw.get("dishName")
    raw_description = raw.get("dishDescription")
    raw_price = raw.get("dishPrice")
    raw_options = raw.get("choices")
    raw_image = raw.get("dishImageUrl")
    if dish_id is None:
        return None
    if not isinstance(name, str) or not name:
        return None
    if raw_description is not None and not isinstance(raw_description, str):
        return None
    if not is_num(raw_price) or raw_price < 0:
        return None
    if raw_options is not None and not isinstance(raw_options, list):
        return None

    options: list[DishOption] = []
    for raw_option in raw_options or []:
        option = _try_build_option_group(raw_option)
        if option is None:
            return None
        options.append(option)

    return Dish(
        id=dish_id,
        name=name,
        description=raw_description if isinstance(raw_description, str) else "",
        price=float(raw_price),
        options=options,
        image_url=raw_image if isinstance(raw_image, str) and raw_image else None,
    )


def _try_read_dish_id(raw: object) -> str | None:
    """A non-empty string as is, a number through Dart's ``toString``,
    ``None`` for anything else (an empty string included)."""
    if isinstance(raw, str):
        return raw or None
    if is_num(raw):
        return dart_num_to_string(raw)
    return None


def _try_build_option_group(raw: object) -> DishOption | None:
    """One ``choices[]`` entry: ``{textBeforeChoosing, subs: [{name}]}``."""
    if not isinstance(raw, dict):
        return None
    name = raw.get("textBeforeChoosing")
    raw_values = raw.get("subs")
    if not isinstance(name, str) or not name:
        return None
    if not isinstance(raw_values, list):
        return None
    values: list[str] = []
    for raw_value in raw_values:
        if not isinstance(raw_value, dict):
            return None
        value_name = raw_value.get("name")
        if not isinstance(value_name, str) or not value_name:
            return None
        values.append(value_name)
    return DishOption(name=name, values=values)


def _dart_lower(char: str) -> str:
    """Dart's one-to-one ``toLowerCase`` for one character (Python's can
    expand: ``İ`` becomes ``i`` plus a combining dot there, ``i`` in Dart)."""
    lowered = char.lower()
    return lowered if len(lowered) == 1 else lowered[0]


def _slugify_category_name(name: str) -> str:
    """For a category with no numeric ``categoryID``: ``cat_`` plus ``name``
    lower-cased, every character that is not an
    ASCII letter or digit or in the Hebrew block U+0590-U+05FF turned into
    ``-``, dash runs collapsed and edge dashes trimmed.

    A name with nothing left falls back to ``String.hashCode`` in hex, see
    ``dart_string_hash`` (unverified against a Dart VM).
    """
    pieces: list[str] = []
    for char in name:
        lower = _dart_lower(char)
        code = ord(lower)
        is_ascii_alnum = 0x30 <= code <= 0x39 or 0x61 <= code <= 0x7A
        is_hebrew = 0x0590 <= code <= 0x05FF
        pieces.append(lower if is_ascii_alnum or is_hebrew else "-")
    collapsed = _EDGE_DASHES.sub("", _DASH_RUNS.sub("-", "".join(pieces)))
    slug = collapsed or format(dart_string_hash(name), "x")
    return f"cat_{slug}"

"""10bis ``Restaurants/{id}/Menu`` payload to ``Menu`` (D25, #323).

Python twin of Dart ``TenBisMenuMapper`` (``lib/services/menu/tenbis/
tenbis_menu_mapper.dart``), whose doc comment holds the rules. Pure and never
raising: any shape the mapper does not know answers ``None``.

The payload is nested (``categoriesList`` -> ``dishList`` -> ``dishOptionsList``).
A category id is derived from its name (``cat_<slug>``); a ``dishId`` is a
non-empty string or a number written as Dart's ``toString`` writes it
(``12.0`` stays ``"12.0"``); prices are already in shekels.
"""

import re

from pydantic import ValidationError

from app.keto.models import Dish, DishOption, Menu, MenuCategory, VenueRef
from app.platforms._dart import dart_num_to_string, dart_string_hash, is_num

_DEFAULT_CURRENCY = "ILS"
"""10bis is Israel-only and no observed payload names a currency."""

_DASH_RUNS = re.compile(r"-+")
_EDGE_DASHES = re.compile(r"^-|-$")


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
    if not isinstance(raw, dict):
        return None
    raw_categories = raw.get("categoriesList")
    if not isinstance(raw_categories, list):
        return None

    used_dish_ids: set[str] = set()
    categories: list[MenuCategory] = []
    for raw_category in raw_categories:
        category = _try_build_category(raw_category, used_dish_ids)
        if category is None:
            return None
        categories.append(category)

    currency = raw.get("currency")
    venue_name = raw.get("restaurantName")
    return Menu(
        venue_ref=ref,
        currency=currency
        if isinstance(currency, str) and currency
        else _DEFAULT_CURRENCY,
        fetched_at=fetched_at,
        categories=categories,
        venue_name=venue_name if isinstance(venue_name, str) and venue_name else None,
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
    return MenuCategory(
        id=_slugify_category_name(category_name), name=category_name, dishes=dishes
    )


def _try_build_dish(raw: object) -> Dish | None:
    """One ``dishList[]`` entry; ``price`` is read as-is, never divided."""
    if not isinstance(raw, dict):
        return None
    dish_id = _try_read_dish_id(raw.get("dishId"))
    name = raw.get("dishName")
    raw_description = raw.get("dishDescription")
    raw_price = raw.get("price")
    raw_options = raw.get("dishOptionsList")
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
    """One ``dishOptionsList[]`` entry: ``{name, values: [{name}]}``."""
    if not isinstance(raw, dict):
        return None
    name = raw.get("name")
    raw_values = raw.get("values")
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
    """``cat_`` plus ``name`` lower-cased, every character that is not an
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

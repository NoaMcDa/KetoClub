"""Wolt consumer-assortment payload to ``Menu`` (D25, #323).

Python twin of Dart ``WoltMenuMapper`` (``lib/services/menu/wolt/
wolt_menu_mapper.dart``), whose doc comment holds the rules. Pure and never
raising: any shape the mapper does not know answers ``None`` (Dart's
``platformChanged``).

The payload is three flat sibling collections, ``categories``, ``items`` and
``options``, joined by id. Prices are integer agorot, divided by 100; the
currency is ``ILS`` unless a non-empty top-level ``currency`` says otherwise;
a category's ``item_ids`` come first, then its (recursive) subcategories'; an
unknown ``item_id`` or ``option_id`` is skipped; the first category to claim
a dish id keeps it; ``venueName`` is always null.
"""

from typing import Any

from pydantic import ValidationError

from app.keto.models import Dish, DishOption, Menu, MenuCategory, VenueRef
from app.platforms._dart import is_num

DEFAULT_CURRENCY = "ILS"
"""The currency of every Wolt Israel venue; the payload carries none."""


def map_wolt_menu(raw: object, *, ref: VenueRef, fetched_at: str) -> Menu | None:
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
    raw_currency = raw.get("currency")
    raw_categories = raw.get("categories")
    raw_items = raw.get("items")
    raw_options = raw.get("options")
    if not isinstance(raw_categories, list):
        return None
    if not isinstance(raw_items, list):
        return None
    if raw_options is not None and not isinstance(raw_options, list):
        return None

    option_groups: dict[str, DishOption] = {}
    for raw_option in raw_options or []:
        entry = _try_build_option_group(raw_option)
        if entry is None:
            return None
        option_groups[entry[0]] = entry[1]

    items_by_id: dict[str, Dish] = {}
    for raw_item in raw_items:
        dish = _try_build_item(raw_item, option_groups)
        if dish is None:
            return None
        items_by_id[dish.id] = dish

    used_dish_ids: set[str] = set()
    categories: list[MenuCategory] = []
    for raw_category in raw_categories:
        category = _try_build_category(raw_category, items_by_id, used_dish_ids)
        if category is None:
            return None
        categories.append(category)

    return Menu(
        venue_ref=ref,
        currency=(
            raw_currency
            if isinstance(raw_currency, str) and raw_currency
            else DEFAULT_CURRENCY
        ),
        fetched_at=fetched_at,
        categories=categories,
    )


def _try_build_option_group(raw: object) -> tuple[str, DishOption] | None:
    """One entry of the top-level ``options[]`` id-lookup table."""
    if not isinstance(raw, dict):
        return None
    option_id = raw.get("id")
    name = raw.get("name")
    raw_values = raw.get("values")
    if not isinstance(option_id, str) or not option_id:
        return None
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
    return option_id, DishOption(name=name, values=values)


def _try_build_item(raw: object, option_groups: dict[str, DishOption]) -> Dish | None:
    """One ``items[]`` entry; ``price`` goes from agorot to major units."""
    if not isinstance(raw, dict):
        return None
    item_id = raw.get("id")
    name = raw.get("name")
    raw_description = raw.get("description")
    raw_price = raw.get("price")
    raw_item_options = raw.get("options")
    if raw_item_options is None:
        raw_item_options = []
    if not isinstance(item_id, str) or not item_id:
        return None
    if not isinstance(name, str) or not name:
        return None
    if raw_description is not None and not isinstance(raw_description, str):
        return None
    if not is_num(raw_price) or raw_price < 0:
        return None
    if not isinstance(raw_item_options, list):
        return None
    options: list[DishOption] = []
    for raw_item_option in raw_item_options:
        if not isinstance(raw_item_option, dict):
            return None
        option_id = raw_item_option.get("option_id")
        if not isinstance(option_id, str):
            return None
        group = option_groups.get(option_id)
        if group is None:
            continue
        label = raw_item_option.get("name")
        if isinstance(label, str) and label and label != group.name:
            options.append(DishOption(name=label, values=group.values))
        else:
            options.append(group)
    return Dish(
        id=item_id,
        name=name,
        description=raw_description if isinstance(raw_description, str) else "",
        price=raw_price / 100,
        options=options,
        image_url=_try_read_image_url(raw.get("images")),
    )


def _try_read_image_url(raw_images: object) -> str | None:
    """The first image's ``url`` when it is a non-empty string, else null."""
    if not isinstance(raw_images, list) or not raw_images:
        return None
    first: Any = raw_images[0]
    if not isinstance(first, dict):
        return None
    url = first.get("url")
    return url if isinstance(url, str) and url else None


def _try_build_category(
    raw: object, items_by_id: dict[str, Dish], used_dish_ids: set[str]
) -> MenuCategory | None:
    """One ``categories[]`` entry; the first category to use a dish keeps it."""
    if not isinstance(raw, dict):
        return None
    category_id = raw.get("id")
    name = raw.get("name")
    if not isinstance(category_id, str) or not category_id:
        return None
    if not isinstance(name, str) or not name:
        return None
    item_ids = _try_read_item_ids(raw.get("item_ids"))
    if item_ids is None:
        return None
    dishes: list[Dish] = []
    for item_id in [*item_ids, *_subcategory_item_ids(raw)]:
        dish = items_by_id.get(item_id)
        if dish is None:
            continue
        if dish.id in used_dish_ids:
            continue
        used_dish_ids.add(dish.id)
        dishes.append(dish)
    return MenuCategory(id=category_id, name=name, dishes=dishes)


def _try_read_item_ids(raw: object) -> list[str] | None:
    """``raw`` as a list of id strings, or ``None`` for anything else."""
    if not isinstance(raw, list):
        return None
    ids: list[str] = []
    for item_id in raw:
        if not isinstance(item_id, str):
            return None
        ids.append(item_id)
    return ids


def _subcategory_item_ids(category: dict[str, Any]) -> list[str]:
    """Every item id under ``category``'s ``subcategories``, depth first.

    Tolerant by design: an absent or malformed list, or a malformed entry,
    contributes nothing.
    """
    raw_subcategories = category.get("subcategories")
    if not isinstance(raw_subcategories, list):
        return []
    ids: list[str] = []
    for raw_subcategory in raw_subcategories:
        if not isinstance(raw_subcategory, dict):
            continue
        item_ids = _try_read_item_ids(raw_subcategory.get("item_ids"))
        if item_ids is None:
            continue
        ids.extend(item_ids)
        ids.extend(_subcategory_item_ids(raw_subcategory))
    return ids

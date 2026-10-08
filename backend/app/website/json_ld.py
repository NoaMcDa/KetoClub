"""schema.org menu markup out of a page's JSON-LD blocks (D19, #326).

The Python twin of ``JsonLdMenuMapper``: ``Menu`` -> ``MenuSection`` ->
``MenuItem``, and a ``Restaurant``'s ``hasMenu`` link. Pure and never raises:
a block of any other shape yields nothing. The markup is rare and often
partial, so it is tried first because it is cheap, not because it is
expected to hit.
"""

from collections.abc import Iterator
from typing import Any

from app.keto.dart_text import dart_trim
from app.keto.models import Dish, MenuCategory
from app.keto.text_menu import scrub_lone_surrogates
from app.keto.vocabulary import vocabulary
from app.website.html import DartUri, UriFormatError


def categories_from(blocks: list[Any]) -> list[MenuCategory] | None:
    """The categories of every schema.org ``Menu`` in ``blocks``, or ``None``
    when none holds a named item.

    Each ``MenuSection`` (nested ones flattened) is a category; items directly
    on a ``Menu`` go to a category named after the menu. Every dish gets
    ``price 0`` (a site's price is unverified) and an id ``j1..jN`` in
    document order, at most ``maxAnalysedDishes`` of them.
    """
    max_dishes = vocabulary().caps.max_analysed_dishes
    categories: list[MenuCategory] = []
    dish_count = 0

    def add_category(name: str, items: list[Any]) -> None:
        nonlocal dish_count
        dishes: list[Dish] = []
        for item in items:
            if dish_count >= max_dishes:
                break
            if not isinstance(item, dict):
                continue
            dish_name = _text(item.get("name"))
            if dish_name is None:
                continue
            dish_count += 1
            dishes.append(
                Dish(
                    id=f"j{dish_count}",
                    name=dish_name,
                    description=_text(item.get("description")) or "",
                    price=0.0,
                    options=[],
                )
            )
        if not dishes:
            return
        categories.append(
            MenuCategory(id=f"jsonld-{len(categories) + 1}", name=name, dishes=dishes)
        )

    def add_sections(sections: list[Any], fallback_name: str) -> None:
        # Pre-order, nested sections flattened; a stack, not recursion, so a
        # deeply nested page cannot exhaust Python's stack.
        pending = [(child, fallback_name) for child in reversed(sections)]
        while pending:
            section, fallback = pending.pop()
            if not isinstance(section, dict):
                continue
            name = _text(section.get("name")) or fallback
            add_category(name, _list(section.get("hasMenuItem")))
            pending.extend(
                (child, name)
                for child in reversed(_list(section.get("hasMenuSection")))
            )

    for menu in _nodes_of_type(blocks, "Menu"):
        name = _text(menu.get("name")) or "Menu"
        add_category(name, _list(menu.get("hasMenuItem")))
        add_sections(_list(menu.get("hasMenuSection")), name)
    return categories or None


def menu_url_from(blocks: list[Any], base: DartUri) -> DartUri | None:
    """The first menu page a ``hasMenu`` (or a ``Menu``'s own ``url``) points
    to, resolved against ``base``, or ``None`` when there is none."""
    for node in _all_nodes(blocks):
        for target in _list(node.get("hasMenu")):
            if isinstance(target, dict):
                url = _text(target.get("url")) or _text(target.get("@id"))
            else:
                url = _text(target)
            resolved = _http_uri(url, base)
            if resolved is not None:
                return resolved
    for menu in _nodes_of_type(blocks, "Menu"):
        resolved = _http_uri(_text(menu.get("url")), base)
        if resolved is not None:
            return resolved
    return None


def _http_uri(value: str | None, base: DartUri) -> DartUri | None:
    if value is None:
        return None
    try:
        resolved = base.resolve(value)
    except UriFormatError:
        return None
    return resolved if resolved.scheme in ("http", "https") else None


def _all_nodes(blocks: list[Any]) -> Iterator[dict[str, Any]]:
    """Every JSON object anywhere in ``blocks``, ``@graph`` members included,
    outermost first."""
    pending: list[Any] = list(blocks)
    index = 0
    while index < len(pending):
        node = pending[index]
        index += 1
        if isinstance(node, dict):
            yield node
            pending.extend(node.values())
        elif isinstance(node, list):
            pending.extend(node)


def _nodes_of_type(blocks: list[Any], node_type: str) -> list[dict[str, Any]]:
    """The objects whose ``@type`` is ``node_type`` or a list holding it, in
    document order (a match is not searched further)."""
    found: list[dict[str, Any]] = []
    pending: list[Any] = [blocks]
    while pending:
        node = pending.pop()
        if isinstance(node, list):
            pending.extend(reversed(node))
        elif isinstance(node, dict):
            if node_type in _list(node.get("@type")):
                found.append(node)
            else:
                pending.extend(reversed(list(node.values())))
    return found


def _list(value: Any) -> list[Any]:
    if value is None:
        return []
    return value if isinstance(value, list) else [value]


def _text(value: Any) -> str | None:
    """``value`` trimmed, when it is a non-blank string."""
    if not isinstance(value, str):
        return None
    trimmed = scrub_lone_surrogates(dart_trim(value))
    return trimmed or None

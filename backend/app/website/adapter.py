"""The pure decision steps of ``WebsiteMenuAdapter`` (D19, #326).

The Dart adapter fetches the pasted page, then decides what it holds; this
module is that deciding without the fetching. The route that does the I/O
calls :func:`read_page` on the page it fetched and acts on the answer:

* :class:`Located`: the menu is in the page itself (JSON-LD markup, or the
  page's own priced text through :func:`app.keto.text_menu.parse`).
* :class:`NeedsFetch`: the page links to a menu page. Fetch it once (never a
  second hop) and read it with :func:`read_linked_page`.
* :class:`PdfLink`: the page links to a PDF. Fetch it and send it to the
  vision path (no text layer: it reverses most Hebrew PDFs).
* :class:`Failed`: nothing readable, and why.

A link's fetch can still fail, or turn out to hold nothing: both carry the
page's own text read (``fallback``) as the last resort, and
:func:`finish_after_link` applies Dart's rule (the linked result when it
worked, else the page's text, else the link's own failure).

Any text read from a page is rejected as ``menuNotFound`` when
:func:`looks_character_reversed` says it is reversed Hebrew.
"""

import re
from dataclasses import dataclass
from datetime import datetime
from typing import Final

from app.keto.models import Menu, MenuCategory, VenueRef
from app.keto.text_menu import dart_iso8601, parse
from app.keto.vocabulary import vocabulary
from app.website.html import DartUri, is_javascript_only, reserves_ai
from app.website.locator import JsonLdMenuFound, MenuLinkFound, locate, menu_text

_CURRENCY: Final = "ILS"
_HEBREW_WORD: Final = re.compile("[א-ת]+")
_FINAL_FORMS: Final = "ךםןףץ"
_HEBREW_LETTER: Final = re.compile("[א-ת]")

DISALLOWED_BY_ROBOTS: Final = "disallowedByRobots"
JS_ONLY_PAGE: Final = "jsOnlyPage"
MENU_NOT_FOUND: Final = "menuNotFound"


def looks_character_reversed(text: str) -> bool:
    """Whether ``text`` reads as character-reversed Hebrew (``hebrew_order.dart``).

    A text layer extracted from a Hebrew PDF, or an old "visual Hebrew" page,
    can come out with every word's letters backwards. Hebrew writes a
    final-form letter only at the end of a word, so a word that *starts* with
    one is proof the text is reversed, and one such word rejects the whole
    text. Text with no Hebrew is never reversed by this test.
    """
    return any(
        match.group(0)[0] in _FINAL_FORMS for match in _HEBREW_WORD.finditer(text)
    )


@dataclass(frozen=True)
class Located:
    """The menu found in the page's text or markup: ``categories``, every dish
    priced ``0`` (a site's price is unverified)."""

    categories: list[MenuCategory]

    def to_menu(self, ref: VenueRef, *, now: datetime | str) -> Menu:
        """The ``Menu`` ``WebsiteMenuAdapter._stamp`` builds for ``ref``."""
        return Menu(
            venue_ref=ref,
            currency=_CURRENCY,
            fetched_at=now if isinstance(now, str) else dart_iso8601(now),
            categories=self.categories,
        )


@dataclass(frozen=True)
class Failed:
    """A page with nothing readable. ``reason`` is the Dart
    ``MenuFetchFailureReason`` name: ``disallowedByRobots`` (the page opts
    out of AI use), ``jsOnlyPage`` or ``menuNotFound``."""

    reason: str


@dataclass(frozen=True)
class NeedsFetch:
    """The page links to a menu page at ``url``; ``fallback`` is the page's
    own text read, the last resort when the link yields nothing."""

    url: DartUri
    fallback: "Located | Failed | None"


@dataclass(frozen=True)
class PdfLink:
    """The page links to a PDF at ``url`` (for the vision path); ``fallback``
    is as for :class:`NeedsFetch`."""

    url: DartUri
    fallback: "Located | Failed | None"


PageReading = Located | Failed | NeedsFetch | PdfLink


def read_page(
    html: str,
    final_url: DartUri | str,
    *,
    now: datetime | str,
    uncategorised_name: str | None = None,
) -> PageReading:
    """``WebsiteMenuAdapter._fromPage`` without the fetching.

    ``final_url`` is the page's URL after redirects (a string is parsed and
    may raise :class:`~app.website.html.UriFormatError`). ``now`` only stamps
    the intermediate text parse. ``uncategorised_name`` overrides the name of
    the section holding dishes before any header; by default it is the Hebrew
    or English website name, by whether the page text holds a Hebrew letter.
    """
    if reserves_ai(html):
        return Failed(DISALLOWED_BY_ROBOTS)
    page_url = _as_uri(final_url)
    location = locate(html, page_url)
    # JSON-LD is data in the page source: readable however the page is
    # rendered, so it is taken before the JavaScript-only test.
    if isinstance(location, JsonLdMenuFound):
        return _menu_from(location.categories)
    if is_javascript_only(html):
        return Failed(JS_ONLY_PAGE)
    fallback = _from_text(html, now=now, uncategorised_name=uncategorised_name)
    if isinstance(location, MenuLinkFound):
        if location.is_pdf:
            return PdfLink(location.uri, fallback)
        return NeedsFetch(location.uri, fallback)
    return fallback if fallback is not None else Failed(MENU_NOT_FOUND)


def read_linked_page(
    html: str,
    final_url: DartUri | str,
    *,
    now: datetime | str,
    uncategorised_name: str | None = None,
) -> Located | Failed:
    """``WebsiteMenuAdapter._followLink`` for a page: read for JSON-LD or
    text, never followed further."""
    if reserves_ai(html):
        return Failed(DISALLOWED_BY_ROBOTS)
    location = locate(html, _as_uri(final_url))
    if isinstance(location, JsonLdMenuFound):
        return _menu_from(location.categories)
    if is_javascript_only(html):
        return Failed(JS_ONLY_PAGE)
    found = _from_text(html, now=now, uncategorised_name=uncategorised_name)
    return found if found is not None else Failed(MENU_NOT_FOUND)


def finish_after_link[T](
    pending: NeedsFetch | PdfLink, linked: T | Failed
) -> T | Located | Failed:
    """The result once ``pending``'s link has been followed: ``linked`` when
    it is not a :class:`Failed`; otherwise the page's own text if it had a
    reading (even a ``Failed`` one), else the link's own failure."""
    if not isinstance(linked, Failed):
        return linked
    return pending.fallback if pending.fallback is not None else linked


def _as_uri(url: DartUri | str) -> DartUri:
    return url if isinstance(url, DartUri) else DartUri.parse(url)


def _menu_from(categories: list[MenuCategory]) -> Located | Failed:
    for category in categories:
        for dish in category.dishes:
            if looks_character_reversed(dish.name) or looks_character_reversed(
                dish.description
            ):
                return Failed(MENU_NOT_FOUND)
    return Located(categories)


def _from_text(
    html: str, *, now: datetime | str, uncategorised_name: str | None
) -> Located | Failed | None:
    """The menu in ``html``'s own text, or ``None`` when it holds none."""
    text = menu_text(html)
    if text is None:
        return None
    website = vocabulary().website
    name = uncategorised_name or (
        website.website_category_name_he
        if _HEBREW_LETTER.search(text)
        else website.website_category_name_en
    )
    parsed = parse(text, now=now, uncategorised_name=name)
    if parsed is None:
        return None
    return _menu_from(parsed.categories)

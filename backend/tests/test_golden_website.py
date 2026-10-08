"""Replay of ``fixtures/golden/website.json`` through the Python port.

Each golden entry is one HTML page, the URL it was fetched from and every
reading the Dart ``WebsiteHtml``, ``JsonLdMenuMapper`` and
``WebsiteMenuLocator`` made of it. The Python port must answer the same for
every recorded field, once both sides are written as canonical JSON (#326).
"""

import json
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

import pytest

from app.keto.models import VenueRef, to_json
from app.keto.text_menu import parse
from app.keto.vocabulary import vocabulary
from app.website import html as website_html
from app.website.adapter import (
    Failed,
    Located,
    NeedsFetch,
    PdfLink,
    finish_after_link,
    looks_character_reversed,
    read_linked_page,
    read_page,
)
from app.website.html import DartUri, UriFormatError, decode_full
from app.website.json_ld import categories_from, menu_url_from
from app.website.locator import locate, location_to_json, menu_text

_GOLDEN = Path(__file__).parent / "fixtures" / "golden" / "website.json"
_ENTRIES: list[dict[str, Any]] = json.loads(_GOLDEN.read_text(encoding="utf-8"))
_GOLDEN_NOW = datetime(2026, 1, 1, tzinfo=UTC)
_IDS = [entry["name"] for entry in _ENTRIES]


def _canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, ensure_ascii=False)


def _entry(name: str) -> dict[str, Any]:
    return next(entry for entry in _ENTRIES if entry["name"] == name)


def test_golden_is_not_empty() -> None:
    assert len(_ENTRIES) >= 25
    kinds = {entry["located"]["kind"] for entry in _ENTRIES}
    assert kinds == {"jsonLd", "link", "none"}


@pytest.mark.parametrize("entry", _ENTRIES, ids=_IDS)
def test_lines(entry: dict[str, Any]) -> None:
    assert website_html.lines(entry["html"]) == entry["lines"]


@pytest.mark.parametrize("entry", _ENTRIES, ids=_IDS)
def test_json_ld_blocks(entry: dict[str, Any]) -> None:
    blocks = website_html.json_ld_blocks(entry["html"])
    assert _canonical(blocks) == _canonical(entry["jsonLdBlocks"])


@pytest.mark.parametrize("entry", _ENTRIES, ids=_IDS)
def test_links(entry: dict[str, Any]) -> None:
    base = DartUri.parse(entry["baseUrl"])
    actual = [
        {"uri": link.uri.to_string(), "text": link.text}
        for link in website_html.links(entry["html"], base)
    ]
    assert _canonical(actual) == _canonical(entry["links"])


@pytest.mark.parametrize("entry", _ENTRIES, ids=_IDS)
def test_javascript_only_and_ai_reservation(entry: dict[str, Any]) -> None:
    assert website_html.is_javascript_only(entry["html"]) is entry["isJavaScriptOnly"]
    assert website_html.reserves_ai(entry["html"]) is entry["reservesAi"]


@pytest.mark.parametrize("entry", _ENTRIES, ids=_IDS)
def test_json_ld_categories_and_menu_url(entry: dict[str, Any]) -> None:
    blocks = website_html.json_ld_blocks(entry["html"])
    categories = categories_from(blocks)
    actual = None if categories is None else [to_json(c) for c in categories]
    assert _canonical(actual) == _canonical(entry["jsonLdCategories"])
    url = menu_url_from(blocks, DartUri.parse(entry["baseUrl"]))
    assert (None if url is None else url.to_string()) == entry["jsonLdMenuUrl"]


@pytest.mark.parametrize("entry", _ENTRIES, ids=_IDS)
def test_located(entry: dict[str, Any]) -> None:
    location = locate(entry["html"], DartUri.parse(entry["baseUrl"]))
    assert _canonical(location_to_json(location)) == _canonical(entry["located"])


@pytest.mark.parametrize("entry", _ENTRIES, ids=_IDS)
def test_menu_text_text_menu_and_reversal(entry: dict[str, Any]) -> None:
    text = menu_text(entry["html"])
    assert text == entry["menuText"]
    website = vocabulary().website
    text_menu = (
        None
        if text is None
        else parse(
            text,
            now=_GOLDEN_NOW,
            uncategorised_name=(
                website.website_category_name_he
                if any("א" <= char <= "ת" for char in text)
                else website.website_category_name_en
            ),
        )
    )
    actual_menu = None if text_menu is None else to_json(text_menu)
    assert _canonical(actual_menu) == _canonical(entry["textMenu"])

    categories = categories_from(website_html.json_ld_blocks(entry["html"]))
    read = (
        categories
        if categories is not None
        else (None if text_menu is None else text_menu.categories)
    )
    reversed_text = (
        None
        if read is None
        else any(
            looks_character_reversed(dish.name)
            or looks_character_reversed(dish.description)
            for category in read
            for dish in category.dishes
        )
    )
    assert reversed_text == entry["anyCharacterReversed"]


# --- Dart ``Uri.resolve(...).toString()`` ---------------------------------------
# Recorded by running Dart's own ``Uri.parse(base).resolve(ref).removeFragment()``
# (Dart 3.13, the call ``WebsiteHtml.links`` makes);
# ``None`` is a ``FormatException``. Beyond the golden pages, this pins the
# escaping and resolution rules link handling relies on.

_URI_TABLE: list[tuple[str, str, str | None]] = [
    ("https://cafe.example/he/menu/", "/menu", "https://cafe.example/menu"),
    ("https://cafe.example/he/menu/", "menu", "https://cafe.example/he/menu/menu"),
    (
        "https://cafe.example/he/menu/",
        "../up/MENU.PDF",
        "https://cafe.example/he/up/MENU.PDF",
    ),
    ("https://cafe.example/he/menu/", "../../../x", "https://cafe.example/x"),
    (
        "https://cafe.example/he/menu/",
        "./a/./b/../c",
        "https://cafe.example/he/menu/a/c",
    ),
    (
        "https://cafe.example/he/menu/",
        "//www.Cafe.Example:443/Menu",
        "https://www.cafe.example/Menu",
    ),
    ("https://cafe.example/he/menu/", "HTTP://X.COM:80/a", "http://x.com/a"),
    ("https://cafe.example/he/menu/", "https://x.com:443/a", "https://x.com/a"),
    ("https://cafe.example/he/menu/", "https://x.com:8443/a", "https://x.com:8443/a"),
    ("https://cafe.example/he/menu/", "https://u:p@x.com/a", "https://u:p@x.com/a"),
    ("https://cafe.example/he/menu/", "/a b", "https://cafe.example/a%20b"),
    ("https://cafe.example/he/menu/", "/a%20b", "https://cafe.example/a%20b"),
    ("https://cafe.example/he/menu/", "/%7e%41%fa", "https://cafe.example/~A%FA"),
    ("https://cafe.example/he/menu/", "/%7E%41%FA", "https://cafe.example/~A%FA"),
    ("https://cafe.example/he/menu/", "/%zz", "https://cafe.example/%25zz"),
    ("https://cafe.example/he/menu/", "/100%", "https://cafe.example/100%25"),
    (
        "https://cafe.example/he/menu/",
        "/תפריט",
        "https://cafe.example/%D7%AA%D7%A4%D7%A8%D7%99%D7%98",
    ),
    ("https://cafe.example/he/menu/", "/😀", "https://cafe.example/%F0%9F%98%80"),
    (
        "https://cafe.example/he/menu/",
        "/a[1]?b[]=c",
        "https://cafe.example/a%5B1%5D?b%5B%5D=c",
    ),
    ("https://cafe.example/he/menu/", "/a\\b", "https://cafe.example/a/b"),
    ("https://cafe.example/he/menu/", "\\\\x.com\\p", "https://x.com/p"),
    ("https://cafe.example/he/menu/", "?x=1", "https://cafe.example/he/menu/?x=1"),
    ("https://cafe.example/he/menu/", "?", "https://cafe.example/he/menu/?"),
    ("https://cafe.example/he/menu/", "#frag", "https://cafe.example/he/menu/"),
    ("https://cafe.example/he/menu/", "", "https://cafe.example/he/menu/"),
    ("https://cafe.example/he/menu/", "x?y#z", "https://cafe.example/he/menu/x?y"),
    ("https://cafe.example/he/menu/", "http://[::1]:8080/a", "http://[::1]:8080/a"),
    ("https://cafe.example/he/menu/", "http://[::1", None),
    ("https://cafe.example/he/menu/", "http://x.com:abc/", None),
    ("https://cafe.example/he/menu/", "http://exa mple.com/", "http://exa%20mple.com/"),
    (
        "https://cafe.example/he/menu/",
        "http://קפה.com/",
        "http://%D7%A7%D7%A4%D7%94.com/",
    ),
    ("https://cafe.example/he/menu/", "HTTP://%41bc.com/", "http://abc.com/"),
    ("https://cafe.example/he/menu/", ":abc", None),
    ("https://cafe.example/he/menu/", "1a:b", None),
    ("https://cafe.example/he/menu/", "a b:c", None),
    ("https://cafe.example/he/menu/", "mailto:a@b.c", "mailto:a@b.c"),
    ("https://cafe.example/he/menu/", "tel:+972501234567", "tel:+972501234567"),
    ("https://cafe.example/he/menu/", "javascript:void(0)", "javascript:void(0)"),
    ("https://cafe.example/he/menu/", "./a:b", "https://cafe.example/he/menu/a%3Ab"),
    ("https://x.com", "menu", "https://x.com/menu"),
    ("https://x.com", "../menu", "https://x.com/menu"),
    ("https://x.com", "?q=1", "https://x.com?q=1"),
    ("https://x.com/a/b", "c", "https://x.com/a/c"),
    ("https://x.com/a/b/", "../../../c", "https://x.com/c"),
    ("https://x.com/a?b#c", "d", "https://x.com/d"),
    ("https://x.com/a?b#c", "", "https://x.com/a?b"),
    ("https://x.com/a?b#c", "?e", "https://x.com/a?e"),
    ("https://x.com:80/a", "//y.com", "https://y.com"),
    ("http://x.com:80/a", "//y.com:80/b", "http://y.com/b"),
    ("https://x.com/a/b/c/d", "../../x/./y/../z", "https://x.com/a/x/z"),
    ("https://x.com/a/./b", "c", "https://x.com/a/c"),
]


@pytest.mark.parametrize(
    ("base", "reference", "expected"),
    _URI_TABLE,
    ids=[f"{index:02d}-{row[1]}" for index, row in enumerate(_URI_TABLE)],
)
def test_dart_uri_resolution(base: str, reference: str, expected: str | None) -> None:
    try:
        actual: str | None = (
            DartUri.parse(base).resolve(reference).remove_fragment().to_string()
        )
    except UriFormatError:
        actual = None
    assert actual == expected


# --- the adapter's pure decision steps ----------------------------------------

_MENU_PAGE = (
    "<p>Caesar salad 52</p><p>romaine, parmesan</p><p>Steak 98</p><p>Salmon 88</p>"
)
_PRICED_TEXT_NAMES = ["Caesar salad", "Steak", "Salmon"]


def _names(reading: Located) -> list[str]:
    return [dish.name for c in reading.categories for dish in c.dishes]


def test_a_priced_page_is_read_as_its_own_menu() -> None:
    reading = read_page(_MENU_PAGE, "https://cafe.example/", now=_GOLDEN_NOW)
    assert isinstance(reading, Located)
    assert _names(reading) == _PRICED_TEXT_NAMES
    assert reading.categories[0].name == "Menu"


def test_hebrew_page_text_gets_the_hebrew_section_name() -> None:
    page = "<p>סלט 52</p><p>שקשוקה 48</p><p>חומוס 30</p>"
    reading = read_page(page, "https://cafe.example/", now=_GOLDEN_NOW)
    assert isinstance(reading, Located)
    assert reading.categories[0].name == "תפריט"


def test_the_section_name_can_be_overridden() -> None:
    reading = read_page(
        _MENU_PAGE, "https://cafe.example/", now=_GOLDEN_NOW, uncategorised_name="Food"
    )
    assert isinstance(reading, Located)
    assert reading.categories[0].name == "Food"


def test_located_stamps_a_menu() -> None:
    reading = read_page(
        _MENU_PAGE, DartUri.parse("https://c.example/"), now=_GOLDEN_NOW
    )
    assert isinstance(reading, Located)
    ref = VenueRef(source="website", platform_id="https://c.example/")
    menu = reading.to_menu(ref, now=_GOLDEN_NOW)
    assert menu.venue_ref == ref
    assert menu.currency == "ILS"
    assert menu.fetched_at == "2026-01-01T00:00:00.000Z"
    assert menu.categories == reading.categories


def test_an_ai_opt_out_stops_the_read() -> None:
    page = '<meta name="robots" content="noai">' + _MENU_PAGE
    assert read_page(page, "https://c.example/", now=_GOLDEN_NOW) == Failed(
        "disallowedByRobots"
    )
    assert read_linked_page(page, "https://c.example/", now=_GOLDEN_NOW) == Failed(
        "disallowedByRobots"
    )


def test_a_javascript_only_page_stops_the_read_but_json_ld_is_taken_first() -> None:
    shell = '<div id="root"></div><script src="a.js"></script>'
    assert read_page(shell, "https://c.example/", now=_GOLDEN_NOW) == Failed(
        "jsOnlyPage"
    )
    assert read_linked_page(shell, "https://c.example/", now=_GOLDEN_NOW) == Failed(
        "jsOnlyPage"
    )
    ld = (
        '<script type="application/ld+json">{"@type":"Menu","hasMenuItem":'
        '[{"name":"Soup"}]}</script>'
    )
    reading = read_page(shell + ld, "https://c.example/", now=_GOLDEN_NOW)
    assert isinstance(reading, Located)
    assert _names(reading) == ["Soup"]


def test_a_page_with_no_menu_is_menu_not_found() -> None:
    page = "<p>Welcome</p>"
    assert read_page(page, "https://c.example/", now=_GOLDEN_NOW) == Failed(
        "menuNotFound"
    )
    assert read_linked_page(page, "https://c.example/", now=_GOLDEN_NOW) == Failed(
        "menuNotFound"
    )


def test_reversed_hebrew_is_rejected_whichever_way_it_was_read() -> None:
    text_page = "<p>ףבא 52</p><p>ךלמ 48</p><p>סלט 30</p>"
    assert read_page(text_page, "https://c.example/", now=_GOLDEN_NOW) == Failed(
        "menuNotFound"
    )
    ld = (
        '<script type="application/ld+json">{"@type":"Menu","hasMenuItem":'
        '[{"name":"ם"},{"name":"ok","description":"ןב"}]}</script>'
    )
    assert read_page(ld, "https://c.example/", now=_GOLDEN_NOW) == Failed(
        "menuNotFound"
    )


@pytest.mark.parametrize(
    ("text", "reversed_"),
    [("שלום", False), ("םולש", True), ("hello", False), ("", False), ("a ףב", True)],
)
def test_looks_character_reversed(text: str, reversed_: bool) -> None:
    assert looks_character_reversed(text) is reversed_


def test_a_menu_link_needs_a_fetch_and_keeps_the_pages_own_text_as_fallback() -> None:
    page = '<a href="/our-menu">Menu</a>' + _MENU_PAGE
    reading = read_page(page, "https://c.example/", now=_GOLDEN_NOW)
    assert isinstance(reading, NeedsFetch)
    assert reading.url.to_string() == "https://c.example/our-menu"
    assert isinstance(reading.fallback, Located)
    assert _names(reading.fallback) == _PRICED_TEXT_NAMES


def test_a_pdf_link_is_handed_to_the_vision_path() -> None:
    page = '<a href="https://files.example/Menu.PDF">Menu</a>'
    reading = read_page(page, "https://c.example/", now=_GOLDEN_NOW)
    assert isinstance(reading, PdfLink)
    assert reading.url.to_string() == "https://files.example/Menu.PDF"
    assert reading.fallback is None


def test_the_link_result_wins_and_its_failure_falls_back_to_the_pages_text() -> None:
    page = '<a href="/our-menu">Menu</a>' + _MENU_PAGE
    pending = read_page(page, "https://c.example/", now=_GOLDEN_NOW)
    assert isinstance(pending, NeedsFetch)
    linked = read_linked_page(
        "<p>Steak 98</p><p>Salmon 88</p><p>Fish 70</p>",
        "https://c.example/our-menu",
        now=_GOLDEN_NOW,
    )
    assert finish_after_link(pending, linked) is linked
    assert finish_after_link(pending, Failed("menuNotFound")) is pending.fallback


def test_a_failed_link_without_a_fallback_keeps_its_own_failure() -> None:
    pending = PdfLink(DartUri.parse("https://f.example/m.pdf"), None)
    failure = Failed("websitePdfUnread")
    assert finish_after_link(pending, failure) is failure


def test_an_unparseable_final_url_is_the_callers_error() -> None:
    with pytest.raises(UriFormatError):
        read_page("<p>x</p>", "http://[bad", now=_GOLDEN_NOW)


# --- smaller pins ---------------------------------------------------------------


def test_numeric_references_that_spell_a_surrogate_pair_join_into_one_character() -> (
    None
):
    assert website_html.decode_entities("&#xD83D;&#xDE00;") == "\U0001f600"


def test_a_lone_surrogate_survives_in_lines_but_never_reaches_a_dish() -> None:
    assert website_html.lines("<p>a&#xD83D;b</p>") == ["a\ud83db"]
    menu = parse("a\ud83db 40", now=_GOLDEN_NOW)
    assert menu is not None
    assert menu.categories[0].dishes[0].name == "a�b"


def test_an_astronomically_long_numeric_reference_is_a_space() -> None:
    assert website_html.decode_entities("&#" + "9" * 5000 + ";") == " "


@pytest.mark.parametrize(
    ("port", "expected"),
    [
        ("http://x.com:80/", "http://x.com/"),
        ("http://x.com:0x50/", "http://x.com/"),
        ("http://x.com:+80/", "http://x.com/"),
        ("http://x.com: 80/", "http://x.com/"),
        ("ftp://x.com:0/", "ftp://x.com/"),
        ("http://x.com:-80/", "http://x.com:-80/"),
        ("http://x.com:8_0/", None),
        ("http://x.com:9223372036854775808/", None),
        ("http://x.com:8080:90/", None),
        ("http://[1::2::3]/", None),
        ("http://[::1]:80/", "http://[::1]/"),
    ],
)
def test_ports_follow_dart_int_try_parse(port: str, expected: str | None) -> None:
    try:
        actual: str | None = DartUri.parse(port).to_string()
    except UriFormatError:
        actual = None
    assert actual == expected


def test_an_ipv6_host_reads_without_brackets() -> None:
    uri = DartUri.parse("http://[::1]:8080/a")
    assert uri.host_text == "::1"
    assert uri.host == "[::1]"


def test_decode_full_rejects_bytes_that_are_not_utf8() -> None:
    assert decode_full("/%D7%AA") == "/ת"
    assert decode_full("/plain") == "/plain"
    with pytest.raises(UriFormatError):
        decode_full("/%FA%F4")


def test_json_ld_tolerates_deep_nesting_and_the_dish_cap() -> None:
    nested: dict[str, Any] = {"name": "leaf", "hasMenuItem": [{"name": "Deep"}]}
    for depth in range(400):
        nested = {"name": f"s{depth}", "hasMenuSection": [nested]}
    deep = [{"@type": "Menu", "hasMenuSection": [nested]}]
    categories = categories_from(deep)
    assert categories is not None
    assert categories[0].dishes[0].name == "Deep"

    many = [
        {
            "@type": "Menu",
            "hasMenuItem": [{"name": f"d{i}"} for i in range(1005)],
        }
    ]
    capped = categories_from(many)
    assert capped is not None
    assert len(capped[0].dishes) == 1000
    assert capped[0].dishes[-1].id == "j1000"


def test_json_ld_without_a_menu_yields_nothing() -> None:
    assert categories_from([]) is None
    assert categories_from([{"@type": "Restaurant"}, "x", 3, None]) is None
    assert menu_url_from([], DartUri.parse("https://c.example/")) is None

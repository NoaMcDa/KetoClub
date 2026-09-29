"""Tests for the pure crawl-hygiene helpers in ``app.services.website``."""

import pytest

from app.services.website import (
    charset_of,
    document_kind,
    header_reserves_ai,
    html_reserves_ai,
    is_public_address,
    looks_javascript_only,
    parse_robots,
    path_of,
    visible_text,
)

# --- robots.txt -------------------------------------------------------------


def test_no_rules_allows_everything() -> None:
    rules = parse_robots("")
    assert rules.allows("/menu")
    assert rules.allows("")


def test_star_group_disallow_applies() -> None:
    rules = parse_robots("User-agent: *\nDisallow: /private\n")
    assert not rules.allows("/private/menu.pdf")
    assert rules.allows("/menu")


def test_disallow_all_refuses_every_path_but_robots_txt() -> None:
    rules = parse_robots("User-agent: *\nDisallow: /\n")
    assert not rules.allows("/")
    assert not rules.allows("/menu")
    assert rules.allows("/robots.txt")


def test_our_own_group_replaces_the_star_group() -> None:
    text = (
        "User-agent: *\nDisallow: /\n\n"
        "User-agent: KetoClubBot\nAllow: /\nDisallow: /admin\n"
    )
    rules = parse_robots(text)
    assert rules.allows("/menu")
    assert not rules.allows("/admin/x")


def test_our_group_alone_can_refuse_us() -> None:
    text = "User-agent: *\nAllow: /\n\nUser-agent: ketoclubbot\nDisallow: /\n"
    assert not parse_robots(text).allows("/menu")


def test_other_bots_groups_are_ignored() -> None:
    text = "User-agent: Googlebot\nDisallow: /\n"
    assert parse_robots(text).allows("/menu")


def test_consecutive_user_agent_lines_share_one_group() -> None:
    text = "User-agent: Googlebot\nUser-agent: *\nDisallow: /menu\n"
    assert not parse_robots(text).allows("/menu")


def test_longest_match_wins_and_ties_go_to_allow() -> None:
    text = "User-agent: *\nDisallow: /menu\nAllow: /menu/food\nAllow: /menu\n"
    rules = parse_robots(text)
    assert rules.allows("/menu/food")
    assert rules.allows("/menu")


def test_wildcards_and_end_anchor() -> None:
    text = "User-agent: *\nDisallow: /*.pdf$\nDisallow: /tmp*x\n"
    rules = parse_robots(text)
    assert not rules.allows("/files/menu.pdf")
    assert rules.allows("/files/menu.pdf?v=2")
    assert not rules.allows("/tmp/abcx")


def test_empty_disallow_comments_and_unknown_keys_are_ignored() -> None:
    text = (
        "# comment\nUser-agent: * # everyone\nDisallow:\n"
        "Crawl-delay: 5\nSitemap: https://x.test/sitemap.xml\nnonsense line\n"
    )
    assert parse_robots(text).allows("/anything")


def test_rules_before_any_user_agent_are_ignored() -> None:
    assert parse_robots("Disallow: /\n").allows("/menu")


def test_path_of_keeps_the_query() -> None:
    assert path_of("https://x.test/menu?lang=he") == "/menu?lang=he"
    assert path_of("https://x.test") == "/"


# --- AI opt-out signals -----------------------------------------------------


@pytest.mark.parametrize(
    ("headers", "reserved"),
    [
        ({"x-robots-tag": "noai, noimageai"}, True),
        ({"x-robots-tag": "noindex"}, False),
        ({"tdm-reservation": "1"}, True),
        ({"tdm-reservation": "0"}, False),
        ({}, False),
    ],
)
def test_header_reserves_ai(headers: dict[str, str], reserved: bool) -> None:
    assert header_reserves_ai(headers) is reserved


@pytest.mark.parametrize(
    ("page", "reserved"),
    [
        ('<meta name="robots" content="noai, noimageai">', True),
        ("<meta name='KetoClubBot' content='noai'>", True),
        ('<meta name="tdm-reservation" content="1">', True),
        ('<meta name="robots" content="noindex">', False),
        ('<meta charset="utf-8"><meta name=robots content=index>', False),
    ],
)
def test_html_reserves_ai(page: str, reserved: bool) -> None:
    assert html_reserves_ai(page) is reserved


# --- JavaScript-only pages --------------------------------------------------

_MENU_TEXT = " ".join(["Caesar salad 52"] * 30)


def test_a_bare_app_shell_is_javascript_only() -> None:
    page = '<html><body><div id="root"></div><script src="/app.js"></script>'
    assert looks_javascript_only(page)


def test_a_noscript_plea_is_javascript_only() -> None:
    page = (
        "<body><noscript>You need to enable JavaScript to run this app."
        "</noscript><p>Loading</p></body>"
    )
    assert looks_javascript_only(page)


def test_a_rendered_page_with_scripts_is_not_javascript_only() -> None:
    page = f"<body><p>{_MENU_TEXT}</p><script>track()</script></body>"
    assert not looks_javascript_only(page)


def test_a_page_with_json_ld_is_left_to_the_app() -> None:
    page = (
        '<script type="application/ld+json">{"@type": "Menu"}</script>'
        '<div id="root"></div><script src="/app.js"></script>'
    )
    assert not looks_javascript_only(page)


def test_a_short_static_page_is_not_javascript_only() -> None:
    assert not looks_javascript_only("<body><p>Closed today.</p></body>")


def test_visible_text_drops_scripts_styles_and_entities() -> None:
    page = (
        "<style>p{}</style><!-- c --><p>Fish&amp;chips</p><script>var x = 1;</script>"
    )
    assert visible_text(page) == "Fish&chips"


# --- content ----------------------------------------------------------------


@pytest.mark.parametrize(
    ("content_type", "head", "kind"),
    [
        ("text/html; charset=utf-8", b"<!doc", "html"),
        ("application/xhtml+xml", b"<?xml", "html"),
        ("application/pdf", b"%PDF-", "pdf"),
        ("application/octet-stream", b"%PDF-", "pdf"),
        ("image/png", b"\x89PNG\r", None),
        ("", b"", None),
    ],
)
def test_document_kind(content_type: str, head: bytes, kind: str | None) -> None:
    assert document_kind(content_type, head) == kind


def test_charset_of() -> None:
    assert charset_of('text/html; charset="windows-1255"') == "windows-1255"
    assert charset_of("text/html") == "utf-8"


@pytest.mark.parametrize(
    ("address", "public"),
    [
        ("93.184.216.34", True),
        ("2606:2800:220:1:248:1893:25c8:1946", True),
        ("127.0.0.1", False),
        ("10.0.0.5", False),
        ("192.168.1.1", False),
        ("169.254.169.254", False),
        ("::1", False),
        ("224.0.0.1", False),
        ("not-an-ip", False),
    ],
)
def test_is_public_address(address: str, public: bool) -> None:
    assert is_public_address(address) is public

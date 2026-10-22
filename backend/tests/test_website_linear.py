"""#268: the website readers run in linear time with the regexes' exact
results.

Two kinds of test. Differential ones replay thousands of random tag soups
through the old regexes (copied here verbatim, the reference) and through
their linear stand-ins, and require identical output; the D25 goldens
(``test_golden_website.py``) still pin the port to Dart on top. Timing ones
are the issue's reproductions: a 2 MB page of unclosed ``<script>`` and a
12-star robots.txt pattern, each of which took from minutes to half an hour
before, must finish well under a second.
"""

import random
import re
import time
from collections.abc import Callable

import pytest

from app.keto.dart_text import dart_lower
from app.keto.text_menu import WS
from app.services import website as fetch_judge
from app.services.website import RobotsRules, _matches, parse_robots
from app.website import html as reader
from app.website import locator
from app.website.adapter import read_page
from app.website.html import DartUri
from app.website.linear import PairedTags, find_tags, sub_comments, sub_tags

# --- the reference regexes, as they were before #268 -------------------------

_FLAGS = re.IGNORECASE | re.ASCII
_OLD_COMMENT = re.compile("<!--.*?-->", re.DOTALL)
_OLD_READER_INVISIBLE = re.compile(
    rf"<(script|style|noscript|template|svg|head|nav|footer)\b[^>]*>.*?</\1{WS}*>",
    _FLAGS | re.DOTALL,
)
_OLD_READER_NOSCRIPT = re.compile(
    rf"<noscript\b[^>]*>(.*?)</noscript{WS}*>", _FLAGS | re.DOTALL
)
_OLD_ANCHOR = re.compile(r"<a\b([^>]*)>(.*?)</a" + f"{WS}*>", _FLAGS | re.DOTALL)
_OLD_JSON_LD = re.compile(
    r"""<script\b[^>]*type"""
    + WS
    + r"""*="""
    + WS
    + r"""*["']?application/ld\+json["']?[^>]*>(.*?)</script"""
    + WS
    + "*>",
    _FLAGS | re.DOTALL,
)
_OLD_JUDGE_INVISIBLE = re.compile(
    r"<(script|style|noscript|template|svg)\b[^>]*>.*?</\1\s*>",
    re.DOTALL | re.IGNORECASE,
)
_OLD_JUDGE_NOSCRIPT = re.compile(
    r"<noscript\b[^>]*>(.*?)</noscript\s*>", re.DOTALL | re.IGNORECASE
)
_OLD_TRAILING_COLONS = re.compile(r":+\Z")


def _old_robots_match(pattern: str, path: str) -> bool:
    anchored = pattern.endswith("$")
    body = pattern[:-1] if anchored else pattern
    regex = ".*".join(re.escape(part) for part in body.split("*"))
    return re.match(regex + ("$" if anchored else ""), path) is not None


# --- random tag soup -----------------------------------------------------------

# Every character the patterns care about, the case-folding oddities among
# them (U+017F long s, U+212A Kelvin, U+0130/U+0131 dotted and dotless i),
# and the whitespace each flavour of ``\s`` disagrees on.
_PIECES = [
    "<",
    ">",
    "/",
    "!",
    "-",
    "--",
    "<!--",
    "-->",
    "<script",
    "</script",
    "<SCRIPT",
    "</Script",
    "<ſcript",
    "</ſcript",
    "<style",
    "</style",
    "<noscript",
    "</noscript",
    "<noſcript",
    "<noscrİpt",
    "</noscrİpt",
    "</noscrıpt",
    "<template",
    "</template",
    "<svg",
    "</svg",
    "<head",
    "</head",
    "<header",
    "<nav",
    "</nav",
    "<footer",
    "</footer",
    "<a",
    "</a",
    "<A",
    "</A",
    "<abbr",
    "<meta",
    "<p",
    "</p",
    "<td",
    "<br",
    " type=",
    "type",
    '="application/ld+json"',
    "application/ld+json",
    " href='x'",
    ' href="y"',
    "javascript",
    " ",
    "  ",
    "\t",
    "\n",
    "\u00a0",
    "\u2003",
    "\u0085",
    "x",
    "K",
    "\u212a",
    "1",
    "_",
    "א",
    "&amp;",
]


def _soup(rng: random.Random, pieces: int) -> str:
    return "".join(rng.choice(_PIECES) for _ in range(rng.randrange(pieces)))


def _soups(count: int = 4000, pieces: int = 24) -> list[str]:
    rng = random.Random(268)
    return [_soup(rng, pieces) for _ in range(count)]


_DENSE_PIECES = [
    "<style",
    "<script",
    "<SVG",
    "<noscript",
    "<a",
    "<noſcript",
    ">",
    " ",
    "x",
    "</style>",
    "</script>",
    "</svg >",
    "</noscript>",
    "</noscrıpt>",
    "</a>",
    "</ſcript>",
    "<!--",
    "-->",
    ' type="application/ld+json"',
]


def _dense_soups(count: int = 4000) -> list[str]:
    """Soups thick with closing tags and with opening tags sharing one
    ``>``, where the shortcuts in ``app.website.linear`` are taken."""
    rng = random.Random(2683)
    return [
        "".join(rng.choice(_DENSE_PIECES) for _ in range(rng.randrange(16)))
        for _ in range(count)
    ]


_SOUPS = (
    [
        "<style <script>x</script>",
        "<script <style>x</style>",
        "<style <svg <script>x</script></svg>",
        "<noſcript>javascript</noscrıpt>",
        '<script <script type="application/ld+json">{}</script>',
        '<script type="application/ld+json" <script>{}</script>',
    ]
    + _soups()
    + _dense_soups()
)


@pytest.mark.parametrize(
    ("old", "new"),
    [
        (_OLD_READER_INVISIBLE, reader._INVISIBLE),
        (_OLD_READER_NOSCRIPT, reader._NOSCRIPT),
        (_OLD_ANCHOR, reader._ANCHOR),
        (_OLD_JSON_LD, reader._JSON_LD),
        (_OLD_JUDGE_INVISIBLE, fetch_judge._INVISIBLE),
        (_OLD_JUDGE_NOSCRIPT, fetch_judge._NOSCRIPT),
    ],
    ids=[
        "reader-invisible",
        "reader-noscript",
        "reader-anchor",
        "reader-json-ld",
        "judge-invisible",
        "judge-noscript",
    ],
)
def test_paired_tags_match_exactly_where_the_regex_did(
    old: re.Pattern[str], new: PairedTags
) -> None:
    for text in _SOUPS:
        expected = [(m.start(), m.end()) for m in old.finditer(text)]
        assert [(b.start, b.end) for b in new.finditer(text)] == expected, text
        assert new.sub("\n", text) == old.sub("\n", text), text


@pytest.mark.parametrize(
    ("old", "new"),
    [
        (_OLD_READER_NOSCRIPT, reader._NOSCRIPT),
        (_OLD_JSON_LD, reader._JSON_LD),
        (_OLD_JUDGE_NOSCRIPT, fetch_judge._NOSCRIPT),
    ],
    ids=["reader-noscript", "reader-json-ld", "judge-noscript"],
)
def test_a_blocks_content_is_the_regexs_group(
    old: re.Pattern[str], new: PairedTags
) -> None:
    for text in _SOUPS:
        expected = [m.group(1) for m in old.finditer(text)]
        got = [text[b.content_start : b.content_end] for b in new.finditer(text)]
        assert got == expected, text


def test_an_anchors_attributes_and_text_are_the_regexs_groups() -> None:
    for text in _SOUPS:
        expected = [(m.group(1), m.group(2)) for m in _OLD_ANCHOR.finditer(text)]
        got = [
            (
                text[b.name_end : b.content_start - 1],
                text[b.content_start : b.content_end],
            )
            for b in reader._ANCHOR.finditer(text)
        ]
        assert got == expected, text


def test_comments_are_removed_exactly_as_the_regex_did() -> None:
    for text in _SOUPS:
        assert sub_comments(" ", text) == _OLD_COMMENT.sub(" ", text), text


@pytest.mark.parametrize(
    "pattern",
    [reader._TAG, reader._BLOCK_TAG, reader._CELL_TAG, reader._META],
    ids=["tag", "block-tag", "cell-tag", "meta"],
)
def test_tag_patterns_cut_at_the_last_gt_give_the_same_answer(
    pattern: re.Pattern[str],
) -> None:
    for text in _SOUPS:
        assert sub_tags(pattern, " ", text) == pattern.sub(" ", text), text
        assert [m.span() for m in find_tags(pattern, text)] == [
            m.span() for m in pattern.finditer(text)
        ], text


def test_the_readers_whole_outputs_are_unchanged_on_random_soup() -> None:
    """End to end over each public reading, against a re-assembly of the
    old pipeline from the reference regexes."""

    def old_lines(html: str) -> list[str]:
        without = _OLD_READER_INVISIBLE.sub("\n", _OLD_COMMENT.sub(" ", html))
        broken = reader._TAG.sub(
            " ", reader._CELL_TAG.sub(" ", reader._BLOCK_TAG.sub("\n", without))
        )
        found = (
            reader.dart_trim(reader._SPACES.sub(" ", raw))
            for raw in reader._LINE_BREAK.split(reader.decode_entities(broken))
        )
        return [line for line in found if line]

    for text in _SOUPS:
        assert reader.lines(text) == old_lines(text), text


# --- the locator's trailing price ---------------------------------------------

_PRICE_PIECES = [
    " ",
    "\u2003",
    "\t",
    "-",
    "–",
    "—",
    ":",
    ".",
    "…",
    "|",
    ",",
    "₪",
    "NIS",
    "nis",
    "ILS",
    'ש"ח',
    "ש״ח",
    "1",
    "23",
    "4567",
    "89",
    "x",
    "Dish",
    "א",
]


def test_the_trailing_price_is_found_exactly_where_the_regex_found_it() -> None:
    rng = random.Random(2681)
    for _ in range(20000):
        line = "".join(rng.choice(_PRICE_PIECES) for _ in range(rng.randrange(14)))
        old = locator._TRAILING_PRICE.search(line)
        new = locator._trailing_price(line)
        assert (old and old.span()) == (new and new.span()), line


def test_trailing_colons_are_stripped_exactly_as_the_regex_did() -> None:
    for line in ["", ":", "a:", "a::", ":a:", "a: :", "::a", "a:b::"]:
        assert line.rstrip(":") == _OLD_TRAILING_COLONS.sub("", line)


# --- robots.txt patterns ------------------------------------------------------


def test_robots_patterns_match_exactly_as_the_regex_did() -> None:
    rng = random.Random(2682)
    alphabet = ["/", "a", "b", "ab", ".", "?", "=", "*", "$", "%2F", "\\"]
    for _ in range(20000):
        pattern = "".join(rng.choice(alphabet) for _ in range(rng.randrange(8)))
        path = "".join(rng.choice(alphabet[:-2]) for _ in range(rng.randrange(10)))
        assert _matches(pattern, path) == _old_robots_match(pattern, path), (
            pattern,
            path,
        )


# --- the issue's reproductions ----------------------------------------------

_TWO_MB = 2 * 1024 * 1024
_UNCLOSED_SCRIPTS = "<script>" * (_TWO_MB // len("<script>"))


def _seconds(work: Callable[[], object]) -> float:
    """The CPU seconds ``work`` takes: this process's, not the wall clock's,
    so a busy machine running other jobs does not fail the test."""
    started = time.process_time()
    work()
    return time.process_time() - started


@pytest.mark.parametrize(
    "reading",
    [
        fetch_judge.visible_text,
        fetch_judge.looks_javascript_only,
        fetch_judge.html_reserves_ai,
        reader.lines,
        reader.is_javascript_only,
        reader.json_ld_blocks,
        lambda page: reader.links(page, DartUri.parse("https://cafe.example/")),
        lambda page: read_page(
            page, DartUri.parse("https://cafe.example/"), now="2026-10-01T00:00:00.000Z"
        ),
    ],
    ids=[
        "judge-visible-text",
        "judge-js-only",
        "judge-reserves-ai",
        "reader-lines",
        "reader-js-only",
        "reader-json-ld",
        "reader-links",
        "read-page",
    ],
)
def test_two_megabytes_of_unclosed_script_tags_take_well_under_a_second(
    reading: Callable[[str], object],
) -> None:
    # Before #268: about half an hour (2.9 s at 80 KB, 11 s at 160 KB, 45 s
    # at 320 KB, quadrupling with each doubling).
    assert _seconds(lambda: reading(_UNCLOSED_SCRIPTS)) < 1.0


@pytest.mark.parametrize(
    "page",
    [
        "<!--" * (_TWO_MB // 4),
        "<" * _TWO_MB,
        "<a " * (_TWO_MB // 3),
        "<p>Dish 52</p>" * 5 + "<p>a" + "-" * _TWO_MB + "x</p>",
        "<p>Dish 52</p>" * 5 + "<p>a" + "\u2003" * _TWO_MB + "x</p>",
        "<p>Dish 52</p>" * 5 + "<p>" + ":" * _TWO_MB + "x</p>",
        "<p>Dish 52</p>" * 5 + "<p>a" + " ." * (_TWO_MB // 2) + "x</p>",
    ],
    ids=["comments", "lt", "anchors", "dashes", "em-spaces", "colons", "dots"],
)
def test_other_two_megabyte_traps_take_seconds_not_hours(page: str) -> None:
    # Each of these was quadratic or worse before: the dashes, em-spaces and
    # colons took over five seconds at 40 KB already, hours at 2 MB. The bound
    # is looser than the issue's one second because the whole reader runs
    # here, linear but in Python, not one pattern.
    base = DartUri.parse("https://cafe.example/")
    assert _seconds(lambda: read_page(page, base, now="2026-10-01T00:00:00.000Z")) < 3.0
    assert _seconds(lambda: fetch_judge.looks_javascript_only(page)) < 1.0


def test_a_twelve_star_robots_pattern_takes_well_under_a_second() -> None:
    # Before #268: 163 s against a 41-character path.
    rules = parse_robots("User-agent: *\nDisallow: /" + "*a" * 12 + "*b\n")
    path = "/" + "a" * 40
    assert _seconds(lambda: rules.allows(path)) < 1.0
    assert rules.allows(path)
    assert not rules.allows(path + "b")


def test_a_robots_pattern_of_many_stars_on_a_long_path_stays_fast() -> None:
    rules: RobotsRules = parse_robots(
        "User-agent: *\nDisallow: /" + "*a" * 500 + "*b$\n"
    )
    path = "/" + "a" * 2000
    assert _seconds(lambda: rules.allows(path)) < 1.0


def test_a_huge_numeric_reference_does_not_crash_the_page_judge() -> None:
    # html.unescape raised ValueError past Python's int-string limit, a 500.
    page = "<p>&#" + "1" * 5000 + ";</p>"
    assert fetch_judge.visible_text(page) == "\N{REPLACEMENT CHARACTER}"
    assert (
        fetch_judge.visible_text("<p>&#0000065;&#99999999</p>")
        == "A\N{REPLACEMENT CHARACTER}"
    )


def test_dart_lower_takes_str_lower_only_where_they_agree() -> None:
    """The fast path of ``dart_lower`` (#268) against its per-character
    definition, over every code point, with and without the two
    exceptions."""

    def per_character(text: str) -> str:
        return "".join(
            char.lower()
            if len(char.lower()) == 1
            else ("i" if char == "\N{LATIN CAPITAL LETTER I WITH DOT ABOVE}" else char)
            for char in text
        )

    sigma = "\N{GREEK CAPITAL LETTER SIGMA}"
    dotted = "\N{LATIN CAPITAL LETTER I WITH DOT ABOVE}"
    everything = "".join(chr(code) for code in range(0x110000))
    assert dart_lower(everything) == per_character(everything)
    plain = everything.replace(sigma, "").replace(dotted, "")
    assert dart_lower(plain) == plain.lower() == per_character(plain)
    assert dart_lower(f"AB{sigma} {dotted}") == "ab\N{GREEK SMALL LETTER SIGMA} i"

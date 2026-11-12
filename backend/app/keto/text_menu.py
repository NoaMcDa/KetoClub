"""Pasted text to a ``Menu``: the Python twin of ``TextMenuSource`` (D18, D25).

Pure: no I/O, and :func:`parse` never raises on any ``str``. Text is the one
classifier input, so a pasted menu needs no engine of its own; it only needs
to become dishes. The rules, in the order they apply to each line (the Dart
``TextMenuSource`` docs are the reference):

Each line is first cleaned:

* Lines are trimmed (Dart ``trim``) and blank ones dropped, though a blank
  line is remembered, because it can end a section header.
* A WhatsApp sender prefix (``[12/11/2026, 14:02] Dana: ``) is removed (#479).
* A line wrapped in ``*…*`` or ``_…_`` loses the markers and is emphasised;
  ``*…*`` inside a line loses its markers.
* A leading bullet is removed and remembered: a dash, a number (``1.``,
  ``2)``) or any run of symbols (#282).
* A price is stripped: a trailing one, a leading one and a size's one; a line
  that was only a price disappears, and a line that lost a price is priced.

Then each line is a section header (ends in ``:``, or emphasised and
unpriced); a wrapped line of the dish above (``(``; a dash unless that dish
was bulleted; a lowercase start unless that dish's name has one); in a priced
paste, an unpriced unbulleted line after a priced dish is its description (a short
all-capitals Latin line is a header) and an unpriced short line before a
priced one is a header; a short line standing alone between blank lines is a
header (off when no two non-blank lines are adjacent); and every other line is
a dish: ``price 0``, no options, id ``p1..pN``.

The Dart regexes are **non-unicode** ones, so this module spells their
semantics out instead of leaning on Python's defaults: ``\\d`` is ASCII only,
``\\s`` is ECMAScript's set (it includes NBSP and U+202F, and not U+0085 or
U+001C-U+001F), lines split only on ``\\r\\n|\\r|\\n`` (U+2028 and U+0085 stay
inside a line), and ``$`` is the end of the string, never before a trailing
newline. The two ``unicode: true`` regexes (``\\p{L}``/``\\p{N}`` and
``^\\p{Ll}``) are answered by :func:`has_letter_or_digit`,
:func:`has_letter` and :func:`starts_lowercase`, which also reproduce the
Unicode version Dart ships: characters added to Unicode after it (for
example the Egyptian Hieroglyphs Extended-A letters) are not letters there.
"""

import re
from bisect import bisect_right
from dataclasses import dataclass
from datetime import UTC, datetime
from typing import Final

import regex

from app.keto.dart_text import dart_trim, from_utf16_units, utf16_units
from app.keto.fingerprint import scan_ref
from app.keto.models import Dish, Menu, MenuCategory, VenueRef
from app.keto.vocabulary import vocabulary

# --- Dart regexp / Unicode semantics, shared with ``app.website`` -------------

WS_CLASS: Final = r"\t\n\v\f\r    -     　﻿"
"""The inside of a character class holding what ECMAScript ``\\s`` matches
(and so what a non-unicode Dart ``\\s`` matches)."""

WS: Final = f"[{WS_CLASS}]"
"""A regex source for one Dart ``\\s`` character."""

NOT_WS: Final = f"[^{WS_CLASS}]"
"""A regex source for one Dart ``\\S`` character."""

# Code points that Python's ``regex`` (a newer Unicode) knows as letters,
# numbers or lowercase letters and that the Unicode version Dart ships does
# not. Measured against the Dart VM with a sweep of every code point.
_NEWER_LETTERS: Final = (
    (0x558, 0x558), (0x58B, 0x58C), (0x88F, 0x88F), (0xC5C, 0xC5C),
    (0xCDC, 0xCDC), (0x208F, 0x208F), (0x209D, 0x209F), (0xA7CE, 0xA7CF),
    (0xA7D2, 0xA7D2), (0xA7D4, 0xA7D4), (0xA7DD, 0xA7DD), (0xA7E2, 0xA7E2),
    (0xA7F1, 0xA7F1), (0xAB6C, 0xAB6D), (0x107BB, 0x107BF), (0x10940, 0x10959),
    (0x10EC5, 0x10EC7), (0x10ED9, 0x10EEE), (0x11B0A, 0x11B0A),
    (0x11DB0, 0x11DDB), (0x11DF1, 0x11DF1), (0x16EA0, 0x16EB8),
    (0x16EBB, 0x16ED3), (0x16FF2, 0x16FF3), (0x187F8, 0x187FF),
    (0x18CD6, 0x18CDA), (0x18D09, 0x18D20), (0x18D80, 0x18DF2),
    (0x18E00, 0x19191), (0x191A0, 0x191D2), (0x1B123, 0x1B128),
    (0x1B168, 0x1B168), (0x1D6A6, 0x1D6A6), (0x1DF1F, 0x1DF24),
    (0x1DF2B, 0x1DF81), (0x1DF90, 0x1DF96), (0x1DFCD, 0x1DFFF),
    (0x1E6C0, 0x1E6DE), (0x1E6E0, 0x1E6E2), (0x1E6E4, 0x1E6E5),
    (0x1E6E7, 0x1E6ED), (0x1E6F0, 0x1E6F4), (0x1E6FE, 0x1E6FF),
    (0x2B73A, 0x2B73F), (0x2B81E, 0x2B81E), (0x2CEA2, 0x2CEAD),
    (0x323B0, 0x33479), (0x3D000, 0x3FC3F),
)  # fmt: skip
_NEWER_NUMBERS: Final = (
    (0x11DE0, 0x11DE9), (0x1246F, 0x1246F), (0x12475, 0x1247F),
    (0x12550, 0x12686), (0x16FF4, 0x16FF6),
)  # fmt: skip
_NEWER_LOWERCASE: Final = (
    (0xA7CF, 0xA7CF), (0x16EBB, 0x16ED3), (0x1D6A6, 0x1D6A6),
    (0x1DF1F, 0x1DF24), (0x1DF2B, 0x1DF3F), (0x1DF41, 0x1DF47),
    (0x1DF49, 0x1DF49), (0x1DF4B, 0x1DF4C), (0x1DF4E, 0x1DF50),
    (0x1DF52, 0x1DF67), (0x1DF69, 0x1DF69), (0x1DF6B, 0x1DF6B),
    (0x1DF6D, 0x1DF6D), (0x1DF6F, 0x1DF71), (0x1DF73, 0x1DF73),
    (0x1DF75, 0x1DF75), (0x1DF77, 0x1DF77), (0x1DF79, 0x1DF79),
    (0x1DF7B, 0x1DF7B), (0x1DF7D, 0x1DF7D), (0x1DF7F, 0x1DF7F),
    (0x1DF90, 0x1DF96),
)  # fmt: skip
_OLDER_LOWERCASE: Final = 0x295
"""A lowercase letter in Dart's Unicode that the newer data recategorised."""

_LETTER: Final = regex.compile(r"\p{L}")
_NUMBER: Final = regex.compile(r"\p{N}")
_LOWERCASE: Final = regex.compile(r"\p{Ll}")


def _in_ranges(code: int, ranges: tuple[tuple[int, int], ...]) -> bool:
    index = bisect_right(ranges, (code, 0x10FFFF)) - 1
    return index >= 0 and ranges[index][0] <= code <= ranges[index][1]


def _is_letter(char: str) -> bool:
    return bool(_LETTER.match(char)) and not _in_ranges(ord(char), _NEWER_LETTERS)


def _is_number(char: str) -> bool:
    return bool(_NUMBER.match(char)) and not _in_ranges(ord(char), _NEWER_NUMBERS)


def _is_lowercase(char: str) -> bool:
    if ord(char) == _OLDER_LOWERCASE:
        return True
    return bool(_LOWERCASE.match(char)) and not _in_ranges(ord(char), _NEWER_LOWERCASE)


def has_letter(text: str) -> bool:
    """Whether ``text`` holds a ``\\p{L}`` code point (Dart unicode regex)."""
    return any(_is_letter(char) for char in text)


def has_letter_or_digit(text: str) -> bool:
    """Whether ``text`` holds a ``[\\p{L}\\p{N}]`` code point."""
    return any(_is_letter(char) or _is_number(char) for char in text)


def starts_lowercase(text: str) -> bool:
    """``RegExp(r'^\\p{Ll}', unicode: true).hasMatch(text)``."""
    return bool(text) and _is_lowercase(text[0])


def dart_upper_first(text: str) -> str:
    """``text[0].toUpperCase() + text.substring(1)`` on Dart's UTF-16 string.

    Dart upper-cases one UTF-16 code unit: an astral first character is a
    lone high surrogate, which has no upper case, so the text is unchanged;
    and the mapping is the one-to-one (simple) one of Dart's older Unicode,
    so ``ß`` stays ``ß`` where Python's full mapping gives ``SS``.
    """
    if not text:
        return text
    first = text[0]
    code = ord(first)
    if code > 0xFFFF or _in_ranges(code, _NO_UPPERCASE):
        return text
    if code in _TITLECASE_AS_UPPER:
        return chr(_TITLECASE_AS_UPPER[code]) + text[1:]
    upper = first.upper()
    return (upper if len(upper) == 1 else first) + text[1:]


_NO_UPPERCASE: Final = (
    (0x23F, 0x240), (0x252, 0x252), (0x25C, 0x25C), (0x261, 0x261),
    (0x265, 0x266), (0x26A, 0x26A), (0x26C, 0x26C), (0x282, 0x282),
    (0x287, 0x287), (0x29D, 0x29E), (0x3F3, 0x3F3), (0x525, 0x525),
    (0x527, 0x527), (0x529, 0x529), (0x52B, 0x52B), (0x52D, 0x52D),
    (0x52F, 0x52F), (0x10D0, 0x10FA), (0x10FD, 0x10FF), (0x13F8, 0x13FD),
    (0x1C80, 0x1C88), (0x1D8E, 0x1D8E), (0x2C5F, 0x2C5F), (0x2CEC, 0x2CEC),
    (0x2CEE, 0x2CEE), (0x2CF3, 0x2CF3), (0x2D27, 0x2D27), (0x2D2D, 0x2D2D),
    (0xA661, 0xA661), (0xA699, 0xA699), (0xA69B, 0xA69B), (0xA791, 0xA791),
    (0xA793, 0xA794), (0xA797, 0xA797), (0xA799, 0xA799), (0xA79B, 0xA79B),
    (0xA79D, 0xA79D), (0xA79F, 0xA79F), (0xA7A1, 0xA7A1), (0xA7A3, 0xA7A3),
    (0xA7A5, 0xA7A5), (0xA7A7, 0xA7A7), (0xA7A9, 0xA7A9), (0xA7B5, 0xA7B5),
    (0xA7B7, 0xA7B7), (0xA7B9, 0xA7B9), (0xA7BB, 0xA7BB), (0xA7BD, 0xA7BD),
    (0xA7BF, 0xA7BF), (0xA7C1, 0xA7C1), (0xA7C3, 0xA7C3), (0xA7C8, 0xA7C8),
    (0xA7CA, 0xA7CA), (0xA7D1, 0xA7D1), (0xA7D7, 0xA7D7), (0xA7D9, 0xA7D9),
    (0xA7F6, 0xA7F6), (0xAB53, 0xAB53), (0xAB70, 0xABBF),
)  # fmt: skip
"""Characters Python upper-cases and Dart's older Unicode does not."""

_TITLECASE_AS_UPPER: Final = {
    **{base + offset: base + offset + 8 for base in (0x1F80, 0x1F90, 0x1FA0)
       for offset in range(8)},
    0x1FB3: 0x1FBC,
    0x1FC3: 0x1FCC,
    0x1FF3: 0x1FFC,
}  # fmt: skip
"""Greek letters with ypogegrammeni, whose Dart upper case is the title-case
form (Python's full mapping gives two characters)."""


_LONE_SURROGATE: Final = re.compile("[\ud800-\udfff]")


def join_surrogates(text: str) -> str:
    """``text`` with adjacent high and low surrogate code points joined into
    the astral character a Dart (UTF-16) string already is: a page can spell
    an emoji as two numeric references, ``&#xD83D;&#xDE00;``."""
    if _LONE_SURROGATE.search(text) is None:
        return text
    return from_utf16_units(utf16_units(text))


def scrub_lone_surrogates(text: str) -> str:
    """``text`` with each remaining lone surrogate replaced by U+FFFD.

    Dart strings may hold one, and so may a page (``&#xD83D;``) or a pasted
    JSON body, but a Python ``str`` holding one cannot be encoded as UTF-8
    nor held by a wire model, so it is replaced before a dish is built.
    """
    return _LONE_SURROGATE.sub("\ufffd", join_surrogates(text))


def dart_iso8601(moment: datetime) -> str:
    """``DateTime.toIso8601String()``.

    An aware ``moment`` is a UTC ``DateTime`` (converted, suffixed ``Z``); a
    naive one is a local ``DateTime`` (no suffix). Milliseconds are always
    written, microseconds only when non-zero.
    """
    aware = moment.tzinfo is not None
    if aware:
        moment = moment.astimezone(UTC)
    millis, micros = divmod(moment.microsecond, 1000)
    text = (
        f"{moment.year:04d}-{moment.month:02d}-{moment.day:02d}"
        f"T{moment.hour:02d}:{moment.minute:02d}:{moment.second:02d}.{millis:03d}"
    )
    if micros:
        text += f"{micros:03d}"
    return text + ("Z" if aware else "")


# --- the paste reader ---------------------------------------------------------

_UNCATEGORISED_ID: Final = "pasted"
_CURRENCY: Final = "ILS"
_DEFAULT_UNCATEGORISED_NAME: Final = "Pasted menu"

_LINE_BREAK: Final = re.compile(r"\r\n|\r|\n")
_WHITESPACE: Final = re.compile(f"{WS}+")
_DIGIT: Final = re.compile("[0-9]")
_MIN_PRICED_LINES: Final = 3

CURRENCY_SOURCE: Final = (
    "(?:₪|NIS|ILS|ש[\\x22״׳']?ח|שקלים|שקל|shekels?|shkalim|sheqalim)"
)
"""``priceCurrencySource``, verbatim (it holds no ``\\s``, ``\\d`` or ``$``)."""

PRICE_SUFFIX_SOURCE: Final = (
    rf"(?:^|{WS}+|{WS}*[-–—:.…|]+{WS}*)(?:(?:מחיר|price){WS}*:?{WS}*)?(?:\({WS}*)?"
    rf"(?:{CURRENCY_SOURCE}{WS}*)?[0-9]+(?:[.,][0-9]{{1,2}})?(?:[.,]-)?"
    rf"(?:{WS}*/{WS}*[0-9]+(?:[.,][0-9]{{1,2}})?)*(?:{WS}*{CURRENCY_SOURCE})?"
    rf"(?:{WS}*\))?{WS}*\Z"
)
"""``pastedPriceSuffix`` with Dart's ``\\s``, ``\\d`` and ``$`` spelled out."""

_PRICE_SUFFIX: Final = re.compile(PRICE_SUFFIX_SOURCE, re.IGNORECASE | re.ASCII)
_PRICE_PREFIX: Final = re.compile(
    rf"^(?:{CURRENCY_SOURCE}{WS}*[0-9]+(?:[.,][0-9]{{1,2}})?"
    rf"|[0-9]{{2,}}(?:[.,][0-9]{{1,2}})?(?:{WS}*{CURRENCY_SOURCE})?)"
    rf"(?:{WS}*[-–—:.…|]+{WS}*|{WS}+)"
    r'(?!(?:g|gr|grams?|kg|ml|cl|oz|pcs|pieces|ג|גר|גרם|יח|יחידות|מ"ל|ק"ג)'
    rf"(?:{WS}|[.,)]|\Z))"
    rf"(?={NOT_WS})",
    re.IGNORECASE | re.ASCII,
)
"""``pastedPricePrefix``."""
_SIZED_PRICE: Final = re.compile(
    rf"{WS}+[0-9]{{2,}}(?:[.,][0-9]{{1,2}})?(?:{WS}*{CURRENCY_SOURCE})?(?={WS}*/)",
    re.IGNORECASE | re.ASCII,
)
"""``pastedSizedPrice``."""
_CHAT_PREFIX: Final = re.compile(
    rf"^[‎‏]*(?:\[[0-9]{{1,4}}[./-][0-9]{{1,2}}[./-][0-9]{{1,4}},?{WS}+"
    rf"[0-9]{{1,2}}:[0-9]{{2}}(?::[0-9]{{2}})?(?:{WS}*[AaPp]\.?[Mm]\.?)?\]{WS}*"
    rf"|[0-9]{{1,4}}[./-][0-9]{{1,2}}[./-][0-9]{{1,4}},?{WS}+[0-9]{{1,2}}:[0-9]{{2}}"
    rf"(?::[0-9]{{2}})?(?:{WS}*[AaPp]\.?[Mm]\.?)?{WS}+[-–]{WS}+)"
    rf"[^:\[\]]{{1,60}}?:{WS}*"
)
"""``pastedChatPrefix``."""
_SPACE: Final = re.compile(WS)
_LATIN_CAPITAL: Final = re.compile("[A-Z]")
_DASH_BULLET: Final = re.compile(f"^[-–—]+{WS}*")
_NUMBER_BULLET: Final = re.compile(f"^[0-9]{{1,2}}[.)]{WS}+")
_EMPHASIS: Final = re.compile(
    rf"^([*_])([^*_{WS_CLASS}](?:[^*_]*[^*_{WS_CLASS}])?)\1\Z"
)
_INNER_BOLD: Final = re.compile(rf"\*([^*{WS_CLASS}](?:[^*]*[^*{WS_CLASS}])?)\*")
_NOT_BULLETS: Final = "([\"'״׳“”„‘’«₪"

_BULLET_NONE: Final = 0
_BULLET_DASH: Final = 1
_BULLET_OTHER: Final = 2


@dataclass(frozen=True, slots=True)
class _Line:
    """One pasted line after cleaning (Dart ``_Line``)."""

    text: str
    priced: bool
    bullet: int
    emphasised: bool


def parse(
    text: str,
    *,
    now: datetime | str,
    uncategorised_name: str = _DEFAULT_UNCATEGORISED_NAME,
) -> Menu | None:
    """``TextMenuSource.parse``: the menu ``text`` describes, stamped ``now``
    (a ``datetime``, written as Dart's ``toIso8601String``, or the ready
    string), or ``None`` when it holds no dish.

    Dishes before any header go into a category named ``uncategorised_name``
    (which must be non-empty, as every wire name is). The menu's ref is
    ``scan/<fingerprint hex>``, so pasting the same dishes again is the same
    cache entry.
    """
    fetched_at = now if isinstance(now, str) else dart_iso8601(now)
    max_dishes = vocabulary().caps.max_analysed_dishes
    lines = [dart_trim(line) for line in _LINE_BREAK.split(scrub_lone_surrogates(text))]
    blank_rule_on = _has_adjacent_lines(lines)
    read = [_read(line) for line in lines]
    priced_count = sum(1 for line in read if line is not None and line.priced)
    unpriced_count = sum(
        1
        for line in read
        if line is not None and not line.priced and not line.text.endswith(":")
    )
    priced_paste = (
        priced_count >= _MIN_PRICED_LINES and priced_count * 2 >= unpriced_count
    )
    max_words = vocabulary().pasted.pasted_header_max_words

    categories: list[MenuCategory] = []
    category_id = _UNCATEGORISED_ID
    category_name = uncategorised_name
    dishes: list[Dish] = []
    header_count = 0
    dish_count = 0
    can_continue = False
    dish_line: _Line | None = None

    def start_category(name: str) -> None:
        nonlocal category_id, category_name, dishes, header_count, can_continue
        if dishes:
            categories.append(
                MenuCategory(id=category_id, name=category_name, dishes=dishes)
            )
            dishes = []
        header_count += 1
        category_id = f"{_UNCATEGORISED_ID}-{header_count}"
        category_name = name
        can_continue = False

    def describe(part: str) -> None:
        last = dishes.pop()
        dishes.append(
            Dish(
                id=last.id,
                name=last.name,
                description=part
                if not last.description
                else f"{last.description} {part}",
                price=0.0,
                options=[],
            )
        )

    for index, raw in enumerate(lines):
        if not raw:
            can_continue = False
            continue
        if dish_count >= max_dishes:
            break

        line = read[index]
        if line is None:
            continue
        cleaned = line.text

        if cleaned.endswith(":"):
            name = dart_trim(cleaned[:-1])
            if name:
                start_category(name)
                continue
        if line.emphasised and not line.priced:
            start_category(cleaned)
            continue

        above = dish_line
        if can_continue and above is not None and _continues(line, above):
            describe(cleaned)
            continue

        if priced_paste and not line.priced and line.bullet == _BULLET_NONE:
            short = (
                not _DIGIT.search(cleaned)
                and len(_WHITESPACE.split(cleaned)) <= max_words
            )
            if can_continue and above is not None and above.priced:
                if short and _is_capitals_only(cleaned):
                    start_category(cleaned)
                else:
                    describe(cleaned)
                continue
            if short and _next_is_priced(read, index):
                start_category(cleaned)
                continue

        if blank_rule_on and _is_short_header(cleaned, lines, index):
            start_category(cleaned)
            continue

        dish_count += 1
        dishes.append(
            Dish(
                id=f"p{dish_count}", name=cleaned, description="", price=0.0, options=[]
            )
        )
        can_continue = True
        dish_line = line

    if dishes:
        categories.append(
            MenuCategory(id=category_id, name=category_name, dishes=dishes)
        )
    if not categories:
        return None

    provisional = Menu(
        venue_ref=VenueRef(source="scan", platform_id="pending"),
        currency=_CURRENCY,
        fetched_at=fetched_at,
        categories=categories,
    )
    return Menu(
        venue_ref=scan_ref(provisional),
        currency=_CURRENCY,
        fetched_at=fetched_at,
        categories=categories,
    )


def _has_adjacent_lines(lines: list[str]) -> bool:
    """Whether two non-blank lines sit next to each other."""
    return any(lines[index] and lines[index - 1] for index in range(1, len(lines)))


def _is_short_header(cleaned: str, lines: list[str], index: int) -> bool:
    """Whether ``cleaned`` (line ``index``, price-free) is short, digit-free,
    alone in its line group and followed by a blank line and then more text."""
    if _DIGIT.search(cleaned):
        return False
    if index > 0 and lines[index - 1]:
        return False
    max_words = vocabulary().pasted.pasted_header_max_words
    if len(_WHITESPACE.split(cleaned)) > max_words:
        return False
    follower = index + 1
    if follower >= len(lines) or lines[follower]:
        return False
    return any(lines[later] for later in range(follower + 1, len(lines)))


def _read(raw: str) -> _Line | None:
    """``raw``, a trimmed line, cleaned (Dart ``_read``), or ``None`` when
    nothing but punctuation is left of it."""
    text = _CHAT_PREFIX.sub("", raw, count=1)
    emphasised = False
    emphasis = _EMPHASIS.search(text)
    if emphasis is not None:
        text = emphasis.group(2)
        emphasised = True
    text = _INNER_BOLD.sub(lambda match: match.group(1), text)
    bullet = _BULLET_NONE
    dash = _DASH_BULLET.match(text)
    number = _NUMBER_BULLET.match(text) if dash is None else None
    if dash is not None:
        text = text[dash.end() :]
        bullet = _BULLET_DASH
    elif number is not None:
        text = text[number.end() :]
        bullet = _BULLET_OTHER
    else:
        start = 0
        while start < len(text) and _is_bullet_char(text[start]):
            start += 1
        if start > 0:
            text = dart_trim(text[start:])
            bullet = _BULLET_OTHER
    without_suffix = dart_trim(_PRICE_SUFFIX.sub("", text, count=1))
    without_prefix = _PRICE_PREFIX.sub("", without_suffix, count=1)
    cleaned = dart_trim(_SIZED_PRICE.sub("", without_prefix))
    if not has_letter_or_digit(cleaned):
        return None
    return _Line(
        text=cleaned,
        priced=without_suffix != dart_trim(text) or without_prefix != without_suffix,
        bullet=bullet,
        emphasised=emphasised,
    )


def _is_bullet_char(char: str) -> bool:
    """Whether ``char`` is part of a leading bullet."""
    return (
        not has_letter_or_digit(char)
        and _SPACE.fullmatch(char) is None
        and char not in _NOT_BULLETS
    )


def _continues(line: _Line, above: _Line) -> bool:
    """Whether ``line`` reads as the wrapped tail of the dish ``above`` made."""
    if line.bullet == _BULLET_OTHER:
        return False
    if line.bullet == _BULLET_DASH:
        return above.bullet == _BULLET_NONE
    if line.text.startswith("("):
        return True
    return starts_lowercase(line.text) and not starts_lowercase(above.text)


def _is_capitals_only(text: str) -> bool:
    """Whether ``text`` holds a Latin capital and no lowercase letter."""
    return _LATIN_CAPITAL.search(text) is not None and not any(
        _is_lowercase(char) for char in text
    )


def _next_is_priced(read: list[_Line | None], index: int) -> bool:
    """Whether the next line after ``index`` that was read is priced."""
    for later in read[index + 1 :]:
        if later is not None:
            return later.priced
    return False

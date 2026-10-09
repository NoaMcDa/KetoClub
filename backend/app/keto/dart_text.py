"""Dart ``String`` semantics the port must reproduce (architecture.md D25).

A Dart ``String`` is a sequence of UTF-16 code units, and several of its
methods differ from Python's ``str`` in ways that change a result:

* **Lengths and indices are UTF-16 code units.** An astral character
  (an emoji, a mathematical letter) is one Python character but two Dart
  units, so ``len`` undercounts it. :func:`utf16_len`,
  :func:`utf16_units` and :func:`utf16_slice` count and cut the Dart way.
* **``toLowerCase`` maps one character to one character.** Python's
  ``str.lower`` applies the full Unicode mapping (``İ`` becomes ``i`` plus a
  combining dot) and a final-sigma rule (``ΑΣ`` becomes ``ας``); Dart does
  neither. :func:`dart_lower` lowercases character by character.
* **``trim`` strips a different set.** Dart strips U+FEFF and U+0085 but not
  the information separators U+001C–U+001F, which Python's ``strip``
  removes. :func:`dart_trim` strips exactly Dart's set.

Every function here is pure and total: a lone surrogate (which Python and
Dart strings may both hold) is carried through, never an error.
"""

from typing import Final

DART_WHITESPACE: Final[frozenset[str]] = frozenset(
    [chr(code) for code in range(0x09, 0x0E)]
    + [
        " ",
        "\u0085",
        " ",
        " ",
        *[chr(code) for code in range(0x2000, 0x200B)],
        " ",
        " ",
        " ",
        " ",
        "　",
        "﻿",
    ]
)
"""The characters Dart's ``String.trim`` removes from either end."""


def utf16_units(text: str) -> list[int]:
    """``text`` as Dart's ``codeUnits``: its UTF-16 code units, in order.

    An astral character becomes its surrogate pair; a lone surrogate stays
    one unit.
    """
    encoded = text.encode("utf-16-le", errors="surrogatepass")
    return [
        int.from_bytes(encoded[index : index + 2], "little")
        for index in range(0, len(encoded), 2)
    ]


def utf16_len(text: str) -> int:
    """Dart's ``String.length``: the number of UTF-16 code units."""
    return len(text) + sum(1 for char in text if ord(char) > 0xFFFF)


def from_utf16_units(units: list[int]) -> str:
    """The string Dart's ``String.fromCharCodes`` builds from ``units``.

    A surrogate pair joins into one astral character; an unpaired surrogate
    stays a lone surrogate.
    """
    encoded = b"".join(unit.to_bytes(2, "little") for unit in units)
    return encoded.decode("utf-16-le", errors="surrogatepass")


def utf16_slice(text: str, start: int, end: int | None = None) -> str:
    """Dart's ``substring(start, end)``, indexed in UTF-16 code units.

    Cutting through a surrogate pair leaves a lone surrogate, as Dart does.
    """
    return from_utf16_units(utf16_units(text)[start:end])


def dart_lower(text: str) -> str:
    """Dart's ``toLowerCase``: a one-to-one lowercase per character.

    No final-sigma rule (``Σ`` is always ``σ``) and no multi-character
    mapping (``İ`` is ``i``, not ``i`` plus U+0307).
    """
    out: list[str] = []
    for char in text:
        lowered = char.lower()
        if len(lowered) != 1:
            # The only unconditional one-to-many lowercase mapping is U+0130,
            # whose simple (one-to-one) lowercase is a plain ``i``.
            lowered = "i" if char == "İ" else char
        out.append(lowered)
    return "".join(out)


def dart_trim(text: str) -> str:
    """Dart's ``String.trim``: strips :data:`DART_WHITESPACE` from both ends."""
    start = 0
    end = len(text)
    while start < end and text[start] in DART_WHITESPACE:
        start += 1
    while end > start and text[end - 1] in DART_WHITESPACE:
        end -= 1
    return text[start:end]

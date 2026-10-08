"""Trigger patterns: the one Latin and one Hebrew word boundary.

The Python twins of ``latinTriggerPattern`` and ``hebrewTriggerPattern`` in
``lib/utils/classification_rules.dart`` (architecture.md D25). Each builder
has two halves: a ``*_source`` function that returns the **Dart pattern
source text** exactly as Dart builds it (pinned by the vocabulary golden's
``latinTriggerPatternExample``/``hebrewTriggerPatternExample``), and a
``*_pattern`` function that compiles that same source with Python ``re``
flags that reproduce the Dart semantics:

* **Latin** — ``\\b<trigger>\\b``, case-insensitive, non-unicode. Dart's
  ``\\b`` is ASCII-only, so the Python pattern uses ``re.ASCII``: a Hebrew
  letter, ``ß``, ``ı`` or an astral letter beside a trigger counts as a
  boundary, and ``_`` does not. Every normalised Latin trigger in the
  vocabulary is ASCII, and Dart's non-unicode ignore-case never maps a
  non-ASCII character onto an ASCII one, so ASCII-only case folding is
  exact.
* **Hebrew** — ``(?<![א-ת])`` then up to two grammatical prefix letters
  (``בהוכלמש``, part of the match span) when ``allow_prefix``, the trigger,
  an optional inflection, and ``(?![א-ת])``. Case-sensitive.

Triggers must already be normalised (:func:`app.keto.normaliser.normalise`).
Match *offsets* from these patterns are Python code-point indices; a caller
that needs Dart (UTF-16) offsets converts them with
:func:`app.keto.dart_text.utf16_len` over the prefix.
"""

import re
from functools import cache
from typing import Final

HEBREW_LETTERS: Final = "א-ת"
"""The Hebrew letter range the lookarounds use (U+05D0–U+05EA)."""

HEBREW_PREFIXES: Final = "בהוכלמש"
"""The grammatical prefix particles allowed directly before a trigger."""

_HEBREW_INFLECTION: Final = "(?:ימ|ות|יות|י|ית)?"

_DART_ESCAPED: Final = frozenset("$()*+.?[\\]^{|}")
"""The characters Dart's ``RegExp.escape`` prefixes with a backslash."""


def dart_regexp_escape(text: str) -> str:
    """Dart's ``RegExp.escape``: a backslash before each of
    ``$ ( ) * + . ? [ \\ ] ^ { | }`` and nothing else."""
    return "".join("\\" + char if char in _DART_ESCAPED else char for char in text)


def latin_trigger_source(normalised_trigger: str) -> str:
    """The Dart source of ``latinTriggerPattern(normalised_trigger)``."""
    return f"\\b{dart_regexp_escape(normalised_trigger)}\\b"


def hebrew_trigger_source(
    normalised_trigger: str,
    *,
    allow_inflection: bool = False,
    allow_prefix: bool = True,
) -> str:
    """The Dart source of ``hebrewTriggerPattern(normalised_trigger, ...)``."""
    prefix = f"[{HEBREW_PREFIXES}]{{0,2}}" if allow_prefix else ""
    inflection = _HEBREW_INFLECTION if allow_inflection else ""
    return (
        f"(?<![{HEBREW_LETTERS}]){prefix}"
        f"{dart_regexp_escape(normalised_trigger)}{inflection}"
        f"(?![{HEBREW_LETTERS}])"
    )


@cache
def latin_trigger_pattern(normalised_trigger: str) -> re.Pattern[str]:
    """``latinTriggerPattern``: an ASCII word-boundary, ignore-case match."""
    return re.compile(
        latin_trigger_source(normalised_trigger), re.ASCII | re.IGNORECASE
    )


@cache
def hebrew_trigger_pattern(
    normalised_trigger: str,
    *,
    allow_inflection: bool = False,
    allow_prefix: bool = True,
) -> re.Pattern[str]:
    """``hebrewTriggerPattern``: the Hebrew-letter lookaround match."""
    return re.compile(
        hebrew_trigger_source(
            normalised_trigger,
            allow_inflection=allow_inflection,
            allow_prefix=allow_prefix,
        )
    )

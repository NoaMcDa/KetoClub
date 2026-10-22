"""Linear-time stand-ins for the website readers' tag regexes (#268).

A pattern such as ``<(script|style)\\b[^>]*>.*?</\\1\\s*>`` costs the length
of the rest of the page at every opening tag that is never closed, so a page
of repeated ``<script>`` takes time quadratic in its size: about half an hour
for the 2 MB ``WEBSITE_MAX_HTML_BYTES`` allows. The same holds for
``<!--.*?-->`` and for a lone ``<[^>]+>`` with no ``>`` after it.

Each helper here returns **exactly** what the regex it replaces returns, for
every input, and is pinned to it by a differential test
(``tests/test_website_linear.py``); only the cost changes. They are what both
readers use: the D25 port of the Dart reader (:mod:`app.website.html`, pinned
to Dart by the golden corpus) and the ``/v1/website/fetch`` page judge
(:mod:`app.services.website`).

The trick in every case is the same: a regex attempt that scans far and fails
is skipped when it is known to fail, and an attempt that scans far and
succeeds consumes what it scanned, so nothing is scanned twice.

* An opening tag ends at the first ``>`` after its name (``[^>]*>`` can end
  nowhere else), found once and shared by every candidate before it.
* The lazy ``.*?</\\1\\s*>`` ends at the first closing tag of the same name
  after that ``>``, looked up in a sorted index of every closing tag built in
  one pass. Names are compared lower-cased, as Python's backreference
  compares them under ``IGNORECASE``.
* A pattern that must end in ``>`` cannot match after a page's last ``>``, so
  the tail past it is never searched.
"""

import re
from bisect import bisect_left
from collections.abc import Callable, Iterator
from dataclasses import dataclass
from typing import Final

_DOTTED_CAPITAL_I: Final = "\N{LATIN CAPITAL LETTER I WITH DOT ABOVE}"


def _backreference_key(name: str) -> str:
    """``name`` as Python's ``IGNORECASE`` backreference compares it.

    ``re`` compares backreferences character by character through the simple
    lower-case mapping. ``str.lower`` is that mapping for every character but
    U+0130, the one character whose full lower case is two characters.
    """
    if _DOTTED_CAPITAL_I not in name:
        return name.lower()
    return "".join("i" if char == _DOTTED_CAPITAL_I else char.lower() for char in name)


@dataclass(frozen=True, slots=True)
class Block:
    """One ``<name ...>...</name>`` element as a regex match would span it.

    ``name_end`` is just past the tag name (where ``[^>]*`` starts),
    ``content_start`` just past the opening tag's ``>``, ``content_end`` at
    the closing tag's ``<`` and ``end`` just past its ``>``.
    """

    start: int
    name_end: int
    content_start: int
    content_end: int
    end: int


OpenTagCheck = Callable[[str, int, int], bool]
"""``(text, start, end)``: whether the opening tag ``text[start:end]`` (its
``<`` to its ``>`` inclusive) is one the pattern accepts."""


class PairedTags:
    """The non-overlapping matches of ``<(names)\\b[^>]*>(.*?)</\\1{space}*>``,
    or of ``<name\\b[^>]*>(.*?)</name{space}*>`` when ``same_name`` is false.

    ``names`` is the alternation's source and ``space`` the regex source of
    one whitespace character, both exactly as in the pattern replaced;
    ``same_name`` says whether the closing tag is a backreference to the
    opening one's name (``\\1``) or the name spelled out again, which under
    Unicode case folding is not the same thing (``</noscrıpt>`` closes
    ``<noſcript>`` only in the second form);
    ``flags`` are its flags (``IGNORECASE`` at least; ``DOTALL`` is implied by
    the lazy body this class emulates). ``open_tag`` narrows which opening
    tags count, for a pattern whose ``[^>]*`` is split around a required
    attribute; it must be such that when it refuses a tag it also refuses
    every later candidate ending at the same ``>`` (true of any
    ``<name\\b[^>]*X[^>]*>``, because the first ``[^>]*`` can swallow the
    later candidate).
    """

    def __init__(
        self,
        names: str,
        *,
        space: str,
        flags: int,
        same_name: bool,
        open_tag: OpenTagCheck | None = None,
    ) -> None:
        self._opener = re.compile(rf"<({names})\b", flags)
        self._closer = re.compile(rf"</({names}){space}*>", flags)
        self._same_name = same_name
        self._open_tag = open_tag

    def _key(self, name: str) -> str:
        return _backreference_key(name) if self._same_name else ""

    def _closers(self, text: str) -> tuple[dict[str, tuple[list[int], list[int]]], int]:
        """Every closing tag's start and end, by name key, and the last
        start of any (-1 for none)."""
        index: dict[str, tuple[list[int], list[int]]] = {}
        last = -1
        for match in self._closer.finditer(text):
            starts, ends = index.setdefault(self._key(match.group(1)), ([], []))
            starts.append(match.start())
            ends.append(match.end())
            last = match.start()
        return index, last

    def finditer(self, text: str) -> Iterator[Block]:
        """Every match, left to right, as ``re.finditer`` would yield them."""
        closers, last_closer = self._closers(text)
        position = 0
        next_gt = -2  # not looked up yet
        # Candidates ending at the same ">" share their fate: a refused open
        # tag refuses them all, and so does a missing closing tag of the
        # same name (the closing tag is looked for after that ">" alike).
        refused_gt = -1
        unclosed_gt = -1
        unclosed: set[str] = set()
        for candidate in self._opener.finditer(text):
            start = candidate.start()
            if start < position:
                continue
            name_end = candidate.end()
            if next_gt != -1 and next_gt < name_end:
                next_gt = text.find(">", name_end)
            if next_gt == -1:
                return  # no ">" left: no later candidate can match either
            if last_closer <= next_gt:
                return  # no closing tag left after this ">": none can match
            if next_gt == refused_gt:
                continue
            if self._open_tag is not None and not self._open_tag(
                text, start, next_gt + 1
            ):
                refused_gt = next_gt
                continue
            key = self._key(candidate.group(1))
            if unclosed_gt != next_gt:
                unclosed_gt, unclosed = next_gt, set()
            elif key in unclosed:
                continue
            starts, ends = closers.get(key, ([], []))
            at = bisect_left(starts, next_gt + 1)
            if at == len(starts):
                unclosed.add(key)
                continue
            block = Block(
                start=start,
                name_end=name_end,
                content_start=next_gt + 1,
                content_end=starts[at],
                end=ends[at],
            )
            position = block.end
            yield block

    def sub(self, replacement: str, text: str) -> str:
        """``pattern.sub(replacement, text)`` for a literal ``replacement``."""
        pieces: list[str] = []
        kept = 0
        for block in self.finditer(text):
            pieces.append(text[kept : block.start])
            pieces.append(replacement)
            kept = block.end
        if not pieces:
            return text
        pieces.append(text[kept:])
        return "".join(pieces)


def sub_comments(replacement: str, text: str) -> str:
    """``re.sub("<!--.*?-->", replacement, text, flags=re.DOTALL)``."""
    pieces: list[str] = []
    kept = 0
    position = 0
    while True:
        start = text.find("<!--", position)
        if start == -1:
            break
        close = text.find("-->", start + 4)
        if close == -1:
            break  # unclosed: no later "<!--" has a "-->" after it either
        pieces.append(text[kept:start])
        pieces.append(replacement)
        kept = position = close + 3
    if not pieces:
        return text
    pieces.append(text[kept:])
    return "".join(pieces)


def sub_tags(pattern: re.Pattern[str], replacement: str, text: str) -> str:
    """``pattern.sub(replacement, text)`` for a pattern that ends in ``>``
    and holds no ``>`` before it except in ``[^>]`` (``<[^>]+>``,
    ``<meta\\b[^>]*>``): with the tail past the last ``>`` cut off, every
    attempt that scans finds its ``>`` and consumes what it scanned.
    """
    last = text.rfind(">")
    if last == -1:
        return text
    return pattern.sub(replacement, text[: last + 1]) + text[last + 1 :]


def find_tags(pattern: re.Pattern[str], text: str) -> Iterator[re.Match[str]]:
    """``pattern.finditer(text)`` for a pattern :func:`sub_tags` accepts."""
    return pattern.finditer(text, 0, text.rfind(">") + 1)

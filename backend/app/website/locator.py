"""Finding a restaurant page's menu, and reading it out of its text (D19, #326).

The Python twin of ``WebsiteMenuLocator``. Pure: no I/O and nothing raises.
:func:`locate` tries, in order:

1. JSON-LD ``Menu`` / ``MenuSection`` / ``MenuItem`` markup with named items.
2. A link to the menu: the JSON-LD ``hasMenu`` URL first, then the page's own
   links whose address or text says "menu" or "תפריט", or that end in
   ``.pdf``. A menu-named PDF comes first, then a menu-named page, then any
   PDF, each group in page order. A page link must stay on the same site
   (``www.`` aside); a PDF may live elsewhere. A link back to the page itself
   is skipped.
3. Nothing: the caller reads the page itself with :func:`menu_text`.
"""

import re
from dataclasses import dataclass
from typing import Final

from app.keto.dart_text import dart_lower, dart_trim
from app.keto.models import MenuCategory, to_json
from app.keto.text_menu import WS, dart_upper_first, has_letter, starts_lowercase
from app.keto.vocabulary import vocabulary
from app.website.html import (
    DartUri,
    PageLink,
    UriFormatError,
    decode_full,
    json_ld_blocks,
    lines,
    links,
)
from app.website.json_ld import categories_from, menu_url_from


@dataclass(frozen=True)
class JsonLdMenuFound:
    """The page carries a schema.org menu with items (step 1)."""

    categories: list[MenuCategory]


@dataclass(frozen=True)
class MenuLinkFound:
    """The page links to its menu, a menu page or a PDF (step 2)."""

    uri: DartUri

    @property
    def is_pdf(self) -> bool:
        """Whether ``uri`` names a PDF."""
        return _is_pdf(self.uri)


@dataclass(frozen=True)
class NoMenuLink:
    """Neither: the page's own text is all there is to read (step 3)."""


MenuLocation = JsonLdMenuFound | MenuLinkFound | NoMenuLink


def location_to_json(location: MenuLocation) -> dict[str, object]:
    """``location`` as the ``{kind, ...}`` object the golden export writes."""
    match location:
        case JsonLdMenuFound(categories=categories):
            return {"kind": "jsonLd", "categories": [to_json(c) for c in categories]}
        case MenuLinkFound(uri=uri):
            return {"kind": "link", "uri": uri.to_string(), "isPdf": location.is_pdf}
        case NoMenuLink():
            return {"kind": "none"}


def locate(html: str, page_url: DartUri) -> MenuLocation:
    """Where ``html``, fetched from ``page_url``, keeps its menu."""
    blocks = json_ld_blocks(html)
    categories = categories_from(blocks)
    if categories is not None:
        return JsonLdMenuFound(categories)

    from_json_ld = menu_url_from(blocks, page_url)
    if from_json_ld is not None and not _same_page(from_json_ld, page_url):
        return MenuLinkFound(from_json_ld)

    best: MenuLinkFound | None = None
    best_score = 0
    for link in links(html, page_url):
        if _same_page(link.uri, page_url):
            continue
        is_pdf = _is_pdf(link.uri)
        named = _names_menu(link)
        if not is_pdf and not (named and _same_site(link.uri, page_url)):
            continue
        score = 3 if named and is_pdf else (2 if named else 1)
        if score > best_score:
            best = MenuLinkFound(link.uri)
            best_score = score
    return best if best is not None else NoMenuLink()


_PRICE_ONLY: Final = re.compile(
    rf'^(?:₪{WS}*)?[0-9]{{1,4}}(?:[.,][0-9]{{1,2}})?{WS}*(?:₪|NIS|ILS|ש["״]ח)?\Z',
    re.IGNORECASE | re.ASCII,
)
_TRAILING_PRICE: Final = re.compile(
    rf"(?:{WS}+|{WS}*[-–—:.…|]+{WS}*)(?:₪{WS}*)?[0-9]{{1,4}}(?:[.,][0-9]{{1,2}})?"
    rf'(?:{WS}*(?:₪|NIS|ILS|ש["״]ח))?{WS}*\Z',
    re.IGNORECASE | re.ASCII,
)
_ENDS_IN_DIGIT: Final = re.compile(r"[0-9\-–/]\Z")
_BULLET: Final = re.compile(rf"^[-•*·▪►]+{WS}*")
_WHITESPACE: Final = re.compile(f"{WS}+")
_TRAILING_COLONS: Final = re.compile(r":+\Z")
_ESCAPE: Final = re.compile("%([0-9A-Fa-f]{2})")


def menu_text(html: str) -> str | None:
    """The page's menu as lines ``text_menu.parse`` reads (a header per
    ``Name:`` line, a dish per line, its description on a ``- `` line after
    it), or ``None`` when fewer than ``minPricedLines`` lines carry a price.

    Prices are how a menu is told apart from the rest of a page, and only the
    stretch from the first priced line to the last is read, so navigation
    above and contact details below never become dishes. A page whose prices
    sit on their own lines reads each price as closing a dish: the line
    before it is the description when there are two, and a third line before
    those is a section header. A page whose prices end the dish line reads
    each priced line as a dish, and the lines after it as its description,
    except a short last line (three words, no comma) right before the next
    dish, which is a header. Nothing after the last priced dish is read. The
    prices themselves are dropped, as a paste's are.
    """
    page_lines = lines(html)
    price_only = 0
    inline = 0
    for line in page_lines:
        if _PRICE_ONLY.search(line):
            price_only += 1
        elif _inline_dish_name(line) is not None:
            inline += 1
    if price_only + inline < vocabulary().website.min_priced_lines:
        return None
    out = (
        _from_separate_prices(page_lines)
        if price_only >= inline
        else _from_inline_prices(page_lines)
    )
    return "\n".join(out) if out else None


def _from_separate_prices(page_lines: list[str]) -> list[str]:
    out: list[str] = []
    pending: list[str] = []
    for line in page_lines:
        if not _PRICE_ONLY.search(line):
            pending.append(line)
            continue
        block, pending = pending, []
        if not block:
            continue
        if len(block) == 1:
            _emit_dish(out, block[0], [])
        else:
            if len(block) >= 3:
                _emit_header(out, block[-3])
            _emit_dish(out, block[-2], [block[-1]])
    return out


def _from_inline_prices(page_lines: list[str]) -> list[str]:
    out: list[str] = []
    between: list[str] = []
    description: list[str] = []
    have_dish = False
    name: str | None = None

    def close_dish() -> None:
        nonlocal name, description
        if name is not None:
            _emit_dish(out, name, description)
        name = None
        description = []

    for line in page_lines:
        dish_name = _inline_dish_name(line)
        if dish_name is None:
            between.append(line)
            continue
        if not have_dish:
            if between and _looks_like_header(between[-1]):
                _emit_header(out, between[-1])
        elif len(between) == 1 and _looks_like_header(between[0]):
            close_dish()
            _emit_header(out, between[0])
        elif len(between) > 1:
            description.extend(between[:-1])
            close_dish()
            _emit_header(out, between[-1])
        else:
            description.extend(between)
        close_dish()
        name = dish_name
        have_dish = True
        between = []
    # Lines after the last priced dish are the page's footer, never its
    # description.
    close_dish()
    return out


def _inline_dish_name(line: str) -> str | None:
    """The dish name in ``line`` when it ends in a price, else ``None``. The
    name must hold a letter and must not itself end in a digit or a dash."""
    match = _TRAILING_PRICE.search(line)
    if match is None:
        return None
    rest = dart_trim(line[: match.start()])
    if not has_letter(rest) or _ENDS_IN_DIGIT.search(rest):
        return None
    return rest


def _looks_like_header(line: str) -> bool:
    return "," not in line and len(_WHITESPACE.split(line)) <= 3


def _emit_header(out: list[str], line: str) -> None:
    name = dart_trim(_TRAILING_COLONS.sub("", _clean(line)))
    if has_letter(name):
        out.append(f"{name}:")


def _emit_dish(out: list[str], line: str, about: list[str]) -> None:
    name = _clean(line)
    if name.endswith(":"):
        name = dart_trim(name[:-1])
    if not has_letter(name):
        return
    # ``text_menu.parse`` reads a line starting in lower case as the previous
    # dish's description; a dish name is capitalised so it stays a dish.
    if starts_lowercase(name):
        name = dart_upper_first(name)
    out.append(name)
    text = " ".join(cleaned for cleaned in map(_clean, about) if has_letter(cleaned))
    if text:
        out.append(f"- {text}")


def _clean(line: str) -> str:
    return dart_trim(_WHITESPACE.sub(" ", _BULLET.sub("", line, count=1)))


def _is_pdf(uri: DartUri) -> bool:
    return _lower(uri.path).endswith(".pdf")


def _lower(text: str) -> str:
    """Dart ``toLowerCase`` (one-to-one), fast for ASCII."""
    return text.lower() if text.isascii() else dart_lower(text)


def _names_menu(link: PageLink) -> bool:
    address = _lower(_decode_path(link.uri.path))
    text = _lower(link.text)
    return any(
        word in address or word in text for word in vocabulary().website.menu_words
    )


def _decode_path(path: str) -> str:
    """``path`` percent-decoded as UTF-8, else byte by byte as windows-1255
    (older Hebrew sites encode ``תפריט`` as ``%FA%F4%F8%E9%E8``). Never
    raises."""
    try:
        return decode_full(path)
    except UriFormatError:

        def one(match: re.Match[str]) -> str:
            octet = int(match.group(1), 16)
            # The Hebrew letters of windows-1255 sit at 0xE0-0xFA.
            return chr(0x05D0 + octet - 0xE0 if 0xE0 <= octet <= 0xFA else octet)

        return _ESCAPE.sub(one, path)


def _same_site(a: DartUri, b: DartUri) -> bool:
    return _bare_host(a) == _bare_host(b)


def _bare_host(uri: DartUri) -> str:
    host = _lower(uri.host_text)
    return host[4:] if host.startswith("www.") else host


def _same_page(a: DartUri, b: DartUri) -> bool:
    return (
        _same_site(a, b)
        and _trim_slash(a.path) == _trim_slash(b.path)
        and a.query_text == b.query_text
    )


def _trim_slash(path: str) -> str:
    return path[:-1] if path.endswith("/") else path

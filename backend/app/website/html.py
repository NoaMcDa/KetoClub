"""Pure readings of one HTML page for the website menu source (D19, #326).

The Python twin of ``WebsiteHtml`` in
``lib/services/menu/website/website_html.dart``: a page's visible lines,
links and JSON-LD blocks, and the two signals that stop a read (an AI opt-out
and a page that renders only with JavaScript). Regular expressions, not a
DOM, exactly as in Dart, and nothing here raises on any ``str``.

Two Dart behaviours are reproduced on purpose and are the reason this module
is longer than a handful of regexes:

* **The Dart regexes are non-unicode ones.** ``\\s`` is ECMAScript's set
  (:data:`app.keto.text_menu.WS`), ``\\b`` and the case-insensitive flag are
  ASCII-only, so every pattern here is compiled ``re.ASCII`` and spells its
  whitespace class out.
* **A link is a Dart ``Uri``.** Page links are resolved against the page's
  URL and written back with ``Uri.toString()``, whose escaping and resolution
  rules differ from ``urllib``'s: uppercase percent-escapes, ``%7E`` decoded
  to ``~``, ``[``/``]`` escaped, ``\\`` read as ``/``, a default port dropped,
  dot segments removed. :class:`DartUri` is a port of the parts of
  ``dart:core``'s ``Uri`` that ``http(s)`` links reach (scheme, authority,
  path, query, fragment, ``resolve``, ``removeFragment``, ``toString``). It
  lives here because :mod:`app.website.json_ld` and
  :mod:`app.website.locator` both build on it and import this module.
"""

import ipaddress
import json
import re
import string
from dataclasses import dataclass
from typing import Any, Final

from app.keto.dart_text import dart_lower, dart_trim, utf16_len
from app.keto.text_menu import NOT_WS, WS, join_surrogates
from app.keto.vocabulary import vocabulary

# --- Dart's ``Uri`` -----------------------------------------------------------


class UriFormatError(ValueError):
    """Dart's ``FormatException`` from ``Uri.parse``/``Uri.resolve``."""


_UNRESERVED: Final = frozenset(string.ascii_letters + string.digits + "-._~")
_SUB_DELIMS: Final = frozenset("!$&'()*+,;=")
_USERINFO: Final = _UNRESERVED | _SUB_DELIMS | {":"}
_REG_NAME: Final = _UNRESERVED | _SUB_DELIMS
_PATH_OR_SLASH: Final = _UNRESERVED | _SUB_DELIMS | {":", "@", "/"}
_QUERY: Final = _UNRESERVED | _SUB_DELIMS | {":", "@", "/", "?"}
_GEN_DELIMS: Final = frozenset(":/?#[]@")
_HEX: Final = frozenset("0123456789abcdefABCDEF")
_SCHEME_END: Final = re.compile(r"[:/\\]")
_AUTHORITY_END: Final = re.compile(r"[/\\]")
_SCHEME_CHARS: Final = re.compile(r"[A-Za-z][A-Za-z0-9+.\-]*")
_DEFAULT_PORTS: Final = {"http": 80, "https": 443}


def _fail(message: str) -> UriFormatError:
    return UriFormatError(message)


def _escape_char(code: int) -> str:
    """Dart ``_escapeChar``: ``%XX`` for ASCII, else the UTF-8 bytes (a lone
    surrogate is encoded as three bytes, as Dart's hand-rolled encoder does).
    """
    if code <= 0x7F:
        return f"%{code:02X}"
    if code <= 0x7FF:
        octets = [0xC0 | code >> 6, 0x80 | code & 0x3F]
    elif code <= 0xFFFF:
        octets = [0xE0 | code >> 12, 0x80 | code >> 6 & 0x3F, 0x80 | code & 0x3F]
    else:
        octets = [
            0xF0 | code >> 18,
            0x80 | code >> 12 & 0x3F,
            0x80 | code >> 6 & 0x3F,
            0x80 | code & 0x3F,
        ]
    return "".join(f"%{octet:02X}" for octet in octets)


def _normalize_escape(source: str, index: int, *, lower_case: bool) -> str | None:
    """Dart ``_normalizeEscape``: ``None`` keeps the escape, ``"%"`` marks it
    invalid, anything else replaces its three characters."""
    if index + 2 >= len(source):
        return "%"
    first, second = source[index + 1], source[index + 2]
    if first not in _HEX or second not in _HEX:
        return "%"
    value = int(first + second, 16)
    if chr(value) in _UNRESERVED:
        char = chr(value)
        return char.lower() if lower_case and "A" <= char <= "Z" else char
    if first >= "a" or second >= "a":
        return source[index : index + 3].upper()
    return None


def _normalize(
    component: str,
    allowed: frozenset[str],
    *,
    escape_delimiters: bool = False,
    replace_backslash: bool = False,
) -> str:
    """Dart ``_normalizeOrSubstring``: percent-escape what ``allowed`` lacks,
    uppercase escapes, decode escaped unreserved characters."""
    out: list[str] = []
    index = 0
    size = len(component)
    while index < size:
        char = component[index]
        if char in allowed:
            out.append(char)
            index += 1
        elif char == "%":
            replacement = _normalize_escape(component, index, lower_case=False)
            if replacement is None:
                out.append(component[index : index + 3])
                index += 3
            elif replacement == "%":
                out.append("%25")
                index += 1
            else:
                out.append(replacement)
                index += 3
        elif char == "\\" and replace_backslash:
            out.append("/")
            index += 1
        elif not escape_delimiters and char in _GEN_DELIMS:
            raise _fail("Invalid character")
        else:
            out.append(_escape_char(ord(char)))
            index += 1
    return "".join(out)


def _make_scheme(scheme: str) -> str:
    if not scheme:
        return ""
    if not ("A" <= scheme[0] <= "Z" or "a" <= scheme[0] <= "z"):
        raise _fail("Scheme not starting with alphabetic character")
    return scheme.lower()


def _make_port(port: int | None, scheme: str) -> int | None:
    default = _DEFAULT_PORTS.get(scheme, 0)
    return None if port is not None and port == default else port


def _normalize_reg_name(host: str) -> str:
    out: list[str] = []
    index = 0
    while index < len(host):
        char = host[index]
        if char == "%":
            replacement = _normalize_escape(host, index, lower_case=True)
            if replacement is None:
                out.append(host[index : index + 3])
                index += 3
            elif replacement == "%":
                out.append("%25")
                index += 1
            else:
                out.append(replacement)
                index += 3
        elif char in _REG_NAME:
            out.append(char.lower() if "A" <= char <= "Z" else char)
            index += 1
        elif char in _GEN_DELIMS:
            raise _fail("Invalid character")
        else:
            out.append(_escape_char(ord(char)))
            index += 1
    return "".join(out)


def _make_host(host: str) -> str:
    """Dart ``_makeHost``: a bracketed IPv6 address, else a normalised
    reg-name (lower case, escaped)."""
    if not host:
        return ""
    if host[0] == "[":
        if host[-1] != "]":
            raise _fail("Missing end `]` to match `[` in host")
        inner = host[1:-1]
        try:
            ipaddress.IPv6Address(inner)
        except ValueError:
            raise _fail("Invalid IPv6 address") from None
        if "%" in inner:
            raise _fail("Zone ids are not supported")
        return f"[{inner.lower()}]"
    return _normalize_reg_name(host)


def _may_contain_dot_segments(path: str) -> bool:
    return path.startswith(".") or "/." in path


def _remove_dot_segments(path: str) -> str:
    if not _may_contain_dot_segments(path):
        return path
    output: list[str] = []
    append_slash = False
    for segment in path.split("/"):
        append_slash = False
        if segment == "..":
            if output:
                output.pop()
                if not output:
                    output.append("")
            append_slash = True
        elif segment == ".":
            append_slash = True
        else:
            output.append(segment)
    if append_slash:
        output.append("")
    return "/".join(output)


def _escape_scheme(path: str) -> str:
    if len(path) >= 2 and path[0].isascii() and path[0].isalpha():
        for index in range(1, len(path)):
            char = path[index]
            if char == ":":
                return f"{path[:index]}%3A{path[index + 1 :]}"
            if not char.isascii() or not (char.isalnum() or char in "+-."):
                break
    return path


def _normalize_relative_path(path: str, *, allow_scheme: bool) -> str:
    if not _may_contain_dot_segments(path):
        return path if allow_scheme else _escape_scheme(path)
    output: list[str] = []
    append_slash = False
    for segment in path.split("/"):
        if segment == "..":
            append_slash = True
            if output and output[-1] != "..":
                output.pop()
            else:
                output.append("..")
        elif segment == ".":
            append_slash = True
        else:
            append_slash = False
            if not segment and not output:
                segment = "./"
            output.append(segment)
    if not output:
        return "./"
    if append_slash:
        output.append("")
    if not allow_scheme:
        output[0] = _escape_scheme(output[0])
    return "/".join(output)


def _normalize_path(path: str, scheme: str, *, has_authority: bool) -> str:
    if (
        not scheme
        and not has_authority
        and not path.startswith("/")
        and not path.startswith("\\")
    ):
        return _normalize_relative_path(path, allow_scheme=False)
    return _remove_dot_segments(path)


def _make_path(path: str, scheme: str, *, has_authority: bool) -> str:
    is_file = scheme == "file"
    result = _normalize(
        path, _PATH_OR_SLASH, escape_delimiters=True, replace_backslash=True
    )
    if not result:
        if is_file:
            return "/"
    elif (is_file or has_authority) and not result.startswith("/"):
        result = "/" + result
    return _normalize_path(result, scheme, has_authority=has_authority)


def _merge_paths(base: str, reference: str) -> str:
    back_count = 0
    ref_start = 0
    while reference.startswith("../", ref_start):
        ref_start += 3
        back_count += 1
    base_end = base.rfind("/")
    while base_end > 0 and back_count > 0:
        new_end = base.rfind("/", 0, base_end)
        if new_end < 0:
            break
        delta = base_end - new_end
        if (
            delta in (2, 3)
            and base[new_end + 1] == "."
            and (delta == 2 or base[new_end + 2] == ".")
        ):
            break
        base_end = new_end
        back_count -= 1
    return base[: base_end + 1] + reference[ref_start - 3 * back_count :]


@dataclass(frozen=True)
class DartUri:
    """A normalised Dart ``Uri``: ``scheme``, ``user_info``, ``host`` (``None``
    when there is no authority), ``port`` (``None`` when absent or the
    scheme's default), ``path``, ``query`` and ``fragment`` (``None`` when
    the URI has none; ``""`` when it has an empty one)."""

    scheme: str = ""
    user_info: str = ""
    host: str | None = None
    port: int | None = None
    path: str = ""
    query: str | None = None
    fragment: str | None = None

    @property
    def has_authority(self) -> bool:
        """Dart ``hasAuthority``."""
        return self.host is not None

    @property
    def host_text(self) -> str:
        """Dart ``Uri.host``: ``""`` when there is no authority, and an IPv6
        address without its brackets."""
        host = self.host or ""
        return host[1:-1] if host.startswith("[") else host

    @property
    def query_text(self) -> str:
        """Dart ``Uri.query``: ``""`` when there is no query."""
        return self.query or ""

    @classmethod
    def parse(cls, text: str) -> "DartUri":
        """Dart ``Uri.parse``; raises :class:`UriFormatError` where Dart
        throws a ``FormatException``."""
        fragment: str | None = None
        cut = text.find("#")
        if cut >= 0:
            fragment, text = text[cut + 1 :], text[:cut]
        query: str | None = None
        cut = text.find("?")
        if cut >= 0:
            query, text = text[cut + 1 :], text[:cut]
        scheme = ""
        # The first ``:`` before any ``/`` ends the scheme, whatever precedes
        # it; one that is not a valid scheme is an error, not a path.
        colon = _SCHEME_END.search(text)
        if colon is not None and colon.group(0) == ":":
            scheme = _make_scheme(text[: colon.start()])
            if not scheme:
                raise _fail("Invalid empty scheme")
            if not _SCHEME_CHARS.fullmatch(scheme):
                raise _fail("Illegal scheme character")
            text = text[colon.end() :]

        host: str | None = None
        user_info = ""
        port: int | None = None
        if text[:2] in ("//", "\\\\", "/\\", "\\/"):
            end = _AUTHORITY_END.search(text, 2)
            authority = text[2 : end.start()] if end else text[2:]
            text = text[end.start() :] if end else ""
            at = authority.rfind("@")
            if at >= 0:
                user_info = _normalize(authority[:at], _USERINFO)
                authority = authority[at + 1 :]
            host_text, port_text = _split_port(authority)
            host = _make_host(host_text)
            if port_text:
                number = _try_parse_int(port_text)
                if number is None:
                    raise _fail("Invalid port")
                port = _make_port(number, scheme)
        return cls(
            scheme=scheme,
            user_info=user_info,
            host=host,
            port=port,
            path=_make_path(text, scheme, has_authority=host is not None),
            query=None
            if query is None
            else _normalize(query, _QUERY, escape_delimiters=True),
            fragment=None
            if fragment is None
            else _normalize(fragment, _QUERY, escape_delimiters=True),
        )

    def resolve(self, reference: str) -> "DartUri":
        """Dart ``Uri.resolve``: ``resolve_uri(DartUri.parse(reference))``."""
        return self.resolve_uri(DartUri.parse(reference))

    def resolve_uri(self, reference: "DartUri") -> "DartUri":
        """Dart ``Uri.resolveUri`` (RFC 3986 section 5.2)."""
        at_start, after_scheme, after_authority, after_path, after_query = range(5)
        split = at_start
        user_info = ""
        host: str | None = None
        port: int | None = None
        query: str | None = None
        if reference.scheme:
            scheme = reference.scheme
            if reference.has_authority:
                user_info, host, port = (
                    reference.user_info,
                    reference.host,
                    reference.port,
                )
            path = _remove_dot_segments(reference.path)
            query = reference.query
        else:
            scheme = self.scheme
            if reference.has_authority:
                user_info = reference.user_info
                host = reference.host
                port = _make_port(reference.port, scheme)
                path = _remove_dot_segments(reference.path)
                query = reference.query
                split = after_scheme
            else:
                user_info, host, port = self.user_info, self.host, self.port
                if not reference.path:
                    path = self.path
                    if reference.query is not None:
                        split = after_path
                        query = reference.query
                    else:
                        query = self.query
                        split = after_query
                else:
                    split = after_authority
                    if reference.path.startswith("/"):
                        path = _remove_dot_segments(reference.path)
                    elif not self.path:
                        if self.has_authority:
                            path = _remove_dot_segments("/" + reference.path)
                        elif self.scheme:
                            path = _remove_dot_segments(reference.path)
                        else:
                            path = reference.path
                    else:
                        merged = _merge_paths(self.path, reference.path)
                        if (
                            self.scheme
                            or self.has_authority
                            or self.path.startswith("/")
                        ):
                            path = _remove_dot_segments(merged)
                        else:
                            path = _normalize_relative_path(
                                merged, allow_scheme=bool(self.scheme)
                            )
                    query = reference.query
        fragment = reference.fragment
        if split == at_start:
            scheme = _make_scheme(scheme)
        if split <= after_scheme:
            if user_info:
                user_info = _normalize(user_info, _USERINFO)
            if port is not None:
                port = _make_port(port, scheme)
            if host:
                host = _make_host(host)
        if split <= after_path:
            path = _make_path(path, scheme, has_authority=host is not None)
            if query is not None:
                query = _normalize(query, _QUERY, escape_delimiters=True)
        if fragment is not None:
            fragment = _normalize(fragment, _QUERY, escape_delimiters=True)
        return DartUri(scheme, user_info, host, port, path, query, fragment)

    def remove_fragment(self) -> "DartUri":
        """Dart ``removeFragment``."""
        if self.fragment is None:
            return self
        return DartUri(
            self.scheme, self.user_info, self.host, self.port, self.path, self.query
        )

    def to_string(self) -> str:
        """Dart ``Uri.toString``."""
        parts: list[str] = []
        if self.scheme:
            parts.append(f"{self.scheme}:")
        if self.host is not None or self.scheme == "file":
            parts.append("//")
            if self.user_info:
                parts.append(f"{self.user_info}@")
            if self.host is not None:
                parts.append(self.host)
            if self.port is not None:
                parts.append(f":{self.port}")
        parts.append(self.path)
        if self.query is not None:
            parts.append(f"?{self.query}")
        if self.fragment is not None:
            parts.append(f"#{self.fragment}")
        return "".join(parts)

    def __str__(self) -> str:
        return self.to_string()


_INT_TEXT: Final = re.compile(rf"{WS}*([+-]?)(?:0[xX]([0-9a-fA-F]+)|([0-9]+)){WS}*\Z")
_INT64_MAX: Final = 2**63 - 1


def _try_parse_int(text: str) -> int | None:
    """Dart ``int.tryParse`` (VM): an optional sign, decimal digits or ``0x``
    hex digits, surrounding whitespace ignored, 64-bit range."""
    match = _INT_TEXT.match(text)
    if match is None:
        return None
    sign, hexadecimal, decimal = match.groups()
    value = int(hexadecimal, 16) if hexadecimal else int(decimal)
    value = -value if sign == "-" else value
    return value if -_INT64_MAX - 1 <= value <= _INT64_MAX else None


def _split_port(authority: str) -> tuple[str, str]:
    """The host and the port text of ``authority`` (userinfo already cut)."""
    if authority.startswith("["):
        close = authority.find("]")
        if close < 0:
            raise _fail("Missing end `]` to match `[` in host")
        rest = authority[close + 1 :]
        if not rest:
            return authority, ""
        if not rest.startswith(":"):
            raise _fail("Invalid character after the host")
        return authority[: close + 1], rest[1:]
    colon = authority.rfind(":")
    if colon < 0:
        return authority, ""
    return authority[:colon], authority[colon + 1 :]


def decode_full(path: str) -> str:
    """Dart ``Uri.decodeFull``: ``%XX`` runs decoded as UTF-8; raises
    :class:`UriFormatError` on bytes that are not UTF-8 (a ``FormatException``
    in Dart). ``path`` is an already-normalised ``Uri.path``."""
    if "%" not in path:
        return path
    octets = bytearray()
    index = 0
    while index < len(path):
        char = path[index]
        if char == "%":
            pair = path[index + 1 : index + 3]
            if len(pair) != 2 or not all(c in _HEX for c in pair):
                raise _fail("Illegal percent encoding in URI")
            octets.append(int(pair, 16))
            index += 3
        else:
            octets.extend(char.encode("utf-8", "surrogatepass"))
            index += 1
    try:
        return octets.decode("utf-8")
    except UnicodeDecodeError:
        raise _fail("Invalid UTF-8") from None


# --- the page readings --------------------------------------------------------


@dataclass(frozen=True)
class PageLink:
    """One ``<a href>``: where it points (resolved against the page's own
    URL) and the text a reader sees on it, whitespace collapsed."""

    uri: DartUri
    text: str


_FLAGS: Final = re.IGNORECASE | re.ASCII
_COMMENT: Final = re.compile("<!--.*?-->", re.DOTALL)
_INVISIBLE: Final = re.compile(
    rf"<(script|style|noscript|template|svg|head|nav|footer)\b[^>]*>.*?</\1{WS}*>",
    _FLAGS | re.DOTALL,
)
_SCRIPTS_ONLY: Final = re.compile(
    rf"<(script|style|noscript|template|svg)\b[^>]*>.*?</\1{WS}*>",
    _FLAGS | re.DOTALL,
)
_NOSCRIPT: Final = re.compile(
    rf"<noscript\b[^>]*>(.*?)</noscript{WS}*>", _FLAGS | re.DOTALL
)
_BLOCK_TAG: Final = re.compile(
    "</?(p|div|li|ul|ol|h[1-6]|tr|table|tbody|thead|section|article|main|"
    "header|aside|br|dd|dt|dl|figure|figcaption|blockquote|pre|hr|form|"
    r"option|label|button)\b[^>]*>",
    _FLAGS,
)
_CELL_TAG: Final = re.compile(r"</?(td|th)\b[^>]*>", _FLAGS)
_TAG: Final = re.compile("<[^>]+>")
_SPACES: Final = re.compile("[ \t\f\v ‎‏]+")
_LINE_BREAK: Final = re.compile(r"\r\n|\r|\n")
_WHITESPACE: Final = re.compile(f"{WS}+")
_ANCHOR: Final = re.compile(r"<a\b([^>]*)>(.*?)</a" + f"{WS}*>", _FLAGS | re.DOTALL)
_META: Final = re.compile(r"<meta\b[^>]*>", _FLAGS)
_ATTRIBUTE: Final = re.compile(
    rf"""([a-zA-Z:-]+){WS}*={WS}*(?:"([^"]*)"|'([^']*)'|({NOT_WS[:-1]}>]+))"""
)
_JSON_LD: Final = re.compile(
    r"""<script\b[^>]*type"""
    + WS
    + r"""*="""
    + WS
    + r"""*["']?application/ld\+json["']?[^>]*>(.*?)</script"""
    + WS
    + "*>",
    _FLAGS | re.DOTALL,
)
_ENTITY: Final = re.compile("&(#x[0-9a-fA-F]+|#[0-9]+|[a-zA-Z]+);")

_NAMED_ENTITIES: Final = {
    "amp": "&",
    "lt": "<",
    "gt": ">",
    "quot": '"',
    "apos": "'",
    "nbsp": " ",
    "ndash": "–",
    "mdash": "—",
    "hellip": "…",
    "rsquo": "’",
    "lsquo": "‘",
    "rdquo": "”",
    "ldquo": "“",
    "bull": "•",
    "middot": "·",
    "shekel": "₪",
}


def _lower(text: str) -> str:
    """Dart ``toLowerCase`` (one-to-one), fast for the common ASCII page."""
    return text.lower() if text.isascii() else dart_lower(text)


def decode_entities(text: str) -> str:
    """``text`` with HTML character references decoded; an unknown named
    reference is left as written, an out-of-range numeric one is a space."""

    def replace(match: re.Match[str]) -> str:
        body = match.group(1)
        if body.startswith("#"):
            hexadecimal = body.startswith("#x")
            try:
                code = int(
                    body[2:] if hexadecimal else body[1:], 16 if hexadecimal else 10
                )
            except ValueError:  # more digits than Python's int limit
                return " "
            if code <= 0 or code > 0x10FFFF:
                return " "
            return chr(code)
        return _NAMED_ENTITIES.get(body.lower(), match.group(0))

    return join_surrogates(_ENTITY.sub(replace, text))


def lines(html: str) -> list[str]:
    """The page's visible text as trimmed, non-blank lines in reading order.

    Drops comments, ``<head>``, scripts, styles, templates, SVG, ``<nav>``
    and ``<footer>``; starts a new line at every block element and joins
    table cells with a space, so a row reads ``Dish 52`` as one line.
    """
    without_hidden = _INVISIBLE.sub("\n", _COMMENT.sub(" ", html))
    broken = _TAG.sub(" ", _CELL_TAG.sub(" ", _BLOCK_TAG.sub("\n", without_hidden)))
    found = (
        dart_trim(_SPACES.sub(" ", raw))
        for raw in _LINE_BREAK.split(decode_entities(broken))
    )
    return [line for line in found if line]


def is_javascript_only(html: str) -> bool:
    """Whether the page renders its content only with JavaScript: almost no
    visible text beside an executable script, or a ``<noscript>`` asking for
    JavaScript with little text left. A JSON-LD block is data, so it never
    counts."""
    website = vocabulary().website
    without_hidden = _SCRIPTS_ONLY.sub(" ", _COMMENT.sub(" ", html))
    text = dart_trim(
        _WHITESPACE.sub(" ", decode_entities(_TAG.sub(" ", without_hidden)))
    )
    code = _lower(_JSON_LD.sub(" ", html))
    if "<script" in code and utf16_len(text) < website.js_only_text_chars:
        return True
    for match in _NOSCRIPT.finditer(html):
        if "javascript" in _lower(match.group(1)):
            return utf16_len(text) < website.js_only_noscript_text_chars
    return False


def _attributes_of(tag: str) -> dict[str, str]:
    attributes: dict[str, str] = {}
    for match in _ATTRIBUTE.finditer(tag):
        value = next((g for g in match.group(2, 3, 4) if g is not None), "")
        attributes[match.group(1).lower()] = value
    return attributes


def reserves_ai(html: str) -> bool:
    """Whether the page opts out of AI use in its own ``<meta>`` tags:
    ``robots`` (or ``ketoclubbot``) with ``noai``, or ``tdm-reservation`` = 1.
    """
    for match in _META.finditer(html):
        attributes = _attributes_of(match.group(0))
        name = _lower(dart_trim(attributes.get("name", "")))
        content = _lower(dart_trim(attributes.get("content", "")))
        if name in ("robots", "ketoclubbot") and "noai" in [
            dart_trim(part) for part in content.split(",")
        ]:
            return True
        if name == "tdm-reservation" and content == "1":
            return True
    return False


def _reject_constant(name: str) -> Any:
    raise ValueError(name)


def _try_decode(source: str) -> Any:
    """Dart ``jsonDecode(source.trim())``, or ``None`` when it throws."""
    try:
        return json.loads(dart_trim(source), parse_constant=_reject_constant)
    except (ValueError, RecursionError):
        return None


def json_ld_blocks(html: str) -> list[Any]:
    """Every JSON-LD block on the page, decoded; a block that is not valid
    JSON (or is the JSON ``null``) is skipped."""
    decoded = (_try_decode(match.group(1)) for match in _JSON_LD.finditer(html))
    return [block for block in decoded if block is not None]


def links(html: str, base: DartUri) -> list[PageLink]:
    """Every ``http``/``https`` link on the page, resolved against ``base``,
    in page order. Fragment-only and ``javascript:``/``mailto:``/``tel:``
    links are dropped."""
    found: list[PageLink] = []
    for match in _ANCHOR.finditer(html):
        href = _attributes_of(f"<a {match.group(1)}>").get("href")
        if href is None or not dart_trim(href) or href.startswith("#"):
            continue
        try:
            target = base.resolve(decode_entities(dart_trim(href))).remove_fragment()
        except UriFormatError:
            continue
        if target.scheme not in ("http", "https"):
            continue
        text = dart_trim(
            _WHITESPACE.sub(" ", decode_entities(_TAG.sub(" ", match.group(2))))
        )
        found.append(PageLink(uri=target, text=text))
    return found

"""Crawl hygiene for ``POST /v1/website/fetch`` (architecture.md D19, #181).

Pure helpers the route composes: ``robots.txt`` parsing and matching
(RFC 9309, the subset restaurant sites use), the ``noai`` / TDM-reservation
opt-out signals, the JavaScript-only page test, content sniffing and the
public-address check that keeps the route from fetching anything on a private
network. None of them performs I/O; the route owns the HTTP calls.

The menu *locator* (JSON-LD, ``/menu`` / ``תפריט`` / ``.pdf`` links, the page
itself) is deliberately not here: it runs in the app on every platform
(``lib/services/menu/website/``), so phones, which fetch sites directly
(D17), and the web build, which fetches through this route, read a page the
same way. This module only decides whether a page may be fetched at all and
what kind of document came back.
"""

import html
import ipaddress
import re
from dataclasses import dataclass, field
from typing import Final, Literal
from urllib.parse import urlsplit

from app.website.linear import PairedTags, find_tags, sub_comments, sub_tags

# The product token KetoClub's fetcher answers to in robots.txt, matched
# case-insensitively against each ``User-agent`` line (RFC 9309 §2.2.1).
ROBOTS_TOKEN: Final = "ketoclubbot"

# How much visible text a page may have and still be judged JavaScript-only
# when it also carries a script: an app shell has next to none. The app
# applies the same bounds (``WebsiteHtml`` in lib/services/menu/website/).
JS_ONLY_TEXT_CHARS: Final = 50

# The same bound when the page's own <noscript> asks for JavaScript.
JS_ONLY_NOSCRIPT_TEXT_CHARS: Final = 200

DocumentKind = Literal["html", "pdf"]

_EMBEDDED_IPV4_NETWORKS: Final = (
    ipaddress.IPv6Network("64:ff9b::/96"),  # NAT64, RFC 6052
    ipaddress.IPv6Network("64:ff9b:1::/48"),  # local-use NAT64, RFC 8215
    ipaddress.IPv6Network("::/96"),  # IPv4-compatible, RFC 4291 §2.5.5.1
)

# ``<!--.*?-->``, ``<(script|style|noscript|template|svg)\b[^>]*>.*?</\1\s*>``
# and ``<noscript\b[^>]*>(.*?)</noscript\s*>``, run in linear time with the
# regexes' exact results by ``app.website.linear`` (#268): as regexes they
# rescan the rest of the page at every unclosed tag.
_INVISIBLE = PairedTags(
    "script|style|noscript|template|svg",
    space=r"\s",
    flags=re.IGNORECASE,
    same_name=True,
)
_NOSCRIPT = PairedTags("noscript", space=r"\s", flags=re.IGNORECASE, same_name=False)
_TAG = re.compile(r"<[^>]+>")
_HUGE_DECIMAL_REFERENCE = re.compile(r"&#0*+[0-9]{8,};?")
_WHITESPACE = re.compile(r"\s+")
_META = re.compile(r"<meta\b[^>]*>", re.IGNORECASE)
_ATTRIBUTE = re.compile(
    r"""([a-zA-Z-]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))""", re.IGNORECASE
)


@dataclass(frozen=True)
class _Rule:
    allow: bool
    pattern: str


@dataclass
class RobotsRules:
    """The ``Allow`` / ``Disallow`` rules that apply to KetoClub on one host.

    ``allow_all`` marks a host with no usable robots.txt (a 4xx, or no group
    for KetoClub or ``*``), which RFC 9309 §2.3.1.3 reads as "no rules".
    """

    rules: list[_Rule] = field(default_factory=list)

    def allows(self, path: str) -> bool:
        """Whether ``path`` (path plus query) may be fetched.

        The longest matching pattern wins and a tie goes to ``Allow``
        (RFC 9309 §2.2.2); ``/robots.txt`` itself is always allowed.
        """
        if not path:
            path = "/"
        if path == "/robots.txt":
            return True
        best: _Rule | None = None
        for rule in self.rules:
            if not _matches(rule.pattern, path):
                continue
            if best is None or len(rule.pattern) > len(best.pattern):
                best = rule
            elif len(rule.pattern) == len(best.pattern) and rule.allow:
                best = rule
        return best is None or best.allow


def parse_robots(text: str) -> RobotsRules:
    """Parse ``text`` into the rules for ``ROBOTS_TOKEN``, else for ``*``.

    Consecutive ``User-agent`` lines open one group; every group naming
    KetoClub is merged, and only when none does are the ``*`` groups used
    (RFC 9309 §2.2.1). Unknown keys (``Sitemap``, ``Crawl-delay``) and lines
    without a colon are ignored.
    """
    ours: list[_Rule] = []
    anyone: list[_Rule] = []
    names_ours = False
    agents: list[str] = []
    in_rules = False
    found_ours = False

    for raw in text.splitlines():
        line = raw.split("#", 1)[0].strip()
        if ":" not in line:
            continue
        key, value = (part.strip() for part in line.split(":", 1))
        key = key.lower()
        if key == "user-agent":
            if in_rules:
                agents = []
                in_rules = False
            agents.append(value.lower())
            names_ours = any(ROBOTS_TOKEN in agent for agent in agents)
            found_ours = found_ours or names_ours
            continue
        if key not in ("allow", "disallow") or not agents:
            continue
        in_rules = True
        if not value:
            continue  # An empty Disallow allows everything: no rule.
        rule = _Rule(allow=key == "allow", pattern=value)
        if names_ours:
            ours.append(rule)
        elif "*" in agents:
            anyone.append(rule)

    return RobotsRules(rules=ours if found_ours else anyone)


def _matches(pattern: str, path: str) -> bool:
    """Whether a robots ``pattern`` (``*`` wildcards, ``$`` end) matches.

    The pattern matches from the start of ``path``; without a trailing ``$``
    it need only match a prefix. Every other character is literal. Matched
    without a regex (#268): ``*`` as an unbounded ``.*`` backtracks
    exponentially in the number of stars, so a hostile robots.txt could
    stall the server. Each literal piece between stars is found at its
    leftmost place after the previous one, which is the same answer: a
    leftmost place leaves the most path for every piece after it.
    """
    anchored = pattern.endswith("$")
    pieces = (pattern[:-1] if anchored else pattern).split("*")
    head, *rest = pieces
    if not path.startswith(head):
        return False
    if not rest:
        return path == head if anchored else True
    *middle, tail = rest
    position = len(head)
    for piece in middle:
        found = path.find(piece, position)
        if found == -1:
            return False
        position = found + len(piece)
    if anchored:
        return len(path) - len(tail) >= position and path.endswith(tail)
    return path.find(tail, position) != -1


def path_of(url: str) -> str:
    """The path and query of ``url``, the part robots.txt rules match."""
    parts = urlsplit(url)
    path = parts.path or "/"
    return f"{path}?{parts.query}" if parts.query else path


def is_public_address(address: str) -> bool:
    """Whether ``address`` is a globally routable IP address.

    Loopback, private, link-local, multicast, reserved and unspecified
    addresses are all refused, so a pasted URL cannot make this server
    fetch something on its own network. An IPv4-mapped IPv6 address is
    judged by the IPv4 address it maps; NAT64 and IPv4-compatible ones are
    refused outright.
    """
    try:
        ip = ipaddress.ip_address(address)
    except ValueError:
        return False
    if isinstance(ip, ipaddress.IPv6Address):
        if ip.ipv4_mapped is not None:
            return is_public_address(str(ip.ipv4_mapped))
        # IPv4 behind an IPv6 form that Python calls global (#267): NAT64
        # (64:ff9b::a00:1 reaches 10.0.0.1 through a NAT64 gateway) and the
        # deprecated IPv4-compatible ::a.b.c.d, refused whatever they embed.
        if any(ip in network for network in _EMBEDDED_IPV4_NETWORKS):
            return False
    return ip.is_global and not ip.is_multicast


def header_reserves_ai(headers: dict[str, str]) -> bool:
    """Whether response ``headers`` opt out of AI use of the page.

    ``X-Robots-Tag: noai`` (the de-facto directive) or ``tdm-reservation: 1``
    (the W3C TDMRep header). Keys are expected lower-cased.
    """
    robots_tag = headers.get("x-robots-tag", "").lower()
    if "noai" in _directives(robots_tag):
        return True
    return headers.get("tdm-reservation", "").strip() == "1"


def html_reserves_ai(page: str) -> bool:
    """Whether ``page`` opts out of AI use in its own ``<meta>`` tags.

    ``<meta name="robots" content="noai">`` (or a ``name`` naming KetoClub)
    and ``<meta name="tdm-reservation" content="1">``.
    """
    for meta in find_tags(_META, page):
        attributes = {
            match.group(1).lower(): (
                match.group(2) or match.group(3) or match.group(4) or ""
            )
            for match in _ATTRIBUTE.finditer(meta.group(0))
        }
        name = attributes.get("name", "").strip().lower()
        content = attributes.get("content", "").strip().lower()
        if name in ("robots", ROBOTS_TOKEN) and "noai" in _directives(content):
            return True
        if name == "tdm-reservation" and content == "1":
            return True
    return False


def _directives(value: str) -> set[str]:
    return {part.strip() for part in value.split(",") if part.strip()}


def visible_text(page: str) -> str:
    """The text a reader would see in ``page``, whitespace collapsed."""
    without = _INVISIBLE.sub(" ", sub_comments(" ", page))
    return _WHITESPACE.sub(" ", _unescape(sub_tags(_TAG, " ", without))).strip()


def _unescape(text: str) -> str:
    """``html.unescape``, which raises ``ValueError`` on a decimal reference
    longer than Python's integer-string limit; any reference of eight or
    more significant digits is past U+10FFFF, which ``html.unescape`` reads
    as U+FFFD anyway."""
    return html.unescape(_HUGE_DECIMAL_REFERENCE.sub("\ufffd", text))


def looks_javascript_only(page: str) -> bool:
    """Whether ``page`` renders its content only with JavaScript.

    True when almost no text survives once scripts, styles and templates are
    removed and the page carries a script, or when its ``<noscript>`` asks
    for JavaScript and little text is left. Such a page is out of scope for
    #181 (no headless browser), so it fails with its own reason rather than
    being read as a page with no menu. A page carrying JSON-LD is never
    judged here: that markup is readable data however the page renders, and
    the app reads it before applying the same test itself.
    """
    lowered = page.lower()
    if "application/ld+json" in lowered:
        return False
    text_length = len(visible_text(page))
    if "<script" in lowered and text_length < JS_ONLY_TEXT_CHARS:
        return True
    for block in _NOSCRIPT.finditer(page):
        if "javascript" in page[block.content_start : block.content_end].lower():
            return text_length < JS_ONLY_NOSCRIPT_TEXT_CHARS
    return False


def document_kind(content_type: str, head: bytes) -> DocumentKind | None:
    """What a response is: ``html``, ``pdf``, or None for anything else.

    A PDF is recognised by its media type or by its ``%PDF-`` signature
    (servers often send PDFs as ``application/octet-stream``).
    """
    media = content_type.split(";", 1)[0].strip().lower()
    if media == "application/pdf" or head.startswith(b"%PDF-"):
        return "pdf"
    if media in ("text/html", "application/xhtml+xml"):
        return "html"
    return None


def charset_of(content_type: str) -> str:
    """The ``charset`` parameter of ``content_type``, defaulting to UTF-8."""
    for parameter in content_type.split(";")[1:]:
        key, _, value = parameter.partition("=")
        if key.strip().lower() == "charset" and value.strip():
            return value.strip().strip('"').lower()
    return "utf-8"


def decode_page(content: bytes, content_type: str) -> str:
    """``content`` decoded by its declared charset, never raising.

    A charset Python does not know (``LookupError``) or one that cannot decode
    the bytes (``ValueError``, which covers ``UnicodeDecodeError``) falls back
    to UTF-8 with replacement characters, so a mislabelled page still reads.
    """
    try:
        return content.decode(charset_of(content_type), errors="replace")
    except (LookupError, ValueError):
        return content.decode("utf-8", errors="replace")

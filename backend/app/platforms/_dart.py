"""Dart runtime behaviours the platform mappers must reproduce (D25, #323).

Private to ``app.platforms``. Each helper names the Dart construct it stands
in for; Python's own spelling differs from Dart's in every one of them.
"""

import math
from typing import TypeGuard

_DART_WHITESPACE = frozenset(
    "\t\n\v\f\r \u0085      　﻿" + "".join(chr(c) for c in range(0x2000, 0x200B))
)
"""What Dart's ``String.trim`` strips: Unicode White_Space plus U+FEFF, and
not U+001C-U+001F, which Python's ``str.strip`` strips."""


def is_blank(value: str) -> bool:
    """Dart ``value.trim().isEmpty``."""
    return all(char in _DART_WHITESPACE for char in value)


def is_num(value: object) -> TypeGuard[int | float]:
    """Dart ``value is num``: an int or a double, never a bool."""
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def is_finite(value: int | float) -> bool:
    """Dart ``num.isFinite``."""
    return not isinstance(value, float) or math.isfinite(value)


def dart_round(value: int | float) -> int:
    """Dart ``num.round()``: halves round away from zero (Python rounds to
    even). ``value`` must be finite."""
    if isinstance(value, int):
        return value
    magnitude = abs(value)
    whole = math.floor(magnitude)
    if magnitude - whole >= 0.5:
        whole += 1
    return -whole if value < 0 else whole


def dart_num_to_string(value: int | float) -> str:
    """Dart VM ``num.toString()``: ``12`` is ``"12"``, ``12.0`` is
    ``"12.0"``, and a double switches to an exponent below ``1e-6`` and from
    ``1e21`` up (Python's ``repr`` does so below ``1e-4`` and from ``1e16``).
    """
    if isinstance(value, int):
        return str(value)
    if math.isnan(value):
        return "NaN"
    if math.isinf(value):
        return "Infinity" if value > 0 else "-Infinity"
    if value == 0:
        return "-0.0" if math.copysign(1.0, value) < 0 else "0.0"
    sign = "-" if value < 0 else ""
    digits, point = _shortest_digits(abs(value))
    # The value is 0.<digits> * 10**point, so its decimal exponent is point-1.
    exp10 = point - 1
    if -6 <= exp10 < 21:
        if point <= 0:
            return f"{sign}0.{'0' * -point}{digits}"
        if point >= len(digits):
            return f"{sign}{digits}{'0' * (point - len(digits))}.0"
        return f"{sign}{digits[:point]}.{digits[point:]}"
    scientific = digits[0] + ("." + digits[1:] if len(digits) > 1 else "")
    return f"{sign}{scientific}e{'+' if exp10 >= 0 else '-'}{abs(exp10)}"


def _shortest_digits(value: float) -> tuple[str, int]:
    """``(digits, point)`` with ``value == 0.<digits> * 10**point`` using the
    shortest round-tripping digits, which ``repr`` produces."""
    text = repr(value)
    mantissa, _, exp_text = text.partition("e")
    exp10 = int(exp_text) if exp_text else 0
    whole, _, fraction = mantissa.partition(".")
    digits = whole + fraction
    point = len(whole) + exp10
    stripped = digits.lstrip("0")
    point -= len(digits) - len(stripped)
    digits = stripped.rstrip("0") or "0"
    return digits, point


def dart_string_hash(value: str) -> int:
    """Dart VM ``String.hashCode``: one-at-a-time over the UTF-16 code units,
    finalised to 30 bits.

    Unverified against a Dart VM (no golden covers it); only the 10bis
    category-id fallback for a name with no letter or digit uses it.
    """
    data = value.encode("utf-16-le", "surrogatepass")
    units = [int.from_bytes(data[i : i + 2], "little") for i in range(0, len(data), 2)]
    mask = 0xFFFFFFFF
    hash_ = 0
    for unit in units:
        hash_ = (hash_ + unit) & mask
        hash_ = (hash_ + (hash_ << 10)) & mask
        hash_ ^= hash_ >> 6
    hash_ = (hash_ + (hash_ << 3)) & mask
    hash_ ^= hash_ >> 11
    hash_ = (hash_ + (hash_ << 15)) & mask
    hash_ &= (1 << 30) - 1
    return hash_ or 1


_UNRESERVED = frozenset(
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
)
_PATH_CHARS = _UNRESERVED | frozenset("!$&'()*+,;=:@/")
_HEX = frozenset("0123456789abcdefABCDEF")


def dart_https_url(host: str, path: str) -> str:
    """``Uri.https(host, path).toString()`` for an absolute ``path``.

    Escapes a path as Dart does: characters outside unreserved, sub-delims,
    ``:``, ``@`` and ``/`` become uppercase UTF-8 ``%XX``; a valid existing
    escape is kept uppercased (decoded when it names an unreserved
    character); a stray ``%`` becomes ``%25``; dot segments are removed.
    """
    out: list[str] = []
    index = 0
    while index < len(path):
        char = path[index]
        if char == "%":
            pair = path[index + 1 : index + 3]
            if len(pair) == 2 and all(c in _HEX for c in pair):
                decoded = chr(int(pair, 16))
                out.append(decoded if decoded in _UNRESERVED else "%" + pair.upper())
                index += 3
            else:
                out.append("%25")
                index += 1
        elif char in _PATH_CHARS:
            out.append(char)
            index += 1
        else:
            if "\ud800" <= char <= "\udfff":
                char = "�"
            out.extend(f"%{byte:02X}" for byte in char.encode("utf-8"))
            index += 1
    return f"https://{host}{_remove_dot_segments(''.join(out))}"


def _remove_dot_segments(path: str) -> str:
    """RFC 3986 section 5.2.4 for an absolute path."""
    if "." not in path:
        return path
    segments = path.split("/")
    kept: list[str] = []
    for position, segment in enumerate(segments):
        last = position == len(segments) - 1
        if segment == ".":
            if last:
                kept.append("")
        elif segment == "..":
            if len(kept) > 1:
                kept.pop()
            if last:
                kept.append("")
        else:
            kept.append(segment)
    return "/".join(kept)

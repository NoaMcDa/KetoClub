"""The menu fingerprint: a stable hash of a menu's dish text.

The Python twin of ``TextNormaliser.menuFingerprint`` in
``lib/utils/text_normaliser.dart`` (architecture.md §6.4, D23, D25): a 32-bit
FNV-1a over the **UTF-16 code units** of every dish's
:func:`~app.keto.normaliser.dish_search_text`, in menu order, each followed by
a NUL. A scan or a paste is addressed by it (``scan/<8 hex digits>``), so the
same dishes are one entry on every platform.
"""

from typing import Final

from app.keto.dart_text import utf16_units
from app.keto.models import Menu, VenueRef
from app.keto.normaliser import dish_search_text

_FNV_OFFSET_BASIS: Final = 2166136261
_FNV_PRIME: Final = 16777619
_MASK: Final = 0xFFFFFFFF
_DISH_BOUNDARY: Final = "\u0000"


def fnv1a32(text: str) -> int:
    """32-bit FNV-1a over ``text``'s UTF-16 code units (Dart ``_fnv1a32``)."""
    value = _FNV_OFFSET_BASIS
    for unit in utf16_units(text):
        value = ((value ^ unit) * _FNV_PRIME) & _MASK
    return value


def menu_fingerprint(menu: Menu) -> int:
    """``TextNormaliser.menuFingerprint``: an unsigned 32-bit hash of
    ``menu``'s dish text, order-sensitive."""
    return fnv1a32(
        "".join(dish_search_text(dish) + _DISH_BOUNDARY for dish in menu.all_dishes())
    )


def fingerprint_hex(menu: Menu) -> str:
    """:func:`menu_fingerprint` as 8 lowercase hex digits, zero-padded: the
    form a scan's ``VenueRef.platformId`` carries."""
    return f"{menu_fingerprint(menu):08x}"


def scan_ref(menu: Menu) -> VenueRef:
    """The ``VenueRef`` a scanned or pasted ``menu`` is addressed by:
    ``scan/<fingerprint_hex>`` (D18, D23)."""
    return VenueRef(source="scan", platform_id=fingerprint_hex(menu))

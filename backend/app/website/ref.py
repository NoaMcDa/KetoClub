"""The ``VenueRef`` a restaurant website is addressed by (D19; #334).

The Python twin of ``VenueRefResolver.normaliseWebsiteUrl``
(``lib/services/venue/venue_ref_resolver.dart``): ``website/<normalised
url>``, so the menu ``POST /v1/website-menu`` returns and the row it writes
to ``stored_menus`` are keyed exactly as the app keys the same paste.

Normalising lower-cases the scheme and host (``DartUri.parse`` does), drops
the fragment, a default port, one trailing ``/`` and every tracking
parameter (``utm_*``, ``fbclid``, ``gclid``, ...; #280), and keeps the path
and the rest of the query as given; a query only tracking parameters held is
dropped. A URL that is not ``http``/``https``, has user info, or whose
host has no inner dot or is not public by name (``*.local``,
``*.localhost``, a private IPv4 literal) has no ref. The route still checks
every address the host resolves to before it fetches anything.
"""

import ipaddress
import re
from typing import Final

from app.keto.models import VenueRef
from app.website.html import DartUri, UriFormatError

_NUMERIC_LABEL: Final = re.compile(r"(?:[0-9]+|0x[0-9a-f]*)")
_OCTET: Final = re.compile(r"0|[1-9][0-9]{0,2}")

#: Dart ``VenueRefResolver._trackingParameters``: lower-cased query parameter
#: names that only say where a link was shared from (#280). A name starting
#: with ``utm_`` is one too.
TRACKING_PARAMETERS: Final = frozenset(
    {
        "_ga",
        "_gl",
        "dclid",
        "fbclid",
        "gad_source",
        "gbraid",
        "gclid",
        "gclsrc",
        "igsh",
        "igshid",
        "li_fat_id",
        "mc_cid",
        "mc_eid",
        "mkt_tok",
        "msclkid",
        "srsltid",
        "ttclid",
        "twclid",
        "wbraid",
        "yclid",
    }
)


def is_tracking_query_parameter(name: str) -> bool:
    """Dart ``VenueRefResolver.isTrackingQueryParameter``: ``utm_*`` or one of
    :data:`TRACKING_PARAMETERS`, ignoring (ASCII) case."""
    lower = name.lower()
    return lower.startswith("utm_") or lower in TRACKING_PARAMETERS


def _without_tracking(query: str | None) -> str | None:
    """Dart ``VenueRefResolver._withoutTracking``: ``query`` without its
    tracking parameters; ``None`` when they were all it held, or it was empty
    or absent (Dart writes no bare ``?``)."""
    if not query:
        return None
    kept = [
        pair
        for pair in query.split("&")
        if not is_tracking_query_parameter(pair.split("=", 1)[0])
    ]
    return "&".join(kept) if kept else None


def normalise_website_url(raw: str) -> str | None:
    """``raw`` in the form a website ref stores it, or ``None`` when it is
    not a public ``http``/``https`` web address."""
    try:
        uri = DartUri.parse(raw.strip())
    except UriFormatError:
        return None
    scheme = uri.scheme.lower()
    if scheme not in ("http", "https") or uri.user_info:
        return None
    host = (uri.host or "").lower()
    if "." not in host or host.startswith(".") or host.endswith("."):
        return None
    if not _is_public_name(host):
        return None
    path = uri.path[:-1] if uri.path.endswith("/") else uri.path
    return DartUri(
        scheme=scheme,
        host=host,
        port=uri.port,
        path=path,
        query=_without_tracking(uri.query),
    ).to_string()


def website_ref(raw: str) -> VenueRef | None:
    """``website/<normalised raw>``, or ``None`` (see
    :func:`normalise_website_url`)."""
    normalised = normalise_website_url(raw)
    if normalised is None:
        return None
    return VenueRef(source="website", platform_id=normalised)


def _is_public_name(host: str) -> bool:
    """Dart ``isPublicHost`` for a host with a dot: no ``.local`` or
    ``.localhost`` name, and an IPv4 literal only when it is public."""
    if host.endswith(".localhost") or host.endswith(".local"):
        return False
    last = host.rsplit(".", 1)[-1]
    if not _NUMERIC_LABEL.fullmatch(last):
        return True
    parts = host.split(".")
    if len(parts) != 4 or not all(_OCTET.fullmatch(part) for part in parts):
        return False
    if any(int(part) > 255 for part in parts):
        return False
    address = ipaddress.ip_address(host)
    return address.is_global and not address.is_multicast

"""The ``VenueRef`` a restaurant website is addressed by (D19; #334).

The Python twin of ``VenueRefResolver.normaliseWebsiteUrl``
(``lib/services/venue/venue_ref_resolver.dart``): ``website/<normalised
url>``, so the menu ``POST /v1/website-menu`` returns and the row it writes
to ``stored_menus`` are keyed exactly as the app keys the same paste.

Normalising lower-cases the scheme and host (``DartUri.parse`` does), drops
the fragment, a default port and one trailing ``/``, and keeps the path and
query as given. A URL that is not ``http``/``https``, has user info, or whose
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
        scheme=scheme, host=host, port=uri.port, path=path, query=uri.query
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

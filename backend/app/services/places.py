"""A typed street turned into coordinates, through Photon (#449).

Photon (https://photon.komoot.io) is an OpenStreetMap geocoder that needs no
key. The backend calls it so the provider sees this server rather than the
user's device. This module holds the upstream request and the pure mapping
from Photon's GeoJSON to ``Place`` rows; the Flutter app's direct fallback
implements the same mapping, so the rules here are exact:

- a feature is kept only when ``properties.countrycode`` is ``IL`` (any
  case), ``properties.type`` is ``house`` or ``street``, and
  ``geometry.coordinates`` is ``[longitude, latitude]`` with two finite
  numbers;
- the street is ``properties.street`` for a house and ``properties.name``
  for a street (a blank one drops the feature); the house number is
  ``properties.housenumber`` when non-blank, for a house only;
- the city is ``properties.city``, else ``properties.district``, else null;
- the label is ``"<street> <housenumber>, <city>"`` with the missing parts
  left out; labels are deduplicated keeping Photon's first, and at most
  ``MAX_PLACES`` are returned.

Privacy: the query, the labels and the coordinates are never logged and
never stored. httpx logs every request's URL, and Photon's URL carries the
query, so ``redact_geocoder_queries`` installs a filter that strips the
query string from httpx's line for the geocoder's host.
"""

import logging
import math
from dataclasses import dataclass
from typing import Any, Final, Literal

import httpx

# Photon's own reply is cut at this many features; the answer at MAX_PLACES.
# Asking for more than is returned leaves room for the non-Israeli, unnamed
# and duplicate features the mapping drops.
UPSTREAM_LIMIT: Final = 15
MAX_PLACES: Final = 6

# Israel, as minLon,minLat,maxLon,maxLat (Photon's bbox order).
ISRAEL_BBOX: Final = "34.2,29.4,35.9,33.4"

GEOCODER_TIMEOUT: Final = httpx.Timeout(10.0)

PlaceLanguage = Literal["he", "en"]

_KEPT_TYPES: Final = frozenset({"house", "street"})


@dataclass(frozen=True)
class MappedPlace:
    """One geocoded street or address, in the route's reply shape."""

    label: str
    city: str | None
    latitude: float
    longitude: float


def geocoder_url(base_url: str) -> str:
    """Photon's search endpoint under ``base_url``."""
    return f"{base_url.rstrip('/')}/api/"


def geocoder_params(query: str, language: PlaceLanguage) -> httpx.QueryParams:
    """The upstream query string, ``layer`` repeated.

    Photon accepts ``default``, ``de``, ``en`` and ``fr`` and refuses ``he``
    (400); ``default`` answers the local names, which in Israel are mostly
    Hebrew.
    """
    return httpx.QueryParams(
        [
            ("q", query),
            ("limit", str(UPSTREAM_LIMIT)),
            ("lang", "en" if language == "en" else "default"),
            ("bbox", ISRAEL_BBOX),
            ("layer", "house"),
            ("layer", "street"),
        ]
    )


def map_photon_places(body: Any) -> list[MappedPlace] | None:
    """The places in Photon's reply ``body``, or None when it is not the
    expected shape (not an object, or no ``features`` list).

    A feature that is not usable is skipped, never a reason to refuse the
    whole reply: Photon's results mix every kind of OSM object.
    """
    if not isinstance(body, dict):
        return None
    features = body.get("features")
    if not isinstance(features, list):
        return None

    places: list[MappedPlace] = []
    seen: set[str] = set()
    for feature in features:
        place = _map_feature(feature)
        if place is None or place.label in seen:
            continue
        seen.add(place.label)
        places.append(place)
        if len(places) == MAX_PLACES:
            break
    return places


def _map_feature(feature: Any) -> MappedPlace | None:
    if not isinstance(feature, dict):
        return None
    properties = feature.get("properties")
    geometry = feature.get("geometry")
    if not isinstance(properties, dict) or not isinstance(geometry, dict):
        return None

    country = properties.get("countrycode")
    if not isinstance(country, str) or country.upper() != "IL":
        return None
    kind = properties.get("type")
    if kind not in _KEPT_TYPES:
        return None
    position = _coordinates(geometry.get("coordinates"))
    if position is None:
        return None
    longitude, latitude = position

    if kind == "house":
        street = _text(properties.get("street"))
        number = _text(properties.get("housenumber"))
    else:
        street = _text(properties.get("name"))
        number = None
    if street is None:
        return None
    city = _text(properties.get("city")) or _text(properties.get("district"))

    label = street if number is None else f"{street} {number}"
    if city is not None:
        label = f"{label}, {city}"
    return MappedPlace(
        label=label.strip(), city=city, latitude=latitude, longitude=longitude
    )


def _text(value: Any) -> str | None:
    """``value`` trimmed, or None when it is not a non-blank string."""
    if not isinstance(value, str):
        return None
    trimmed = value.strip()
    return trimmed or None


def _coordinates(value: Any) -> tuple[float, float] | None:
    """``[longitude, latitude]`` as two finite floats, or None."""
    if not isinstance(value, list) or len(value) != 2:
        return None
    numbers: list[float] = []
    for item in value:
        # bool is an int subclass; a true/false coordinate is not a number.
        if isinstance(item, bool) or not isinstance(item, int | float):
            return None
        number = float(item)
        if not math.isfinite(number):
            return None
        numbers.append(number)
    return numbers[0], numbers[1]


class _GeocoderQueryRedactor(logging.Filter):
    """Strips the query string from httpx's request line for the hosts it
    holds, so the typed street never reaches a log record."""

    def __init__(self) -> None:
        super().__init__()
        self.hosts: set[str] = set()

    def filter(self, record: logging.LogRecord) -> bool:
        if isinstance(record.args, tuple) and self.hosts:
            record.args = tuple(self._redact(arg) for arg in record.args)
        return True

    def _redact(self, arg: object) -> object:
        if isinstance(arg, httpx.URL) and arg.host in self.hosts and arg.query:
            return arg.copy_with(query=None)
        return arg


_REDACTOR: Final = _GeocoderQueryRedactor()
logging.getLogger("httpx").addFilter(_REDACTOR)


def redact_geocoder_queries(base_url: str) -> None:
    """Keep the query string of every request to ``base_url``'s host out of
    httpx's log line. Idempotent; called once per app."""
    host = httpx.URL(base_url).host
    if host:
        _REDACTOR.hosts.add(host)

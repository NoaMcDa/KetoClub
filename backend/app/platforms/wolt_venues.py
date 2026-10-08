"""Wolt discovery page to ``Venue`` list (D25, #323).

Python twin of Dart ``WoltVenueMapper`` (``lib/services/venue/wolt/
wolt_venue_mapper.dart``), whose doc comment holds the rules. Pure and never
raising. Every ``sections[].items[]`` entry is walked in order; one without a
``venue`` object, or whose venue lacks a non-blank ``slug`` or ``name``, is
skipped; the first occurrence of a slug wins. Only a body with no
``sections`` list answers ``None``.
"""

from typing import Any

from app.keto.models import MenuSourceName, Venue, VenueRef
from app.platforms._dart import (
    dart_https_url,
    dart_round,
    is_blank,
    is_finite,
    is_num,
)

_SOURCE: MenuSourceName = "wolt"


def map_wolt_venues(raw: object) -> list[Venue] | None:
    """The venues in ``raw`` in page order, deduplicated by slug, or
    ``None`` when ``raw`` has no ``sections`` list."""
    if not isinstance(raw, dict):
        return None
    sections = raw.get("sections")
    if not isinstance(sections, list):
        return None

    seen_slugs: set[str] = set()
    venues: list[Venue] = []
    for section in sections:
        if not isinstance(section, dict):
            continue
        items = section.get("items")
        if not isinstance(items, list):
            continue
        for item in items:
            if not isinstance(item, dict):
                continue
            venue = _try_build_venue(item)
            if venue is None:
                continue
            if venue.ref.platform_id in seen_slugs:
                continue
            seen_slugs.add(venue.ref.platform_id)
            venues.append(venue)
    return venues


def _try_build_venue(item: dict[str, Any]) -> Venue | None:
    """The venue one list item describes, or ``None`` without a usable
    ``venue`` object."""
    raw = item.get("venue")
    if not isinstance(raw, dict):
        return None
    slug = _non_empty_string(raw.get("slug"))
    name = _non_empty_string(raw.get("name"))
    if slug is None or name is None:
        return None

    position = _read_position(raw.get("location"))
    estimate = raw.get("estimate")
    online = raw.get("online")
    return Venue(
        ref=VenueRef(source=_SOURCE, platform_id=slug),
        name=name,
        address=_non_empty_string(raw.get("address")),
        city=_non_empty_string(raw.get("city")),
        latitude=position[0] if position else None,
        longitude=position[1] if position else None,
        source_url=dart_https_url("wolt.com", f"/en/isr/tel-aviv/restaurant/{slug}"),
        cuisine_tags=_read_tags(raw.get("tags")),
        is_online=online if isinstance(online, bool) else None,
        image_url=_image_url(item.get("image")) or _image_url(raw.get("brand_image")),
        short_description=_non_empty_string(raw.get("short_description")),
        platform_rating=_read_rating(raw.get("rating")),
        estimate_minutes=(
            dart_round(estimate) if is_num(estimate) and is_finite(estimate) else None
        ),
    )


def _read_position(raw: object) -> tuple[float, float] | None:
    """A GeoJSON ``[longitude, latitude]`` pair as ``(latitude, longitude)``,
    or ``None`` unless it holds two finite, in-range numbers first."""
    if not isinstance(raw, list) or len(raw) < 2:
        return None
    lon, lat = raw[0], raw[1]
    if not is_num(lon) or not is_num(lat):
        return None
    if not is_finite(lon) or not is_finite(lat):
        return None
    if lat < -90 or lat > 90 or lon < -180 or lon > 180:
        return None
    return float(lat), float(lon)


def _read_tags(raw: object) -> list[str]:
    """The non-blank strings of a ``tags`` list, in order."""
    if not isinstance(raw, list):
        return []
    return [tag for tag in raw if isinstance(tag, str) and not is_blank(tag)]


def _read_rating(raw: object) -> float | None:
    """``rating.score`` as a float, or ``None`` when absent or not a finite
    number."""
    if not isinstance(raw, dict):
        return None
    score = raw.get("score")
    if not is_num(score) or not is_finite(score):
        return None
    return float(score)


def _image_url(raw: object) -> str | None:
    """The ``url`` of an image object, when it is a non-blank string."""
    if not isinstance(raw, dict):
        return None
    return _non_empty_string(raw.get("url"))


def _non_empty_string(raw: object) -> str | None:
    """``raw`` itself (untrimmed) when it is a string with a non-blank
    character, else ``None``."""
    return raw if isinstance(raw, str) and not is_blank(raw) else None

import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/venue/venue_ref_resolver.dart';

/// Normalises a Wolt discovery page — the body of `pages/restaurants` or
/// `pages/search` — into a list of [Venue]s
/// (`phase2_discovery_research.md` §2.1, §5).
///
/// Pure: no I/O, and [map] never throws. A change to Wolt's URLs or
/// headers belongs in `wolt_venue_search_service.dart`, not here; a
/// change to the JSON shape belongs here and nowhere else.
///
/// Both endpoints answer `{sections: [{items: [{venue: {...}}]}]}`. Which
/// section holds the full list varies between sources, so **every
/// section and every item is walked**, in order. Rules applied:
///
/// - An item with no `venue` object is skipped (promo tiles, category
///   carousels). So is a venue without a non-empty `slug` and `name`
///   string: the slug is how its menu is fetched, the name how it is
///   shown, and a venue lacking either is useless on a card.
/// - The first occurrence of a slug wins; a later duplicate — the same
///   venue listed in a second section — is dropped.
/// - `location` is GeoJSON order, `[longitude, latitude]`: index 1 is the
///   latitude. Anything but two in-range numbers leaves both null.
/// - `tags` become [Venue.cuisineTags] (non-empty strings only, order
///   kept); `online` becomes [Venue.isOnline]; `short_description`,
///   `address` are copied when non-empty strings.
/// - The item's own `image.url` becomes [Venue.imageUrl], falling back
///   to the venue's `brand_image.url`.
/// - `rating.score` (Wolt's 0–10 customer score, not a keto score)
///   becomes [Venue.platformRating]; `estimate` (minutes) becomes
///   [Venue.estimateMinutes], rounded.
/// - [Venue.sourceUrl] is [VenueRefResolver.platformUrl]'s link for the
///   slug, the same link the menu screen's "open on Wolt" action uses.
/// - Any field absent or of the wrong type is null (or empty), never a
///   failure; unknown keys anywhere, including a top-level
///   `_fixture_note`, are ignored.
///
/// Only a body with no `sections` list at all is not a discovery page;
/// [map] answers null for it so the caller can report `platformChanged`.
abstract final class WoltVenueMapper {
  /// The venues in [json], in page order and deduplicated by slug, or
  /// null when [json] has no `sections` list. Never throws.
  static List<Venue>? map(Map<String, Object?> json) {
    final sections = json['sections'];
    if (sections is! List<Object?>) return null;

    final seenSlugs = <String>{};
    final venues = <Venue>[];
    for (final section in sections) {
      if (section is! Map<String, Object?>) continue;
      final items = section['items'];
      if (items is! List<Object?>) continue;
      for (final item in items) {
        if (item is! Map<String, Object?>) continue;
        final venue = _tryBuildVenue(item);
        if (venue == null) continue;
        if (!seenSlugs.add(venue.ref.platformId)) continue;
        venues.add(venue);
      }
    }
    return venues;
  }

  /// The venue one list [item] describes, or null when it has no usable
  /// `venue` object.
  static Venue? _tryBuildVenue(Map<String, Object?> item) {
    final raw = item['venue'];
    if (raw is! Map<String, Object?>) return null;
    final slug = _nonEmptyString(raw['slug']);
    final name = _nonEmptyString(raw['name']);
    if (slug == null || name == null) return null;

    final ref = VenueRef(source: MenuSource.wolt, platformId: slug);
    final position = _readPosition(raw['location']);
    final estimate = raw['estimate'];
    final online = raw['online'];
    return Venue(
      ref: ref,
      name: name,
      address: _nonEmptyString(raw['address']),
      latitude: position?.latitude,
      longitude: position?.longitude,
      sourceUrl: VenueRefResolver.platformUrl(ref)?.toString(),
      cuisineTags: _readTags(raw['tags']),
      isOnline: online is bool ? online : null,
      imageUrl: _imageUrl(item['image']) ?? _imageUrl(raw['brand_image']),
      shortDescription: _nonEmptyString(raw['short_description']),
      platformRating: _readRating(raw['rating']),
      estimateMinutes: estimate is num && estimate.isFinite
          ? estimate.round()
          : null,
    );
  }

  /// A GeoJSON `[longitude, latitude]` pair, or null unless [raw] holds
  /// two finite, in-range numbers first.
  static ({double latitude, double longitude})? _readPosition(Object? raw) {
    if (raw is! List<Object?> || raw.length < 2) return null;
    final lon = raw[0];
    final lat = raw[1];
    if (lon is! num || lat is! num) return null;
    if (!lon.isFinite || !lat.isFinite) return null;
    if (lat < -90 || lat > 90 || lon < -180 || lon > 180) return null;
    return (latitude: lat.toDouble(), longitude: lon.toDouble());
  }

  /// The non-empty strings of a `tags` list, in order; empty otherwise.
  static List<String> _readTags(Object? raw) {
    if (raw is! List<Object?>) return const <String>[];
    return List<String>.unmodifiable(<String>[
      for (final tag in raw)
        if (tag is String && tag.trim().isNotEmpty) tag,
    ]);
  }

  /// `rating.score` as a double, or null when absent or not a number.
  static double? _readRating(Object? raw) {
    if (raw is! Map<String, Object?>) return null;
    final score = raw['score'];
    if (score is! num || !score.isFinite) return null;
    return score.toDouble();
  }

  /// The `url` of an image object, when it is a non-empty string.
  static String? _imageUrl(Object? raw) {
    if (raw is! Map<String, Object?>) return null;
    return _nonEmptyString(raw['url']);
  }

  static String? _nonEmptyString(Object? raw) =>
      raw is String && raw.trim().isNotEmpty ? raw : null;
}

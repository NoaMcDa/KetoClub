import 'package:flutter/foundation.dart';

/// The platform a menu was read from (architecture.md §7).
enum MenuSource {
  /// Wolt delivery, addressed by venue slug.
  wolt,

  /// 10bis corporate delivery, addressed by numeric restaurant id.
  tenbis,

  /// Tabit dine-in POS, addressed by site id. Phase 2+.
  tabit,

  /// Ontopo reservations, addressed by venue id. Phase 4.
  ontopo;

  /// The source whose [name] equals [wire], or null when none does.
  ///
  /// Matches by string, never by ordinal, so reordering this enum cannot
  /// silently re-map cached data.
  static MenuSource? tryParse(String wire) {
    for (final source in MenuSource.values) {
      if (source.name == wire) return source;
    }
    return null;
  }
}

/// How KetoClub addresses one venue on one platform (architecture.md §7).
@immutable
final class VenueRef {
  /// Creates a reference to [platformId] on [source].
  const new({required this.source, required this.platformId});

  /// Reads a reference written by [toJson].
  ///
  /// Returns null for any shape mismatch and never throws, so a stale or
  /// corrupt cache entry is a miss rather than a crash.
  static VenueRef? tryFrom(Map<String, Object?> json) {
    final source = json['source'];
    final platformId = json['platformId'];
    if (source is! String || platformId is! String) return null;
    if (platformId.isEmpty) return null;
    final parsed = MenuSource.tryParse(source);
    return parsed == null
        ? null
        : VenueRef(source: parsed, platformId: platformId);
  }

  /// The platform this venue is read from.
  final MenuSource source;

  /// The platform's own identifier: slug, restaurant id, site id, venue id.
  final String platformId;

  /// A stable cache key, unique across platforms.
  String get cacheKey => '${source.name}/$platformId';

  /// Writes a form [tryFrom] can read back.
  Map<String, Object?> toJson() => <String, Object?>{
    'source': source.name,
    'platformId': platformId,
  };

  @override
  bool operator ==(Object other) =>
      other is VenueRef &&
      other.source == source &&
      other.platformId == platformId;

  @override
  int get hashCode => Object.hash(source, platformId);

  @override
  String toString() => 'VenueRef($cacheKey)';
}

/// A restaurant, as much as a platform tells us about it (architecture.md §7).
///
/// Community fields (`keto_rating_score`, `is_verified_keto_friendly`) are
/// Phase 3 and deliberately unmodelled.
@immutable
final class Venue {
  /// Creates a venue addressed by [ref].
  const new({
    required this.ref,
    required this.name,
    this.address,
    this.latitude,
    this.longitude,
    this.sourceUrl,
  });

  /// How to fetch this venue's menu.
  final VenueRef ref;

  /// The venue name, exactly as the platform prints it.
  final String name;

  /// Street address, when the platform supplies one.
  final String? address;

  /// Latitude in degrees, when the platform supplies one.
  final double? latitude;

  /// Longitude in degrees, when the platform supplies one.
  final double? longitude;

  /// A deep link back to the venue's page on its platform.
  final String? sourceUrl;

  @override
  bool operator ==(Object other) =>
      other is Venue &&
      other.ref == ref &&
      other.name == name &&
      other.address == address &&
      other.latitude == latitude &&
      other.longitude == longitude &&
      other.sourceUrl == sourceUrl;

  @override
  int get hashCode =>
      Object.hash(ref, name, address, latitude, longitude, sourceUrl);
}

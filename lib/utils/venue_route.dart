import 'package:flutter/foundation.dart';
import 'package:ketoclub/models/venue.dart';

/// The route that opens [ref]'s menu: `/venue/{source}/{platformId}`, with
/// the platform id percent-encoded so a website's URL (architecture.md
/// D19) stays one path segment. `app.dart`'s `venueRefFromPath` reads it
/// back; a slug, a numeric id or a scan's hex id is unchanged by the
/// encoding.
String venueRoutePath(VenueRef ref) =>
    '/venue/${ref.source.name}/${Uri.encodeComponent(ref.platformId)}';

/// What the screen that opens a venue already knows about it, passed as the
/// venue route's `arguments` (issue #307): the name a venue card or a Recent
/// row shows, and the venue's city when known. No documented menu payload
/// names the venue, so without a hint the menu header falls back to the
/// slug. A deep link carries none.
@immutable
final class VenueOpenHint {
  /// Creates a hint naming the venue [name] in [city]; either may be null.
  const new({this.name, this.city});

  /// The venue's display name, or null when the opener does not know it.
  final String? name;

  /// The venue's city, or null when the opener does not know it.
  final String? city;

  @override
  bool operator ==(Object other) =>
      other is VenueOpenHint && other.name == name && other.city == city;

  @override
  int get hashCode => Object.hash(name, city);

  @override
  String toString() => 'VenueOpenHint(name: $name, city: $city)';
}

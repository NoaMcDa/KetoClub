import 'package:ketoclub/models/place.dart';
import 'package:ketoclub/services/place/place_search_service.dart';

/// Turns a Photon reply into streets (issue #449, architecture.md D28).
///
/// Pure and total: no HTTP, never throws. `PhotonPlaceSearchService` does
/// the request; this file is the only place Photon's GeoJSON shape is
/// read, so a change of shape touches nothing else. The backend's street
/// search route applies the same rules, so a street found either way
/// reads the same.
///
/// The rules, in order, for each element of `features`:
///
/// 1. Keep it only when `properties.countrycode` is `IL` in any case,
///    `properties.type` is `house` or `street`, and
///    `geometry.coordinates` is exactly `[longitude, latitude]`, two
///    finite numbers.
/// 2. The street is `properties.street` for a `house` and
///    `properties.name` for a `street`; a missing or blank one drops the
///    feature. The house number is `properties.housenumber` when it is a
///    non-blank string, for a `house` only. The city is `properties.city`,
///    else `properties.district`, else none.
/// 3. The label is `"<street> <number>, <city>"`, leaving out the number
///    and the `, <city>` part when absent, trimmed.
///
/// Then the places are deduplicated in Photon's order: a place is skipped
/// when one already kept has the same label, or has the same street and
/// the same house number — each compared trimmed and lower-cased, a
/// missing number matching only a missing number — and lies within
/// [nearDegrees] of it in latitude and in longitude. Photon answers one
/// address several times under different spellings of its city ("תל
/// אביב", "תל אביב-יפו", "תל אביב–יפו"), and a street in several segments;
/// each is one row. The first [placeSearchMaxResults] kept are returned.
abstract final class PhotonPlaceMapper {
  /// How close, in degrees of latitude and of longitude each, two places
  /// with the same street and number must be to count as one (about
  /// 300 m north to south).
  static const double nearDegrees = 0.003;

  /// The places in [decoded], a decoded Photon reply, or null when it is
  /// not one: not an object, or with no `features` list.
  ///
  /// A feature that breaks a rule above, including one that is not an
  /// object, is dropped; it does not fail the reply.
  static List<StreetPlace>? map(Object? decoded) {
    if (decoded is! Map<String, Object?>) return null;
    final features = decoded['features'];
    if (features is! List<Object?>) return null;
    final kept = <_Mapped>[];
    for (final feature in features) {
      final mapped = _place(feature);
      if (mapped == null || kept.any(mapped.isSameAs)) continue;
      kept.add(mapped);
      if (kept.length == placeSearchMaxResults) break;
    }
    return [for (final mapped in kept) mapped.place];
  }

  static _Mapped? _place(Object? feature) {
    if (feature is! Map<String, Object?>) return null;
    final properties = feature['properties'];
    final geometry = feature['geometry'];
    if (properties is! Map<String, Object?>) return null;
    if (geometry is! Map<String, Object?>) return null;

    final country = properties['countrycode'];
    if (country is! String || country.toUpperCase() != 'IL') return null;
    final type = properties['type'];
    if (type != 'house' && type != 'street') return null;

    final coordinates = geometry['coordinates'];
    if (coordinates is! List<Object?> || coordinates.length != 2) return null;
    final longitude = coordinates[0];
    final latitude = coordinates[1];
    if (longitude is! num || latitude is! num) return null;
    if (!longitude.isFinite || !latitude.isFinite) return null;

    final isHouse = type == 'house';
    final street = _text(properties[isHouse ? 'street' : 'name']);
    if (street == null) return null;
    final number = isHouse ? _text(properties['housenumber']) : null;
    final city = _text(properties['city']) ?? _text(properties['district']);

    final head = number == null ? street : '$street $number';
    final label = (city == null ? head : '$head, $city').trim();
    return _Mapped(
      StreetPlace(
        label: label,
        city: city,
        latitude: latitude.toDouble(),
        longitude: longitude.toDouble(),
      ),
      street: street.toLowerCase(),
      number: number?.toLowerCase(),
    );
  }

  /// [value] trimmed when it is a non-blank string, else null.
  static String? _text(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

/// A mapped place with the street and house number it was built from,
/// trimmed and lower-cased, for the dedupe step.
final class _Mapped {
  const new(this.place, {required this.street, required this.number});

  final StreetPlace place;
  final String street;
  final String? number;

  /// Whether this place repeats [kept], one already kept: the same label,
  /// or the same street and number close by.
  bool isSameAs(_Mapped kept) {
    if (place.label == kept.place.label) return true;
    if (street != kept.street || number != kept.number) return false;
    return (place.latitude - kept.place.latitude).abs() <=
            PhotonPlaceMapper.nearDegrees &&
        (place.longitude - kept.place.longitude).abs() <=
            PhotonPlaceMapper.nearDegrees;
  }
}

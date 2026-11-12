import 'package:flutter/foundation.dart';

/// A place the user can choose to look around instead of the device's own
/// position (issue #443): a city KetoClub knows by name, with the
/// coordinates a nearby search is made at.
///
/// Its names are data, not UI copy: a proper noun in each of the two UI
/// languages, read through [nameFor]. That is why they live here and not in
/// the ARB files, the same exception the keto vocabulary makes
/// (architecture.md §12).
@immutable
final class KnownPlace {
  /// Creates a place addressed by [id], named [nameEn] and [nameHe], at
  /// [latitude] and [longitude] in degrees.
  const new({
    required this.id,
    required this.nameEn,
    required this.nameHe,
    required this.latitude,
    required this.longitude,
  });

  /// A stable identifier, lower-case ASCII with hyphens: what
  /// `AppSettings.discoveryPlaceId` stores. Never shown, and never reused
  /// for another place.
  final String id;

  /// The place's name in English.
  final String nameEn;

  /// The place's name in Hebrew.
  final String nameHe;

  /// The latitude of the place's approximate centre, in degrees.
  final double latitude;

  /// The longitude of the place's approximate centre, in degrees.
  final double longitude;

  /// The name to show in the UI language [languageCode]: [nameHe] for
  /// `he`, [nameEn] for anything else.
  String nameFor(String languageCode) => languageCode == 'he' ? nameHe : nameEn;

  @override
  bool operator ==(Object other) =>
      other is KnownPlace &&
      other.id == id &&
      other.nameEn == nameEn &&
      other.nameHe == nameHe &&
      other.latitude == latitude &&
      other.longitude == longitude;

  @override
  int get hashCode => Object.hash(id, nameEn, nameHe, latitude, longitude);

  @override
  String toString() => 'KnownPlace($id)';
}

/// A street, or an address on one, that a street search found (issue
/// #449): what the user can choose to look around instead of a city.
///
/// Unlike a [KnownPlace] it is not bundled data but an answer from a
/// geocoder, so its [label] is shown as the geocoder wrote it — in the
/// language the search was made in, most often Hebrew — and only
/// [label], [latitude] and [longitude] are kept on the device once it is
/// chosen ([toJson]). [city] is for display while choosing and is not
/// stored.
@immutable
final class StreetPlace {
  /// Creates a street labelled [label], in [city] when known, at
  /// [latitude] and [longitude] in degrees.
  const new({
    required this.label,
    required this.latitude,
    required this.longitude,
    this.city,
  });

  /// Reads a street written by [toJson], or a search answer carrying
  /// `label`, `latitude`, `longitude` and an optional `city`.
  ///
  /// Returns null, never throws, when `label` is not a non-blank string,
  /// or either coordinate is not a finite number within its range. A
  /// `city` that is not a non-blank string reads as null.
  static StreetPlace? tryFrom(Map<String, Object?> json) {
    final label = json['label'];
    final latitude = json['latitude'];
    final longitude = json['longitude'];
    if (label is! String || label.trim().isEmpty) return null;
    if (latitude is! num || longitude is! num) return null;
    final lat = latitude.toDouble();
    final lon = longitude.toDouble();
    if (!lat.isFinite || !lon.isFinite) return null;
    if (lat.abs() > 90 || lon.abs() > 180) return null;
    final city = json['city'];
    return StreetPlace(
      label: label.trim(),
      city: city is String && city.trim().isNotEmpty ? city.trim() : null,
      latitude: lat,
      longitude: lon,
    );
  }

  /// What is shown for the street: `"<street> <number>, <city>"`, without
  /// the number or the city when the geocoder had none.
  final String label;

  /// The city the street is in, when the geocoder named one.
  final String? city;

  /// The latitude of the street or address, in degrees.
  final double latitude;

  /// The longitude of the street or address, in degrees.
  final double longitude;

  /// The stored form: [label], [latitude] and [longitude] only.
  Map<String, Object?> toJson() => <String, Object?>{
    'label': label,
    'latitude': latitude,
    'longitude': longitude,
  };

  @override
  bool operator ==(Object other) =>
      other is StreetPlace &&
      other.label == label &&
      other.city == city &&
      other.latitude == latitude &&
      other.longitude == longitude;

  @override
  int get hashCode => Object.hash(label, city, latitude, longitude);

  // Never the label: a street the user chose is where they are looking,
  // and a toString reaches logs and test output.
  @override
  String toString() => 'StreetPlace(…)';
}

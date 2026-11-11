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

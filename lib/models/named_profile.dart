/// One person's named dietary profile on this device (Banto; the Allergens
/// epic, ALG-12, issue #354): "Me", "Dana (8)", "Grandma".
///
/// A device holds the user's own profile, the primary one, plus any number
/// of others up to [NamedProfile.maxProfiles]; any subset can be combined
/// for a menu (`AppSettings.activeProfileIds`). Like the profile itself it
/// stays on the device (contract decision C1): nothing here is put in a
/// request.
library;

import 'package:flutter/foundation.dart';
import 'package:ketoclub/models/dietary_profile.dart';

/// A [DietaryProfile] with a stable id and the name its person goes by.
@immutable
final class NamedProfile {
  /// Creates the profile [id], called [name], holding [profile].
  ///
  /// Takes [name] as given; [normaliseName] is the way in that trims and
  /// caps it.
  const new({
    required this.id,
    required this.name,
    this.profile = DietaryProfile.empty,
  });

  /// Reads one profile written by [toJson], tolerantly; null when [json]
  /// is not an object or has no usable id. Never throws.
  ///
  /// A name that is not a string reads as empty, and the restrictions go
  /// through [DietaryProfile.tryFrom], which drops what it cannot read.
  static NamedProfile? tryFrom(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final rawId = json['id'];
    if (rawId is! String || rawId.trim().isEmpty) return null;
    final rawName = json['name'];
    return NamedProfile(
      id: rawId.trim(),
      name: normaliseName(rawName is String ? rawName : ''),
      profile: DietaryProfile.tryFrom(json[restrictionsKey]),
    );
  }

  /// The id of the device owner's own profile: the one that existed before
  /// there were several, stored where it always was.
  static const String primaryId = 'me';

  /// The most profiles one device keeps, the primary one included.
  static const int maxProfiles = 8;

  /// The longest a name may be, in Unicode code points.
  static const int maxNameLength = 40;

  /// The JSON key the restrictions are written under, here and in a
  /// shared profile.
  static const String restrictionsKey = 'restrictions';

  /// Stable, never shown, never reused for another person on this device.
  final String id;

  /// What the person is called. Empty for a primary profile the user never
  /// renamed, which the UI shows as "Me" in its own language.
  final String name;

  /// The person's restrictions. Empty reads as keto only, as everywhere.
  final DietaryProfile profile;

  /// Whether this is the device owner's own profile.
  bool get isPrimary => id == primaryId;

  /// [raw] trimmed and cut to [maxNameLength] code points, so a cut never
  /// splits a surrogate pair.
  static String normaliseName(String raw) {
    final trimmed = raw.trim();
    final runes = trimmed.runes;
    if (runes.length <= maxNameLength) return trimmed;
    return String.fromCharCodes(runes.take(maxNameLength)).trim();
  }

  /// A copy with [name] (normalised) or [profile] replaced.
  NamedProfile copyWith({String? name, DietaryProfile? profile}) =>
      NamedProfile(
        id: id,
        name: name == null ? this.name : normaliseName(name),
        profile: profile ?? this.profile,
      );

  /// Writes a form [tryFrom] reads back.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    restrictionsKey: profile.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      other is NamedProfile &&
      other.id == id &&
      other.name == name &&
      other.profile == profile;

  @override
  int get hashCode => Object.hash(id, name, profile);

  // An id and a count, never the name or the restrictions, so a logged
  // value cannot carry health data (contract decision C1).
  @override
  String toString() => 'NamedProfile($id, ${profile.entries.length} entries)';
}

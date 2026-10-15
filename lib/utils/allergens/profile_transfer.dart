/// Sharing one profile between devices as text (Banto; the Allergens epic,
/// ALG-12, issue #354).
///
/// There is no account and no server copy: a profile moves only as JSON
/// the user shares themselves (a share sheet, a message) and pastes on the
/// other device, where the import screen says it is health data and asks
/// before saving. The JSON carries the name and the restrictions with
/// their exceptions, nothing else — not the device's profile id, which the
/// receiving device assigns itself. Pure; never throws.
library;

import 'dart:convert';

import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/named_profile.dart';

/// A profile read from shared text: a name and the restrictions.
typedef SharedProfile = ({String name, DietaryProfile profile});

/// Encodes and decodes a shared profile.
abstract final class ProfileTransfer {
  /// The key that marks the JSON as a shared profile, with its format
  /// version as the value.
  static const String formatKey = 'bantoProfile';

  /// The format version [encode] writes.
  static const int formatVersion = 1;

  /// The longest text [decode] reads, in UTF-16 units: far more than any
  /// real profile, and a bound on what a paste can make it parse.
  static const int maxLength = 8000;

  /// [profile], called [name], as one line of JSON for [decode].
  static String encode({
    required String name,
    required DietaryProfile profile,
  }) => jsonEncode(<String, Object?>{
    formatKey: formatVersion,
    'name': NamedProfile.normaliseName(name),
    NamedProfile.restrictionsKey: profile.toJson(),
  });

  /// The profile in [text], or null when [text] is not one [encode]
  /// wrote: not JSON, not an object, without [formatKey], or longer than
  /// [maxLength]. Text around the JSON (a greeting in a message) is
  /// ignored: the object runs from the first `{` to the last `}`.
  ///
  /// The restrictions are read as tolerantly as the device's own
  /// ([DietaryProfile.tryFrom]): an unknown id is dropped, so a profile
  /// from a newer app still imports what this one knows. A name that is
  /// not a string reads as empty.
  static SharedProfile? decode(String text) {
    if (text.length > maxLength) return null;
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(text.substring(start, end + 1));
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, Object?>) return null;
    if (decoded[formatKey] is! int) return null;
    final rawName = decoded['name'];
    return (
      name: NamedProfile.normaliseName(rawName is String ? rawName : ''),
      profile: DietaryProfile.tryFrom(decoded[NamedProfile.restrictionsKey]),
    );
  }
}

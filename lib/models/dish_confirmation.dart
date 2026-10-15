/// What a person learned from the staff about one dish, after the meal
/// (Banto; the Allergens epic, ALG-14, issue #356; architecture.md D27).
///
/// A [DishConfirmation] records one answer to "Did you ask about sesame in
/// this dish?": the staff said it is there ([ConfirmationPolarity.present])
/// or that it is not ([ConfirmationPolarity.absent]). "I didn't ask" is not
/// recorded at all. A [ChangeConfirmation] records whether the kitchen made
/// the change that was asked for.
///
/// Both are kept with the visit history on the device (D23's
/// `menu_history` box) and leave it through nothing: they name a
/// restriction, and the profile never leaves the device (D26 C1). They are
/// facts about one dish on one day, never a rating: nothing sums them into
/// a number for a venue (D27).
///
/// Every reader is tolerant, as the rest of the history is: an unknown
/// name, a missing field or a field of the wrong type makes that one record
/// read as null, and the list holding it drops it.
library;

import 'package:flutter/foundation.dart';
import 'package:ketoclub/models/concern.dart';
import 'package:ketoclub/models/restriction.dart';

/// What the staff said about a restriction in a dish.
enum ConfirmationPolarity {
  /// It is in the dish.
  present,

  /// It is not in the dish.
  absent;

  /// The polarity whose [name] equals [wire], or null when none does.
  static ConfirmationPolarity? tryParse(Object? wire) {
    for (final value in ConfirmationPolarity.values) {
      if (value.name == wire) return value;
    }
    return null;
  }
}

/// [day] as `YYYY-MM-DD`, the form a confirmation's date is stored in.
String confirmationDayKey(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

/// The calendar day [moment] falls on, at midnight, in [moment]'s own
/// zone: a confirmation keeps the day, never the time.
DateTime confirmationDay(DateTime moment) =>
    DateTime(moment.year, moment.month, moment.day);

/// The day [raw] holds as `YYYY-MM-DD`, or null when it holds none.
DateTime? _readDay(Object? raw) {
  if (raw is! String) return null;
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(raw);
  if (match == null) return null;
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final parsed = DateTime(year, month, day);
  // DateTime rolls 2026-02-31 over to March; such a day is no day.
  if (parsed.month != month || parsed.day != day) return null;
  return parsed;
}

/// The fingerprint a dish is named by outside the device: eight lowercase
/// hex digits of a 32-bit FNV-1a hash over [dishId]'s UTF-16 code units
/// (the hash `TextNormaliser.menuFingerprint` uses, D23). It always
/// matches `[A-Za-z0-9._:-]{1,64}`, the shape the backend half of ALG-14
/// (PR #392) keys a shared confirmation by, so the person's own answers,
/// keyed on the device by [DishConfirmation.dishId], can later be uploaded
/// unchanged. Nothing uploads them yet. Two ids of one venue could share a
/// fingerprint, as two pastes can share a ref (D18); the dish id stays the
/// key on the device.
String dishFingerprint(String dishId) {
  var hash = 0x811c9dc5;
  for (final unit in dishId.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

/// [raw] when it is a non-empty string, else null.
String? _optionalText(Object? raw) =>
    raw is String && raw.isNotEmpty ? raw : null;

/// One answer about one restriction in one dish, on one day (ALG-14).
///
/// Keyed by the dish ([dishId], the id `NotesStore` and `AnalysedDish`
/// already pair with the venue), the restriction, the [polarity] and the
/// [day]; [source] and [matchedText] remember where the concern that was
/// asked about had been found, so a confirmed restriction can still be
/// shown where it was found if a later analysis no longer finds it.
///
/// An answer about the user's own words ([RestrictionId.custom], ALG-17)
/// is **local-only**: it is recorded and shown on this device, and never
/// shared, since the words are the profile (C1) and the shared store
/// refuses that id. [isShareable] says which answers a later upload may
/// send, under the dish's [dishFingerprint] and the polarity's name
/// (`present` | `absent`; "didn't ask" is never recorded at all).
@immutable
final class DishConfirmation {
  /// Creates an answer about [restrictionId] in the dish [dishId].
  const new({
    required this.dishId,
    required this.restrictionId,
    required this.polarity,
    required this.day,
    this.source,
    this.matchedText,
  });

  /// Reads an answer written by [toJson], or null, never throwing, when
  /// `dishId`, `restrictionId`, `polarity` or `day` is missing or
  /// malformed. An unknown `source` reads as null.
  static DishConfirmation? tryFromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final dishId = json['dishId'];
    if (dishId is! String || dishId.isEmpty) return null;
    final rawId = json['restrictionId'];
    RestrictionId? restrictionId;
    for (final value in RestrictionId.values) {
      if (value.name == rawId) restrictionId = value;
    }
    final polarity = ConfirmationPolarity.tryParse(json['polarity']);
    final day = _readDay(json['day']);
    if (restrictionId == null || polarity == null || day == null) {
      return null;
    }
    final rawSource = json['source'];
    return DishConfirmation(
      dishId: dishId,
      restrictionId: restrictionId,
      polarity: polarity,
      day: day,
      source: rawSource is String ? ConcernSource.tryParse(rawSource) : null,
      matchedText: _optionalText(json['matchedText']),
    );
  }

  /// The dish the answer is about, by its id in the venue's menu.
  final String dishId;

  /// The restriction that was asked about.
  final RestrictionId restrictionId;

  /// What the staff said.
  final ConfirmationPolarity polarity;

  /// The day of the answer, at midnight.
  final DateTime day;

  /// Where the concern asked about had been found, when known.
  final ConcernSource? source;

  /// The menu's words the concern asked about had matched, when any.
  final String? matchedText;

  /// [dishId]'s fingerprint for the shared store ([dishFingerprint]).
  String get dishKey => dishFingerprint(dishId);

  /// Whether a later upload may share this answer: every restriction but
  /// the user's own words ([RestrictionId.custom]), which stay local.
  bool get isShareable => restrictionId != RestrictionId.custom;

  /// Writes a form [tryFromJson] can read back; a null field is left out.
  Map<String, Object?> toJson() => <String, Object?>{
    'dishId': dishId,
    'restrictionId': restrictionId.name,
    'polarity': polarity.name,
    'day': confirmationDayKey(day),
    'source': ?source?.name,
    'matchedText': ?matchedText,
  };

  @override
  bool operator ==(Object other) =>
      other is DishConfirmation &&
      other.dishId == dishId &&
      other.restrictionId == restrictionId &&
      other.polarity == polarity &&
      other.day == day &&
      other.source == source &&
      other.matchedText == matchedText;

  @override
  int get hashCode =>
      Object.hash(dishId, restrictionId, polarity, day, source, matchedText);

  @override
  String toString() =>
      'DishConfirmation($dishId, ${restrictionId.name}, ${polarity.name}, '
      '${confirmationDayKey(day)})';
}

/// Whether the kitchen made the change asked for on one dish, on one day
/// (ALG-14).
@immutable
final class ChangeConfirmation {
  /// Creates the answer for the dish [dishId].
  const new({required this.dishId, required this.honoured, required this.day});

  /// Reads an answer written by [toJson], or null, never throwing, when a
  /// field is missing or malformed.
  static ChangeConfirmation? tryFromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final dishId = json['dishId'];
    final honoured = json['honoured'];
    final day = _readDay(json['day']);
    if (dishId is! String || dishId.isEmpty || honoured is! bool) return null;
    if (day == null) return null;
    return ChangeConfirmation(dishId: dishId, honoured: honoured, day: day);
  }

  /// The dish the answer is about, by its id in the venue's menu.
  final String dishId;

  /// Whether the kitchen changed the dish as asked.
  final bool honoured;

  /// The day of the answer, at midnight.
  final DateTime day;

  /// Writes a form [tryFromJson] can read back.
  Map<String, Object?> toJson() => <String, Object?>{
    'dishId': dishId,
    'honoured': honoured,
    'day': confirmationDayKey(day),
  };

  @override
  bool operator ==(Object other) =>
      other is ChangeConfirmation &&
      other.dishId == dishId &&
      other.honoured == honoured &&
      other.day == day;

  @override
  int get hashCode => Object.hash(dishId, honoured, day);

  @override
  String toString() =>
      'ChangeConfirmation($dishId, $honoured, ${confirmationDayKey(day)})';
}

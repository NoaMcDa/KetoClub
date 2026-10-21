/// What other people were told by the staff about a venue's dishes, as
/// KetoClub's backend counts it (Banto; the Allergens epic, ALG-14, issue
/// #409; architecture.md D27).
///
/// The backend's venue-menu route answers an optional `confirmations` list
/// beside the menu, one entry per dish and restriction: `{dishFingerprint,
/// restrictionId, present, absent, first, last}`, where `present` and
/// `absent` are how many different installs were told the restriction's
/// ingredient is (or is not) in the dish, each shown by the backend only
/// from three, and `first`/`last` the days (`YYYY-MM-DD`) of those answers.
///
/// Read tolerantly, as every Banto wire field is (D26 C3): an absent or
/// malformed list is none, an entry with a fingerprint that is not a token,
/// an unknown restriction id, the user's own restriction (`custom`, never
/// shared) or a missing day is dropped, and a count that is not a
/// non-negative integer reads as 0. A dish is matched by
/// [dishFingerprint] of its id, the key the device uploads under.
///
/// These are facts about one dish and one restriction, never a rating:
/// nothing sums them into a number for a venue (D27). They name a
/// restriction because the dish was asked about it, not because the user
/// has it; the device reads only those its own profile holds.
library;

import 'package:flutter/foundation.dart';
import 'package:ketoclub/models/dish_confirmation.dart';
import 'package:ketoclub/models/restriction.dart';

/// What a shared dish fingerprint may look like: the backend's
/// `[A-Za-z0-9._:-]{1,64}`.
final RegExp _fingerprint = RegExp(r'^[A-Za-z0-9._:\-]{1,64}$');

/// The day [raw] holds as `YYYY-MM-DD`, at midnight, or null.
DateTime? _day(Object? raw) {
  if (raw is! String) return null;
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(raw);
  if (match == null) return null;
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final parsed = DateTime(year, month, day);
  if (parsed.month != month || parsed.day != day) return null;
  return parsed;
}

/// [raw] as a count: a non-negative integer, else 0.
int _count(Object? raw) => raw is int && raw > 0 ? raw : 0;

/// The counts other people shared about one restriction in one dish.
@immutable
final class SharedConfirmationCount {
  /// Creates the counts for [restrictionId] in the dish [dishFingerprint].
  const new({
    required this.dishFingerprint,
    required this.restrictionId,
    required this.present,
    required this.absent,
    required this.first,
    required this.last,
  });

  /// Reads one wire entry, or null, never throwing; see the library doc.
  static SharedConfirmationCount? tryFrom(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final fingerprint = json['dishFingerprint'];
    final rawId = json['restrictionId'];
    final id = rawId is String ? RestrictionId.tryParse(rawId) : null;
    final first = _day(json['first']);
    final last = _day(json['last']);
    if (fingerprint is! String ||
        !_fingerprint.hasMatch(fingerprint) ||
        id == null ||
        id == RestrictionId.custom ||
        first == null ||
        last == null) {
      return null;
    }
    return SharedConfirmationCount(
      dishFingerprint: fingerprint,
      restrictionId: id,
      present: _count(json['present']),
      absent: _count(json['absent']),
      first: first,
      last: last,
    );
  }

  /// The dish, as [dishFingerprint] of its id.
  final String dishFingerprint;

  /// The restriction the people asked about.
  final RestrictionId restrictionId;

  /// How many people were told it is in the dish; 0 below the backend's
  /// threshold.
  final int present;

  /// How many people were told it is not in the dish; 0 below the
  /// backend's threshold.
  final int absent;

  /// The first day of the counted answers.
  final DateTime first;

  /// The last day of the counted answers.
  final DateTime last;

  /// The wire form [tryFrom] reads, for the menu cache.
  Map<String, Object?> toJson() => <String, Object?>{
    'dishFingerprint': dishFingerprint,
    'restrictionId': restrictionId.name,
    'present': present,
    'absent': absent,
    'first': confirmationDayKey(first),
    'last': confirmationDayKey(last),
  };

  @override
  bool operator ==(Object other) =>
      other is SharedConfirmationCount &&
      other.dishFingerprint == dishFingerprint &&
      other.restrictionId == restrictionId &&
      other.present == present &&
      other.absent == absent &&
      other.first == first &&
      other.last == last;

  @override
  int get hashCode =>
      Object.hash(dishFingerprint, restrictionId, present, absent, first, last);

  @override
  String toString() =>
      'SharedConfirmationCount($dishFingerprint, ${restrictionId.name}, '
      '+$present -$absent)';
}

/// Every count the backend answered for one venue's menu.
@immutable
final class SharedConfirmations {
  /// Creates the venue's [counts].
  const new(this.counts);

  /// Reads the venue-menu route's (and the menu cache's) `confirmations`
  /// list, or null when it is absent, not a list or holds no readable
  /// entry. Never throws.
  static SharedConfirmations? tryFrom(Object? json) {
    if (json is! List<Object?>) return null;
    final counts = <SharedConfirmationCount>[
      for (final raw in json) ?SharedConfirmationCount.tryFrom(raw),
    ];
    if (counts.isEmpty) return null;
    return SharedConfirmations(
      List<SharedConfirmationCount>.unmodifiable(counts),
    );
  }

  /// One entry per dish and restriction, in the backend's order.
  final List<SharedConfirmationCount> counts;

  /// The counts about the dish [dishId], matched by [dishFingerprint].
  List<SharedConfirmationCount> forDish(String dishId) {
    final fingerprint = dishFingerprint(dishId);
    return <SharedConfirmationCount>[
      for (final count in counts)
        if (count.dishFingerprint == fingerprint) count,
    ];
  }

  /// The wire form [tryFrom] reads, for the menu cache.
  List<Map<String, Object?>> toJson() => <Map<String, Object?>>[
    for (final count in counts) count.toJson(),
  ];

  @override
  bool operator ==(Object other) =>
      other is SharedConfirmations && listEquals(other.counts, counts);

  @override
  int get hashCode => Object.hashAll(counts);

  @override
  String toString() => 'SharedConfirmations(${counts.length})';
}

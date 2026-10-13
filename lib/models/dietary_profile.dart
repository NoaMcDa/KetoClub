/// The user's dietary profile (Banto; the Allergens epic, ALG-02a, issue
/// #344): the restrictions they chose, each with a few free-text
/// exceptions.
///
/// There are no severity levels, and there never will be: whether a
/// restriction is strict comes from its kind in the taxonomy
/// (`RestrictionKind.isStrict`), never from the profile. That is also why
/// "does this profile hold a strict entry" is not a getter here: models
/// may import nothing above `models/` (architecture.md §5), and the kinds
/// live in `lib/utils/allergens/taxonomy.dart`, so the question is answered
/// by the `hasStrictEntry` extension in
/// `lib/utils/dietary_profile_strictness.dart`, one layer up.
///
/// The profile stays on the device (Banto contract decision C1): it is kept
/// by `SettingsStore` beside the other preferences and is never put in a
/// request.
library;

import 'package:flutter/foundation.dart';
import 'package:ketoclub/models/restriction.dart';

/// One restriction in a [DietaryProfile], with the user's exceptions to it.
@immutable
final class ProfileEntry {
  /// Creates the entry for [restrictionId] with [exceptions].
  ///
  /// Takes [exceptions] as given; [DietaryProfile.withEntry] and
  /// [DietaryProfile.tryFrom] are the ways in that trim, de-duplicate and
  /// cap them ([normaliseExceptions]).
  const new({required this.restrictionId, this.exceptions = const <String>[]});

  /// The most exceptions one entry keeps.
  static const int maxExceptions = 5;

  /// The longest one exception may be, in Unicode code points.
  static const int maxExceptionLength = 60;

  /// The restriction this entry records.
  final RestrictionId restrictionId;

  /// What the user eats despite the restriction, in their own words, such
  /// as "butter" under lactose. At most [maxExceptions], each at most
  /// [maxExceptionLength] code points once normalised.
  final List<String> exceptions;

  /// [raw] trimmed, with blanks and repeats dropped, each cut to
  /// [maxExceptionLength] code points and the list cut to [maxExceptions].
  ///
  /// Cut by code point rather than by UTF-16 unit, so a cut never splits a
  /// surrogate pair. The result is unmodifiable.
  static List<String> normaliseExceptions(Iterable<String> raw) {
    final kept = <String>[];
    for (final value in raw) {
      if (kept.length == maxExceptions) break;
      final trimmed = value.trim();
      if (trimmed.isEmpty) continue;
      final runes = trimmed.runes;
      final capped = runes.length > maxExceptionLength
          ? String.fromCharCodes(runes.take(maxExceptionLength)).trim()
          : trimmed;
      if (!kept.contains(capped)) kept.add(capped);
    }
    return List<String>.unmodifiable(kept);
  }

  /// Writes a form [DietaryProfile.tryFrom] reads back.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': restrictionId.name,
    'exceptions': exceptions,
  };

  @override
  bool operator ==(Object other) =>
      other is ProfileEntry &&
      other.restrictionId == restrictionId &&
      listEquals(other.exceptions, exceptions);

  @override
  int get hashCode => Object.hash(restrictionId, Object.hashAll(exceptions));

  @override
  String toString() => exceptions.isEmpty
      ? restrictionId.name
      : '${restrictionId.name} (except ${exceptions.join(', ')})';
}

/// The restrictions a user chose, in the order they added them, at most one
/// entry per [RestrictionId].
@immutable
final class DietaryProfile {
  /// Creates a profile holding [entries], which must not repeat an id.
  ///
  /// [withEntry], [withoutEntry] and [DietaryProfile.tryFrom] keep that
  /// rule for you.
  const new({this.entries = const <ProfileEntry>[]});

  /// Reads a profile written by [toJson], tolerantly, and never throws.
  ///
  /// Added after installs already existed, so nothing here invalidates the
  /// settings record around it: a value that is not a list reads as
  /// [empty]; an item that is not an object, or whose id
  /// [RestrictionId.tryParse] does not recognise, is dropped; a repeated
  /// id keeps its first entry; exceptions that are not a list read as
  /// none, non-string exceptions are dropped, and the rest go through
  /// [ProfileEntry.normaliseExceptions].
  factory tryFrom(Object? json) {
    if (json is! List<Object?>) return empty;
    final entries = <ProfileEntry>[];
    final seen = <RestrictionId>{};
    for (final item in json) {
      if (item is! Map<String, Object?>) continue;
      final rawId = item['id'];
      if (rawId is! String) continue;
      final id = RestrictionId.tryParse(rawId);
      if (id == null || !seen.add(id)) continue;
      final rawExceptions = item['exceptions'];
      final exceptions = rawExceptions is List<Object?>
          ? rawExceptions.whereType<String>()
          : const <String>[];
      entries.add(
        ProfileEntry(
          restrictionId: id,
          exceptions: ProfileEntry.normaliseExceptions(exceptions),
        ),
      );
    }
    return entries.isEmpty
        ? empty
        : DietaryProfile(entries: List<ProfileEntry>.unmodifiable(entries));
  }

  /// The profile with no restriction: a keto-only user, today's app.
  static const DietaryProfile empty = DietaryProfile();

  /// The chosen restrictions, in the order they were added.
  final List<ProfileEntry> entries;

  /// Whether no restriction is chosen.
  bool get isEmpty => entries.isEmpty;

  /// Whether [id] is in the profile.
  bool contains(RestrictionId id) => entryFor(id) != null;

  /// The entry for [id], or null when the profile does not hold it.
  ProfileEntry? entryFor(RestrictionId id) {
    for (final entry in entries) {
      if (entry.restrictionId == id) return entry;
    }
    return null;
  }

  /// A copy holding [id] with [exceptions], normalised.
  ///
  /// When [id] is already present its entry keeps its place and, if
  /// [exceptions] is given, takes the new ones; omitting [exceptions] then
  /// keeps the old. A new [id] goes last, with no exceptions unless given.
  DietaryProfile withEntry(RestrictionId id, {List<String>? exceptions}) {
    final existing = entryFor(id);
    final entry = ProfileEntry(
      restrictionId: id,
      exceptions: exceptions == null
          ? existing?.exceptions ?? const <String>[]
          : ProfileEntry.normaliseExceptions(exceptions),
    );
    final next = existing == null
        ? <ProfileEntry>[...entries, entry]
        : <ProfileEntry>[
            for (final current in entries)
              if (current.restrictionId == id) entry else current,
          ];
    return DietaryProfile(entries: List<ProfileEntry>.unmodifiable(next));
  }

  /// A copy without [id]; the same profile when it does not hold [id].
  DietaryProfile withoutEntry(RestrictionId id) {
    if (!contains(id)) return this;
    final next = <ProfileEntry>[
      for (final entry in entries)
        if (entry.restrictionId != id) entry,
    ];
    return next.isEmpty
        ? empty
        : DietaryProfile(entries: List<ProfileEntry>.unmodifiable(next));
  }

  /// Writes a list [DietaryProfile.tryFrom] reads back: one object per
  /// entry, in order.
  List<Map<String, Object?>> toJson() => <Map<String, Object?>>[
    for (final entry in entries) entry.toJson(),
  ];

  @override
  bool operator ==(Object other) =>
      other is DietaryProfile && listEquals(other.entries, entries);

  @override
  int get hashCode => Object.hashAll(entries);

  @override
  String toString() => 'DietaryProfile(${entries.join(', ')})';
}

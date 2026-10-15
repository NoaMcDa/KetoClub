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
  const new({
    required this.restrictionId,
    this.exceptions = const <String>[],
    this.terms = const <String>[],
  });

  /// The most exceptions one entry keeps.
  static const int maxExceptions = 5;

  /// The longest one exception may be, in Unicode code points.
  static const int maxExceptionLength = 60;

  /// The most free-text terms the user's own restriction keeps (ALG-17).
  static const int maxTerms = 10;

  /// The longest one free-text term may be, in Unicode code points: an
  /// ingredient's name, not a sentence.
  static const int maxTermLength = 40;

  /// The restriction this entry records.
  final RestrictionId restrictionId;

  /// What the user eats despite the restriction, in their own words, such
  /// as "butter" under lactose. At most [maxExceptions], each at most
  /// [maxExceptionLength] code points once normalised.
  final List<String> exceptions;

  /// The user's own words for what they cannot eat ("kiwi", "כוסברה"):
  /// held only by the [RestrictionId.custom] entry (ALG-17), and matched
  /// literally on the device, never sent anywhere (D26 C1). At most
  /// [maxTerms], each at most [maxTermLength] code points once normalised
  /// ([normaliseTerms]). Empty for every other entry.
  final List<String> terms;

  /// [raw] trimmed, with blanks and repeats dropped, each cut to
  /// [maxExceptionLength] code points and the list cut to [maxExceptions].
  ///
  /// Cut by code point rather than by UTF-16 unit, so a cut never splits a
  /// surrogate pair. The result is unmodifiable.
  static List<String> normaliseExceptions(Iterable<String> raw) =>
      _normalise(raw, maxCount: maxExceptions, maxLength: maxExceptionLength);

  /// [raw] trimmed, with blanks and repeats dropped (a repeat ignoring
  /// case: "Kiwi" after "kiwi"), each cut to [maxTermLength] code points
  /// and the list cut to [maxTerms]. Unmodifiable.
  static List<String> normaliseTerms(Iterable<String> raw) => _normalise(
    raw,
    maxCount: maxTerms,
    maxLength: maxTermLength,
    ignoreCase: true,
  );

  static List<String> _normalise(
    Iterable<String> raw, {
    required int maxCount,
    required int maxLength,
    bool ignoreCase = false,
  }) {
    final kept = <String>[];
    final seen = <String>{};
    for (final value in raw) {
      if (kept.length == maxCount) break;
      final trimmed = value.trim();
      if (trimmed.isEmpty) continue;
      final runes = trimmed.runes;
      final capped = runes.length > maxLength
          ? String.fromCharCodes(runes.take(maxLength)).trim()
          : trimmed;
      if (seen.add(ignoreCase ? capped.toLowerCase() : capped)) {
        kept.add(capped);
      }
    }
    return List<String>.unmodifiable(kept);
  }

  /// Writes a form [DietaryProfile.tryFrom] reads back. [terms] are
  /// written only when there are some, so every entry but the user's own
  /// restriction writes exactly what it wrote before ALG-17.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': restrictionId.name,
    'exceptions': exceptions,
    if (terms.isNotEmpty) 'terms': terms,
  };

  @override
  bool operator ==(Object other) =>
      other is ProfileEntry &&
      other.restrictionId == restrictionId &&
      listEquals(other.exceptions, exceptions) &&
      listEquals(other.terms, terms);

  @override
  int get hashCode => Object.hash(
    restrictionId,
    Object.hashAll(exceptions),
    Object.hashAll(terms),
  );

  /// The id and its exceptions and, for the user's own restriction, how
  /// many words it holds — never the words themselves, which are health
  /// data and stay out of logs (D26 C1).
  @override
  String toString() {
    final own = terms.isEmpty ? '' : ' (${terms.length} terms)';
    return exceptions.isEmpty
        ? '${restrictionId.name}$own'
        : '${restrictionId.name}$own (except ${exceptions.join(', ')})';
  }
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
  /// [ProfileEntry.normaliseExceptions]. The user's own restriction
  /// ([RestrictionId.custom]) reads its `terms` the same way
  /// ([ProfileEntry.normaliseTerms]) and is dropped when none is left,
  /// since it means nothing without them; `terms` on any other entry is
  /// ignored.
  factory tryFrom(Object? json) {
    if (json is! List<Object?>) return empty;
    final entries = <ProfileEntry>[];
    final seen = <RestrictionId>{};
    for (final item in json) {
      if (item is! Map<String, Object?>) continue;
      final rawId = item['id'];
      if (rawId is! String) continue;
      final id = RestrictionId.tryParse(rawId);
      if (id == null || seen.contains(id)) continue;
      final rawExceptions = item['exceptions'];
      final exceptions = rawExceptions is List<Object?>
          ? rawExceptions.whereType<String>()
          : const <String>[];
      final rawTerms = item['terms'];
      final terms = id == RestrictionId.custom && rawTerms is List<Object?>
          ? ProfileEntry.normaliseTerms(rawTerms.whereType<String>())
          : const <String>[];
      if (id == RestrictionId.custom && terms.isEmpty) continue;
      seen.add(id);
      entries.add(
        ProfileEntry(
          restrictionId: id,
          exceptions: ProfileEntry.normaliseExceptions(exceptions),
          terms: terms,
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

  /// Whether the profile holds a restriction other than keto: what turns
  /// ingredient extraction on (`ClassificationOptions.fromSettings`, D26
  /// C2). Keto alone is today's app, so it asks for nothing more.
  bool get hasNonKetoEntry =>
      entries.any((entry) => entry.restrictionId != RestrictionId.keto);

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
  ///
  /// [terms] are the user's own restriction's words ([ProfileEntry.terms],
  /// normalised by [ProfileEntry.normaliseTerms]), kept or replaced the
  /// same way; they are read only for [RestrictionId.custom].
  DietaryProfile withEntry(
    RestrictionId id, {
    List<String>? exceptions,
    List<String>? terms,
  }) {
    final existing = entryFor(id);
    final entry = ProfileEntry(
      restrictionId: id,
      exceptions: exceptions == null
          ? existing?.exceptions ?? const <String>[]
          : ProfileEntry.normaliseExceptions(exceptions),
      terms: id != RestrictionId.custom
          ? const <String>[]
          : terms == null
          ? existing?.terms ?? const <String>[]
          : ProfileEntry.normaliseTerms(terms),
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

  /// The user's own words ([RestrictionId.custom]'s [ProfileEntry.terms]),
  /// in the order added; empty when the profile holds none (ALG-17).
  List<String> get customTerms =>
      entryFor(RestrictionId.custom)?.terms ?? const <String>[];

  /// A copy whose own restriction also holds [term] (ALG-17): the entry is
  /// added last when absent, and [term] goes after the words already
  /// there. The same profile when [term] is blank, already held (ignoring
  /// case) or the entry is full ([ProfileEntry.maxTerms]).
  DietaryProfile withCustomTerm(String term) {
    final held = customTerms;
    final next = ProfileEntry.normaliseTerms(<String>[...held, term]);
    if (next.length == held.length) return this;
    return withEntry(RestrictionId.custom, terms: next);
  }

  /// A copy whose own restriction no longer holds [term]; the entry itself
  /// goes with its last word. The same profile when [term] is not held.
  DietaryProfile withoutCustomTerm(String term) {
    final held = customTerms;
    if (!held.contains(term)) return this;
    final next = <String>[
      for (final kept in held)
        if (kept != term) kept,
    ];
    return next.isEmpty
        ? withoutEntry(RestrictionId.custom)
        : withEntry(RestrictionId.custom, terms: next);
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

/// The Recent list's own memory: one entry per menu opened on this device
/// (issue #307).
///
/// **This is a list of menus opened on this device, like pins and notes —
/// never a record of the user** (architecture.md D8). An entry names a
/// menu (its [VenueRef], the venue name and city it was shown under) and
/// carries what the Recent list shows for it (when it was first and last
/// opened, how often, its dish count, score and verdict counts). Nothing in
/// it identifies who opened it, and **nothing in it leaves the device
/// through this store**: it is read by the controllers behind the Recent
/// list, the menu screen and Settings, and written to a Hive box on the
/// device, nowhere else.
///
/// Unlike the menu cache, whose entries expire after a day unless pinned,
/// an entry here stays until the user removes it or clears the list, so a
/// menu opened last month is still listed (with its last score) after its
/// cached copy has gone.
///
/// Banto (ALG-14, architecture.md D27) keeps the post-meal answers here
/// too: what the staff said about a dish (`DishConfirmation`) and whether
/// the kitchen made a change (`ChangeConfirmation`), written only when
/// there are some, so a keto build's entries are byte for byte as before.
/// They name a restriction, and like the rest of the entry they stay on
/// the device (D26 C1).
///
/// The Recent tab's per-profile row and "Worked for me" (issues #411,
/// #412) add, each written only under a non-keto profile or after a mark
/// and so absent from every keto entry: the four state counts the menu had
/// for the profile it was opened with and that profile's fingerprint
/// ([VisitSnapshot]), the strict dishes the post-meal prompt asks about once
/// the cached menu has expired, and the people the venue "worked for"
/// ([VisitEntry.workedFor]). Like the rest they never leave the device (D23,
/// D26 C1) and sum into no number (D27).
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:ketoclub/models/dish_confirmation.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/models/visit_dish.dart';
import 'package:ketoclub/services/platform/clock.dart';
import 'package:ketoclub/services/storage/storage_key.dart';

/// What a menu looked like for one profile when it was last opened (Banto,
/// issue #411): the four state counts, a fingerprint of the restrictions
/// they were made for, and the strict dishes the post-meal prompt asks
/// about. Recorded by `MenuController.open` under a non-keto profile only.
@immutable
final class VisitSnapshot {
  /// Creates a snapshot; [strictDishes] is cut to the first
  /// [VisitEntry.maxConfirmations].
  new({
    required this.fits,
    required this.withChange,
    required this.ask,
    required this.avoid,
    required this.profileFingerprint,
    required List<VisitDish> strictDishes,
  }) : strictDishes = List<VisitDish>.unmodifiable(
         strictDishes.take(VisitEntry.maxConfirmations),
       );

  /// Food dishes that fit (for a strict profile: no trigger found).
  final int fits;

  /// Food dishes that fit with a change.
  final int withChange;

  /// Food dishes to ask about.
  final int ask;

  /// Food dishes to avoid.
  final int avoid;

  /// A hash of the sorted restriction ids the counts were made for.
  final String profileFingerprint;

  /// The dishes the profile had a strict concern about, in menu order.
  final List<VisitDish> strictDishes;
}

/// One menu in the visit history: which menu, under what name, when and how
/// often it was opened, and the numbers the Recent list last showed for it.
@immutable
final class VisitEntry {
  /// Creates an entry for [ref].
  const new({
    required this.ref,
    required this.firstOpenedAt,
    required this.lastOpenedAt,
    required this.openCount,
    this.name,
    this.city,
    this.dishCount,
    this.score,
    this.greenCount,
    this.yellowCount,
    this.openedStrict = false,
    this.confirmations = const <DishConfirmation>[],
    this.changeConfirmations = const <ChangeConfirmation>[],
    this.fits,
    this.withChange,
    this.ask,
    this.avoid,
    this.profileFingerprint,
    this.strictDishes,
    this.workedFor = const <String>[],
  });

  /// The most [confirmations] (and, separately, [changeConfirmations]) an
  /// entry keeps; past it the oldest days are dropped first (ALG-14).
  static const int maxConfirmations = 200;

  /// The most people [workedFor] names: a device holds at most this many
  /// profiles.
  static const int maxWorkedFor = 8;

  /// Reads an entry written by [toJson].
  ///
  /// Tolerant by design, so an entry written by a newer or older build still
  /// reads: an unknown field is ignored, and a missing `openCount` reads as
  /// 1 (the entry exists, so the menu was opened at least once). Returns
  /// null for any other shape mismatch — a missing or malformed ref or
  /// timestamp, or a field of the wrong type — and never throws.
  ///
  /// The post-meal answers (ALG-14, D27) are read more tolerantly still,
  /// so a bad one never costs the visit: `openedStrict` is true only when
  /// it is `true`, and a `confirmations` or `changeConfirmations` that is
  /// not a list reads as empty, a malformed answer in it is dropped, and
  /// so is a repeat. The same goes for the Recent tab's fields (#411,
  /// #412): a count that is not an int, a fingerprint that is not a string,
  /// a `strictDishes` that is not a list (a malformed dish in it is dropped,
  /// at most [maxConfirmations] kept) and a `workedFor` that is not a list
  /// of non-empty strings (at most [maxWorkedFor], repeats dropped) each read
  /// as absent.
  static VisitEntry? tryFrom(Map<String, Object?> json) {
    final rawSource = json['source'];
    final rawId = json['platformId'];
    if (rawSource is! String || rawId is! String || rawId.isEmpty) {
      return null;
    }
    final source = MenuSource.tryParse(rawSource);
    if (source == null) return null;
    final first = _readTime(json['firstOpenedAt']);
    final last = _readTime(json['lastOpenedAt']);
    if (first == null || last == null) return null;
    final rawCount = json['openCount'];
    if (rawCount != null && rawCount is! int) return null;
    final name = json['name'];
    final city = json['city'];
    final dishCount = json['dishCount'];
    final score = json['score'];
    final green = json['greenCount'];
    final yellow = json['yellowCount'];
    if (name != null && name is! String) return null;
    if (city != null && city is! String) return null;
    if (dishCount != null && dishCount is! int) return null;
    if (score != null && score is! num) return null;
    if (green != null && green is! int) return null;
    if (yellow != null && yellow is! int) return null;
    return VisitEntry(
      ref: VenueRef(source: source, platformId: rawId),
      name: name as String?,
      city: city as String?,
      firstOpenedAt: first,
      lastOpenedAt: last,
      openCount: rawCount as int? ?? 1,
      dishCount: dishCount as int?,
      score: (score as num?)?.toDouble(),
      greenCount: green as int?,
      yellowCount: yellow as int?,
      openedStrict: json['openedStrict'] == true,
      confirmations: _readList(
        json['confirmations'],
        DishConfirmation.tryFromJson,
      ),
      changeConfirmations: _readList(
        json['changeConfirmations'],
        ChangeConfirmation.tryFromJson,
      ),
      fits: _readCount(json['fits']),
      withChange: _readCount(json['withChange']),
      ask: _readCount(json['ask']),
      avoid: _readCount(json['avoid']),
      profileFingerprint: _readText(json['profileFingerprint']),
      strictDishes: json['strictDishes'] is List<Object?>
          ? _readList(json['strictDishes'], VisitDish.tryFromJson)
          : null,
      workedFor: _readNames(json['workedFor']),
    );
  }

  /// The non-negative count [raw] holds, or null when it holds none.
  static int? _readCount(Object? raw) => raw is int && raw >= 0 ? raw : null;

  /// The non-empty string [raw] holds, or null when it holds none.
  static String? _readText(Object? raw) =>
      raw is String && raw.isNotEmpty ? raw : null;

  /// The distinct non-empty strings [raw] holds, at most [maxWorkedFor];
  /// empty when [raw] is not a list.
  static List<String> _readNames(Object? raw) {
    if (raw is! List<Object?>) return const <String>[];
    final names = <String>[];
    for (final item in raw) {
      if (item is String && item.isNotEmpty && !names.contains(item)) {
        names.add(item);
      }
      if (names.length == maxWorkedFor) break;
    }
    return List<String>.unmodifiable(names);
  }

  /// The records [raw] holds, each read by [read]: malformed ones and
  /// repeats dropped, at most [maxConfirmations] kept; empty when [raw]
  /// is not a list.
  static List<T> _readList<T>(Object? raw, T? Function(Object?) read) {
    if (raw is! List<Object?>) return List<T>.unmodifiable(<T>[]);
    final kept = <T>[];
    for (final item in raw) {
      final value = read(item);
      if (value != null && !kept.contains(value)) kept.add(value);
      if (kept.length == maxConfirmations) break;
    }
    return List<T>.unmodifiable(kept);
  }

  /// The ISO-8601 timestamp [raw] holds, or null when it holds none.
  static DateTime? _readTime(Object? raw) =>
      raw is String ? DateTime.tryParse(raw) : null;

  /// Which menu, on which platform, this entry is for.
  final VenueRef ref;

  /// The venue name the menu was shown under, or null when none is known.
  final String? name;

  /// The city the venue is in, or null when none is known.
  final String? city;

  /// When this menu was first opened on this device.
  final DateTime firstOpenedAt;

  /// When this menu was most recently opened on this device.
  final DateTime lastOpenedAt;

  /// How many times this menu has been opened on this device; at least 1.
  final int openCount;

  /// How many dishes the menu had when last opened, or null when unknown.
  final int? dishCount;

  /// The keto score out of 10 the menu last had, or null when it had none.
  final double? score;

  /// How many dishes the last analysis placed green, or null when unknown.
  final int? greenCount;

  /// How many dishes the last analysis placed yellow, or null when unknown.
  final int? yellowCount;

  /// Whether the menu was ever opened with a strict restriction in the
  /// profile (Banto, ALG-14): what puts the post-meal "Did you ask?"
  /// prompt on its Recent row. A flag, never the restriction (D26 C1).
  final bool openedStrict;

  /// What the staff said about the menu's dishes after a meal (ALG-14,
  /// D27): one answer per dish, restriction, polarity and day. Empty when
  /// none was recorded.
  final List<DishConfirmation> confirmations;

  /// Whether the kitchen made the change asked for, per dish and day
  /// (ALG-14). Empty when none was recorded.
  final List<ChangeConfirmation> changeConfirmations;

  /// How many food dishes fit the profile the menu was last opened with
  /// (Banto, #411); null for a keto entry or one opened before the field.
  final int? fits;

  /// How many food dishes fit with a change, from the same visit as
  /// [fits].
  final int? withChange;

  /// How many food dishes are to be asked about, from the same visit.
  final int? ask;

  /// How many food dishes are to be avoided, from the same visit.
  final int? avoid;

  /// A hash of the sorted restriction ids [fits] and the rest were made for
  /// (`profileFingerprintOf`), so a changed profile reads as "re-check"
  /// rather than as stale numbers; null with them.
  final String? profileFingerprint;

  /// The dishes the profile had a strict concern about when the menu was
  /// last opened, at most [maxConfirmations]: what the post-meal prompt
  /// asks about once the cached menu has gone (#411). Null when none was
  /// recorded (a keto entry, an older one); empty when the menu was read
  /// and held nothing to ask about.
  final List<VisitDish>? strictDishes;

  /// The people this venue "worked for" (Banto, #412): their profile names,
  /// or `Me` for the owner's own unnamed one. Empty when none, and never
  /// written then. A mark is the person's own and a filter only: nothing
  /// sums it into a number (D27).
  final List<String> workedFor;

  /// Whether the four state counts are all recorded.
  bool get hasStates =>
      fits != null && withChange != null && ask != null && avoid != null;

  /// This entry with [name] and [city] replaced (null clears).
  VisitEntry renamed({required String? name, required String? city}) =>
      _copy(name: name, city: city, replaceName: true);

  /// This entry with [workedFor] replaced by [names], repeats dropped and
  /// cut to [maxWorkedFor].
  VisitEntry withWorkedFor(Iterable<String> names) =>
      _copy(workedFor: _readNames(names.toList()));

  /// A copy with the given parts replaced; [name] and [city] only when
  /// [replaceName] (they may be set to null).
  VisitEntry _copy({
    String? name,
    String? city,
    bool replaceName = false,
    List<DishConfirmation>? confirmations,
    List<ChangeConfirmation>? changes,
    List<String>? workedFor,
  }) => VisitEntry(
    ref: ref,
    name: replaceName ? name : this.name,
    city: replaceName ? city : this.city,
    firstOpenedAt: firstOpenedAt,
    lastOpenedAt: lastOpenedAt,
    openCount: openCount,
    dishCount: dishCount,
    score: score,
    greenCount: greenCount,
    yellowCount: yellowCount,
    openedStrict: openedStrict,
    confirmations: confirmations ?? this.confirmations,
    changeConfirmations: changes ?? changeConfirmations,
    fits: fits,
    withChange: withChange,
    ask: ask,
    avoid: avoid,
    profileFingerprint: profileFingerprint,
    strictDishes: strictDishes,
    workedFor: workedFor ?? this.workedFor,
  );

  /// This entry with its post-meal answers replaced by [confirmations] and
  /// [changes], repeats dropped and each cut to the [maxConfirmations]
  /// latest days.
  VisitEntry withConfirmations({
    required List<DishConfirmation> confirmations,
    required List<ChangeConfirmation> changes,
  }) => _copy(
    confirmations: _newest(confirmations, (item) => item.day),
    changes: _newest(changes, (item) => item.day),
  );

  /// [items] without repeats, cut to the [maxConfirmations] whose [day] is
  /// latest, otherwise in their given order.
  static List<T> _newest<T>(List<T> items, DateTime Function(T) day) {
    final unique = <T>[];
    for (final item in items) {
      if (!unique.contains(item)) unique.add(item);
    }
    if (unique.length <= maxConfirmations) {
      return List<T>.unmodifiable(unique);
    }
    final byDay = List<T>.of(unique)..sort((a, b) => day(b).compareTo(day(a)));
    final kept = byDay.take(maxConfirmations).toSet();
    return List<T>.unmodifiable(unique.where(kept.contains));
  }

  /// Writes a form [tryFrom] can read back. A null field is left out, and
  /// so are `openedStrict` when false and the post-meal answers when there
  /// are none (ALG-14), so a keto build's entry is byte for byte what it
  /// was before them.
  Map<String, Object?> toJson() => <String, Object?>{
    'source': ref.source.name,
    'platformId': ref.platformId,
    'name': ?name,
    'city': ?city,
    'firstOpenedAt': firstOpenedAt.toIso8601String(),
    'lastOpenedAt': lastOpenedAt.toIso8601String(),
    'openCount': openCount,
    'dishCount': ?dishCount,
    'score': ?score,
    'greenCount': ?greenCount,
    'yellowCount': ?yellowCount,
    if (openedStrict) 'openedStrict': true,
    if (confirmations.isNotEmpty)
      'confirmations': <Object?>[
        for (final confirmation in confirmations) confirmation.toJson(),
      ],
    if (changeConfirmations.isNotEmpty)
      'changeConfirmations': <Object?>[
        for (final change in changeConfirmations) change.toJson(),
      ],
    'fits': ?fits,
    'withChange': ?withChange,
    'ask': ?ask,
    'avoid': ?avoid,
    'profileFingerprint': ?profileFingerprint,
    if (strictDishes case final dishes?)
      'strictDishes': <Object?>[for (final dish in dishes) dish.toJson()],
    if (workedFor.isNotEmpty) 'workedFor': workedFor,
  };

  @override
  bool operator ==(Object other) =>
      other is VisitEntry &&
      other.ref == ref &&
      other.name == name &&
      other.city == city &&
      other.firstOpenedAt == firstOpenedAt &&
      other.lastOpenedAt == lastOpenedAt &&
      other.openCount == openCount &&
      other.dishCount == dishCount &&
      other.score == score &&
      other.greenCount == greenCount &&
      other.yellowCount == yellowCount &&
      other.openedStrict == openedStrict &&
      listEquals(other.confirmations, confirmations) &&
      listEquals(other.changeConfirmations, changeConfirmations) &&
      other.fits == fits &&
      other.withChange == withChange &&
      other.ask == ask &&
      other.avoid == avoid &&
      other.profileFingerprint == profileFingerprint &&
      listEquals(other.strictDishes, strictDishes) &&
      listEquals(other.workedFor, workedFor);

  @override
  int get hashCode => Object.hash(
    ref,
    name,
    city,
    firstOpenedAt,
    lastOpenedAt,
    openCount,
    dishCount,
    score,
    greenCount,
    yellowCount,
    openedStrict,
    Object.hashAll(confirmations),
    Object.hashAll(changeConfirmations),
    fits,
    withChange,
    ask,
    avoid,
    profileFingerprint,
    strictDishes == null ? null : Object.hashAll(strictDishes!),
    Object.hashAll(workedFor),
  );

  @override
  String toString() => 'VisitEntry(${ref.cacheKey}, opened $openCount×)';
}

/// On-device storage for one [VisitEntry] per [VenueRef] (issue #307,
/// architecture.md D8). See this library's doc comment: a list of menus
/// opened on this device that never leaves it through this store.
///
/// Every method never throws: a storage failure reads back as "nothing
/// recorded" and a failed write is dropped, so a broken history degrades
/// the Recent list instead of crashing the screen above it.
abstract interface class VisitHistoryStore {
  /// The entry recorded for [ref], or null when there is none — including
  /// on a storage failure.
  ///
  /// Never throws.
  Future<VisitEntry?> read(VenueRef ref);

  /// Every recorded entry, in no particular order; a caller wanting them
  /// sorted sorts the list itself. A corrupt entry is left out rather than
  /// failing the whole list.
  ///
  /// Never throws; a storage failure reads as an empty list.
  Future<List<VisitEntry>> entries();

  /// Records that [ref]'s menu was opened now.
  ///
  /// The first visit creates an entry whose first and last opened times
  /// are both now, opened once. A later visit moves the last opened time to
  /// now and counts one more opening, leaving the first opened time alone.
  /// Each of [name], [city], [dishCount], [score], [greenCount] and
  /// [yellowCount] replaces the recorded value when given and keeps it when
  /// null: a null never erases what an earlier visit recorded. In the same
  /// way [openedStrict] (ALG-14) sets [VisitEntry.openedStrict] when true
  /// and keeps it when false, and the post-meal answers are always kept.
  /// A [snapshot] (Banto, #411) replaces the recorded state counts,
  /// fingerprint and strict dishes as a whole when given and keeps them when
  /// null; the people in [VisitEntry.workedFor] are always kept.
  ///
  /// Never throws.
  Future<void> recordVisit(
    VenueRef ref, {
    String? name,
    String? city,
    int? dishCount,
    double? score,
    int? greenCount,
    int? yellowCount,
    bool openedStrict = false,
    VisitSnapshot? snapshot,
  });

  /// Replaces the people [ref]'s entry "worked for" (Banto, #412) with
  /// [names] ([VisitEntry.withWorkedFor]). Does nothing when [ref] has no
  /// entry, so a mark never creates one.
  ///
  /// Never throws.
  Future<void> setWorkedFor(VenueRef ref, Iterable<String> names);

  /// Replaces the post-meal answers recorded for [ref] (ALG-14, D27) with
  /// [confirmations] and [changes] ([VisitEntry.withConfirmations]). Does
  /// nothing when [ref] has no entry, so an answer never creates one.
  ///
  /// Never throws.
  Future<void> setConfirmations(
    VenueRef ref, {
    required List<DishConfirmation> confirmations,
    required List<ChangeConfirmation> changes,
  });

  /// Replaces both the name and the city recorded for [ref] with [name] and
  /// [city]; a null clears that field. Does nothing when [ref] has no
  /// entry, so a rename never creates one.
  ///
  /// Never throws.
  Future<void> rename(
    VenueRef ref, {
    required String? name,
    required String? city,
  });

  /// Removes the entry for [ref], leaving every other entry untouched. A
  /// no-op when there is none.
  ///
  /// Never throws.
  Future<void> remove(VenueRef ref);

  /// Removes every entry.
  ///
  /// Never throws.
  Future<void> clear();
}

/// [existing] updated by one more visit at [now] (see
/// [VisitHistoryStore.recordVisit]), or a first visit when it is null.
VisitEntry visitAfterOpening(
  VisitEntry? existing,
  VenueRef ref,
  DateTime now, {
  String? name,
  String? city,
  int? dishCount,
  double? score,
  int? greenCount,
  int? yellowCount,
  bool openedStrict = false,
  VisitSnapshot? snapshot,
}) => VisitEntry(
  ref: ref,
  name: name ?? existing?.name,
  city: city ?? existing?.city,
  firstOpenedAt: existing?.firstOpenedAt ?? now,
  lastOpenedAt: now,
  openCount: existing == null ? 1 : existing.openCount + 1,
  dishCount: dishCount ?? existing?.dishCount,
  score: score ?? existing?.score,
  greenCount: greenCount ?? existing?.greenCount,
  yellowCount: yellowCount ?? existing?.yellowCount,
  openedStrict: openedStrict || (existing?.openedStrict ?? false),
  confirmations: existing?.confirmations ?? const <DishConfirmation>[],
  changeConfirmations:
      existing?.changeConfirmations ?? const <ChangeConfirmation>[],
  fits: snapshot?.fits ?? existing?.fits,
  withChange: snapshot?.withChange ?? existing?.withChange,
  ask: snapshot?.ask ?? existing?.ask,
  avoid: snapshot?.avoid ?? existing?.avoid,
  profileFingerprint:
      snapshot?.profileFingerprint ?? existing?.profileFingerprint,
  strictDishes: snapshot?.strictDishes ?? existing?.strictDishes,
  workedFor: existing?.workedFor ?? const <String>[],
);

/// A [VisitHistoryStore] in a Hive box of JSON strings, one per venue,
/// keyed by [storageKeyFor] so no key passes Hive's 255-byte limit (issue
/// #280).
///
/// The box is supplied as a lazily-invoked opener rather than a `Box`,
/// because `di.dart` must not perform plugin I/O while constructing the
/// dependency graph (the same shape as `HiveMenuCache`). The opener is
/// invoked at most once; its result is reused by every later call.
final class HiveVisitHistoryStore implements VisitHistoryStore {
  /// Creates a store over the box [openBox] returns, stamping visits with
  /// [clock].
  new({required this.openBox, required this.clock});

  /// Opens (or creates) the backing box. Invoked at most once; see
  /// [_openedBox].
  final Future<Box<String>> Function() openBox;

  /// The only source of "now" for [recordVisit].
  final Clock clock;

  /// The box, once opened. Holds the in-flight (or completed) future so
  /// nothing here touches the box before [openBox] has actually run.
  Future<Box<String>>? _box;

  /// Returns the box, opening it via [openBox] on the first call and
  /// reusing that result on every later call.
  Future<Box<String>> _openedBox() => _box ??= openBox();

  /// The box, or null when it cannot be opened.
  Future<Box<String>?> _boxOrNull() async {
    try {
      return await _openedBox();
      // A broken box is a miss, never a throw.
      // ignore: avoid_catching_errors
    } on HiveError {
      return null;
    }
  }

  /// Decodes one stored value, or null when it is corrupt.
  static VisitEntry? _decode(String? raw) {
    if (raw == null) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, Object?>) return null;
    return VisitEntry.tryFrom(decoded);
  }

  /// Stores [entry] under its ref's storage key; a failed write is dropped.
  Future<void> _put(Box<String> box, VisitEntry entry) async {
    try {
      await box.put(storageKeyFor(entry.ref), jsonEncode(entry.toJson()));
      // Drop the write; a broken box degrades instead of throwing.
      // ignore: avoid_catching_errors
    } on HiveError {
      // Nothing to do: the write above never landed.
    }
  }

  /// The entry stored in [box] for [ref], or null.
  static VisitEntry? _get(Box<String> box, VenueRef ref) {
    try {
      return _decode(box.get(storageKeyFor(ref)));
      // A broken box is a miss, never a throw.
      // ignore: avoid_catching_errors
    } on HiveError {
      return null;
    }
  }

  @override
  Future<VisitEntry?> read(VenueRef ref) async {
    final box = await _boxOrNull();
    if (box == null) return null;
    return _get(box, ref);
  }

  @override
  Future<List<VisitEntry>> entries() async {
    final box = await _boxOrNull();
    if (box == null) return const <VisitEntry>[];
    final List<String> raw;
    try {
      raw = box.values.toList();
      // A closed or otherwise broken box reads as empty, never throws.
      // ignore: avoid_catching_errors
    } on HiveError {
      return const <VisitEntry>[];
    }
    return <VisitEntry>[...raw.map(_decode).nonNulls];
  }

  @override
  Future<void> recordVisit(
    VenueRef ref, {
    String? name,
    String? city,
    int? dishCount,
    double? score,
    int? greenCount,
    int? yellowCount,
    bool openedStrict = false,
    VisitSnapshot? snapshot,
  }) async {
    final box = await _boxOrNull();
    if (box == null) return;
    await _put(
      box,
      visitAfterOpening(
        _get(box, ref),
        ref,
        clock.now(),
        name: name,
        city: city,
        dishCount: dishCount,
        score: score,
        greenCount: greenCount,
        yellowCount: yellowCount,
        openedStrict: openedStrict,
        snapshot: snapshot,
      ),
    );
  }

  @override
  Future<void> setWorkedFor(VenueRef ref, Iterable<String> names) async {
    final box = await _boxOrNull();
    if (box == null) return;
    final existing = _get(box, ref);
    if (existing == null) return;
    await _put(box, existing.withWorkedFor(names));
  }

  @override
  Future<void> setConfirmations(
    VenueRef ref, {
    required List<DishConfirmation> confirmations,
    required List<ChangeConfirmation> changes,
  }) async {
    final box = await _boxOrNull();
    if (box == null) return;
    final existing = _get(box, ref);
    if (existing == null) return;
    await _put(
      box,
      existing.withConfirmations(
        confirmations: confirmations,
        changes: changes,
      ),
    );
  }

  @override
  Future<void> rename(
    VenueRef ref, {
    required String? name,
    required String? city,
  }) async {
    final box = await _boxOrNull();
    if (box == null) return;
    final existing = _get(box, ref);
    if (existing == null) return;
    await _put(box, existing.renamed(name: name, city: city));
  }

  @override
  Future<void> remove(VenueRef ref) async {
    final box = await _boxOrNull();
    if (box == null) return;
    try {
      await box.delete(storageKeyFor(ref));
      // An entry that cannot be deleted just stays listed.
      // ignore: avoid_catching_errors
    } on HiveError {
      // Nothing to do: the delete above never landed.
    }
  }

  @override
  Future<void> clear() async {
    final box = await _boxOrNull();
    if (box == null) return;
    try {
      await box.clear();
      // An unclearable box just keeps its entries.
      // ignore: avoid_catching_errors
    } on HiveError {
      // Nothing to do: the clear above never landed.
    }
  }
}

/// A [VisitHistoryStore] that remembers nothing: reads answer null, lists
/// are empty and writes are ignored. The no-I/O default for a dependency set
/// that does not care about history (tests, and any caller built before
/// issue #307).
final class NoVisitHistoryStore implements VisitHistoryStore {
  /// Creates the store that remembers nothing.
  const new();

  @override
  Future<VisitEntry?> read(VenueRef ref) async => null;

  @override
  Future<List<VisitEntry>> entries() async => const <VisitEntry>[];

  @override
  Future<void> recordVisit(
    VenueRef ref, {
    String? name,
    String? city,
    int? dishCount,
    double? score,
    int? greenCount,
    int? yellowCount,
    bool openedStrict = false,
    VisitSnapshot? snapshot,
  }) async {}

  @override
  Future<void> setWorkedFor(VenueRef ref, Iterable<String> names) async {}

  @override
  Future<void> setConfirmations(
    VenueRef ref, {
    required List<DishConfirmation> confirmations,
    required List<ChangeConfirmation> changes,
  }) async {}

  @override
  Future<void> rename(
    VenueRef ref, {
    required String? name,
    required String? city,
  }) async {}

  @override
  Future<void> remove(VenueRef ref) async {}

  @override
  Future<void> clear() async {}
}

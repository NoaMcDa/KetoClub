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
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/platform/clock.dart';

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
  });

  /// Reads an entry written by [toJson].
  ///
  /// Tolerant by design, so an entry written by a newer or older build still
  /// reads: an unknown field is ignored, and a missing `openCount` reads as
  /// 1 (the entry exists, so the menu was opened at least once). Returns
  /// null for any other shape mismatch — a missing or malformed ref or
  /// timestamp, or a field of the wrong type — and never throws.
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
    );
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

  /// Writes a form [tryFrom] can read back. A null field is left out.
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
      other.yellowCount == yellowCount;

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
  /// null: a null never erases what an earlier visit recorded.
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
VisitEntry _visitAfterOpening(
  VisitEntry? existing,
  VenueRef ref,
  DateTime now, {
  String? name,
  String? city,
  int? dishCount,
  double? score,
  int? greenCount,
  int? yellowCount,
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
);

/// [existing] with its name and city replaced by [name] and [city] (see
/// [VisitHistoryStore.rename]).
VisitEntry _visitRenamed(
  VisitEntry existing, {
  required String? name,
  required String? city,
}) => VisitEntry(
  ref: existing.ref,
  name: name,
  city: city,
  firstOpenedAt: existing.firstOpenedAt,
  lastOpenedAt: existing.lastOpenedAt,
  openCount: existing.openCount,
  dishCount: existing.dishCount,
  score: existing.score,
  greenCount: existing.greenCount,
  yellowCount: existing.yellowCount,
);

/// A [VisitHistoryStore] in a Hive box of JSON strings, one per
/// [VenueRef.cacheKey].
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

  /// Stores [entry] under its ref's cache key; a failed write is dropped.
  Future<void> _put(Box<String> box, VisitEntry entry) async {
    try {
      await box.put(entry.ref.cacheKey, jsonEncode(entry.toJson()));
      // Drop the write; a broken box degrades instead of throwing.
      // ignore: avoid_catching_errors
    } on HiveError {
      // Nothing to do: the write above never landed.
    }
  }

  /// The entry stored in [box] for [ref], or null.
  static VisitEntry? _get(Box<String> box, VenueRef ref) {
    try {
      return _decode(box.get(ref.cacheKey));
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
  }) async {
    final box = await _boxOrNull();
    if (box == null) return;
    await _put(
      box,
      _visitAfterOpening(
        _get(box, ref),
        ref,
        clock.now(),
        name: name,
        city: city,
        dishCount: dishCount,
        score: score,
        greenCount: greenCount,
        yellowCount: yellowCount,
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
    await _put(box, _visitRenamed(existing, name: name, city: city));
  }

  @override
  Future<void> remove(VenueRef ref) async {
    final box = await _boxOrNull();
    if (box == null) return;
    try {
      await box.delete(ref.cacheKey);
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

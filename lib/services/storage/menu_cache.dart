import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/utils/verdict_counts.dart';

/// The reason whose `name` equals [wire], or null when none does.
///
/// Matches by string, never by ordinal, so reordering
/// [MenuAnalysisFailureReason] cannot silently re-map cached data. A
/// private copy of the same helper `models/analysis.dart` keeps for
/// itself: `models/failures.dart` declares no members beyond the enum
/// values, and this file must not edit the frozen `models/` sources to
/// add one.
MenuAnalysisFailureReason? _tryParseFailureReason(String wire) {
  for (final reason in MenuAnalysisFailureReason.values) {
    if (reason.name == wire) return reason;
  }
  return null;
}

/// Reads a [MenuAnalysis] written by [_analysisToJson].
///
/// Returns null for any shape mismatch and never throws.
MenuAnalysis? _analysisFrom(Map<String, Object?> json) {
  final kind = json['kind'];
  if (kind is! String) return null;
  if (kind == 'analysed') return MenuAnalysed.tryFrom(json);
  if (kind == 'failed') {
    final rawReason = json['reason'];
    final rawDetail = json['detail'];
    if (rawReason is! String) return null;
    final reason = _tryParseFailureReason(rawReason);
    if (reason == null) return null;
    if (rawDetail != null && rawDetail is! String) return null;
    return MenuAnalysisFailed(
      reason: reason,
      detail: rawDetail is String ? rawDetail : null,
    );
  }
  return null;
}

/// Writes [analysis] in a form [_analysisFrom] can read back, tagging it
/// with a `kind` discriminator since `MenuAnalysis` is sealed over two
/// unrelated shapes.
Map<String, Object?> _analysisToJson(MenuAnalysis analysis) =>
    switch (analysis) {
      final MenuAnalysed analysed => <String, Object?>{
        'kind': 'analysed',
        ...analysed.toJson(),
      },
      final MenuAnalysisFailed failed => <String, Object?>{
        'kind': 'failed',
        ...failed.toJson(),
      },
    };

/// A menu and its analysis as one cache entry (architecture.md §6.4):
/// `venueRef -> {menu, analysis, fetchedAt, engine}`. [Menu.fetchedAt]
/// carries `fetchedAt` and, when [analysis] is a [MenuAnalysed],
/// [MenuAnalysed.engine] carries `engine`, so this type adds no field for
/// either.
@immutable
final class CachedMenu {
  /// Creates an entry for [menu], with [analysis] once one has been
  /// computed from it.
  const new({required this.menu, this.analysis});

  /// Reads an entry written by [toJson].
  ///
  /// Returns null for any shape mismatch, including a malformed [menu] or
  /// [analysis], and never throws.
  static CachedMenu? tryFrom(Map<String, Object?> json) {
    final rawMenu = json['menu'];
    final rawAnalysis = json['analysis'];
    if (rawMenu is! Map<String, Object?>) return null;
    final menu = Menu.tryFrom(rawMenu);
    if (menu == null) return null;
    if (rawAnalysis == null) return CachedMenu(menu: menu);
    if (rawAnalysis is! Map<String, Object?>) return null;
    final analysis = _analysisFrom(rawAnalysis);
    if (analysis == null) return null;
    return CachedMenu(menu: menu, analysis: analysis);
  }

  /// The cached menu.
  final Menu menu;

  /// The cached analysis, or null when [menu] has not been analysed yet.
  final MenuAnalysis? analysis;

  /// Writes a form [tryFrom] can read back.
  Map<String, Object?> toJson() => <String, Object?>{
    'menu': menu.toJson(),
    'analysis': analysis == null ? null : _analysisToJson(analysis!),
  };

  @override
  bool operator ==(Object other) =>
      other is CachedMenu && other.menu == menu && other.analysis == analysis;

  @override
  int get hashCode => Object.hash(menu, analysis);

  @override
  String toString() => 'CachedMenu(${menu.venueRef.cacheKey})';
}

/// One [CachedMenu] summarised for a list of every cached menu (issue #48's
/// Saved tab), without the dishes, categories or full analysis a screen
/// listing many entries has no use for.
///
/// [engine] is non-null exactly when the cached entry's analysis is a
/// [MenuAnalysed] — a failed analysis, or no analysis at all, both read as
/// null here, and a caller after only "was this analysed" reads that off
/// [analysed] rather than testing [engine] for null itself.
@immutable
final class CachedMenuEntry {
  /// Creates a summary for [ref], as fetched at [fetchedAt].
  const new({
    required this.ref,
    required this.venueName,
    required this.fetchedAt,
    required this.dishCount,
    required this.engine,
    this.score,
    this.greenCount = 0,
    this.yellowCount = 0,
    this.pinned = false,
  });

  /// Summarises [cached] for the Saved list: its venue, fetch time, dish
  /// count, engine, and — from a completed analysis that placed at least
  /// one dish — the keto score and verdict counts the Explore venue card
  /// shows for the same menu (`ketoScore`, architecture.md D13).
  ///
  /// [pinned] is whether the user asked to keep the entry past the cache
  /// window ([MenuCache.pin]); it is not part of [cached], which never
  /// carries it.
  // A named constructor still needs its class name (see `VerdictTone.lerp`).
  // ignore: unnecessary_type_name_in_constructor
  factory CachedMenuEntry.summarise(CachedMenu cached, {bool pinned = false}) {
    final analysis = cached.analysis;
    final menu = cached.menu;
    if (analysis is! MenuAnalysed) {
      return CachedMenuEntry(
        ref: menu.venueRef,
        venueName: menu.venueName,
        fetchedAt: menu.fetchedAt,
        dishCount: menu.allDishes.length,
        engine: null,
        pinned: pinned,
      );
    }
    // Food only (D21): a drink or an extra is listed but never counted.
    final counts = VerdictCounts.of(menu, analysis);
    final score = counts.score;
    return CachedMenuEntry(
      ref: menu.venueRef,
      venueName: menu.venueName,
      fetchedAt: menu.fetchedAt,
      dishCount: menu.allDishes.length,
      engine: analysis.engine,
      score: score,
      greenCount: score == null ? 0 : counts.green,
      yellowCount: score == null ? 0 : counts.yellow,
      pinned: pinned,
    );
  }

  /// Which venue, on which platform, this entry is for.
  final VenueRef ref;

  /// The venue name from the cached [Menu], or null when the source
  /// platform did not supply one ([Menu.venueName]'s own doc comment).
  final String? venueName;

  /// When the cached menu was fetched ([Menu.fetchedAt]) — not when it was
  /// last opened; [MenuCache] tracks no separate "last opened" timestamp.
  final DateTime fetchedAt;

  /// How many dishes the cached menu has, across every category.
  final int dishCount;

  /// Which engine produced the cached analysis, or null when the entry
  /// has none, or has only a failed one.
  final AnalysisEngine? engine;

  /// The keto score out of 10 for the cached analysis, or null when the
  /// entry has no completed analysis or it placed no dish — never a
  /// fabricated `0.0` (see `ketoScore`).
  final double? score;

  /// How many dishes the cached analysis placed green; 0 when [score] is
  /// null.
  final int greenCount;

  /// How many dishes the cached analysis placed yellow; 0 when [score] is
  /// null.
  final int yellowCount;

  /// Whether the user asked to keep this entry past the cache window
  /// ([MenuCache.pin]), exempting it from expiry.
  final bool pinned;

  /// Whether the cached menu carries a completed ([MenuAnalysed]) analysis.
  bool get analysed => engine != null;

  /// This entry with [pinned] replaced.
  CachedMenuEntry withPinned({required bool pinned}) => CachedMenuEntry(
    ref: ref,
    venueName: venueName,
    fetchedAt: fetchedAt,
    dishCount: dishCount,
    engine: engine,
    score: score,
    greenCount: greenCount,
    yellowCount: yellowCount,
    pinned: pinned,
  );

  @override
  bool operator ==(Object other) =>
      other is CachedMenuEntry &&
      other.ref == ref &&
      other.venueName == venueName &&
      other.fetchedAt == fetchedAt &&
      other.dishCount == dishCount &&
      other.engine == engine &&
      other.score == score &&
      other.greenCount == greenCount &&
      other.yellowCount == yellowCount &&
      other.pinned == pinned;

  @override
  int get hashCode => Object.hash(
    ref,
    venueName,
    fetchedAt,
    dishCount,
    engine,
    score,
    greenCount,
    yellowCount,
    pinned,
  );

  @override
  String toString() => 'CachedMenuEntry(${ref.cacheKey}, $dishCount dishes)';
}

/// On-device storage for one [CachedMenu] per [VenueRef] (architecture.md
/// §6.4). Backed by Hive; a storage failure reads back as a miss, never a
/// throw, so a broken cache degrades instead of crashing the repository
/// above it.
abstract interface class MenuCache {
  /// The entry cached for [ref], or null on a miss — including a storage
  /// failure, which reads the same as "never cached".
  ///
  /// Never throws.
  Future<CachedMenu?> read(VenueRef ref);

  /// Stores [entry] under its [CachedMenu.menu]'s [Menu.venueRef],
  /// replacing any previous entry for that ref.
  ///
  /// Never throws.
  Future<void> write(CachedMenu entry);

  /// Empties the cache entirely.
  ///
  /// Never throws.
  Future<void> clear();

  /// How many menus are currently cached — one per distinct [VenueRef]
  /// that has been [write]n and not since removed by [clear].
  ///
  /// This is a count of entries, not a count of bytes. Hive's `Box`
  /// reports how many keys it holds, not the on-disk size of the box
  /// file, and on web — where the box lives in IndexedDB rather than a
  /// file at all — there is no file to size in the first place, so a
  /// byte figure would be fabricated on at least one platform this app
  /// ships on (architecture.md §6.4). Issue #61's "Saved menus section
  /// in Settings: count, size, clear" is read as wanting this entry
  /// count for "size": how many menus the section can offer to clear,
  /// not their storage footprint.
  ///
  /// Never throws; a storage failure reads as `0`, the same as an empty
  /// cache.
  Future<int> size();

  /// A [CachedMenuEntry] for every menu currently cached, in no
  /// particular order — a caller wanting them sorted (issue #48's Saved
  /// tab shows newest first) sorts this list itself.
  ///
  /// A corrupt entry is left out rather than failing the whole list,
  /// matching [read]'s "a broken box degrades" rule. Never throws; a
  /// storage failure reads as an empty list.
  Future<List<CachedMenuEntry>> entries();

  /// How many menus are currently cached — the same figure [size] already
  /// reports. Added under its own name for issue #61's Settings section,
  /// which reads plainly as "count, size, clear" and would otherwise have
  /// to call a method named for the wrong one of those three words.
  ///
  /// Never throws; a storage failure reads as `0`.
  Future<int> count();

  /// Deletes the single entry cached for [ref], leaving every other entry
  /// untouched. A no-op, not a throw, when nothing is cached for [ref] —
  /// the same "already gone" tolerance [clear] has for an empty cache.
  ///
  /// Never throws.
  Future<void> remove(VenueRef ref);

  /// Keeps ([pinned] true) or stops keeping ([pinned] false) the entry
  /// cached for [ref] past the cache window: a pinned entry is exempt
  /// from expiry, so the repository serves it without refetching until
  /// the user asks for a refresh. A pin is a flag on a menu, never a user
  /// record (architecture.md D8).
  ///
  /// A no-op when nothing is cached for [ref], so a pin never outlives its
  /// menu. [remove] and [clear] drop the pin along with the entry. Never
  /// throws.
  Future<void> pin(VenueRef ref, {bool pinned = true});

  /// Whether the entry cached for [ref] is pinned ([pin]). False for a
  /// ref with no entry, and on a storage failure. Never throws.
  Future<bool> isPinned(VenueRef ref);
}

/// A [MenuCache] in a Hive box of JSON strings.
///
/// The box is supplied as a lazily-invoked opener rather than a `Box`,
/// because `di.dart` must not perform plugin I/O while constructing the
/// dependency graph: `buildDependencies()` is called from `main()` and
/// from tests that run without a plugin binding. The opener is invoked at
/// most once; its result is cached and reused by every later call.
///
/// Pins ([pin]) live in a second, tiny box ([openPinBox]) of cache keys
/// rather than inside the entries, so the entry JSON, and with it every
/// box already on a device, is unchanged: no schema migration.
final class HiveMenuCache implements MenuCache {
  /// Creates a cache over the box [openBox] returns, keeping pins in the
  /// box [openPinBox] returns.
  ///
  /// With no [openPinBox] pins are held in memory for this instance only;
  /// `di.dart` always supplies one.
  new({required this.openBox, this.openPinBox});

  /// Opens (or creates) the backing box. Invoked at most once; see
  /// [_box].
  final Future<Box<String>> Function() openBox;

  /// Opens (or creates) the box of pinned cache keys, or null to keep pins
  /// in memory only. Invoked at most once; see [_pinBox].
  final Future<Box<String>> Function()? openPinBox;

  /// The pinned cache keys when [openPinBox] is null.
  final Set<String> _memoryPins = <String>{};

  /// The pin box, once opened (the same lazy-once shape as [_box]).
  Future<Box<String>>? _pinBox;

  Future<Box<String>>? _openedPinBox() {
    final open = openPinBox;
    if (open == null) return null;
    return _pinBox ??= open();
  }

  /// The pinned cache keys; empty on a storage failure.
  Future<Set<String>> _pinnedKeys() async {
    final opened = _openedPinBox();
    if (opened == null) return Set<String>.of(_memoryPins);
    try {
      final box = await opened;
      return box.keys.whereType<String>().toSet();
      // A broken box reads as "nothing pinned", never a throw.
      // ignore: avoid_catching_errors
    } on HiveError {
      return <String>{};
    }
  }

  /// Records or forgets the pin for [key]; a failed write is dropped.
  Future<void> _setPinKey(String key, {required bool pinned}) async {
    final opened = _openedPinBox();
    if (opened == null) {
      pinned ? _memoryPins.add(key) : _memoryPins.remove(key);
      return;
    }
    try {
      final box = await opened;
      if (pinned) {
        await box.put(key, 'pinned');
      } else {
        await box.delete(key);
      }
      // A pin that cannot be stored is dropped; the entry still expires.
      // ignore: avoid_catching_errors
    } on HiveError {
      // Nothing to do: the pin write above never landed.
    }
  }

  /// Forgets every pin.
  Future<void> _clearPins() async {
    final opened = _openedPinBox();
    if (opened == null) {
      _memoryPins.clear();
      return;
    }
    try {
      await (await opened).clear();
      // An unclearable pin box leaves harmless keys for absent entries.
      // ignore: avoid_catching_errors
    } on HiveError {
      // Nothing to do: the clear above never landed.
    }
  }

  /// The box, once opened. Holds the in-flight (or completed) future
  /// rather than a `Box` directly, so nothing here touches the box before
  /// [openBox] has actually run.
  Future<Box<String>>? _box;

  /// Returns the box, opening it via [openBox] on the first call and
  /// reusing that result on every later call.
  Future<Box<String>> _openedBox() => _box ??= openBox();

  @override
  Future<CachedMenu?> read(VenueRef ref) async {
    final Box<String> box;
    try {
      box = await _openedBox();
      // A broken box is a miss, never a throw (architecture.md §6.4).
      // ignore: avoid_catching_errors
    } on HiveError {
      return null;
    }
    String? raw;
    try {
      raw = box.get(ref.cacheKey);
      // A broken box is a miss, never a throw (architecture.md §6.4).
      // ignore: avoid_catching_errors
    } on HiveError {
      return null;
    }
    if (raw == null) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, Object?>) return null;
    return CachedMenu.tryFrom(decoded);
  }

  @override
  Future<void> write(CachedMenu entry) async {
    final Box<String> box;
    try {
      box = await _openedBox();
      // A broken box drops the write, never throws (architecture.md §6.4).
      // ignore: avoid_catching_errors
    } on HiveError {
      return;
    }
    final key = entry.menu.venueRef.cacheKey;
    final value = jsonEncode(entry.toJson());
    try {
      await box.put(key, value);
      // Drop the write; a broken box degrades instead of throwing.
      // ignore: avoid_catching_errors
    } on HiveError {
      // Nothing to do: the write above never landed.
    }
  }

  @override
  Future<void> clear() async {
    final Box<String> box;
    try {
      box = await _openedBox();
      // Nothing to clear if the box itself never opened.
      // ignore: avoid_catching_errors
    } on HiveError {
      return;
    }
    try {
      await box.clear();
      // An unclearable box just keeps its stale entries.
      // ignore: avoid_catching_errors
    } on HiveError {
      // Nothing to do: the clear above never landed.
    }
    // Settings' "Clear" clears everything, pinned entries included.
    await _clearPins();
  }

  @override
  Future<void> remove(VenueRef ref) async {
    final Box<String> box;
    try {
      box = await _openedBox();
      // Nothing to remove if the box itself never opened.
      // ignore: avoid_catching_errors
    } on HiveError {
      return;
    }
    try {
      await box.delete(ref.cacheKey);
      // An entry that cannot be deleted just stays stale.
      // ignore: avoid_catching_errors
    } on HiveError {
      // Nothing to do: the delete above never landed.
    }
    await _setPinKey(ref.cacheKey, pinned: false);
  }

  @override
  Future<void> pin(VenueRef ref, {bool pinned = true}) async {
    if (pinned) {
      final Box<String> box;
      try {
        box = await _openedBox();
        if (!box.containsKey(ref.cacheKey)) return;
        // A broken box cannot hold a pin for a menu it cannot read.
        // ignore: avoid_catching_errors
      } on HiveError {
        return;
      }
    }
    await _setPinKey(ref.cacheKey, pinned: pinned);
  }

  @override
  Future<bool> isPinned(VenueRef ref) async =>
      (await _pinnedKeys()).contains(ref.cacheKey);

  @override
  Future<int> size() async {
    final Box<String> box;
    try {
      box = await _openedBox();
      // A box that never opened holds nothing readable: 0, not a throw.
      // ignore: avoid_catching_errors
    } on HiveError {
      return 0;
    }
    try {
      return box.length;
      // A closed or otherwise broken box reads as empty, never throws.
      // ignore: avoid_catching_errors
    } on HiveError {
      return 0;
    }
  }

  @override
  Future<int> count() => size();

  @override
  Future<List<CachedMenuEntry>> entries() async {
    final Box<String> box;
    try {
      box = await _openedBox();
      // A box that never opened holds nothing readable: [], not a throw.
      // ignore: avoid_catching_errors
    } on HiveError {
      return const <CachedMenuEntry>[];
    }
    List<String> raw;
    try {
      raw = box.values.toList();
      // A closed or otherwise broken box reads as empty, never throws.
      // ignore: avoid_catching_errors
    } on HiveError {
      return const <CachedMenuEntry>[];
    }
    final pins = await _pinnedKeys();
    final result = <CachedMenuEntry>[];
    for (final value in raw) {
      final Object? decoded;
      try {
        decoded = jsonDecode(value);
      } on FormatException {
        continue;
      }
      if (decoded is! Map<String, Object?>) continue;
      final cached = CachedMenu.tryFrom(decoded);
      if (cached == null) continue;
      result.add(
        CachedMenuEntry.summarise(
          cached,
          pinned: pins.contains(cached.menu.venueRef.cacheKey),
        ),
      );
    }
    return result;
  }
}

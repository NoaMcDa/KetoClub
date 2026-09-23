import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';

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
  });

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

  /// Whether the cached menu carries a completed ([MenuAnalysed]) analysis.
  bool get analysed => engine != null;

  @override
  bool operator ==(Object other) =>
      other is CachedMenuEntry &&
      other.ref == ref &&
      other.venueName == venueName &&
      other.fetchedAt == fetchedAt &&
      other.dishCount == dishCount &&
      other.engine == engine;

  @override
  int get hashCode => Object.hash(ref, venueName, fetchedAt, dishCount, engine);

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
}

/// A [MenuCache] in a Hive box of JSON strings.
///
/// The box is supplied as a lazily-invoked opener rather than a `Box`,
/// because `di.dart` must not perform plugin I/O while constructing the
/// dependency graph: `buildDependencies()` is called from `main()` and
/// from tests that run without a plugin binding. The opener is invoked at
/// most once; its result is cached and reused by every later call.
final class HiveMenuCache implements MenuCache {
  /// Creates a cache over the box [openBox] returns.
  new({required this.openBox});

  /// Opens (or creates) the backing box. Invoked at most once; see
  /// [_box].
  final Future<Box<String>> Function() openBox;

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
  }

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
        CachedMenuEntry(
          ref: cached.menu.venueRef,
          venueName: cached.menu.venueName,
          fetchedAt: cached.menu.fetchedAt,
          dishCount: cached.menu.allDishes.length,
          engine: switch (cached.analysis) {
            final MenuAnalysed analysed => analysed.engine,
            _ => null,
          },
        ),
      );
    }
    return result;
  }
}

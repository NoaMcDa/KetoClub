import 'package:flutter/foundation.dart';
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
}

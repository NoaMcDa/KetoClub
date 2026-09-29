import 'package:flutter/foundation.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/scanned_menu.dart';
import 'package:ketoclub/services/classifier/menu_classifier.dart';

/// What one [ScannedMenuClassifier.classify] call produced (architecture.md
/// §6.2, D15; issue #89).
///
/// Sealed, so a caller's `switch` must handle both outcomes.
@immutable
sealed class ScannedMenuResult {
  /// Lets the two outcomes be `const`.
  const new();
}

/// The pages were read and classified: [menu] is the transcription and
/// [analysis] its verdicts, from the same one request.
///
/// [menu] carries a `VenueRef` whose source is `MenuSource.scan` and no
/// page bytes at all, so it can be stored and cached like a pasted menu;
/// the pages themselves stay with the caller.
final class ScannedMenuRead extends ScannedMenuResult {
  /// Creates a successful read of [menu], classified as [analysis].
  const new({required this.menu, required this.analysis});

  /// The dishes transcribed from the pages.
  final Menu menu;

  /// The verdicts for [menu]'s dishes.
  final MenuAnalysed analysis;

  @override
  bool operator ==(Object other) =>
      other is ScannedMenuRead &&
      other.menu == menu &&
      other.analysis == analysis;

  @override
  int get hashCode => Object.hash(menu, analysis);

  @override
  String toString() => 'ScannedMenuRead(${menu.venueRef.cacheKey})';
}

/// The pages could not be read or classified, for [reason].
///
/// There is no rules fallback for a photograph — the rule engine needs
/// text the pages do not have — so every failure reaches the caller.
final class ScannedMenuFailed extends ScannedMenuResult {
  /// Creates a failure for [reason].
  const new({required this.reason});

  /// Why the scan produced no menu.
  final MenuAnalysisFailureReason reason;

  @override
  bool operator ==(Object other) =>
      other is ScannedMenuFailed && other.reason == reason;

  @override
  int get hashCode => reason.hashCode;

  @override
  String toString() => 'ScannedMenuFailed($reason)';
}

/// Reads photographed or PDF menu pages and classifies the dishes on them
/// (architecture.md §6.2, D15; issue #89).
///
/// A sibling of [MenuClassifier], not an implementation of it:
/// [MenuClassifier.classify] takes a [Menu], which a photograph does not
/// have yet, and putting the bytes on [Menu] would push them into the
/// Hive cache. A [ScannedMenu] never reaches the cache; the [Menu] a
/// [ScannedMenuRead] returns never carries a byte of it.
abstract interface class ScannedMenuClassifier {
  /// Transcribes and classifies every page of [scan], steered by
  /// [options].
  ///
  /// Never throws: every failure is a [ScannedMenuFailed]. One call per
  /// scan, all pages in one request (D6) — an implementation must not
  /// fan out per page. Any page count, including zero, resolves to a
  /// result; bounding the count and size is the caller's job
  /// (`maxScanPages`, `maxScanPageBytes`).
  Future<ScannedMenuResult> classify(
    ScannedMenu scan, {
    required ClassificationOptions options,
  });
}

/// The [ScannedMenuClassifier] the app ships with until the vision
/// classifier is wired in (issue #89): it answers
/// [MenuAnalysisFailureReason.notConfigured] for every scan, without any
/// I/O, the same reason a build with no way to reach the model reports.
final class UnavailableScannedMenuClassifier implements ScannedMenuClassifier {
  /// Creates the classifier; it holds no state.
  const new();

  @override
  Future<ScannedMenuResult> classify(
    ScannedMenu scan, {
    required ClassificationOptions options,
  }) async =>
      const ScannedMenuFailed(reason: MenuAnalysisFailureReason.notConfigured);
}

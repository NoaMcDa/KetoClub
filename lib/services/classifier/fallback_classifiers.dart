/// Classifiers that try KetoClub's backend first and an on-device engine
/// second (architecture.md D25; issue #328).
library;

import 'package:flutter/foundation.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/scanned_menu.dart';
import 'package:ketoclub/services/classifier/menu_classifier.dart';
import 'package:ketoclub/services/classifier/scanned_menu_classifier.dart';

/// Whether a primary engine's failure for [reason] hands the call to the
/// fallback engine: only when the backend could not answer this call at
/// all — none is configured, it could not be reached, it took too long,
/// or its analysis bucket is empty.
///
/// Every other reason is an answer about the menu itself
/// ([MenuAnalysisFailureReason.noDishesFound]) or a failure the fallback
/// would most likely repeat, so the primary's result stands. An
/// exhaustive switch with no `default`, so a new reason has to be placed
/// on one side or the other deliberately.
bool _shouldFallBack(MenuAnalysisFailureReason reason) {
  switch (reason) {
    case MenuAnalysisFailureReason.notConfigured:
    case MenuAnalysisFailureReason.backendUnreachable:
    case MenuAnalysisFailureReason.timeout:
    case MenuAnalysisFailureReason.rateLimited:
      return true;
    case MenuAnalysisFailureReason.offline:
    case MenuAnalysisFailureReason.badResponse:
    case MenuAnalysisFailureReason.noDishesFound:
    case MenuAnalysisFailureReason.consentWithheld:
    case MenuAnalysisFailureReason.apiKeyMissing:
    case MenuAnalysisFailureReason.apiKeyRejected:
      return false;
  }
}

/// Whether a chain whose fallback failed too reports the fallback's
/// failure rather than [primary], the primary's: only when [primary] said
/// nothing more than that no backend is configured, so the fallback's
/// failure is the one that says why the engine that tried did not answer.
bool _reportsFallback(MenuAnalysisFailureReason primary) =>
    primary == MenuAnalysisFailureReason.notConfigured;

/// A [MenuClassifier] that asks [_primary] first and, only when it could
/// not answer at all, [_fallback] (architecture.md D25).
///
/// The primary is meant to be `BackendMenuClassifier` and the fallback an
/// engine on the device, so that a build or a moment without a reachable
/// backend still classifies. The chain:
///
/// 1. The primary's [MenuAnalysed] is returned as it is — including one
///    the server stamped as rule-based after its own model call failed.
/// 2. A primary failure the fallback is not for
///    ([FallbackMenuClassifier.shouldFallBack] is false) is returned as
///    it is, and the fallback is never asked.
/// 3. Otherwise the fallback answers. Its [MenuAnalysed] is returned; if
///    it fails too, the primary's failure is reported, unless the primary
///    only said [MenuAnalysisFailureReason.notConfigured] — then the
///    fallback's failure is, since it is the one that tried.
///
/// Consent and connectivity are not checked here: put this chain behind
/// a router that checks them, such as `RoutingMenuClassifier`. Both
/// engines get the same `options`, so each announces itself as it starts
/// (#65). Never throws, as neither engine does.
@immutable
final class FallbackMenuClassifier implements MenuClassifier {
  /// Creates a chain asking `primary`, then `fallback`.
  const new({required this._primary, required this._fallback});

  /// Whether a primary failure for [reason] is handed to the fallback:
  /// [MenuAnalysisFailureReason.notConfigured],
  /// [MenuAnalysisFailureReason.backendUnreachable],
  /// [MenuAnalysisFailureReason.timeout] and
  /// [MenuAnalysisFailureReason.rateLimited], and nothing else.
  static bool shouldFallBack(MenuAnalysisFailureReason reason) =>
      _shouldFallBack(reason);

  final MenuClassifier _primary;
  final MenuClassifier _fallback;

  @override
  Future<MenuAnalysis> classify(
    Menu menu, {
    ClassificationOptions options = const ClassificationOptions(),
  }) async {
    final first = await _primary.classify(menu, options: options);
    if (first is! MenuAnalysisFailed || !_shouldFallBack(first.reason)) {
      return first;
    }
    final second = await _fallback.classify(menu, options: options);
    return switch (second) {
      final MenuAnalysed analysed => analysed,
      final MenuAnalysisFailed failed =>
        _reportsFallback(first.reason) ? failed : first,
    };
  }
}

/// A [ScannedMenuClassifier] that asks [_primary] first and, only when it
/// could not answer at all, [_fallback] (architecture.md D15, D25).
///
/// The primary is meant to be `BackendScannedMenuClassifier` and the
/// fallback the device's own `VisionMenuClassifier`. The chain is
/// [FallbackMenuClassifier]'s, with [ScannedMenuRead] and
/// [ScannedMenuFailed] in place of an analysis and its failure: a read is
/// returned as it is; a failure [shouldFallBack] rejects is returned
/// without asking the fallback; otherwise the fallback's read is
/// returned, or, if it fails too, the primary's failure unless that was
/// only [MenuAnalysisFailureReason.notConfigured].
///
/// Consent and connectivity are not checked here: put this chain behind
/// `RoutingScannedMenuClassifier`. Never throws, as neither engine does.
@immutable
final class FallbackScannedMenuClassifier implements ScannedMenuClassifier {
  /// Creates a chain asking `primary`, then `fallback`.
  const new({required this._primary, required this._fallback});

  /// Whether a primary failure for [reason] is handed to the fallback;
  /// the same rule as [FallbackMenuClassifier.shouldFallBack].
  static bool shouldFallBack(MenuAnalysisFailureReason reason) =>
      _shouldFallBack(reason);

  final ScannedMenuClassifier _primary;
  final ScannedMenuClassifier _fallback;

  @override
  Future<ScannedMenuResult> classify(
    ScannedMenu scan, {
    required ClassificationOptions options,
  }) async {
    final first = await _primary.classify(scan, options: options);
    if (first is! ScannedMenuFailed || !_shouldFallBack(first.reason)) {
      return first;
    }
    final second = await _fallback.classify(scan, options: options);
    return switch (second) {
      final ScannedMenuRead read => read,
      final ScannedMenuFailed failed =>
        _reportsFallback(first.reason) ? failed : first,
    };
  }
}

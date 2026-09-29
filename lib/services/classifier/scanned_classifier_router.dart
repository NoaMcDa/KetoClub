/// The scan path's router: the consent and connectivity rules the text
/// router applies, in front of the vision engine, with no rules fallback
/// behind it (architecture.md §6.2, D15; issue #89).
library;

import 'package:flutter/foundation.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/scanned_menu.dart';
import 'package:ketoclub/services/classifier/menu_classifier.dart';
import 'package:ketoclub/services/classifier/scanned_menu_classifier.dart';
import 'package:ketoclub/services/platform/connectivity.dart';

/// Decides, per scan, whether the vision engine may be asked at all
/// (architecture.md §6.2).
///
/// Mirrors `RoutingMenuClassifier`'s first two rules, in the same order:
///
/// 1. **No consent.** When the user has not allowed AI analysis,
///    [MenuAnalysisFailureReason.consentWithheld] — neither
///    [_connectivity] nor [_vision] is consulted, so no page leaves the
///    device.
/// 2. **The `Connectivity` pre-check (D10).** A `false` reading is
///    [MenuAnalysisFailureReason.offline] without a request spent.
/// 3. **The vision engine**, whose result — a read, or a chat failure
///    mapped one to one onto [MenuAnalysisFailureReason], or
///    [MenuAnalysisFailureReason.noDishesFound] for a transcription with
///    no dish — is returned as it is.
///
/// Unlike the text router there is no rules fallback: the heuristic needs
/// dish text, and a photograph has none until the model reads it. Every
/// failure therefore reaches the caller as a [ScannedMenuFailed], whose
/// copy `failure_copy.dart` already has.
@immutable
final class RoutingScannedMenuClassifier implements ScannedMenuClassifier {
  /// Creates a router in front of `vision` that pre-checks `connectivity`
  /// before ever calling it.
  const new({required this._vision, required this._connectivity});

  final ScannedMenuClassifier _vision;
  final Connectivity _connectivity;

  @override
  Future<ScannedMenuResult> classify(
    ScannedMenu scan, {
    required ClassificationOptions options,
  }) async {
    if (!options.estimationConsentGiven) {
      // Rule 1 (§6.2, §11): the pages may not leave the device.
      return const ScannedMenuFailed(
        reason: MenuAnalysisFailureReason.consentWithheld,
      );
    }
    if (!await _connectivity.isOnline()) {
      // Rule 2 (§6.2, D10): the device plainly has no route, so the
      // request — and the quota it would spend — is skipped.
      return const ScannedMenuFailed(reason: MenuAnalysisFailureReason.offline);
    }
    return await _vision.classify(scan, options: options);
  }
}

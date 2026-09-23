/// The router between the LLM and heuristic classification engines
/// (architecture.md §6.2, §10, §11).
library;

import 'package:flutter/foundation.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/services/classifier/menu_classifier.dart';
import 'package:ketoclub/services/platform/connectivity.dart';

/// Re-stamps [heuristicResult] with a [RulesEngine] tag naming [reason],
/// the way the router shows "why" it fell back instead of using the
/// LLM.
///
/// The heuristic engine never produces [MenuAnalysisFailed] (it places
/// every dish it is given), but this helper still degrades gracefully
/// on one rather than casting: if it ever did, there is no dish list to
/// re-stamp, so the failure is returned exactly as the heuristic gave
/// it, unre-stamped, rather than crashing the router.
MenuAnalysis _toRulesResult(
  MenuAnalysis heuristicResult,
  MenuAnalysisFailureReason reason,
) {
  return switch (heuristicResult) {
    final MenuAnalysed analysed => analysed.copyWithEngine(
      RulesEngine(reason: reason),
    ),
    final MenuAnalysisFailed failed => failed,
  };
}

/// Picks the LLM or heuristic engine per call, and degrades between them
/// on failure (architecture.md §6.2).
///
/// Three rules, in order:
///
/// 1. **No consent.** When the user has not allowed AI analysis in
///    Settings, the heuristic answers, stamped
///    [MenuAnalysisFailureReason.consentWithheld]. Neither
///    [_connectivity] nor [_llm] is consulted: no dish text leaves the
///    device.
/// 2. **The `Connectivity` pre-check (architecture.md §14 D10).** Before
///    ever sending a request to KetoClub's server, [classify] asks
///    [_connectivity] whether the device appears to have a route at all;
///    a `false` reading skips the LLM call entirely, falling straight to
///    the heuristic stamped [MenuAnalysisFailureReason.offline].
///    [Connectivity.isOnline] is a hint, never a verdict, so a `true`
///    reading that turns out wrong is not a bug in this router: the LLM
///    call is still attempted and still fails with its own reason.
/// 3. **The LLM.** Every failure except
///    [MenuAnalysisFailureReason.noDishesFound] falls back to the
///    heuristic with the reason carried, so the UI can say why it is
///    showing rule-based results. Nothing pre-checks whether the server
///    is up: the call is the probe.
///
/// The router announces nothing through
/// [ClassificationOptions.onEngineStarted] itself: it passes `options`
/// through unchanged and each engine announces itself as it starts, so
/// a listener learns the outcome of the three rules above without any
/// of them being restated outside this class (issue #65).
@immutable
final class RoutingMenuClassifier implements MenuClassifier {
  /// Creates a router that sends the primary engine's requests through
  /// [_llm], falls back to [_heuristic], and consults [_connectivity]
  /// before ever calling [_llm].
  ///
  /// Positional and private, matching every other service constructor
  /// in this layer (see `HeuristicMenuClassifier`, `MenuController`):
  /// Dart has no way to make a named initializing formal private at the
  /// call site, so the choice is positional or a suppressed lint.
  const new(this._llm, this._heuristic, this._connectivity);

  final MenuClassifier _llm;
  final MenuClassifier _heuristic;
  final Connectivity _connectivity;

  @override
  Future<MenuAnalysis> classify(
    Menu menu, {
    ClassificationOptions options = const ClassificationOptions(),
  }) async {
    if (!options.estimationConsentGiven) {
      // Rule 1 (architecture.md §6.2, §11): the user has not allowed dish
      // text to leave the device, so the server is never asked.
      return _toRulesResult(
        await _heuristic.classify(menu, options: options),
        MenuAnalysisFailureReason.consentWithheld,
      );
    }

    final online = await _connectivity.isOnline();
    if (!online) {
      // Rule 2 (architecture.md §6.2, §14 D10): the device plainly has
      // no route, so the request — and the quota it would spend — is
      // skipped entirely, straight to the heuristic.
      return _toRulesResult(
        await _heuristic.classify(menu, options: options),
        MenuAnalysisFailureReason.offline,
      );
    }

    final result = await _llm.classify(menu, options: options);
    return switch (result) {
      final MenuAnalysed analysed => analysed,
      final MenuAnalysisFailed failed => await _handleLlmFailure(
        failed,
        menu,
        options,
      ),
    };
  }

  /// Decides what the router shows after [failed] came back from the
  /// LLM engine (architecture.md §6.2, §10).
  ///
  /// An exhaustive switch with no `default`, so a new reason has to be
  /// placed on one side or the other deliberately.
  Future<MenuAnalysis> _handleLlmFailure(
    MenuAnalysisFailed failed,
    Menu menu,
    ClassificationOptions options,
  ) async {
    switch (failed.reason) {
      case MenuAnalysisFailureReason.notConfigured:
      case MenuAnalysisFailureReason.offline:
      case MenuAnalysisFailureReason.timeout:
      case MenuAnalysisFailureReason.rateLimited:
      case MenuAnalysisFailureReason.badResponse:
      case MenuAnalysisFailureReason.backendUnreachable:
      case MenuAnalysisFailureReason.consentWithheld:
        // The reason is surfaced on the rules result so the UI can say
        // why it is showing rule-based results (architecture.md §10).
        // §6.2 says a bad response is "not silently papered over"; it is
        // not, because the failure is named on the result, never hidden.
        // `consentWithheld` cannot come from the LLM engine in practice —
        // only rule 1 above produces it — but if it ever did, falling
        // back is what that reason means.
        return _toRulesResult(
          await _heuristic.classify(menu, options: options),
          failed.reason,
        );
      case MenuAnalysisFailureReason.noDishesFound:
        // The parser reports this when the model saw dishes but placed
        // none. §10's table gives it a bare failure message with "try
        // rules" as a *manual* way out, so it is returned as-is rather
        // than auto-falling back; the heuristic is never called for it.
        return failed;
    }
  }
}

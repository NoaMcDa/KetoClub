/// The router between the LLM and heuristic classification engines
/// (architecture.md §6.2, §10, §11).
library;

import 'package:flutter/foundation.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/services/classifier/menu_classifier.dart';
import 'package:ketoclub/services/storage/key_store.dart';

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
/// **No `Connectivity` dependency.** architecture.md §6.2's rule 2
/// ("device reports offline → heuristic") is deliberately not
/// implemented here: there is no `Connectivity` abstraction in the
/// dependency table (§8), and a pre-flight connectivity check would add
/// its own outbound host to probe. Letting the LLM call itself fail
/// with [MenuAnalysisFailureReason.offline] and falling back from that
/// covers the same case without the extra dependency.
@immutable
final class RoutingMenuClassifier implements MenuClassifier {
  /// Creates a router that sends the primary engine's requests through
  /// [_llm], falls back to [_heuristic], and checks [_keyStore] for a
  /// stored OpenRouter key before every call.
  ///
  /// Positional and private, matching every other service constructor
  /// in this layer (see `HeuristicMenuClassifier`, `MenuController`):
  /// Dart has no way to make a named initializing formal private at the
  /// call site, so the choice is positional or a suppressed lint.
  const new(this._llm, this._heuristic, this._keyStore);

  final MenuClassifier _llm;
  final MenuClassifier _heuristic;
  final KeyStore _keyStore;

  @override
  Future<MenuAnalysis> classify(
    Menu menu, {
    ClassificationOptions options = const ClassificationOptions(),
  }) async {
    final hasKey = await _keyStore.hasKey();
    if (!hasKey || !options.estimationConsentGiven) {
      // Rule 1 (architecture.md §6.2, §11): no key or no consent is
      // routed to the heuristic identically — the router treats "no
      // consent" exactly like "no key".
      final heuristicResult = await _heuristic.classify(menu, options: options);
      return _toRulesResult(
        heuristicResult,
        MenuAnalysisFailureReason.notConfigured,
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
  Future<MenuAnalysis> _handleLlmFailure(
    MenuAnalysisFailed failed,
    Menu menu,
    ClassificationOptions options,
  ) async {
    switch (failed.reason) {
      case MenuAnalysisFailureReason.offline:
      case MenuAnalysisFailureReason.timeout:
      case MenuAnalysisFailureReason.rateLimited:
        // The reason is surfaced on the rules result so the UI can say
        // why it is showing rule-based results (architecture.md §10).
        return _toRulesResult(
          await _heuristic.classify(menu, options: options),
          failed.reason,
        );
      case MenuAnalysisFailureReason.badResponse:
        // §6.2 says a bad response is "not silently papered over"; §10's
        // table shows the user rules plus "AI analysis failed
        // ({detail})". Both are satisfied by falling back with the
        // reason attached, same as the three cases above: the failure
        // is named, never hidden.
        return _toRulesResult(
          await _heuristic.classify(menu, options: options),
          failed.reason,
        );
      case MenuAnalysisFailureReason.unauthorised:
        // §6.2 and §10 agree this reason does not degrade: the user's
        // key was rejected and must see that, not a quietly weaker
        // rules-based answer. The heuristic is never called.
        return failed;
      case MenuAnalysisFailureReason.noDishesFound:
        // Can arise from `LlmMenuClassifier` (its parser reports this
        // when the model saw dishes but placed none). §10's table gives
        // it a bare failure message with "try rules" as a *manual* way
        // out, unlike the `rules result + ...` phrasing on the four
        // cases above — so, like `unauthorised`, this reason is
        // returned as-is rather than auto-falling back; the heuristic
        // is never called for it.
        return failed;
      case MenuAnalysisFailureReason.notConfigured:
        // Cannot arise from `LlmMenuClassifier` in practice: it is
        // never in `_failureReasonFor`'s `ChatFailureReason` map and
        // `MenuResponseParser` never produces it either — only the
        // router's own rule 1 does. Handled explicitly (not as a
        // `default`) so a real occurrence is not silently swallowed:
        // treated the same as rule 1, since that is exactly what this
        // reason means — fall back to the heuristic, re-stamped
        // `notConfigured`.
        return _toRulesResult(
          await _heuristic.classify(menu, options: options),
          MenuAnalysisFailureReason.notConfigured,
        );
    }
  }
}

import 'package:flutter/foundation.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/utils/constants.dart';

/// Element-wise list equality, used by the equality operator on
/// [ClassificationOptions].
///
/// Not shared with the model files' own copies: this layer keeps its own
/// so it stays self-contained (architecture.md §18.2).
bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Which engine a [MenuClassifier] has started running, as announced
/// through [ClassificationOptions.onEngineStarted] (issue #65).
///
/// Deliberately not [AnalysisEngine]: that type describes a finished
/// result (the model that answered, the reason rules were used), and at
/// the moment an engine starts neither is known yet.
enum ClassifyingEngine {
  /// The hosted language model, reached through KetoClub's server.
  llm,

  /// The on-device rule engine.
  rules,
}

/// Options steering one [MenuClassifier.classify] call (architecture.md
/// §6.2, §9.1).
///
/// [netCarbLimitGrams] and [dietaryConstraints] change what a verdict
/// means, so they are what [snapshot] records beside a cached analysis and
/// what [matches] compares against (issue #57; issue #56 reuses the same
/// seam for its dietary toggles). [estimationConsentGiven] only picks the
/// engine, which the analysis already records itself.
@immutable
final class ClassificationOptions {
  /// Creates options for one [MenuClassifier.classify] call.
  ///
  /// [netCarbLimitGrams] is taken as given; `AppSettings` clamps the
  /// user's choice to [minNetCarbLimitGrams]..[maxNetCarbLimitGrams]
  /// before it reaches here.
  const new({
    this.estimationConsentGiven = false,
    this.dietaryConstraints = const <String>[],
    this.netCarbLimitGrams = defaultNetCarbLimitGrams,
    this.onEngineStarted,
  });

  /// Whether the user has consented to sending menu text to a
  /// third-party LLM for a net-carb estimate (architecture.md §11).
  final bool estimationConsentGiven;

  /// Extra user constraints appended to the LLM system prompt, e.g.
  /// [seedOilFreePromptFragment] (architecture.md §9.1, Tier C). Callers
  /// must not mutate the list passed to the constructor.
  ///
  /// The Settings toggles (issue #56) reach here through
  /// [dietaryConstraintsFor], which fixes their order, so the same toggles
  /// always produce the same list — and so the same prompt, the same
  /// [snapshot] and the same server-side cache key.
  final List<String> dietaryConstraints;

  /// The [dietaryConstraints] the three "Your keto rules" toggles ask for
  /// (issue #56): each switched-on toggle's prompt fragment from
  /// `constants.dart`, always in the order seed-oil free, dairy-free,
  /// carnivore only. All three off yields an empty list, so the prompt
  /// carries no dietary section at all and is byte-for-byte the default.
  static List<String> dietaryConstraintsFor({
    required bool seedOilFree,
    required bool dairyFree,
    required bool carnivoreOnly,
  }) => List<String>.unmodifiable(<String>[
    if (seedOilFree) seedOilFreePromptFragment,
    if (dairyFree) dairyFreePromptFragment,
    if (carnivoreOnly) carnivoreOnlyPromptFragment,
  ]);

  /// Whether the "Strict seed-oil free" toggle is among
  /// [dietaryConstraints] (issue #56), for `HeuristicMenuClassifier`'s
  /// seed-oil rule.
  bool get seedOilFree =>
      dietaryConstraints.contains(seedOilFreePromptFragment);

  /// Whether the "Dairy-free keto" toggle is among [dietaryConstraints]
  /// (issue #56).
  bool get dairyFree => dietaryConstraints.contains(dairyFreePromptFragment);

  /// Whether the "Carnivore only" toggle is among [dietaryConstraints]
  /// (issue #56).
  bool get carnivoreOnly =>
      dietaryConstraints.contains(carnivoreOnlyPromptFragment);

  /// Called by an engine as it starts work on this call, so a screen can
  /// name the engine while it runs ("Asking the AI…" against "Applying
  /// the rules…", issue #65).
  ///
  /// **Each engine announces itself; the router announces nothing.**
  /// `LlmMenuClassifier` calls this with [ClassifyingEngine.llm] and
  /// `HeuristicMenuClassifier` with [ClassifyingEngine.rules], each as
  /// the first statement of its own `classify`. The router's choice —
  /// consent, the connectivity pre-check, the fallback after a failed
  /// LLM call — therefore shows up here as the order the engines start
  /// in, with none of its rules restated anywhere else. A fallback
  /// reads as `llm` followed by `rules`.
  ///
  /// An observer, not an option: it cannot change what the engines
  /// return, so it takes no part in [operator ==], [hashCode] or
  /// [toString]. Null when nobody is listening.
  final void Function(ClassifyingEngine engine)? onEngineStarted;

  /// The net-carb limit in grams above which no dish is green (issue #57):
  /// stated in the LLM prompt's green definition, and applied by
  /// `MenuResponseParser` to the model's own `net_carbs_estimate`.
  final int netCarbLimitGrams;

  /// The options that shape a verdict, as the models-layer value a cached
  /// [MenuAnalysed] records (issue #57).
  AnalysisOptionsSnapshot get snapshot => AnalysisOptionsSnapshot(
    netCarbLimitGrams: netCarbLimitGrams,
    dietaryConstraints: dietaryConstraints,
  );

  /// Whether an analysis recorded under [recorded] answered the same
  /// question these options ask, so it may be reused (issue #57).
  ///
  /// A null [recorded] is an analysis cached before issue #57 recorded
  /// options at all; every such analysis was made under the defaults
  /// (a 6 g limit, no dietary constraints), so it is compared as those.
  bool matches(AnalysisOptionsSnapshot? recorded) =>
      (recorded ?? const ClassificationOptions().snapshot) == snapshot;

  @override
  bool operator ==(Object other) =>
      other is ClassificationOptions &&
      other.estimationConsentGiven == estimationConsentGiven &&
      _listEquals(other.dietaryConstraints, dietaryConstraints) &&
      other.netCarbLimitGrams == netCarbLimitGrams;

  @override
  int get hashCode => Object.hash(
    estimationConsentGiven,
    Object.hashAll(dietaryConstraints),
    netCarbLimitGrams,
  );

  @override
  String toString() =>
      'ClassificationOptions(consent: $estimationConsentGiven, '
      'constraints: $dietaryConstraints, limit: ${netCarbLimitGrams}g)';
}

/// Classifies a menu's dishes by keto-compatibility (architecture.md
/// §6.2).
///
/// One implementation per engine (LLM, on-device heuristic), plus a
/// router that picks between them per call. Nothing in this interface
/// throws across its boundary.
abstract interface class MenuClassifier {
  /// Classifies every dish in [menu], steered by [options].
  ///
  /// A [MenuAnalysed] result records [options]'s
  /// [ClassificationOptions.snapshot] in [MenuAnalysed.options] (issue
  /// #57), so a cached result can later be checked against the options
  /// the user holds then.
  ///
  /// Never throws: every failure is reported as a [MenuAnalysisFailed]
  /// result rather than an exception. Callers make exactly one call per
  /// menu (architecture.md §6.2, constraint D6); an implementation must
  /// not depend on being called more than once, or exactly once, to
  /// behave correctly.
  Future<MenuAnalysis> classify(
    Menu menu, {
    ClassificationOptions options = const ClassificationOptions(),
  });
}

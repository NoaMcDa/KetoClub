import 'package:flutter/foundation.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/menu.dart';

/// Element-wise list equality, used by every `==` in this file.
///
/// Not shared with other model files: each keeps its own copy so it stays
/// self-contained (architecture.md §18.2).
bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// The reason whose `name` equals [wire], or null when none does.
///
/// Matches by string, never by ordinal, so reordering
/// [MenuAnalysisFailureReason] cannot silently re-map cached data. Lives
/// here, not in `failures.dart`, because that file declares no members
/// beyond the enum values themselves.
MenuAnalysisFailureReason? _tryParseFailureReason(String wire) {
  for (final reason in MenuAnalysisFailureReason.values) {
    if (reason.name == wire) return reason;
  }
  return null;
}

/// How the classifier judged one dish (architecture.md §6.2).
enum DishVerdict {
  /// Keto-safe as printed; order with no changes.
  orderAsIs,

  /// Keto-safe once a component is swapped; see
  /// [AnalysedDish.modification].
  modifiable,

  /// Fundamentally high-carb; not worth ordering even with changes.
  nonKeto;

  /// The verdict whose [name] equals [wire], or null when none does.
  ///
  /// Matches by string, never by ordinal, so reordering this enum
  /// cannot silently re-map cached data.
  static DishVerdict? tryParse(String wire) {
    for (final verdict in DishVerdict.values) {
      if (verdict.name == wire) return verdict;
    }
    return null;
  }
}

/// Which verdicts a filtered menu view keeps (architecture.md §6.2, §6.6).
enum MenuFilter {
  /// Only [DishVerdict.orderAsIs] dishes.
  greenOnly,

  /// [DishVerdict.orderAsIs] and [DishVerdict.modifiable] dishes.
  greenAndYellow,

  /// Every dish, including [DishVerdict.nonKeto].
  all;

  /// The filter whose [name] equals [wire], or null when none does.
  ///
  /// Matches by string, never by ordinal, so reordering this enum
  /// cannot silently re-map cached data.
  static MenuFilter? tryParse(String wire) {
    for (final filter in MenuFilter.values) {
      if (filter.name == wire) return filter;
    }
    return null;
  }
}

/// One dish as either engine judged it (architecture.md §6.2).
@immutable
final class AnalysedDish {
  /// Creates a verdict for the dish named [name]. [modification] must be
  /// non-null exactly when [verdict] is [DishVerdict.modifiable].
  const new({
    required this.dishId,
    required this.name,
    required this.verdict,
    required this.why,
    this.modification,
    this.netCarbsEstimate,
  });

  /// Reads a verdict written by [toJson].
  ///
  /// Returns null for any shape mismatch — including a
  /// [DishVerdict.modifiable] verdict with no [modification], or a
  /// non-modifiable verdict that carries one — and never throws.
  static AnalysedDish? tryFrom(Map<String, Object?> json) {
    final dishId = json['dishId'];
    final name = json['name'];
    final rawVerdict = json['verdict'];
    final why = json['why'];
    final rawModification = json['modification'];
    final rawNetCarbs = json['netCarbsEstimate'];
    if (dishId is! String || dishId.isEmpty) return null;
    if (name is! String || name.isEmpty) return null;
    if (rawVerdict is! String) return null;
    final verdict = DishVerdict.tryParse(rawVerdict);
    if (verdict == null) return null;
    if (why is! String || why.isEmpty) return null;
    if (rawModification != null && rawModification is! String) return null;
    final modification = rawModification is String ? rawModification : null;
    final isModifiable = verdict == DishVerdict.modifiable;
    if (isModifiable && (modification == null || modification.isEmpty)) {
      return null;
    }
    if (!isModifiable && modification != null) return null;
    if (rawNetCarbs != null && rawNetCarbs is! num) return null;
    final netCarbsEstimate = rawNetCarbs is num ? rawNetCarbs.toDouble() : null;
    return AnalysedDish(
      dishId: dishId,
      name: name,
      verdict: verdict,
      why: why,
      modification: modification,
      netCarbsEstimate: netCarbsEstimate,
    );
  }

  /// Links back to the dish this verdict is about ([Dish.id] in the
  /// [Menu] it was analysed from).
  final String dishId;

  /// The dish name, exactly as printed on the menu.
  final String name;

  /// Whether the dish can be ordered as-is, modified, or skipped.
  final DishVerdict verdict;

  /// A short explanation of the verdict. Never empty.
  final String why;

  /// The waiter script: what to ask to remove and swap.
  ///
  /// Non-null exactly when [verdict] is [DishVerdict.modifiable].
  final String? modification;

  /// A rough net-carb estimate in grams, from the LLM engine only.
  ///
  /// Never rendered to the user as a fact; the rules engine never sets
  /// it.
  final double? netCarbsEstimate;

  /// Writes a form [tryFrom] can read back.
  Map<String, Object?> toJson() => <String, Object?>{
    'dishId': dishId,
    'name': name,
    'verdict': verdict.name,
    'why': why,
    'modification': modification,
    'netCarbsEstimate': netCarbsEstimate,
  };

  @override
  bool operator ==(Object other) =>
      other is AnalysedDish &&
      other.dishId == dishId &&
      other.name == name &&
      other.verdict == verdict &&
      other.why == why &&
      other.modification == modification &&
      other.netCarbsEstimate == netCarbsEstimate;

  @override
  int get hashCode =>
      Object.hash(dishId, name, verdict, why, modification, netCarbsEstimate);

  @override
  String toString() => 'AnalysedDish($dishId: $verdict)';
}

/// One menu row as the UI shows it: the dish, its category, and its
/// verdict if any.
@immutable
final class DishRow {
  /// Creates a row for [dish] in [category], with [analysis] once the
  /// menu has been analysed.
  const new({required this.dish, required this.category, this.analysis});

  /// The dish as read from the menu.
  final Dish dish;

  /// The name of the category [dish] appears under.
  final String category;

  /// The dish's verdict, or null when the menu has not been analysed.
  final AnalysedDish? analysis;

  @override
  bool operator ==(Object other) =>
      other is DishRow &&
      other.dish == dish &&
      other.category == category &&
      other.analysis == analysis;

  @override
  int get hashCode => Object.hash(dish, category, analysis);

  @override
  String toString() => 'DishRow(${dish.id} in $category)';
}

/// Which engine produced a [MenuAnalysis] (architecture.md §6.2, §7).
///
/// Not constructed directly; use [LlmEngine] or [RulesEngine].
@immutable
sealed class AnalysisEngine {
  /// Subclasses only.
  const new();
}

/// Tags a result as produced by the primary engine: an LLM call through
/// OpenRouter.
@immutable
final class LlmEngine extends AnalysisEngine {
  /// Creates a tag naming the OpenRouter [model] that produced the
  /// result.
  const new({required this.model});

  /// The OpenRouter model id that produced this result.
  final String model;

  /// Writes a form [_engineFrom] can read back.
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': 'llm',
    'model': model,
  };

  @override
  bool operator ==(Object other) => other is LlmEngine && other.model == model;

  @override
  int get hashCode => Object.hash(runtimeType, model);

  @override
  String toString() => 'LlmEngine($model)';
}

/// Tags a result as produced by the fallback engine: on-device
/// heuristics, and why the LLM was not used.
@immutable
final class RulesEngine extends AnalysisEngine {
  /// Creates a tag naming the [reason] the LLM was not used.
  const new({required this.reason});

  /// Why the router fell back to heuristics instead of the LLM.
  final MenuAnalysisFailureReason reason;

  /// Writes a form [_engineFrom] can read back.
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': 'rules',
    'reason': reason.name,
  };

  @override
  bool operator ==(Object other) =>
      other is RulesEngine && other.reason == reason;

  @override
  int get hashCode => Object.hash(runtimeType, reason);

  @override
  String toString() => 'RulesEngine($reason)';
}

/// Reads an [AnalysisEngine] written by [LlmEngine.toJson] or
/// [RulesEngine.toJson], using the `kind` discriminator.
///
/// Returns null for any shape mismatch and never throws.
AnalysisEngine? _engineFrom(Map<String, Object?> json) {
  final kind = json['kind'];
  if (kind is! String) return null;
  if (kind == 'llm') {
    final model = json['model'];
    if (model is! String || model.isEmpty) return null;
    return LlmEngine(model: model);
  }
  if (kind == 'rules') {
    final rawReason = json['reason'];
    if (rawReason is! String) return null;
    final reason = _tryParseFailureReason(rawReason);
    if (reason == null) return null;
    return RulesEngine(reason: reason);
  }
  return null;
}

/// The result of running a [Menu] through the classifier
/// (architecture.md §6.2, §7).
///
/// Not constructed directly; use [MenuAnalysed] or [MenuAnalysisFailed].
@immutable
sealed class MenuAnalysis {
  /// Subclasses only.
  const new();
}

/// A completed analysis: a verdict for each dish the engine could
/// place.
@immutable
final class MenuAnalysed extends MenuAnalysis {
  /// Creates a result for [dishes], noting [unclassified] names and
  /// which [engine] produced it at [analysedAt].
  const new({
    required this.dishes,
    required this.unclassified,
    required this.engine,
    required this.analysedAt,
  });

  /// Reads a result written by [toJson].
  ///
  /// Returns null for any shape mismatch, including a malformed dish
  /// verdict or engine tag, and never throws.
  static MenuAnalysed? tryFrom(Map<String, Object?> json) {
    final rawDishes = json['dishes'];
    final rawUnclassified = json['unclassified'];
    final rawEngine = json['engine'];
    final rawAnalysedAt = json['analysedAt'];
    if (rawDishes is! List<Object?>) return null;
    final dishes = <AnalysedDish>[];
    for (final rawDish in rawDishes) {
      if (rawDish is! Map<String, Object?>) return null;
      final dish = AnalysedDish.tryFrom(rawDish);
      if (dish == null) return null;
      dishes.add(dish);
    }
    if (rawUnclassified is! List<Object?>) return null;
    final unclassified = <String>[];
    for (final name in rawUnclassified) {
      if (name is! String) return null;
      unclassified.add(name);
    }
    if (rawEngine is! Map<String, Object?>) return null;
    final engine = _engineFrom(rawEngine);
    if (engine == null) return null;
    if (rawAnalysedAt is! String) return null;
    final analysedAt = DateTime.tryParse(rawAnalysedAt);
    if (analysedAt == null) return null;
    return MenuAnalysed(
      dishes: dishes,
      unclassified: unclassified,
      engine: engine,
      analysedAt: analysedAt,
    );
  }

  /// A verdict for every dish the engine could place.
  ///
  /// Can be empty when [unclassified] is not: the engine saw dishes but
  /// could place none (architecture.md §9.4). Callers must not mutate
  /// the list passed to the constructor.
  final List<AnalysedDish> dishes;

  /// Dish names seen on the menu but not placed by the engine.
  ///
  /// Shown to the user, never dropped. Callers must not mutate the list
  /// passed to the constructor.
  final List<String> unclassified;

  /// Which engine produced this result.
  final AnalysisEngine engine;

  /// When this analysis was produced.
  final DateTime analysedAt;

  /// A copy of this result with [engine] replaced.
  ///
  /// Used by the router to re-stamp the fallback reason after the fact.
  MenuAnalysed copyWithEngine(AnalysisEngine engine) => MenuAnalysed(
    dishes: dishes,
    unclassified: unclassified,
    engine: engine,
    analysedAt: analysedAt,
  );

  /// Writes a form [tryFrom] can read back.
  Map<String, Object?> toJson() => <String, Object?>{
    'dishes': dishes.map((dish) => dish.toJson()).toList(),
    'unclassified': unclassified,
    'engine': switch (engine) {
      final LlmEngine llm => llm.toJson(),
      final RulesEngine rules => rules.toJson(),
    },
    'analysedAt': analysedAt.toIso8601String(),
  };

  @override
  bool operator ==(Object other) =>
      other is MenuAnalysed &&
      _listEquals(other.dishes, dishes) &&
      _listEquals(other.unclassified, unclassified) &&
      other.engine == engine &&
      other.analysedAt == analysedAt;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(dishes),
    Object.hashAll(unclassified),
    engine,
    analysedAt,
  );

  @override
  String toString() =>
      'MenuAnalysed(${dishes.length} dishes, '
      '${unclassified.length} unclassified)';
}

/// An analysis that could not be produced at all.
@immutable
final class MenuAnalysisFailed extends MenuAnalysis {
  /// Creates a failure for [reason], with an optional [detail].
  const new({required this.reason, this.detail});

  /// Why the analysis could not be produced.
  final MenuAnalysisFailureReason reason;

  /// A short, safe elaboration shown to the user.
  ///
  /// Never an upstream response body, never an API key.
  final String? detail;

  /// Writes this failure as JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'reason': reason.name,
    'detail': detail,
  };

  @override
  bool operator ==(Object other) =>
      other is MenuAnalysisFailed &&
      other.reason == reason &&
      other.detail == detail;

  @override
  int get hashCode => Object.hash(reason, detail);

  @override
  String toString() => 'MenuAnalysisFailed($reason)';
}

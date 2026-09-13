import 'package:flutter/foundation.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/menu.dart';

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

/// Options steering one [MenuClassifier.classify] call (architecture.md
/// §6.2, §9.1).
@immutable
final class ClassificationOptions {
  /// Creates options for one [MenuClassifier.classify] call.
  const new({
    this.estimationConsentGiven = false,
    this.dietaryConstraints = const <String>[],
  });

  /// Whether the user has consented to sending menu text to a
  /// third-party LLM for a net-carb estimate (architecture.md §11).
  final bool estimationConsentGiven;

  /// Extra user constraints appended to the LLM system prompt, e.g.
  /// "seed-oil free" (architecture.md §9.1, Tier C). Callers must not
  /// mutate the list passed to the constructor.
  final List<String> dietaryConstraints;

  @override
  bool operator ==(Object other) =>
      other is ClassificationOptions &&
      other.estimationConsentGiven == estimationConsentGiven &&
      _listEquals(other.dietaryConstraints, dietaryConstraints);

  @override
  int get hashCode =>
      Object.hash(estimationConsentGiven, Object.hashAll(dietaryConstraints));

  @override
  String toString() =>
      'ClassificationOptions(consent: $estimationConsentGiven, '
      'constraints: $dietaryConstraints)';
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

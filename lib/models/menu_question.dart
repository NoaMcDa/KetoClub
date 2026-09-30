import 'package:flutter/foundation.dart';
import 'package:ketoclub/models/failures.dart';

/// Why a menu question could not be answered (architecture.md §9.5;
/// issue #214).
///
/// Reuses [MenuAnalysisFailureReason]'s vocabulary: the same reasons that
/// prevent a menu from being classified also prevent a question from being
/// answered, through the same LLM chat client path. The distinct copy in
/// `failure_copy.dart` is what gives each reason its question-specific
/// message; the enum itself is shared. There is no rules fallback here —
/// unlike menu analysis, a free-text question has no on-device equivalent.
typedef MenuQuestionFailureReason = MenuAnalysisFailureReason;

/// The outcome of one menu question ask call
/// (architecture.md §9.5; issue #214).
///
/// Sealed: either [MenuQuestionAnswered] (success) or [MenuQuestionFailed]
/// (failure). Never throws.
@immutable
sealed class MenuQuestionResult {
  /// Subclasses only.
  const new();
}

/// A successful answer to a menu question.
@immutable
final class MenuQuestionAnswered extends MenuQuestionResult {
  /// Creates a result carrying [answer] and the ids of the dishes it
  /// references.
  const new({required this.answer, required this.referencedDishIds});

  /// The model's answer, trimmed and capped.
  final String answer;

  /// The ids of dishes in the source menu this answer references, in reply
  /// order, deduplicated and capped at 10. May be empty when the answer
  /// does not refer to any specific dish.
  final List<String> referencedDishIds;

  @override
  bool operator ==(Object other) =>
      other is MenuQuestionAnswered &&
      other.answer == answer &&
      _listEquals(other.referencedDishIds, referencedDishIds);

  @override
  int get hashCode => Object.hash(runtimeType, answer, referencedDishIds);

  @override
  String toString() =>
      'MenuQuestionAnswered(answer: $answer, '
      'referencedDishIds: $referencedDishIds)';
}

/// A failed attempt to answer a menu question.
@immutable
final class MenuQuestionFailed extends MenuQuestionResult {
  /// Creates a failure for [reason].
  const new({required this.reason});

  /// Why the question could not be answered.
  final MenuQuestionFailureReason reason;

  @override
  bool operator ==(Object other) =>
      other is MenuQuestionFailed && other.reason == reason;

  @override
  int get hashCode => Object.hash(runtimeType, reason);

  @override
  String toString() => 'MenuQuestionFailed($reason)';
}

/// Compares two lists element by element; [listEquals] from foundation is
/// the canonical way (architecture.md §18.1 "immutable models").
bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

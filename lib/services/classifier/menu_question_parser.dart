/// Parses an LLM reply to a menu question into an answer and a list of
/// referenced dish ids (architecture.md §9.5; issue #214).
///
/// Static, pure, and never throws — the same contract the menu response parser
/// keeps for menu analysis (architecture.md §9.4). A model reply is untrusted
/// input: no field is ever interpreted as an instruction, and an invented dish
/// id is silently dropped rather than shown to the user.
library;

import 'dart:convert';

import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/menu_question.dart';

/// The maximum character length the answer may have (trimmed).
///
/// Matches the cap the system prompt states to the model.
const int _maxAnswerLength = 1200;

/// The maximum number of dish ids the parser keeps.
const int _maxDishIds = 10;

/// Matches a whole reply wrapped in a markdown code fence, with or
/// without a `json` language tag — the same pattern the menu response
/// parser uses.
final RegExp _fencedJson = RegExp(
  r'^```(?:json)?\s*\n?([\s\S]*?)\n?```$',
  caseSensitive: false,
);

/// Parses an LLM reply to a free-text menu question (architecture.md §9.5).
///
/// Static, pure, and never throws: a reply that cannot be parsed yields a
/// [MenuQuestionFailed] with [MenuQuestionFailureReason.badResponse];
/// an answer that names no real dish still succeeds with an empty id list.
abstract final class MenuQuestionParser {
  /// Parses [body] — the raw LLM reply — against [source], the [Menu] the
  /// question was about.
  ///
  /// In order:
  ///
  /// 1. Strips a markdown fence if present, then `jsonDecode`s [body]; a
  ///    throw, or a root that is not a JSON object, is
  ///    [MenuQuestionFailureReason.badResponse].
  /// 2. `answer` missing, not a string, or empty after trimming is also
  ///    [MenuQuestionFailureReason.badResponse].
  /// 3. `answer` is trimmed and capped at [_maxAnswerLength] characters.
  /// 4. `dish_ids` missing or not a list is treated as an empty list — a
  ///    valid answer that refers to no dish.
  /// 5. Each id in `dish_ids` must exist in [source]; invented ids are
  ///    silently dropped. The surviving ids are deduplicated, keeping the
  ///    first occurrence, and capped at [_maxDishIds].
  ///
  /// Returns [MenuQuestionAnswered] on success, [MenuQuestionFailed]
  /// otherwise.
  static MenuQuestionResult parse(String body, Menu source) {
    final decoded = _decode(body);
    if (decoded == null) {
      return const MenuQuestionFailed(
        reason: MenuQuestionFailureReason.badResponse,
      );
    }

    final rawAnswer = decoded['answer'];
    if (rawAnswer is! String) {
      return const MenuQuestionFailed(
        reason: MenuQuestionFailureReason.badResponse,
      );
    }
    final answer = rawAnswer.trim();
    if (answer.isEmpty) {
      return const MenuQuestionFailed(
        reason: MenuQuestionFailureReason.badResponse,
      );
    }
    final cappedAnswer = answer.length > _maxAnswerLength
        ? answer.substring(0, _maxAnswerLength)
        : answer;

    final rawIds = decoded['dish_ids'];
    final knownIds = {for (final d in source.allDishes) d.id};
    final referencedIds = <String>[];
    if (rawIds is List<Object?>) {
      final seen = <String>{};
      for (final raw in rawIds) {
        if (raw is! String) continue;
        final id = raw.trim();
        if (id.isEmpty) continue;
        if (!knownIds.contains(id)) continue; // drop invented ids
        if (!seen.add(id)) continue; // deduplicate
        referencedIds.add(id);
        if (referencedIds.length >= _maxDishIds) break;
      }
    }

    return MenuQuestionAnswered(
      answer: cappedAnswer,
      referencedDishIds: List<String>.unmodifiable(referencedIds),
    );
  }

  /// Strips a markdown fence if present and `jsonDecode`s [body].
  ///
  /// Returns null when [jsonDecode] throws or the decoded root is not a
  /// JSON object.
  static Map<String, Object?>? _decode(String body) {
    final trimmed = body.trim();
    final fenceMatch = _fencedJson.firstMatch(trimmed);
    final unfenced = fenceMatch?.group(1)?.trim() ?? trimmed;
    final Object? decoded;
    try {
      decoded = jsonDecode(unfenced);
    } on FormatException {
      return null;
    }
    return decoded is Map<String, Object?> ? decoded : null;
  }
}

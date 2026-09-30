/// The LLM-backed [MenuQuestionAnswerer] (architecture.md §9.5; issue #214).
///
/// Sends exactly one chat completion per ask call over the same
/// `LlmChatClient` as the menu classifier, maps a `ChatFailed` reason to the
/// equivalent [MenuQuestionFailureReason] through the shared
/// `menuFailureReasonFor` table, and parses the reply through
/// [MenuQuestionParser]. Never throws and has no rules fallback.
library;

import 'package:flutter/foundation.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/menu_question.dart';
import 'package:ketoclub/services/classifier/llm_menu_classifier.dart';
import 'package:ketoclub/services/classifier/menu_question_answerer.dart';
import 'package:ketoclub/services/classifier/menu_question_parser.dart';
import 'package:ketoclub/services/classifier/menu_question_prompt.dart';
import 'package:ketoclub/services/llm/llm_chat_client.dart';

/// The LLM-backed implementation of [MenuQuestionAnswerer].
///
/// Immutable and positional-private like [LlmMenuClassifier] (same
/// architecture.md §18.1 conventions): the types are distinct, so a
/// misordered call does not compile.
@immutable
final class LlmMenuQuestionAnswerer implements MenuQuestionAnswerer {
  /// Creates an answerer that sends requests through [_client].
  const new(this._client);

  final LlmChatClient _client;

  @override
  Future<MenuQuestionResult> ask(
    Menu menu,
    MenuAnalysed analysis,
    String question,
  ) async {
    final result = await _client.complete(
      systemPrompt: MenuQuestionPrompt.systemPrompt(),
      userPrompt: MenuQuestionPrompt.userPrompt(menu, analysis, question),
      responseSchema: MenuQuestionPrompt.responseSchema(),
      schemaName: MenuQuestionPrompt.schemaName,
    );
    switch (result) {
      case ChatCompleted(:final content):
        return MenuQuestionParser.parse(content, menu);
      case ChatFailed(:final reason):
        return MenuQuestionFailed(reason: menuFailureReasonFor(reason));
    }
  }
}

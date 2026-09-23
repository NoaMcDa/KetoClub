/// The primary classification engine (architecture.md §6.2, §9).
///
/// Sequences three pieces it does not own: [MenuAnalysisPrompt] builds
/// the request text and schema, [LlmChatClient] sends it, and
/// [MenuResponseParser] turns the reply into a [MenuAnalysis]. This
/// class touches none of the HTTP transport, and none of the backend
/// address or install id — all of that lives behind [LlmChatClient].
library;

import 'package:flutter/foundation.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/services/classifier/menu_analysis_prompt.dart';
import 'package:ketoclub/services/classifier/menu_classifier.dart';
import 'package:ketoclub/services/classifier/menu_response_parser.dart';
import 'package:ketoclub/services/llm/llm_chat_client.dart';
import 'package:ketoclub/services/platform/clock.dart';

/// The [ChatFailureReason] a [ChatFailed] carried, mapped 1:1 by name to
/// the [MenuAnalysisFailureReason] this classifier reports for it
/// (architecture.md §10).
///
/// An exhaustive switch with no `default`, so a new [ChatFailureReason]
/// value fails to compile here rather than silently reporting the wrong
/// reason to the user.
MenuAnalysisFailureReason _failureReasonFor(ChatFailureReason reason) {
  switch (reason) {
    case ChatFailureReason.notConfigured:
      return MenuAnalysisFailureReason.notConfigured;
    case ChatFailureReason.offline:
      return MenuAnalysisFailureReason.offline;
    case ChatFailureReason.timeout:
      return MenuAnalysisFailureReason.timeout;
    case ChatFailureReason.rateLimited:
      return MenuAnalysisFailureReason.rateLimited;
    case ChatFailureReason.badResponse:
      return MenuAnalysisFailureReason.badResponse;
    case ChatFailureReason.backendUnreachable:
      return MenuAnalysisFailureReason.backendUnreachable;
  }
}

/// The LLM-backed [MenuClassifier] (architecture.md §6.2, §9).
///
/// Sends exactly one chat completion per [classify] call, whatever the
/// menu's dish count (architecture.md constraint D6: the model's daily
/// quota is small, and a per-dish call would burn a whole visit's quota
/// on one menu). Never throws: a transport failure is reported as
/// [MenuAnalysisFailed] and a reply the parser rejects is reported the
/// same way [MenuResponseParser] already reports it.
@immutable
final class LlmMenuClassifier implements MenuClassifier {
  /// Creates a classifier that sends requests through [_client] and
  /// stamps a successful result with [_clock]'s time.
  ///
  /// Positional and private, matching every other service constructor
  /// in this layer (see `HeuristicMenuClassifier`, `MenuController`):
  /// Dart has no way to make a named initializing formal private at the
  /// call site, so the choice is positional or a suppressed lint.
  const new(this._client, this._clock);

  final LlmChatClient _client;
  final Clock _clock;

  @override
  Future<MenuAnalysis> classify(
    Menu menu, {
    ClassificationOptions options = const ClassificationOptions(),
  }) async {
    // Announced before any await, so a listener hears it in the same
    // turn the call starts (issue #65).
    options.onEngineStarted?.call(ClassifyingEngine.llm);
    final systemPrompt = MenuAnalysisPrompt.systemPrompt(options: options);
    final userPrompt = MenuAnalysisPrompt.userPrompt(menu);
    final result = await _client.complete(
      systemPrompt: systemPrompt,
      userPrompt: userPrompt,
      responseSchema: MenuAnalysisPrompt.responseSchema(),
      schemaName: MenuAnalysisPrompt.schemaName,
    );
    switch (result) {
      case ChatCompleted(:final content, :final model):
        // The model the server reports as having served the reply:
        // the app never names a model itself (architecture.md §9.3).
        return MenuResponseParser.parse(
          content,
          source: menu,
          analysedAt: _clock.now(),
          engine: LlmEngine(model: model),
        );
      case ChatFailed(:final reason):
        return MenuAnalysisFailed(reason: _failureReasonFor(reason));
    }
  }
}

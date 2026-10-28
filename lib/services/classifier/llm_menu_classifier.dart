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
/// (architecture.md §10). Shared by [LlmMenuClassifier] and the scan
/// path's `VisionMenuClassifier` (issue #89), so a chat failure reads the
/// same whether a menu or a photograph was being classified.
///
/// An exhaustive switch with no `default`, so a new [ChatFailureReason]
/// value fails to compile here rather than silently reporting the wrong
/// reason to the user.
MenuAnalysisFailureReason menuFailureReasonFor(ChatFailureReason reason) {
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
    case ChatFailureReason.apiKeyMissing:
      return MenuAnalysisFailureReason.apiKeyMissing;
    case ChatFailureReason.apiKeyRejected:
      return MenuAnalysisFailureReason.apiKeyRejected;
  }
}

/// The LLM-backed [MenuClassifier] (architecture.md §6.2, §9).
///
/// Sends as few chat completions per [classify] call as the prompt budget
/// allows (architecture.md D6 as D25 amends it; issue #188): one for every
/// menu [MenuAnalysisPrompt.batches] leaves whole — byte for byte the
/// request sent before batching existed — and, for a larger menu, one per
/// batch, in menu order, each awaited before the next is sent, so a menu
/// never has more than one request of the per-install rate limit in
/// flight. A per-dish call would burn a whole visit's quota on one menu.
///
/// A split menu's batches are merged into one [MenuAnalysed]: their
/// verdicts and their `unclassified` names in batch order, stamped with
/// the first answering batch's model. A batch that fails on its own — a
/// reply the parser rejects, or a [MenuAnalysisFailureReason.badResponse]
/// or [MenuAnalysisFailureReason.timeout] from the client — puts its
/// dishes under `unclassified` and the next batch is still sent; only
/// when no batch was answered is the menu a [MenuAnalysisFailed], with the
/// first batch's reason. Any other failure says the rest would fail the
/// same way (no route, no key, an empty rate-limit bucket), so nothing
/// more is sent and the whole menu is that failure, which
/// `RoutingMenuClassifier` answers with the rules stamped with its reason.
/// So a [MenuAnalysisFailureReason.rateLimited] mid-menu reads "rate
/// limited" on the chip, rather than leaving the remaining dishes as
/// unexplained "could not place" under an AI chip (a [MenuAnalysed] has no
/// place for a reason) and caching that for a day. Through the backend's
/// chat route the batches already sent are completion-cache hits, which
/// spend no quota, when the menu is analysed again (the split is
/// deterministic, so their requests are the same bytes).
///
/// Never throws: a transport failure is reported as [MenuAnalysisFailed]
/// and a reply the parser rejects is reported the same way
/// [MenuResponseParser] already reports it.
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
  }) {
    // Announced before any await, so a listener hears it in the same
    // turn the call starts (issue #65).
    options.onEngineStarted?.call(ClassifyingEngine.llm);
    final batches = MenuAnalysisPrompt.batches(
      menu,
      maxDishes: MenuAnalysisPrompt.batchMaxDishes(
        extract: options.restrictionsRequested,
      ),
    );
    return batches.length == 1
        ? _classifyBatch(batches.single, options)
        : _classifyBatches(batches, options);
  }

  /// Sends [batches] one after another, each awaited before the next, and
  /// merges what they answer (see the class doc for which failures stop
  /// the menu and which only their batch).
  Future<MenuAnalysis> _classifyBatches(
    List<Menu> batches,
    ClassificationOptions options,
  ) async {
    final dishes = <AnalysedDish>[];
    final unclassified = <String>[];
    AnalysisEngine? engine;
    MenuAnalysisFailureReason? firstFailure;
    for (final batch in batches) {
      switch (await _classifyBatch(batch, options)) {
        case final MenuAnalysed analysed:
          engine ??= analysed.engine;
          dishes.addAll(analysed.dishes);
          unclassified.addAll(analysed.unclassified);
        case final MenuAnalysisFailed failed:
          if (_stopsTheMenu(failed.reason)) return failed;
          firstFailure ??= failed.reason;
          unclassified.addAll(batch.allDishes.map((dish) => dish.name));
      }
    }
    if (engine == null) {
      return MenuAnalysisFailed(
        reason: firstFailure ?? MenuAnalysisFailureReason.badResponse,
      );
    }
    return MenuAnalysed(
      dishes: dishes,
      unclassified: unclassified,
      engine: engine,
      analysedAt: _clock.now(),
      options: options.snapshot,
      schemaVersion: MenuResponseParser.schemaVersion,
    );
  }

  /// Whether [reason], answered for one batch of a split menu, means every
  /// later batch would fail the same way, so the menu stops there and is
  /// that failure (issue #188).
  ///
  /// An exhaustive switch with no `default`, so a new reason has to be
  /// placed on one side deliberately.
  static bool _stopsTheMenu(MenuAnalysisFailureReason reason) {
    switch (reason) {
      case MenuAnalysisFailureReason.badResponse:
      case MenuAnalysisFailureReason.timeout:
      case MenuAnalysisFailureReason.noDishesFound:
        // This batch's reply, or this batch's wait: the next batch is a
        // different request and may well be answered.
        return false;
      case MenuAnalysisFailureReason.notConfigured:
      case MenuAnalysisFailureReason.offline:
      case MenuAnalysisFailureReason.rateLimited:
      case MenuAnalysisFailureReason.backendUnreachable:
      case MenuAnalysisFailureReason.consentWithheld:
      case MenuAnalysisFailureReason.apiKeyMissing:
      case MenuAnalysisFailureReason.apiKeyRejected:
        // No route, no key, or an empty bucket: the rest would spend a
        // request each to learn the same thing.
        return true;
    }
  }

  /// Sends one request for [menu] — a whole menu, or one batch of one —
  /// and parses its reply against [menu], reading the reply's ids through
  /// the batch's own prompt ids ([MenuAnalysisPrompt.promptIds]).
  Future<MenuAnalysis> _classifyBatch(
    Menu menu,
    ClassificationOptions options,
  ) async {
    final result = await _client.complete(
      systemPrompt: MenuAnalysisPrompt.systemPrompt(options: options),
      userPrompt: MenuAnalysisPrompt.userPrompt(menu),
      responseSchema: MenuAnalysisPrompt.responseSchema(
        extract: options.restrictionsRequested,
      ),
      schemaName: MenuAnalysisPrompt.schemaName,
    );
    switch (result) {
      case ChatCompleted(:final content, :final model):
        // The model the provider reports as having served the reply:
        // the app never names a model itself (architecture.md §9.3).
        final parsed = MenuResponseParser.parse(
          content,
          source: menu,
          // The short ids this request's prompt numbered [menu]'s dishes
          // with, so a reply's `id` is read back through them.
          promptIds: MenuAnalysisPrompt.promptIds(menu),
          analysedAt: _clock.now(),
          engine: LlmEngine(model: model),
          // The same limit the prompt stated, so the parser holds the
          // model to its own green definition (issue #57).
          netCarbLimitGrams: options.netCarbLimitGrams,
          // Ingredients are read only when the prompt asked for them
          // (ALG-03, D26 C2).
          extract: options.restrictionsRequested,
        );
        return switch (parsed) {
          final MenuAnalysed analysed => analysed.copyWithOptions(
            options.snapshot,
          ),
          final MenuAnalysisFailed failed => failed,
        };
      case ChatFailed(:final reason):
        return MenuAnalysisFailed(reason: menuFailureReasonFor(reason));
    }
  }
}

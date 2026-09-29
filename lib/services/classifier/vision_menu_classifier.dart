/// The scan path's engine: photographed or PDF menu pages transcribed and
/// classified by the model in one request (architecture.md §6.2, §9.4,
/// D15; issue #89).
///
/// Sequences the same three pieces [LlmMenuClassifier] does, with the
/// pages in place of a menu: [MenuAnalysisPrompt] builds the request,
/// [LlmChatClient] sends it with the pages as image parts, and
/// [MenuResponseParser.parseScanned] turns the reply into a transcribed
/// menu and its verdicts.
library;

import 'package:flutter/foundation.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/scanned_menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/classifier/llm_menu_classifier.dart';
import 'package:ketoclub/services/classifier/menu_analysis_prompt.dart';
import 'package:ketoclub/services/classifier/menu_classifier.dart';
import 'package:ketoclub/services/classifier/menu_response_parser.dart';
import 'package:ketoclub/services/classifier/scanned_menu_classifier.dart';
import 'package:ketoclub/services/llm/llm_chat_client.dart';
import 'package:ketoclub/services/platform/clock.dart';

/// The vision-model [ScannedMenuClassifier] (architecture.md §6.2, D15).
///
/// Sends exactly one chat completion per [classify] call, all pages in it
/// (D6): the system prompt is [MenuAnalysisPrompt.visionSystemPrompt] —
/// the text path's own prompt behind a vision preamble — and the response
/// schema and its name are the text path's, unchanged, so the server's
/// schema handling is the one it already has. A two-request design
/// (transcribe, then run the text path) was rejected: checking provenance
/// against a transcript the model wrote checks the model against itself,
/// and spends two of the day's calls.
///
/// A read menu is addressed `VenueRef(scan, <hex of the clock's
/// millisecond stamp>)`, so two scans never share a cache entry the way
/// two identical pastes do. Its analysis carries `LlmEngine(model)` with
/// the model the provider reported, and the options snapshot.
///
/// Never throws. There is no rules fallback here or in the router in
/// front of it: the rule engine needs text a photograph does not have.
@immutable
final class VisionMenuClassifier implements ScannedMenuClassifier {
  /// Creates a classifier that sends pages through `client` and stamps a
  /// read with `clock`'s time.
  const new({required this._client, required this._clock});

  final LlmChatClient _client;
  final Clock _clock;

  @override
  Future<ScannedMenuResult> classify(
    ScannedMenu scan, {
    required ClassificationOptions options,
  }) async {
    // Nothing to read: no request, and no call spent on an empty one.
    if (scan.pages.isEmpty) {
      return const ScannedMenuFailed(
        reason: MenuAnalysisFailureReason.noDishesFound,
      );
    }
    // Announced before any await, as the text engine does (issue #65).
    options.onEngineStarted?.call(ClassifyingEngine.llm);
    final pageCount = scan.pages.length;
    final result = await _client.complete(
      systemPrompt: MenuAnalysisPrompt.visionSystemPrompt(
        pageCount: pageCount,
        options: options,
      ),
      userPrompt: MenuAnalysisPrompt.visionUserPrompt(pageCount),
      responseSchema: MenuAnalysisPrompt.responseSchema(),
      schemaName: MenuAnalysisPrompt.schemaName,
      images: <ChatImagePart>[
        for (final page in scan.pages)
          ChatImagePart(mimeType: page.mimeType, bytes: page.bytes),
      ],
    );
    switch (result) {
      case ChatCompleted(:final content, :final model):
        final readAt = _clock.now();
        final parsed = MenuResponseParser.parseScanned(
          content,
          ref: VenueRef(
            source: MenuSource.scan,
            platformId: readAt.millisecondsSinceEpoch.toRadixString(16),
          ),
          analysedAt: readAt,
          engine: LlmEngine(model: model),
          netCarbLimitGrams: options.netCarbLimitGrams,
        );
        return switch (parsed) {
          ScannedMenuRead(:final menu, :final analysis) => ScannedMenuRead(
            menu: menu,
            analysis: analysis.copyWithOptions(options.snapshot),
          ),
          final ScannedMenuFailed failed => failed,
        };
      case ChatFailed(:final reason):
        return ScannedMenuFailed(reason: menuFailureReasonFor(reason));
    }
  }
}

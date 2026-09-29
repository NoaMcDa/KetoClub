import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/scanned_menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/classifier/menu_analysis_prompt.dart';
import 'package:ketoclub/services/classifier/menu_classifier.dart';
import 'package:ketoclub/services/classifier/scanned_menu_classifier.dart';
import 'package:ketoclub/services/classifier/vision_menu_classifier.dart';
import 'package:ketoclub/services/llm/llm_chat_client.dart';
import 'package:ketoclub/utils/constants.dart';

import '../../fakes/fake_clock.dart';
import '../../fakes/fake_llm_chat_client.dart';
import 'scanned_menu_classifier_contract.dart';

/// The time [FakeClock] reports in every test here.
final DateTime _now = DateTime.utc(2026, 9, 29, 10, 15, 30);

/// The model name every scripted reply reports.
const String _model = 'gemini-test-vision';

/// A valid vision reply: the scanned-valid fixture, as sent.
final String _validReply = File('test/fixtures/llm/llm_scanned_valid.json')
    .readAsStringSync();

/// A page of [mimeType] whose bytes differ by [seed].
ScannedPage _page(int seed, {String mimeType = ScannedPage.jpeg}) =>
    ScannedPage(
      mimeType: mimeType,
      bytes: Uint8List.fromList(<int>[0xff, 0xd8, seed, 0xff, 0xd9]),
    );

/// A scan of three pages: two photographs and a PDF.
ScannedMenu _threePages() => ScannedMenu(
  pages: <ScannedPage>[
    _page(1),
    _page(2, mimeType: ScannedPage.png),
    _page(3, mimeType: ScannedPage.pdf),
  ],
);

/// Options with consent and a non-default limit and constraint, so what
/// reaches the prompt and the snapshot is visibly these.
const ClassificationOptions _steered = ClassificationOptions(
  estimationConsentGiven: true,
  netCarbLimitGrams: 10,
  dietaryConstraints: <String>[dairyFreePromptFragment],
);

/// A classifier over [client] and a clock fixed at [_now].
VisionMenuClassifier _classifier(FakeLlmChatClient client) =>
    VisionMenuClassifier(client: client, clock: FakeClock(_now));

/// A client that answers every request with [_validReply].
FakeLlmChatClient _answering() =>
    FakeLlmChatClient()
      ..fallback = ChatCompleted(content: _validReply, model: _model);

void main() {
  runScannedMenuClassifierContract(
    'VisionMenuClassifier (reading every scan)',
    () => _classifier(_answering()),
  );
  runScannedMenuClassifierContract(
    'VisionMenuClassifier (the client failing)',
    () => _classifier(FakeLlmChatClient()),
  );

  group('VisionMenuClassifier request', () {
    test('sends one request for the whole scan, pages in order', () async {
      // Arrange
      final client = _answering();
      final scan = _threePages();

      // Act
      await _classifier(client).classify(scan, options: _steered);

      // Assert
      expect(client.requests, hasLength(1));
      final images = client.requests.single.images;
      expect(images.map((image) => image.mimeType), <String>[
        ScannedPage.jpeg,
        ScannedPage.png,
        ScannedPage.pdf,
      ]);
      for (var i = 0; i < scan.pages.length; i++) {
        expect(images[i].bytes, orderedEquals(scan.pages[i].bytes));
      }
    });

    test('sends the vision preamble ahead of the text system prompt, '
        'steered by the options', () async {
      // Arrange
      final client = _answering();

      // Act
      await _classifier(client).classify(_threePages(), options: _steered);

      // Assert
      final systemPrompt = client.requests.single.systemPrompt;
      expect(systemPrompt, startsWith(MenuAnalysisPrompt.visionPreamble(3)));
      expect(
        systemPrompt,
        endsWith(MenuAnalysisPrompt.systemPrompt(options: _steered)),
      );
      expect(systemPrompt, contains('3 pages'));
      expect(systemPrompt, contains('v1, v2, v3'));
      expect(systemPrompt, contains(dairyFreePromptFragment));
      expect(
        client.requests.single.userPrompt,
        MenuAnalysisPrompt.visionUserPrompt(3),
      );
    });

    test('sends the text path schema and schema name, unchanged', () async {
      // Arrange
      final client = _answering();

      // Act
      await _classifier(client)
          .classify(_threePages(), options: const ClassificationOptions());

      // Assert
      final request = client.requests.single;
      expect(request.responseSchema, MenuAnalysisPrompt.responseSchema());
      expect(request.schemaName, MenuAnalysisPrompt.schemaName);
    });

    test('announces the model engine before sending', () async {
      // Arrange
      final announced = <ClassifyingEngine>[];
      final options = ClassificationOptions(
        estimationConsentGiven: true,
        onEngineStarted: announced.add,
      );

      // Act
      await _classifier(_answering()).classify(_threePages(), options: options);

      // Assert
      expect(announced, <ClassifyingEngine>[ClassifyingEngine.llm]);
    });

    test('an empty scan sends nothing and is noDishesFound', () async {
      // Arrange
      final client = _answering();

      // Act
      final result = await _classifier(client)
          .classify(ScannedMenu(pages: const []), options: _steered);

      // Assert
      expect(client.requests, isEmpty);
      expect(
        result,
        const ScannedMenuFailed(
          reason: MenuAnalysisFailureReason.noDishesFound,
        ),
      );
    });
  });

  group('VisionMenuClassifier read', () {
    test('addresses the menu by the hex of the clock stamp', () async {
      // Act
      final result = await _classifier(_answering())
          .classify(_threePages(), options: _steered);

      // Assert
      final read = result as ScannedMenuRead;
      expect(
        read.menu.venueRef,
        VenueRef(
          source: MenuSource.scan,
          platformId: _now.millisecondsSinceEpoch.toRadixString(16),
        ),
      );
      expect(read.menu.fetchedAt, _now);
      expect(read.analysis.analysedAt, _now);
    });

    test('stamps the reporting model and records the options', () async {
      // Act
      final result = await _classifier(_answering())
          .classify(_threePages(), options: _steered);

      // Assert
      final read = result as ScannedMenuRead;
      expect(read.analysis.engine, const LlmEngine(model: _model));
      expect(read.analysis.options, _steered.snapshot);
    });

    test('holds the parser to the limit the options state', () async {
      // Act: at 10 g the fixture's 9 g skewers stay green.
      final result = await _classifier(_answering())
          .classify(_threePages(), options: _steered);

      // Assert
      final skewers = (result as ScannedMenuRead).analysis.dishes.last;
      expect(skewers.verdict, DishVerdict.orderAsIs);
    });

    test('a reply the parser rejects is badResponse', () async {
      // Arrange
      final client = FakeLlmChatClient()
        ..fallback = const ChatCompleted(content: 'not json', model: _model);

      // Act
      final result = await _classifier(client)
          .classify(_threePages(), options: _steered);

      // Assert
      expect(
        result,
        const ScannedMenuFailed(reason: MenuAnalysisFailureReason.badResponse),
      );
    });

    test('a reply with no dish is noDishesFound', () async {
      // Arrange
      final client = FakeLlmChatClient()
        ..fallback = const ChatCompleted(
          content: '{"dishes": []}',
          model: _model,
        );

      // Act
      final result = await _classifier(client)
          .classify(_threePages(), options: _steered);

      // Assert
      expect(
        result,
        const ScannedMenuFailed(
          reason: MenuAnalysisFailureReason.noDishesFound,
        ),
      );
    });
  });

  group('VisionMenuClassifier chat failures', () {
    const expected = <ChatFailureReason, MenuAnalysisFailureReason>{
      ChatFailureReason.notConfigured: MenuAnalysisFailureReason.notConfigured,
      ChatFailureReason.offline: MenuAnalysisFailureReason.offline,
      ChatFailureReason.timeout: MenuAnalysisFailureReason.timeout,
      ChatFailureReason.rateLimited: MenuAnalysisFailureReason.rateLimited,
      ChatFailureReason.badResponse: MenuAnalysisFailureReason.badResponse,
      ChatFailureReason.backendUnreachable:
          MenuAnalysisFailureReason.backendUnreachable,
      ChatFailureReason.apiKeyMissing: MenuAnalysisFailureReason.apiKeyMissing,
      ChatFailureReason.apiKeyRejected:
          MenuAnalysisFailureReason.apiKeyRejected,
    };

    test('covers every chat failure reason', () {
      // Assert
      expect(expected.keys.toSet(), ChatFailureReason.values.toSet());
    });

    for (final entry in expected.entries) {
      test('${entry.key.name} maps to ${entry.value.name}', () async {
        // Arrange
        final client = FakeLlmChatClient()
          ..fallback = ChatFailed(reason: entry.key);

        // Act
        final result = await _classifier(client)
            .classify(_threePages(), options: _steered);

        // Assert
        expect(result, ScannedMenuFailed(reason: entry.value));
      });
    }
  });
}

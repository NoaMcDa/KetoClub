import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/scanned_menu.dart';
import 'package:ketoclub/services/classifier/menu_classifier.dart';
import 'package:ketoclub/services/classifier/scanned_classifier_router.dart';
import 'package:ketoclub/services/classifier/scanned_menu_classifier.dart';
import 'package:ketoclub/services/classifier/vision_menu_classifier.dart';
import 'package:ketoclub/services/llm/llm_chat_client.dart';

import '../../fakes/fake_clock.dart';
import '../../fakes/fake_connectivity.dart';
import '../../fakes/fake_llm_chat_client.dart';
import '../../fakes/fake_scanned_menu_classifier.dart';
import 'scanned_menu_classifier_contract.dart';

/// Options with the user's consent to AI analysis.
const ClassificationOptions _consented = ClassificationOptions(
  estimationConsentGiven: true,
);

/// A one-page scan.
ScannedMenu _onePage() => ScannedMenu(
  pages: <ScannedPage>[
    ScannedPage(
      mimeType: ScannedPage.jpeg,
      bytes: Uint8List.fromList(<int>[0xff, 0xd8, 0xff, 0xd9]),
    ),
  ],
);

/// A router over the real vision engine and [client], online per
/// [online].
RoutingScannedMenuClassifier _overClient(
  FakeLlmChatClient client, {
  bool online = true,
}) => RoutingScannedMenuClassifier(
  vision: VisionMenuClassifier(
    client: client,
    clock: FakeClock(DateTime.utc(2026, 9, 29)),
  ),
  connectivity: FakeConnectivity(online: online),
);

void main() {
  runScannedMenuClassifierContract<RoutingScannedMenuClassifier>(
    'RoutingScannedMenuClassifier (over the fake vision engine)',
    () => RoutingScannedMenuClassifier(
      vision: FakeScannedMenuClassifier(),
      connectivity: FakeConnectivity(),
    ),
  );
  runScannedMenuClassifierContract<RoutingScannedMenuClassifier>(
    'RoutingScannedMenuClassifier (over the real vision engine)',
    () => _overClient(
      FakeLlmChatClient()
        ..fallback = ChatCompleted(
          content: File('test/fixtures/llm/llm_scanned_valid.json')
              .readAsStringSync(),
          model: 'm',
        ),
    ),
  );

  group('RoutingScannedMenuClassifier', () {
    test('consent withheld: consentWithheld, and no page is sent', () async {
      // Arrange
      final client = FakeLlmChatClient();
      final connectivity = FakeConnectivity();
      final vision = FakeScannedMenuClassifier();
      final router = RoutingScannedMenuClassifier(
        vision: vision,
        connectivity: connectivity,
      );

      // Act
      final result = await router.classify(
        _onePage(),
        options: const ClassificationOptions(),
      );
      final realResult = await _overClient(client)
          .classify(_onePage(), options: const ClassificationOptions());

      // Assert
      const withheld = ScannedMenuFailed(
        reason: MenuAnalysisFailureReason.consentWithheld,
      );
      expect(result, withheld);
      expect(realResult, withheld);
      expect(vision.calls, isEmpty);
      expect(client.requests, isEmpty);
    });

    test('offline: offline, and the vision engine is never asked', () async {
      // Arrange
      final vision = FakeScannedMenuClassifier();
      final router = RoutingScannedMenuClassifier(
        vision: vision,
        connectivity: FakeConnectivity(online: false),
      );

      // Act
      final result = await router.classify(_onePage(), options: _consented);

      // Assert
      expect(
        result,
        const ScannedMenuFailed(reason: MenuAnalysisFailureReason.offline),
      );
      expect(vision.calls, isEmpty);
    });

    test('online with consent: the vision result, as it is', () async {
      // Arrange
      final vision = FakeScannedMenuClassifier();
      final router = RoutingScannedMenuClassifier(
        vision: vision,
        connectivity: FakeConnectivity(),
      );

      // Act
      final result = await router.classify(_onePage(), options: _consented);

      // Assert
      expect(result, isA<ScannedMenuRead>());
      expect(vision.calls.single.$2, _consented);
    });

    test('no rules fallback: every chat failure reaches the caller, mapped '
        'one to one', () async {
      for (final reason in ChatFailureReason.values) {
        // Arrange
        final client = FakeLlmChatClient()
          ..fallback = ChatFailed(reason: reason);

        // Act
        final result = await _overClient(client)
            .classify(_onePage(), options: _consented);

        // Assert: same name on both sides of the mapping.
        expect(result, isA<ScannedMenuFailed>(), reason: reason.name);
        expect(
          (result as ScannedMenuFailed).reason.name,
          reason.name,
          reason: reason.name,
        );
        expect(client.requests, hasLength(1));
      }
    });

    test('an empty transcription is noDishesFound', () async {
      // Arrange
      final client = FakeLlmChatClient()
        ..fallback = const ChatCompleted(content: '{"dishes":[]}', model: 'm');

      // Act
      final result = await _overClient(client)
          .classify(_onePage(), options: _consented);

      // Assert
      expect(
        result,
        const ScannedMenuFailed(
          reason: MenuAnalysisFailureReason.noDishesFound,
        ),
      );
    });
  });
}

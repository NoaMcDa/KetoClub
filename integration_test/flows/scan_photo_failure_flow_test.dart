// Flow test (FLOW_TEST_CONVENTIONS.md, architecture.md §10, §18.4; issue
// #84, D15): the vision model's request fails with `offline`, and the Scan
// tab says so in its own scan copy (there is no rules fallback for a
// photograph), keeps the pages, and Retry calls the model again.
//
// Connectivity reports online, so the router does not short-circuit: the
// failure comes from the call itself, through the real
// `VisionMenuClassifier`, exactly as a dropped connection mid-request would.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/scanned_menu.dart';
import 'package:ketoclub/services/llm/llm_chat_client.dart';
import 'package:ketoclub/widgets/dish_card.dart';
import 'package:ketoclub/widgets/scan_failure_copy.dart';

import 'flow_support.dart';

/// The English strings this test reads expected copy from, computed the
/// same way the app itself does.
final AppLocalizations _en = AppLocalizationsEn();

/// The Analyse-pages button on the Scan tab.
Finder get _analysePages =>
    find.widgetWithText(FilledButton, _en.scanScreenAnalysePages);

/// The Retry button the failure copy offers.
Finder get _retry => find.widgetWithText(OutlinedButton, _en.actionRetry);

/// Gives the surface a phone-tall viewport, so a lazy `ListView` builds
/// every card (CLAUDE.md's traps); reset when the test ends.
void _useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// The scan copy for an offline failure, computed by the app's own function.
String get _offlineCopy => scanFailureMessage(
  MenuAnalysisFailureReason.offline,
  _en,
  directToGoogle: false,
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Scan photo failure flow', () {
    testWidgets(
      'an offline answer keeps the pages and Retry calls the model again',
      (tester) async {
        // Setup: the model will answer offline twice, then a valid menu.
        _useTallSurface(tester);
        final fakes = FakeAppDependencies();
        final client = FlowFakeLlmChatClient()
          ..enqueue(const ChatFailed(reason: ChatFailureReason.offline))
          ..enqueue(const ChatFailed(reason: ChatFailureReason.offline));
        fakes.scannedClassifierOverride = realScannedClassifier(fakes, client);
        fakes.pagePicker.images = [
          ScannedPage(mimeType: ScannedPage.png, bytes: whitePngBytes),
          ScannedPage(mimeType: ScannedPage.png, bytes: blackPngBytes),
        ];
        await pumpApp(tester, fakes);
        await tapAndSettle(tester, navDestination(_en.navScan));
        await tapAndSettle(tester, find.text(_en.scanScreenModePages));
        await tapAndSettle(tester, find.text(_en.scanScreenActionChoosePhotos));
        expect(_retry, findsNothing);

        // Act: analyse the pages; the request fails.
        await tapAndSettle(tester, _analysePages);

        // Assert: the scan copy for offline, not the rules-fallback copy,
        // with the pages still listed and no menu opened.
        expect(client.calls, hasLength(1));
        expect(find.text(_offlineCopy), findsOneWidget);
        expect(_offlineCopy, _en.scanScreenFailureOffline);
        expect(find.text(_en.analysisOffline), findsNothing);
        expect(find.text(_en.scanScreenPageCount(2, 6)), findsOneWidget);
        expect(find.text(_en.scanScreenPageLabel(1)), findsOneWidget);
        expect(find.text(_en.scanScreenPageLabel(2)), findsOneWidget);
        expect(find.byType(DishCard), findsNothing);
        expect(_retry, findsOneWidget);

        // Act: Retry while the model still answers offline.
        await tapAndSettle(tester, _retry);

        // Assert: the client was called again with the same two pages, and
        // the same copy and pages are still there.
        expect(client.calls, hasLength(2));
        expect(client.calls[1].images, hasLength(2));
        expect(client.calls[1].images[0].bytes, orderedEquals(whitePngBytes));
        expect(client.calls[1].images[1].bytes, orderedEquals(blackPngBytes));
        expect(find.text(_offlineCopy), findsOneWidget);
        expect(find.text(_en.scanScreenPageCount(2, 6)), findsOneWidget);

        // Act: the connection is back; Retry once more.
        client.enqueueReply(validScannedReply(2));
        await tapAndSettle(tester, _retry);

        // Assert: the menu opens with the transcribed dishes.
        expect(client.calls, hasLength(3));
        expect(find.byType(DishCard), findsNWidgets(2));
        expect(find.text(scannedReplyDishNames[0]), findsOneWidget);
        expect(find.text(scannedReplyDishNames[1]), findsOneWidget);
        expect(find.text(_en.scannedMenuReadByAi), findsOneWidget);
      },
    );
  });
}

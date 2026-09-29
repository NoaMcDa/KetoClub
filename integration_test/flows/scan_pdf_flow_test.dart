// Flow test (FLOW_TEST_CONVENTIONS.md, architecture.md §6.2, §18.4; issue
// #84, D15): the journey of choosing one PDF menu on the Scan tab. The real
// vision path runs over a faked chat client, which must receive exactly one
// `application/pdf` part; the menu's page sheet shows a PDF tile, never a
// thumbnail, since a PDF is not rendered.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/models/scanned_menu.dart';
import 'package:ketoclub/services/classifier/menu_analysis_prompt.dart';
import 'package:ketoclub/services/llm/llm_chat_client.dart';
import 'package:ketoclub/widgets/dish_card.dart';
import 'package:ketoclub/widgets/scanned_pages_sheet.dart';

import 'flow_support.dart';

/// The English strings this test reads expected copy from, computed the
/// same way the app itself does.
final AppLocalizations _en = AppLocalizationsEn();

/// The Analyse-pages button on the Scan tab.
Finder get _analysePages =>
    find.widgetWithText(ElevatedButton, _en.scanScreenAnalysePages);

/// Gives the surface a phone-tall viewport, so a lazy `ListView` builds
/// every card (CLAUDE.md's traps); reset when the test ends.
void _useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Scan PDF flow', () {
    testWidgets(
      'one chosen PDF is sent as one application/pdf part and read as a menu',
      (tester) async {
        // Setup: the real vision path over a faked chat client.
        _useTallSurface(tester);
        final fakes = FakeAppDependencies();
        final client = FlowFakeLlmChatClient()
          ..enqueueReply(validScannedReply(2));
        fakes.scannedClassifierOverride = realScannedClassifier(fakes, client);
        fakes.pagePicker.pdf = [
          ScannedPage(mimeType: ScannedPage.pdf, bytes: pdfBytes),
        ];
        await pumpApp(tester, fakes);

        // Act: open the Scan tab and choose the PDF.
        await tapAndSettle(tester, navDestination(_en.navScan));
        await tapAndSettle(tester, find.text(_en.scanScreenActionChoosePdf));

        // Assert: one page is listed, labelled as a document.
        expect(fakes.pagePicker.calls, ['pickPdf']);
        expect(find.text(_en.scanScreenPageCount(1, 6)), findsOneWidget);
        expect(find.text(_en.scanScreenPdfLabel), findsOneWidget);

        // Act: analyse it.
        await tapAndSettle(tester, _analysePages);

        // Assert: exactly one request with exactly one PDF part.
        expect(client.calls, hasLength(1));
        final call = client.calls.single;
        expect(call.images, hasLength(1));
        expect(call.images.single.mimeType, ChatImagePart.pdf);
        expect(call.images.single.bytes, orderedEquals(pdfBytes));
        expect(
          call.systemPrompt,
          contains(MenuAnalysisPrompt.visionPreamble(1)),
        );
        expect(call.schemaName, MenuAnalysisPrompt.schemaName);

        // Assert: the menu screen shows the transcribed dishes and the
        // honest source line, with no price.
        expect(find.byType(DishCard), findsNWidgets(2));
        expect(find.text(scannedReplyDishNames[0]), findsOneWidget);
        expect(find.text(scannedReplyDishNames[1]), findsOneWidget);
        expect(find.text(_en.scannedMenuReadByAi), findsOneWidget);
        expect(find.textContaining('₪'), findsNothing);

        // Act: open the pages the menu was read from.
        await tapAndSettle(tester, find.text(_en.scannedMenuViewPages));

        // Assert: the sheet holds a PDF tile and no image thumbnail.
        expect(find.byType(ScannedPagesSheet), findsOneWidget);
        expect(find.text(_en.scannedMenuPdfPage), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(ScannedPagesSheet),
            matching: find.byType(Image),
          ),
          findsNothing,
        );
      },
    );
  });
}

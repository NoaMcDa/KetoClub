// Flow test (FLOW_TEST_CONVENTIONS.md, architecture.md §6.2, §18.4; issue
// #84, D15): the journey of choosing two photographed menu pages on the Scan
// tab, having the vision model read them, and seeing the transcribed menu
// headed by the page each dish was read from (issue #296).
//
// The real `RoutingScannedMenuClassifier`, `VisionMenuClassifier`, prompt
// builder and response parser run; only the `LlmChatClient` at the far end is
// faked, so the request the app would send is asserted, not assumed.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/models/scanned_menu.dart';
import 'package:ketoclub/services/classifier/menu_analysis_prompt.dart';
import 'package:ketoclub/services/llm/llm_chat_client.dart';
import 'package:ketoclub/widgets/dish_card.dart';
import 'package:ketoclub/widgets/engine_chip.dart';
import 'package:ketoclub/widgets/scanned_page_chips.dart';
import 'package:ketoclub/widgets/scanned_page_header.dart';
import 'package:ketoclub/widgets/scanned_pages_sheet.dart';
import 'package:ketoclub/widgets/verdict_counter_tiles.dart';

import 'flow_support.dart';

/// The English strings this test reads expected copy from, computed the
/// same way the app itself does.
final AppLocalizations _en = AppLocalizationsEn();

/// The Analyse-pages button on the Scan tab.
Finder get _analysePages =>
    find.widgetWithText(FilledButton, _en.scanScreenAnalysePages);

/// The chip labelled [label] in the menu's page chip row (issue #296).
Finder _pageChip(String label) => find.descendant(
  of: find.byType(ScannedPageChips),
  matching: find.text(label),
);

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

  group('Scan photo flow', () {
    testWidgets(
      'two chosen photos are read in one request and shown as a scanned menu',
      (tester) async {
        // Setup: the real vision path over a faked chat client that will
        // answer with a valid two-dish transcription, one dish per page.
        _useTallSurface(tester);
        final fakes = FakeAppDependencies();
        final client = FlowFakeLlmChatClient()
          ..enqueueReply(validScannedReply(2, pages: [1, 2]));
        fakes.scannedClassifierOverride = realScannedClassifier(fakes, client);
        fakes.pagePicker.images = [
          ScannedPage(mimeType: ScannedPage.png, bytes: whitePngBytes),
          ScannedPage(mimeType: ScannedPage.png, bytes: blackPngBytes),
        ];
        await pumpApp(tester, fakes);

        // Act: open the Scan tab and choose the photos.
        await tapAndSettle(tester, navDestination(_en.navScan));
        await tapAndSettle(tester, find.text(_en.scanScreenModePages));
        expect(tester.widget<FilledButton>(_analysePages).onPressed, isNull);
        await tapAndSettle(tester, find.text(_en.scanScreenActionChoosePhotos));

        // Assert: both pages are listed and Analyse is now enabled.
        expect(fakes.pagePicker.calls, ['pickImages']);
        expect(find.text(_en.scanScreenPageCount(2, 6)), findsOneWidget);
        expect(find.text(_en.scanScreenPageLabel(1)), findsOneWidget);
        expect(find.text(_en.scanScreenPageLabel(2)), findsOneWidget);
        expect(tester.widget<FilledButton>(_analysePages).onPressed, isNotNull);

        // Act: tap the first thumbnail to preview it.
        await tapAndSettle(
          tester,
          find
              .descendant(
                of: find.byType(ReorderableListView),
                matching: find.byType(Image),
              )
              .first,
        );

        // Assert: the pages sheet opens at that page, full screen.
        expect(find.byType(ScannedPagesSheet), findsOneWidget);
        expect(
          tester
              .widget<ScannedPagesSheet>(find.byType(ScannedPagesSheet))
              .initialPage,
          0,
        );
        expect(find.byType(InteractiveViewer), findsOneWidget);

        // Act: close the full-screen view, then the sheet.
        await tapAndSettle(
          tester,
          find.descendant(
            of: find.byType(Dialog),
            matching: find.byTooltip(_en.scannedMenuPagesClose),
          ),
        );
        await tapAndSettle(tester, find.byTooltip(_en.scannedMenuPagesClose));
        expect(find.byType(ScannedPagesSheet), findsNothing);

        // Act: drag the first page below the second by its handle.
        await tester.drag(
          find.byTooltip(_en.scanScreenReorderPage(1)),
          const Offset(0, 200),
        );
        await tester.pumpAndSettle();

        // Act: analyse the pages.
        await tapAndSettle(tester, _analysePages);

        // Assert: exactly one request, carrying both pages in the order
        // the user arranged (black first now), under the vision preamble
        // and the text path's own schema name.
        expect(client.calls, hasLength(1));
        final call = client.calls.single;
        expect(call.images, hasLength(2));
        expect(call.images.map((image) => image.mimeType), [
          ChatImagePart.png,
          ChatImagePart.png,
        ]);
        expect(call.images[0].bytes, orderedEquals(blackPngBytes));
        expect(call.images[1].bytes, orderedEquals(whitePngBytes));
        expect(
          call.systemPrompt,
          contains(MenuAnalysisPrompt.visionPreamble(2)),
        );
        expect(call.schemaName, MenuAnalysisPrompt.schemaName);

        // Assert: the menu screen shows the transcribed dishes, the
        // scanned source and the honest "read by AI" line.
        expect(find.byType(VerdictCounterTiles), findsOneWidget);
        expect(find.byType(EngineChip), findsOneWidget);
        expect(find.byType(DishCard), findsNWidgets(2));
        expect(find.text(scannedReplyDishNames[0]), findsOneWidget);
        expect(find.text(scannedReplyDishNames[1]), findsOneWidget);
        expect(find.text(_en.scannedMenuReadByAi), findsOneWidget);
        expect(find.textContaining(_en.scannedMenuTitle), findsWidgets);

        // Assert: a scan has no price, so no currency symbol anywhere.
        expect(find.textContaining('₪'), findsNothing);

        // Assert: each dish is headed by its page, of two (issue #296).
        expect(find.byType(ScannedPageHeader), findsNWidgets(2));
        expect(find.text(_en.scannedPageHeader(1, 2)), findsOneWidget);
        expect(find.text(_en.scannedPageHeader(2, 2)), findsOneWidget);

        // Act: keep page 2 only.
        await tapAndSettle(tester, _pageChip(_en.scannedMenuPageLabel(2)));

        // Assert
        expect(find.byType(DishCard), findsOneWidget);
        expect(find.text(scannedReplyDishNames[1]), findsOneWidget);
        expect(find.text(_en.scannedPageHeader(1, 2)), findsNothing);

        // Act: every page again, then open page 1 from its header.
        await tapAndSettle(tester, _pageChip(_en.scannedPageChipAll));
        expect(find.byType(DishCard), findsNWidgets(2));
        await tapAndSettle(
          tester,
          find.byKey(const ValueKey('scannedPageHeader-1')),
        );

        // Assert: the pages sheet opens at page 1.
        expect(find.byType(ScannedPagesSheet), findsOneWidget);
        expect(
          tester
              .widget<ScannedPagesSheet>(find.byType(ScannedPagesSheet))
              .initialPage,
          0,
        );

        // Act: close the full-screen view, then the sheet.
        await tapAndSettle(
          tester,
          find.descendant(
            of: find.byType(Dialog),
            matching: find.byTooltip(_en.scannedMenuPagesClose),
          ),
        );
        await tapAndSettle(tester, find.byTooltip(_en.scannedMenuPagesClose));
        expect(find.byType(ScannedPagesSheet), findsNothing);

        // Act: open the pages the menu was read from.
        await tapAndSettle(tester, find.text(_en.scannedMenuViewPages));

        // Assert: the sheet shows one thumbnail per page, in order.
        expect(find.byType(ScannedPagesSheet), findsOneWidget);
        expect(find.text(_en.scannedMenuPagesTitle), findsOneWidget);
        final thumbnails = find.descendant(
          of: find.byType(ScannedPagesSheet),
          matching: find.byType(Image),
        );
        expect(thumbnails, findsNWidgets(2));
        expect(
          find.bySemanticsLabel(_en.scannedMenuPageLabel(1)),
          findsOneWidget,
        );
        expect(
          find.bySemanticsLabel(_en.scannedMenuPageLabel(2)),
          findsOneWidget,
        );
        expect(find.text(_en.scannedMenuPdfPage), findsNothing);
        expect(find.textContaining('₪'), findsNothing);
      },
    );
  });
}

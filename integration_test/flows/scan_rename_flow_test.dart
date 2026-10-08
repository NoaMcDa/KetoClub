// Flow test (FLOW_TEST_CONVENTIONS.md, architecture.md §6.2, §18.4; issue
// #315, D15, D24): the journey of naming a scanned menu. Two photographed
// pages are read, the menu is renamed from the menu screen's overflow, and
// the name and city show on the menu, on the Recent tab and in the menu the
// app shares with the store; scanning the same pages again keeps them.
//
// The real vision path runs over a faked chat client, as in
// `scan_photo_flow_test.dart`.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/models/scanned_menu.dart';
import 'package:ketoclub/widgets/dish_card.dart';

import 'flow_support.dart';

/// The English strings this test reads expected copy from, computed the
/// same way the app itself does.
final AppLocalizations _en = AppLocalizationsEn();

/// The Analyse-pages button on the Scan tab.
Finder get _analysePages =>
    find.widgetWithText(FilledButton, _en.scanScreenAnalysePages);

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

  group('Scan rename flow', () {
    testWidgets(
      'a renamed scan shows its name and city on the menu, on Recent and in '
      'the store upload, and keeps them when the same pages are scanned again',
      (tester) async {
        // Setup: the real vision path; the fake answers both scans alike,
        // so both read to the same fingerprint reference.
        _useTallSurface(tester);
        final fakes = FakeAppDependencies();
        final client = FlowFakeLlmChatClient()
          ..enqueueReply(validScannedReply(2, pages: [1, 2]))
          ..enqueueReply(validScannedReply(2, pages: [1, 2]));
        fakes.scannedClassifierOverride = realScannedClassifier(fakes, client);
        fakes.pagePicker.images = [
          ScannedPage(mimeType: ScannedPage.png, bytes: whitePngBytes),
          ScannedPage(mimeType: ScannedPage.png, bytes: blackPngBytes),
        ];
        await pumpApp(tester, fakes);

        // Act: photograph the pages and analyse them.
        await tapAndSettle(tester, navDestination(_en.navScan));
        await tapAndSettle(tester, find.text(_en.scanScreenModePages));
        await tapAndSettle(tester, find.text(_en.scanScreenActionChoosePhotos));
        await tapAndSettle(tester, _analysePages);

        // Assert: the scan opened, unnamed, with a Rename action.
        expect(find.byType(DishCard), findsNWidgets(2));
        await tapAndSettle(tester, find.byTooltip(_en.actionMoreMenuOptions));
        expect(find.text(_en.menuRenameAction), findsOneWidget);

        // Act: rename it.
        await tapAndSettle(tester, find.text(_en.menuRenameAction));
        expect(find.text(_en.menuRenameTitle), findsOneWidget);
        await tester.enterText(
          find.byKey(const ValueKey('menuRenameName')),
          'Café Noam',
        );
        await tester.enterText(
          find.byKey(const ValueKey('menuRenameCity')),
          'Haifa',
        );
        await tapAndSettle(
          tester,
          find.byKey(const ValueKey('menuRenameSave')),
        );

        // Assert: the header and the source line changed in place.
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.text('Café Noam'), findsOneWidget);
        expect(
          find.textContaining(
            _en.sourceWithCity(_en.scannedMenuTitle, 'Haifa'),
          ),
          findsOneWidget,
        );

        // Assert: the store was told the name and city.
        final upload = fakes.menuStoreClient.uploads.last;
        expect(upload.venueName, 'Café Noam');
        expect(upload.city, 'Haifa');

        // Act: back to the Scan tab, then to Recent.
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tapAndSettle(tester, navDestination(_en.navSaved));

        // Assert: the row carries the name and city.
        expect(find.text('Café Noam'), findsOneWidget);
        expect(
          find.textContaining(_en.sourceWithCity(_en.sourceScanned, 'Haifa')),
          findsOneWidget,
        );

        // Act: photograph the same pages again (a finished scan clears the
        // Scan tab) and analyse them.
        await tapAndSettle(tester, navDestination(_en.navScan));
        await tapAndSettle(tester, find.text(_en.scanScreenActionChoosePhotos));
        await tapAndSettle(tester, _analysePages);

        // Assert: the same menu, still named; the second read was spent.
        expect(client.calls, hasLength(2));
        expect(find.byType(DishCard), findsNWidgets(2));
        expect(find.text('Café Noam'), findsOneWidget);
        expect(
          find.textContaining(
            _en.sourceWithCity(_en.scannedMenuTitle, 'Haifa'),
          ),
          findsOneWidget,
        );
        expect(fakes.menuStoreClient.uploads.last.venueName, 'Café Noam');
      },
    );
  });
}

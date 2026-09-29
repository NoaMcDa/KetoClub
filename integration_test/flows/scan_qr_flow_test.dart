// Flow test (FLOW_TEST_CONVENTIONS.md, architecture.md §6.6, §18.4; issue
// #182): "Scan QR code" on the Scan tab reads a table's QR code and lands on
// the right screen for what it holds.
//
// The camera is faked by one `FlowFakeQrScanner` that answers each kind of
// payload a table carries (docs/menu_sources_research.md §3.6); everything
// from the decoded text on is real: `QrPayloadRouter`, `ScanController`, the
// route and the menu screen. A menu link opens that venue's classified menu,
// and the classifier's recorded call proves which venue it was. A Tabit
// code, an Instagram profile and plain text stay on the Scan tab with copy
// that says why.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/widgets/engine_chip.dart';
import 'package:ketoclub/widgets/verdict_counter_tiles.dart';

import 'flow_support.dart';

/// The English strings this test reads expected copy from, computed the
/// same way the app itself does.
final AppLocalizations _en = AppLocalizationsEn();

/// The one dish every stubbed menu carries.
const String _dishName = 'Grilled Salmon';

/// A menu for [ref] with a single dish, so a screen showing it proves the
/// app opened [ref].
MenuFetched _menu(VenueRef ref) => MenuFetched(
  menu: Menu(
    venueRef: ref,
    currency: 'ILS',
    fetchedAt: DateTime.utc(2026),
    categories: const [
      MenuCategory(
        id: 'c1',
        name: 'Mains',
        dishes: [
          Dish(
            id: 'd1',
            name: _dishName,
            description: '',
            price: 44,
            options: <DishOption>[],
          ),
        ],
      ),
    ],
  ),
);

/// The "Scan QR code" action on the Scan tab.
Finder get _scanQr => find.ancestor(
  of: find.text(_en.scanQrAction),
  matching: find.bySubtype<OutlinedButton>(),
);

/// Opens the Scan tab over [fakes] and taps "Scan QR code".
Future<void> _scan(WidgetTester tester, FakeAppDependencies fakes) async {
  await pumpApp(tester, fakes);
  await tapAndSettle(tester, navDestination(_en.navScan));
  await tapAndSettle(tester, _scanQr);
}

/// What a menu screen for a scanned venue shows.
void _expectMenuOpened(FakeAppDependencies fakes, VenueRef ref) {
  expect(find.byType(VerdictCounterTiles), findsOneWidget);
  expect(find.byType(EngineChip), findsOneWidget);
  expect(find.text(_dishName), findsOneWidget);
  expect(fakes.classifier.calls.single.venueRef, ref);
}

/// What the Scan tab shows when a code leads to no menu.
void _expectStayedOnScanTab(FakeAppDependencies fakes) {
  expect(find.text(_en.scanTitle), findsWidgets);
  expect(find.byType(VerdictCounterTiles), findsNothing);
  expect(find.text(_dishName), findsNothing);
  expect(fakes.classifier.calls, isEmpty);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Scan QR flow', () {
    testWidgets("a Wolt code opens that venue's classified menu", (
      tester,
    ) async {
      // Setup
      const ref = VenueRef(
        source: MenuSource.wolt,
        platformId: 'vitrina-lilinblum',
      );
      final fakes = FakeAppDependencies();
      fakes.repository.stub(ref, _menu(ref));
      fakes.qrScanner.payload =
          'https://wolt.com/en/isr/tel-aviv/restaurant/vitrina-lilinblum';

      // Act
      await _scan(tester, fakes);

      // Assert
      _expectMenuOpened(fakes, ref);
      expect(fakes.qrScanner.scanCallCount, 1);
    });

    testWidgets("a 10bis code opens that restaurant's classified menu", (
      tester,
    ) async {
      // Setup
      const ref = VenueRef(source: MenuSource.tenbis, platformId: '654321');
      final fakes = FakeAppDependencies();
      fakes.repository.stub(ref, _menu(ref));
      fakes.qrScanner.payload =
          'https://www.10bis.co.il/next/restaurants/menu/delivery/654321/x';

      // Act
      await _scan(tester, fakes);

      // Assert
      _expectMenuOpened(fakes, ref);
      expect(find.textContaining('10bis'), findsWidgets);
    });

    testWidgets('a Wix site or QR-menu page opens as a website menu', (
      tester,
    ) async {
      // Setup
      const ref = VenueRef(
        source: MenuSource.website,
        platformId: 'https://someone.wixsite.com/resto/menu',
      );
      final fakes = FakeAppDependencies();
      fakes.repository.stub(ref, _menu(ref));
      fakes.qrScanner.payload = 'https://someone.wixsite.com/resto/menu';

      // Act
      await _scan(tester, fakes);

      // Assert: labelled with the site's host, as a pasted URL is (D19).
      _expectMenuOpened(fakes, ref);
      expect(find.textContaining('someone.wixsite.com'), findsWidgets);
    });

    testWidgets("a PDF code opens as a website menu on the PDF's URL", (
      tester,
    ) async {
      // Setup: the website adapter fetches a PDF and hands it to the vision
      // path; what the QR route decides is the reference it opens.
      const pdf = 'https://static.rest.co.il/12345678/29092026/menu.pdf';
      const ref = VenueRef(source: MenuSource.website, platformId: pdf);
      final fakes = FakeAppDependencies();
      fakes.repository.stub(ref, _menu(ref));
      fakes.qrScanner.payload = pdf;

      // Act
      await _scan(tester, fakes);

      // Assert
      _expectMenuOpened(fakes, ref);
    });

    testWidgets('a Tabit code says Tabit is not supported yet', (tester) async {
      // Setup
      final fakes = FakeAppDependencies();
      fakes.qrScanner.payload =
          'https://tabitisrael.co.il/tabit-order?siteName=cafe-noa';

      // Act
      await _scan(tester, fakes);

      // Assert
      expect(find.text(_en.scanQrUnsupportedSource('Tabit')), findsOneWidget);
      _expectStayedOnScanTab(fakes);
    });

    testWidgets('an Instagram code suggests photographing the menu', (
      tester,
    ) async {
      // Setup
      final fakes = FakeAppDependencies();
      fakes.qrScanner.payload = 'https://www.instagram.com/cafe.noa/';

      // Act
      await _scan(tester, fakes);

      // Assert
      expect(find.text(_en.scanQrPhotographInstead), findsOneWidget);
      _expectStayedOnScanTab(fakes);
    });

    testWidgets('a code that is not a link suggests photographing too', (
      tester,
    ) async {
      // Setup
      final fakes = FakeAppDependencies();
      fakes.qrScanner.payload = 'Table 12';

      // Act
      await _scan(tester, fakes);

      // Assert
      expect(find.text(_en.scanQrPhotographInstead), findsOneWidget);
      _expectStayedOnScanTab(fakes);
    });

    testWidgets('a cancelled camera changes nothing and can be retried', (
      tester,
    ) async {
      // Setup: the first scan is cancelled, the second reads a Wolt code.
      const ref = VenueRef(source: MenuSource.wolt, platformId: 'a-b');
      final fakes = FakeAppDependencies();
      fakes.repository.stub(ref, _menu(ref));

      // Act: cancelled.
      await _scan(tester, fakes);

      // Assert
      expect(find.text(_en.scanQrPhotographInstead), findsNothing);
      _expectStayedOnScanTab(fakes);

      // Act: a code this time.
      fakes.qrScanner.payload =
          'https://wolt.com/en/isr/tel-aviv/restaurant/a-b';
      await tapAndSettle(tester, _scanQr);

      // Assert
      _expectMenuOpened(fakes, ref);
      expect(fakes.qrScanner.scanCallCount, 2);
    });

    testWidgets('a build with no camera scanner shows no QR action', (
      tester,
    ) async {
      // Setup: web, where pasting the URL already works.
      final fakes = FakeAppDependencies();
      fakes.qrScanner.available = false;
      await pumpApp(tester, fakes);

      // Act
      await tapAndSettle(tester, navDestination(_en.navScan));

      // Assert
      expect(find.text(_en.scanQrAction), findsNothing);
      expect(find.text(_en.scanScreenActionTakePhoto), findsOneWidget);
    });
  });
}

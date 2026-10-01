// Flow test (FLOW_TEST_CONVENTIONS.md, architecture.md §18.4; issue #11):
// the bottom navigation shell — launch, visit every tab, and return to
// Explore without the navigation stack growing underneath the user; and
// (issue #233) a search on Explore is still there after a tab switch.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/venue/venue_search_service.dart';
import 'package:ketoclub/utils/constants.dart';
import 'package:ketoclub/widgets/venue_card.dart';

import 'flow_support.dart';

/// The English strings this test reads expected copy from, computed the
/// same way the app itself does.
final AppLocalizations _en = AppLocalizationsEn();

/// The app bar title reading [title], scoped for the same reason as
/// [navDestination].
Finder _appBarTitle(String title) =>
    find.descendant(of: find.byType(AppBar), matching: find.text(title));

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Tab navigation flow', () {
    testWidgets(
      'user launches the app, visits every tab, and returns to Explore',
      (tester) async {
        // Setup: the app on top of in-memory fakes, no venue stubbed —
        // this journey never leaves the four tab-root screens.
        final fakes = FakeAppDependencies();
        await pumpApp(tester, fakes);

        // Assert: launch lands on Explore.
        expect(find.text(appName), findsOneWidget);
        expect(find.text(_en.venueSearchLabel), findsOneWidget);

        // Act: Scan.
        await tapAndSettle(tester, navDestination(_en.navScan));

        // Assert
        expect(find.text(_en.scanTitle), findsOneWidget);

        // Act: Saved.
        await tapAndSettle(tester, navDestination(_en.navSaved));

        // Assert
        expect(find.text(_en.savedPlaceholderTitle), findsOneWidget);

        // Act: Settings.
        await tapAndSettle(tester, navDestination(_en.navSettings));

        // Assert
        expect(_appBarTitle(_en.settingsTitle), findsOneWidget);

        // Act: back to Explore.
        await tapAndSettle(tester, navDestination(_en.navExplore));

        // Assert: Explore again, and nothing left over from Settings —
        // pushReplacementNamed means the stack never grew, so there is
        // nothing to pop back through.
        expect(find.text(_en.venueSearchLabel), findsOneWidget);
        expect(_appBarTitle(_en.settingsTitle), findsNothing);
      },
    );

    testWidgets(
      'user searches Explore by name, tabs to Saved and back, and finds '
      'the query, the list and the chip as left (issue #233)',
      (tester) async {
        // Setup: one open and one closed venue answer any name search.
        const open = Venue(
          ref: VenueRef(source: MenuSource.wolt, platformId: 'sushi-bar'),
          name: 'Sushi Bar',
          isOnline: true,
        );
        const closed = Venue(
          ref: VenueRef(source: MenuSource.wolt, platformId: 'sushi-shop'),
          name: 'Sushi Shop',
          isOnline: false,
        );
        final fakes = FakeAppDependencies();
        fakes.venueSearchService.result = const VenuesFound([open, closed]);
        await pumpApp(tester, fakes);

        // Act: search by name, then narrow to Open now.
        await tester.enterText(find.byType(TextField), 'sushi');
        await tester.pump(venueSearchDebounce);
        await tester.pumpAndSettle();
        final openNow = find.widgetWithText(
          ChoiceChip,
          _en.discoveryChipOpenNow,
        );
        await tester.ensureVisible(openNow);
        await tapAndSettle(tester, openNow);

        // Assert
        expect(find.text(open.name), findsOneWidget);
        expect(find.text(closed.name), findsNothing);

        // Act: away to Saved and back.
        await tapAndSettle(tester, navDestination(_en.navSaved));
        expect(find.text(_en.savedPlaceholderTitle), findsOneWidget);
        await tapAndSettle(tester, navDestination(_en.navExplore));

        // Assert: the query, the filtered list and the chip are as left,
        // and nothing was searched again.
        expect(
          find.descendant(
            of: find.byType(TextField),
            matching: find.text('sushi'),
          ),
          findsOneWidget,
        );
        expect(find.byType(VenueCard), findsOneWidget);
        expect(find.text(open.name), findsOneWidget);
        expect(tester.widget<ChoiceChip>(openNow).selected, isTrue);
        expect(fakes.venueSearchService.byNameCalls, ['sushi']);
      },
    );
  });
}

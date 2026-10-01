// Flow test (FLOW_TEST_CONVENTIONS.md, architecture.md §18.4; issue #11):
// the bottom navigation shell — launch, visit every tab, and return to
// Explore without the navigation stack growing underneath the user;
// (issue #233) a search on Explore is still there after a tab switch; and
// (issue #262) the browser's Back after a tab switch returns to Explore,
// and a menu's Settings action followed by a tab leaves no menu behind.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/screens/menu_screen.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
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

/// The Wolt venue page the round-trip flow pastes, in the documented
/// `wolt.com/{lang}/{country}/{city}/restaurant/{slug}` form.
const String _woltUrl =
    'https://wolt.com/en/isr/tel-aviv/restaurant/tab-round-trip';

/// The [VenueRef] [_woltUrl] resolves to, and the key the fake repository
/// is stubbed under.
const VenueRef _ref = VenueRef(
  source: MenuSource.wolt,
  platformId: 'tab-round-trip',
);

/// The one dish on [_menu], visible once the menu screen has loaded.
const String _dishName = 'Grilled Salmon';

/// A one-dish [Menu] for [_ref].
Menu _menu() => Menu(
  venueRef: _ref,
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
);

/// Presses the browser's Back button (Android's system back), as the
/// engine reports it, and settles. Only ever pressed here where the app
/// handles it: an unhandled Back would leave the page under test.
Future<void> _pressBack(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
}

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
        final handle = tester.ensureSemantics();
        expect(find.bySemanticsLabel(appName), findsOneWidget);
        handle.dispose();
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
        // each tab replaced the last, so the stack never grew and there
        // is nothing to pop back through.
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

    testWidgets(
      'user switches to Saved and presses the browser Back button, and is '
      'back on Explore rather than off the site (issue #262)',
      (tester) async {
        // Setup
        final fakes = FakeAppDependencies();
        await pumpApp(tester, fakes);

        // Act: Saved, then Back.
        await tapAndSettle(tester, navDestination(_en.navSaved));
        expect(find.text(_en.savedPlaceholderTitle), findsOneWidget);
        await _pressBack(tester);

        // Assert
        expect(find.text(_en.venueSearchLabel), findsOneWidget);
        expect(find.text(_en.savedPlaceholderTitle), findsNothing);
      },
    );

    testWidgets(
      'user opens a menu, its Settings action, goes Back to the menu, then '
      'to Settings again and on to Explore, and no menu is left behind '
      '(audit G8, issue #262)',
      (tester) async {
        // Setup: one venue the pasted link resolves to.
        final fakes = FakeAppDependencies();
        fakes.repository.stub(_ref, MenuFetched(menu: _menu()));
        await pumpApp(tester, fakes);

        // Act: open the menu, then Settings from its app bar.
        await enterText(tester, _woltUrl);
        await tapAndSettle(tester, find.byTooltip(_en.venueSearchOpenLink));
        expect(find.text(_dishName), findsOneWidget);
        await tapAndSettle(tester, find.byTooltip(_en.actionOpenSettings));
        expect(_appBarTitle(_en.settingsTitle), findsOneWidget);

        // Act: Back returns to the menu Settings was opened from.
        await _pressBack(tester);

        // Assert
        expect(find.text(_dishName), findsOneWidget);
        expect(_appBarTitle(_en.settingsTitle), findsNothing);

        // Act: Settings again, then the Explore tab.
        await tapAndSettle(tester, find.byTooltip(_en.actionOpenSettings));
        await tapAndSettle(tester, navDestination(_en.navExplore));

        // Assert: Explore, with no menu screen kept beneath it.
        expect(find.text(_en.venueSearchLabel), findsOneWidget);
        expect(find.byType(MenuScreen, skipOffstage: false), findsNothing);
      },
    );
  });
}

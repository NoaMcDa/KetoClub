// Flow test (FLOW_TEST_CONVENTIONS.md, architecture.md §18.4; issue #312):
// opening a Discovery card records the visit under the card's name and
// city, opening it again counts a second visit, and once the cached menu
// is gone the "Continue with…" row still names the venue from the visit
// history.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/location/location_service.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/services/venue/venue_search_service.dart';
import 'package:ketoclub/widgets/venue_card.dart';

import 'flow_support.dart';

/// The English strings this test reads expected copy from, computed the
/// same way the app itself does.
final AppLocalizations _en = AppLocalizationsEn();

/// The one venue the nearby search finds: a card named and placed the way
/// the search service reports it.
const Venue _venue = Venue(
  ref: VenueRef(source: MenuSource.wolt, platformId: 'ember-vine'),
  name: 'Ember & Vine',
  city: 'Tel Aviv',
);

/// The venue's menu, which — like every real Wolt menu — names no venue.
final Menu _menu = Menu(
  venueRef: _venue.ref,
  currency: 'ILS',
  fetchedAt: DateTime.utc(2026),
  categories: const <MenuCategory>[
    MenuCategory(
      id: 'c1',
      name: 'Mains',
      dishes: <Dish>[
        Dish(
          id: 'dish-1',
          name: 'Grilled Halloumi Salad',
          description: '',
          price: 56,
          options: <DishOption>[],
        ),
      ],
    ),
  ],
);

/// Opens [_venue]'s card and settles on its menu, locating first when
/// [locate] is true. The Explore list outlives a visit to a menu (issue
/// #233), so a second open finds the card still listed.
Future<void> _openCard(WidgetTester tester, {bool locate = false}) async {
  if (locate) {
    await tapAndSettle(tester, find.byTooltip(_en.discoveryUseLocation));
  }
  final card = find.widgetWithText(VenueCard, _venue.name);
  await tester.ensureVisible(card);
  await tester.pumpAndSettle();
  await tapAndSettle(tester, card);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Visit history flow', () {
    testWidgets(
      'opening a card records its name and city, a second open counts a '
      'second visit, and Continue names the venue once the cache is gone',
      (tester) async {
        // Setup: one nearby venue whose menu is stubbed.
        final fakes = FakeAppDependencies();
        fakes.locationService.result = const LocationFound(
          latitude: 32.0809,
          longitude: 34.7806,
          accuracyMetres: 20,
        );
        fakes.venueSearchService.result = const VenuesFound(<Venue>[_venue]);
        fakes.repository.stub(_venue.ref, MenuFetched(menu: _menu));
        await pumpApp(tester, fakes);

        // Act: open the card.
        await _openCard(tester, locate: true);

        // Assert: the header names the venue from the card, and the visit
        // is recorded under that name and city.
        expect(find.text(_venue.name), findsWidgets);
        final first = await fakes.visitHistory.read(_venue.ref);
        expect(first, isNotNull);
        expect(first!.name, _venue.name);
        expect(first.city, _venue.city);
        expect(first.openCount, 1);

        // Act: back to Explore, and open the same card again.
        await tester.pageBack();
        await tester.pumpAndSettle();
        await _openCard(tester);

        // Assert: one more visit, the name and city kept.
        final second = await fakes.visitHistory.read(_venue.ref);
        expect(second!.openCount, 2);
        expect(second.name, _venue.name);
        expect(second.city, _venue.city);

        // Act: back, forget every cached menu, and return to Explore so its
        // "Continue with…" row is read again.
        await tester.pageBack();
        await tester.pumpAndSettle();
        await fakes.repository.clearCache();
        await tapAndSettle(tester, navDestination(_en.navSettings));
        await tapAndSettle(tester, navDestination(_en.navExplore));

        // Assert: the row still names the venue, from the history alone.
        expect(await fakes.repository.savedMenus(), isEmpty);
        expect(
          find.text(_en.venueSearchContinueWith(_venue.name)),
          findsOneWidget,
        );
      },
    );
  });
}

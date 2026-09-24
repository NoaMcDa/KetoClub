// Flow test (FLOW_TEST_CONVENTIONS.md, architecture.md §6.5, §18.4; issue
// #43): locate reads a position and lists the venues around it in the
// search service's own order, one card's cached analysis gives it numbers
// (D13), and opening a card shows that venue's real menu, from the fake
// repository, not a placeholder.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/location/location_service.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/services/storage/menu_cache.dart';
import 'package:ketoclub/services/venue/venue_search_service.dart';
import 'package:ketoclub/widgets/venue_card.dart';

import 'flow_support.dart';

/// The English strings this test reads expected copy from, computed the
/// same way the app itself does.
final AppLocalizations _en = AppLocalizationsEn();

/// The loaded menu's list, named the way `menu_display_flow_test.dart`
/// names it: the screen holds other scrollables (the search field, the
/// category chip row) and `scrollUntilVisible` needs exactly one.
final Finder _menuList = find
    .descendant(of: find.byType(ListView), matching: find.byType(Scrollable))
    .first;

/// A Wolt venue addressed by [slug], with [address] and [isOnline] as the
/// search service would report them.
Venue _venue(String slug, {String? address, bool? isOnline}) => Venue(
  ref: VenueRef(source: MenuSource.wolt, platformId: slug),
  name: 'Venue $slug',
  address: address,
  isOnline: isOnline,
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Discovery locate flow', () {
    testWidgets(
      'locate lists nearby venues in order, with cached numbers on one '
      'card, and opening a card shows its real menu',
      (tester) async {
        // Setup: three venues in the order the search service promises
        // (nearest first) — one offline, one with an analysis already
        // cached on the device (D13), one plain, with its own menu
        // stubbed so opening it can be asserted on.
        final offline = _venue('closed-bistro', isOnline: false);
        final scored = _venue('ember-vine', address: 'Rothschild 22');
        final plain = _venue('salt-stone');
        const plainMenuDish = Dish(
          id: 'dish-1',
          name: 'Grilled Halloumi Salad',
          description: '',
          price: 56,
          options: <DishOption>[],
        );

        final fakes = FakeAppDependencies();
        fakes.locationService.result = const LocationFound(
          latitude: 32.0809,
          longitude: 34.7806,
          accuracyMetres: 20,
        );
        fakes.venueSearchService.result = VenuesFound([offline, scored, plain]);
        fakes.repository.seedCache(
          CachedMenu(
            menu: Menu(
              venueRef: scored.ref,
              currency: 'ILS',
              fetchedAt: DateTime.utc(2026),
              categories: const <MenuCategory>[],
            ),
            analysis: MenuAnalysed(
              dishes: const <AnalysedDish>[
                AnalysedDish(
                  dishId: '1',
                  name: 'Steak',
                  verdict: DishVerdict.orderAsIs,
                  why: 'Nothing starchy here.',
                ),
              ],
              unclassified: const <String>[],
              engine: const LlmEngine(model: 'test-model'),
              analysedAt: DateTime.utc(2026),
            ),
          ),
        );
        fakes.repository.stub(
          plain.ref,
          MenuFetched(
            menu: Menu(
              venueRef: plain.ref,
              venueName: plain.name,
              currency: 'ILS',
              fetchedAt: DateTime.utc(2026),
              categories: const [
                MenuCategory(id: 'c1', name: 'Mains', dishes: [plainMenuDish]),
              ],
            ),
          ),
        );
        await pumpApp(tester, fakes);

        // Act: locate.
        await tapAndSettle(tester, find.byTooltip(_en.discoveryUseLocation));

        // Assert: a card per venue, in the order the search service gave
        // them, and the cached venue's card shows its score.
        expect(find.byType(VenueCard), findsNWidgets(3));
        final offlineY = tester.getTopLeft(find.text(offline.name)).dy;
        final scoredY = tester.getTopLeft(find.text(scored.name)).dy;
        final plainY = tester.getTopLeft(find.text(plain.name)).dy;
        expect(offlineY, lessThan(scoredY));
        expect(scoredY, lessThan(plainY));
        expect(find.text('10.0'), findsOneWidget);

        // Act: open the plain venue's card. It is the third card, below the
        // fold on the web-server surface: the Discovery list is a Column
        // inside a scroll view, so the text exists but a tap at its centre
        // lands outside the viewport and never reaches the card.
        await tester.ensureVisible(find.text(plain.name));
        await tester.pumpAndSettle();
        await tapAndSettle(tester, find.text(plain.name));

        // Assert: its real menu, from the fake repository, is shown —
        // not a placeholder and not another venue's. The dish sits below
        // the header, the rules banner, the tiles, the search field and
        // the chips, so on the web-server surface it is off screen and the
        // lazy list has not built it yet (CLAUDE.md) — scroll to it first.
        await tester.scrollUntilVisible(
          find.text(plainMenuDish.name),
          200,
          scrollable: _menuList,
        );
        await tester.pumpAndSettle();
        expect(find.text(plainMenuDish.name), findsOneWidget);
      },
    );
  });
}

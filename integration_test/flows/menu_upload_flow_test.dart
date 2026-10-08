// Flow test (FLOW_TEST_CONVENTIONS.md, architecture.md §18.4; issue #312,
// D24): with AI-analysis consent on, opening a Discovery card contributes
// its menu to the shared menu store exactly once, under the card's name
// and city; with consent off, nothing is sent.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/location/location_service.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/services/venue/venue_search_service.dart';
import 'package:ketoclub/widgets/venue_card.dart';

import 'flow_support.dart';

/// The English strings this test reads expected copy from, computed the
/// same way the app itself does.
final AppLocalizations _en = AppLocalizationsEn();

/// The one venue the nearby search finds.
const Venue _venue = Venue(
  ref: VenueRef(source: MenuSource.wolt, platformId: 'salt-stone'),
  name: 'Salt & Stone',
  city: 'Haifa',
);

/// The venue's menu, which names no venue, as every real Wolt menu.
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
          name: 'Ribeye',
          description: '',
          price: 120,
          options: <DishOption>[],
        ),
      ],
    ),
  ],
);

/// A dependency set that finds [_venue] nearby and serves its menu, with
/// AI-analysis consent set to [consent].
Future<FakeAppDependencies> _fakes({required bool consent}) async {
  final fakes = FakeAppDependencies();
  await fakes.settingsStore.write(
    AppSettings(estimationConsentGiven: consent, disclosureSeen: true),
  );
  fakes.locationService.result = const LocationFound(
    latitude: 32.794,
    longitude: 34.9896,
    accuracyMetres: 20,
  );
  fakes.venueSearchService.result = const VenuesFound(<Venue>[_venue]);
  fakes.repository.stub(_venue.ref, MenuFetched(menu: _menu));
  return fakes;
}

/// Locates, then opens [_venue]'s card and settles on its menu.
Future<void> _openCard(WidgetTester tester) async {
  await tapAndSettle(tester, find.byTooltip(_en.discoveryUseLocation));
  final card = find.widgetWithText(VenueCard, _venue.name);
  await tester.ensureVisible(card);
  await tester.pumpAndSettle();
  await tapAndSettle(tester, card);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Menu upload flow', () {
    testWidgets('with consent on, opening a card uploads its menu once, '
        'named and placed as the card was', (tester) async {
      // Setup
      final fakes = await _fakes(consent: true);
      await pumpApp(tester, fakes);

      // Act
      await _openCard(tester);

      // Assert: the menu screen names the venue, and exactly one upload
      // carries its menu.
      expect(find.text(_venue.name), findsWidgets);
      final upload = fakes.menuStoreClient.uploads.single;
      expect(upload.ref, _venue.ref);
      expect(upload.venueName, _venue.name);
      expect(upload.city, _venue.city);
      expect(upload.menu, _menu);
      // The flow classifier answers with the rule engine, whose result is
      // never shared.
      expect(upload.analysis, isNull);
    });

    testWidgets('with consent off, opening a card uploads nothing', (
      tester,
    ) async {
      // Setup
      final fakes = await _fakes(consent: false);
      await pumpApp(tester, fakes);

      // Act
      await _openCard(tester);

      // Assert: the menu screen still opened, and nothing left the device.
      expect(find.text(_venue.name), findsWidgets);
      expect(fakes.menuStoreClient.uploads, isEmpty);
    });
  });
}

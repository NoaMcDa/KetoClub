// Flow test (FLOW_TEST_CONVENTIONS.md; issue #231): the Discovery chips
// combine. There is no Nearby chip, Keto 8+ is always on screen — disabled
// until a card has numbers, enabled once one does — and Open now and
// Keto 8+ together keep only the venues that pass both.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/location/location_service.dart';
import 'package:ketoclub/services/storage/menu_cache.dart';
import 'package:ketoclub/services/venue/venue_search_service.dart';

import 'flow_support.dart';

/// The English strings this test reads expected copy from.
final AppLocalizations _en = AppLocalizationsEn();

/// A Wolt venue addressed by [slug], with [isOnline] as the platform says.
Venue _venue(String slug, {bool? isOnline}) => Venue(
  ref: VenueRef(source: MenuSource.wolt, platformId: slug),
  name: 'Venue $slug',
  isOnline: isOnline,
);

/// A cached menu and analysis for [venue] that scores 10.0 (all green).
CachedMenu _scored(Venue venue) => CachedMenu(
  menu: Menu(
    venueRef: venue.ref,
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
);

/// Scrolls [chip] clear of the bottom navigation, which the web-server
/// surface's short window leaves it under, then taps it.
Future<void> _tapChip(WidgetTester tester, Finder chip) async {
  await tester.ensureVisible(chip);
  await tester.pumpAndSettle();
  await tapAndSettle(tester, chip);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Discovery chips flow', () {
    testWidgets('Keto 8+ is disabled with no numbers, and Open now and Keto '
        '8+ combine once there are some', (tester) async {
      // Setup: two open venues, one of them scored from the cache, and a
      // scored closed one.
      final scoredOpen = _venue('scored-open', isOnline: true);
      final plainOpen = _venue('plain-open', isOnline: true);
      final scoredClosed = _venue('scored-closed', isOnline: false);
      final fakes = FakeAppDependencies();
      fakes.locationService.result = const LocationFound(
        latitude: 32.0809,
        longitude: 34.7806,
        accuracyMetres: 20,
      );
      fakes.venueSearchService.result = VenuesFound([
        scoredOpen,
        plainOpen,
        scoredClosed,
      ]);
      fakes.repository
        ..seedCache(_scored(scoredOpen))
        ..seedCache(_scored(scoredClosed));
      await pumpApp(tester, fakes);

      // Act
      await tapAndSettle(tester, find.byTooltip(_en.discoveryUseLocation));

      // Assert: there is no Nearby chip; the others are there, Keto 8+
      // enabled because two cards carry numbers.
      expect(find.text('Nearby'), findsNothing);
      final keto = find.widgetWithText(
        FilterChip,
        _en.discoveryChipKetoEightPlus,
      );
      final openNow = find.widgetWithText(FilterChip, _en.discoveryChipOpenNow);
      expect(tester.widget<FilterChip>(keto).onSelected, isNotNull);

      // Act: both chips.
      await _tapChip(tester, keto);
      await _tapChip(tester, openNow);

      // Assert: only the venue that is scored and open remains.
      expect(find.text(scoredOpen.name), findsOneWidget);
      expect(find.text(plainOpen.name), findsNothing);
      expect(find.text(scoredClosed.name), findsNothing);
      expect(tester.widget<FilterChip>(keto).selected, isTrue);
      expect(tester.widget<FilterChip>(openNow).selected, isTrue);

      // Act: Keto 8+ off.
      await _tapChip(tester, keto);

      // Assert: Open now alone keeps both open venues.
      expect(find.text(scoredOpen.name), findsOneWidget);
      expect(find.text(plainOpen.name), findsOneWidget);
      expect(find.text(scoredClosed.name), findsNothing);
    });

    testWidgets('Keto 8+ is shown disabled when no card has numbers', (
      tester,
    ) async {
      // Setup
      final fakes = FakeAppDependencies();
      fakes.locationService.result = const LocationFound(
        latitude: 32.0809,
        longitude: 34.7806,
        accuracyMetres: 20,
      );
      fakes.venueSearchService.result = VenuesFound([_venue('plain')]);
      await pumpApp(tester, fakes);

      // Act
      await tapAndSettle(tester, find.byTooltip(_en.discoveryUseLocation));

      // Assert
      final keto = find.widgetWithText(
        FilterChip,
        _en.discoveryChipKetoEightPlus,
      );
      expect(keto, findsOneWidget);
      expect(tester.widget<FilterChip>(keto).onSelected, isNull);
      expect(
        find.byTooltip(_en.discoveryChipKetoEightPlusHint),
        findsOneWidget,
      );
    });
  });
}

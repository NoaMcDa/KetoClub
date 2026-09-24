// Flow test (FLOW_TEST_CONVENTIONS.md, architecture.md §6.5, §6.6, D13;
// issue #43): the Discovery chips narrow a located list — Open now hides
// and restores a closed venue, and Keto 8+ is offered, and filters to a
// venue, only once a card has cached numbers.

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
import 'package:ketoclub/widgets/venue_card.dart';

import 'flow_support.dart';

/// The English strings this test reads expected copy from, computed the
/// same way the app itself does.
final AppLocalizations _en = AppLocalizationsEn();

/// A Wolt venue addressed by [slug].
Venue _venue(String slug, {bool? isOnline}) => Venue(
  ref: VenueRef(source: MenuSource.wolt, platformId: slug),
  name: 'Venue $slug',
  isOnline: isOnline,
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Discovery chips flow', () {
    testWidgets(
      'Open now hides and restores a closed venue, and Keto 8+ appears '
      'and filters only once a card has numbers',
      (tester) async {
        // Setup: a located pair with no cached analysis yet.
        final open = _venue('open-venue', isOnline: true);
        final closed = _venue('closed-venue', isOnline: false);
        final fakes = FakeAppDependencies();
        fakes.locationService.result = const LocationFound(
          latitude: 32.0809,
          longitude: 34.7806,
          accuracyMetres: 20,
        );
        fakes.venueSearchService.result = VenuesFound([open, closed]);
        await pumpApp(tester, fakes);

        // Act: locate.
        await tapAndSettle(tester, find.byTooltip(_en.discoveryUseLocation));

        // Assert: neither card has numbers yet, so Keto 8+ is not offered.
        expect(find.byType(VenueCard), findsNWidgets(2));
        expect(find.text(_en.discoveryChipKetoEightPlus), findsNothing);

        // Act: Open now.
        await tapAndSettle(
          tester,
          find.widgetWithText(ChoiceChip, _en.discoveryChipOpenNow),
        );

        // Assert: the closed venue disappears.
        expect(find.text(open.name), findsOneWidget);
        expect(find.text(closed.name), findsNothing);

        // Act: Open now again.
        await tapAndSettle(
          tester,
          find.widgetWithText(ChoiceChip, _en.discoveryChipOpenNow),
        );

        // Assert: it returns.
        expect(find.text(closed.name), findsOneWidget);

        // Setup: a fresh located pair, one with an analysis already
        // cached on the device scoring above the Keto 8+ threshold (D13).
        final high = _venue('high-venue', isOnline: true);
        final plain = _venue('plain-venue', isOnline: true);
        fakes.repository.seedCache(
          CachedMenu(
            menu: Menu(
              venueRef: high.ref,
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
        fakes.venueSearchService.result = VenuesFound([high, plain]);

        // Act: locate again.
        await tapAndSettle(tester, find.byTooltip(_en.discoveryUseLocation));

        // Assert: Keto 8+ is now offered, with the cached score on show.
        expect(find.text(_en.discoveryChipKetoEightPlus), findsOneWidget);
        expect(find.text('10.0'), findsOneWidget);

        // Act: Keto 8+.
        await tapAndSettle(
          tester,
          find.widgetWithText(ChoiceChip, _en.discoveryChipKetoEightPlus),
        );

        // Assert: only the scored venue remains.
        expect(find.text(high.name), findsOneWidget);
        expect(find.text(plain.name), findsNothing);
      },
    );
  });
}

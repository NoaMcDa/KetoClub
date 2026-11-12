// Flow test (FLOW_TEST_CONVENTIONS.md; issues #450, #451): Explore's first
// wait. The user asks for their location and, while the device takes its
// time, sees the steak, the egg and the lettuce circling with "Finding your
// location…" and a line of kitchen talk that changes as the wait goes on,
// over placeholder cards. When the location answers, the restaurants
// replace all of it and nothing is left moving.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/venue/venue_search_service.dart';
import 'package:ketoclub/widgets/keto_foods.dart';
import 'package:ketoclub/widgets/keto_loader.dart';
import 'package:ketoclub/widgets/skeletons.dart';
import 'package:ketoclub/widgets/venue_card.dart';

import 'flow_support.dart';

/// The English strings this test reads expected copy from.
final AppLocalizations _en = AppLocalizationsEn();

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Loading states flow', () {
    testWidgets('while the location is found the foods circle with what is '
        'happening, and the restaurants replace them', (tester) async {
      // Setup: a location that answers only when the flow says so.
      final fakes = FakeAppDependencies();
      final gate = Completer<void>();
      fakes.locationService.gate = gate.future;
      fakes.venueSearchService.result = const VenuesFound([
        Venue(
          ref: VenueRef(source: MenuSource.wolt, platformId: 'chalas'),
          name: "Chala's",
        ),
      ]);
      await pumpApp(tester, fakes);

      // Act: ask for the location, and wait on it.
      await tester.tap(find.byTooltip(_en.discoveryUseLocation));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Assert: the orbit and its three foods, the status, kitchen talk,
      // and the placeholder cards under them.
      expect(find.byType(KetoOrbit), findsOneWidget);
      expect(find.byType(KetoFoodIcon), findsNWidgets(3));
      expect(find.text(_en.discoveryLocating), findsOneWidget);
      expect(find.text(_en.loadingTalkCarbs), findsOneWidget);
      expect(
        find.byType(VenueCardSkeleton, skipOffstage: false),
        findsNWidgets(3),
      );

      // Act: the wait goes on.
      await tester.pump(kitchenTalkPeriod);
      await tester.pump(const Duration(milliseconds: 300));

      // Assert: the kitchen talk has moved on; the status has not.
      expect(find.text(_en.loadingTalkCarbs), findsNothing);
      expect(find.text(_en.loadingTalkSauces), findsOneWidget);
      expect(find.text(_en.discoveryLocating), findsOneWidget);

      // Act: the location answers.
      gate.complete();
      await tester.pumpAndSettle();

      // Assert: the restaurant, and no loader left behind.
      expect(find.byType(KetoOrbit), findsNothing);
      expect(find.byType(VenueCardSkeleton), findsNothing);
      await showVenueList(tester);
      expect(find.byType(VenueCard), findsOneWidget);
      expect(find.text("Chala's"), findsOneWidget);
    });
  });
}

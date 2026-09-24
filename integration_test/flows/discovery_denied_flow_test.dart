// Flow test (FLOW_TEST_CONVENTIONS.md, architecture.md §6.5, §18.4; issue
// #43): a non-permanent permission denial explains itself and degrades to
// a manual search, which lists whatever the fake search's `byName`
// answers once the user has typed a name and the debounce has elapsed.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/location/location_service.dart';
import 'package:ketoclub/services/venue/venue_search_service.dart';
import 'package:ketoclub/utils/constants.dart';
import 'package:ketoclub/widgets/venue_card.dart';

import 'flow_support.dart';

/// The English strings this test reads expected copy from, computed the
/// same way the app itself does.
final AppLocalizations _en = AppLocalizationsEn();

/// A Wolt venue addressed by [slug].
Venue _venue(String slug) => Venue(
  ref: VenueRef(source: MenuSource.wolt, platformId: slug),
  name: 'Venue $slug',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Discovery denied-permission flow', () {
    testWidgets(
      'a denied permission explains itself, and "Type a name instead" '
      'leads to a name search that lists what it finds',
      (tester) async {
        // Setup: location refuses, but not permanently, and a name search
        // is ready to answer once the user types one.
        final fakes = FakeAppDependencies();
        fakes.locationService.result = const LocationDenied(permanently: false);
        fakes.venueSearchService.result = VenuesFound([_venue('sushi-bar')]);
        await pumpApp(tester, fakes);

        // Act: locate.
        await tapAndSettle(tester, find.byTooltip(_en.discoveryUseLocation));

        // Assert: the denial copy and its manual fallback, no search made.
        expect(find.text(_en.discoveryLocationDeniedTitle), findsOneWidget);
        expect(find.text(_en.discoveryLocationDeniedBody), findsOneWidget);
        expect(find.text(_en.discoveryTypeNameInstead), findsOneWidget);
        expect(fakes.venueSearchService.nearbyCalls, isEmpty);

        // Act: "Type a name instead" focuses the field, then type a name
        // and wait out the search debounce.
        await tapAndSettle(tester, find.text(_en.discoveryTypeNameInstead));
        final field = tester.widget<TextField>(find.byType(TextField));
        expect(field.focusNode?.hasFocus, isTrue);
        await tester.enterText(find.byType(TextField), 'sushi');
        await tester.pump(venueSearchDebounce);
        await tester.pumpAndSettle();

        // Assert: the manual search ran, in the UI language, and its list
        // is shown.
        expect(fakes.venueSearchService.byNameCalls, ['sushi']);
        expect(find.byType(VenueCard), findsOneWidget);
        expect(find.text('Venue sushi-bar'), findsOneWidget);
      },
    );
  });
}

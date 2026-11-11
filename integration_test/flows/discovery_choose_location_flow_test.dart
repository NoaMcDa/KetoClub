// Flow test (FLOW_TEST_CONVENTIONS.md; issue #443): the user looks around a
// place of their own choosing. Open Explore, choose a city in the location
// picker, see the restaurants around it with the city named in the header,
// then narrow the list with the distance chip. A second journey reaches the
// picker from the location-denied card. Neither asks the device where it is
// beyond the refusal the second one starts from.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/models/place.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/location/location_service.dart';
import 'package:ketoclub/services/venue/venue_search_service.dart';
import 'package:ketoclub/utils/known_places.dart';
import 'package:ketoclub/widgets/location_picker_sheet.dart';
import 'package:ketoclub/widgets/venue_card.dart';

import 'flow_support.dart';

/// The English strings this test reads expected copy from.
final AppLocalizations _en = AppLocalizationsEn();

/// Haifa, the city both journeys choose.
final KnownPlace _haifa = knownPlaceById('haifa')!;

/// A Wolt venue addressed by [slug], [km] kilometres due north of Haifa's
/// centre.
Venue _venue(String slug, double km) => Venue(
  ref: VenueRef(source: MenuSource.wolt, platformId: slug),
  name: 'Venue $slug',
  // One degree of latitude is about 111.2 km.
  latitude: _haifa.latitude + km / 111.2,
  longitude: _haifa.longitude,
);

/// Scrolls [target] clear of the bottom navigation, which the web-server
/// surface's short window leaves it under, then taps it.
Future<void> _tapVisible(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tapAndSettle(tester, target);
}

/// Searches the open picker for "haifa" and taps the one row it leaves, so
/// the journey does not depend on how many rows a short window shows.
Future<void> _pickHaifa(WidgetTester tester) async {
  await tester.enterText(
    find.descendant(
      of: find.byType(LocationPickerSheet),
      matching: find.byType(EditableText),
    ),
    'haifa',
  );
  await tester.pumpAndSettle();
  await tapAndSettle(tester, find.widgetWithText(ListTile, 'Haifa'));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Discovery choose-a-location flow', () {
    testWidgets('choosing a city lists its restaurants, names it in the '
        'header, and the distance chip narrows the list', (tester) async {
      // Setup: three restaurants around Haifa, at walking, driving and
      // out-of-town distances.
      final near = _venue('near', 0.4);
      final across = _venue('across', 3);
      final far = _venue('far', 18);
      final fakes = FakeAppDependencies();
      fakes.venueSearchService.result = VenuesFound([near, across, far]);
      await pumpApp(tester, fakes);

      // Assert: nothing is asked for on open.
      expect(find.text(_en.discoveryLocationInvite), findsOneWidget);
      expect(fakes.venueSearchService.nearbyCalls, isEmpty);

      // Act: choose a location, and search the picker for the city.
      await tapAndSettle(tester, find.byTooltip(_en.discoveryChooseLocation));
      expect(find.text(_en.locationPickerTitle), findsOneWidget);
      await _pickHaifa(tester);

      // Assert: the restaurants around Haifa, and Haifa in the header.
      expect(find.byType(LocationPickerSheet), findsNothing);
      final call = fakes.venueSearchService.nearbyCalls.single;
      expect(call.latitude, _haifa.latitude);
      expect(call.longitude, _haifa.longitude);
      expect(
        find.text(_en.discoveryLookingAround.toUpperCase()),
        findsOneWidget,
      );
      expect(find.text('Haifa'), findsOneWidget);
      expect(find.byType(VenueCard), findsNWidgets(3));

      // Act: within 5 km.
      final distance = find.byTooltip(_en.discoveryChipDistanceTooltip);
      await _tapVisible(tester, distance);
      await tapAndSettle(
        tester,
        find.widgetWithText(MenuItemButton, _en.discoveryChipWithinKm(5)),
      );

      // Assert: the out-of-town one is gone and the chip says why.
      expect(find.text(near.name), findsOneWidget);
      expect(find.text(across.name), findsOneWidget);
      expect(find.text(far.name), findsNothing);
      expect(
        tester
            .widget<FilterChip>(
              find.widgetWithText(FilterChip, _en.discoveryChipWithinKm(5)),
            )
            .selected,
        isTrue,
      );

      // Act: within 1 km.
      await _tapVisible(tester, distance);
      await tapAndSettle(
        tester,
        find.widgetWithText(MenuItemButton, _en.discoveryChipWithinKm(1)),
      );

      // Assert
      expect(find.text(near.name), findsOneWidget);
      expect(find.text(across.name), findsNothing);

      // Act: any distance again.
      await _tapVisible(tester, distance);
      await tapAndSettle(
        tester,
        find.widgetWithText(MenuItemButton, _en.discoveryChipAnyDistance),
      );

      // Assert: the whole list is back.
      expect(find.byType(VenueCard), findsNWidgets(3));
    });

    testWidgets('with location refused, the denied card leads to the picker '
        'and a chosen city replaces the card', (tester) async {
      // Setup
      final near = _venue('near', 0.4);
      final fakes = FakeAppDependencies();
      fakes.locationService.result = const LocationDenied(permanently: false);
      fakes.venueSearchService.result = VenuesFound([near]);
      await pumpApp(tester, fakes);

      // Act: ask for the location, which is refused.
      await tapAndSettle(tester, find.byTooltip(_en.discoveryUseLocation));

      // Assert
      expect(find.text(_en.discoveryLocationDeniedTitle), findsOneWidget);
      expect(fakes.venueSearchService.nearbyCalls, isEmpty);

      // Act: the card's way round it.
      await _tapVisible(tester, find.text(_en.discoveryChooseLocation));
      await _pickHaifa(tester);

      // Assert: restaurants, with no permission involved.
      expect(find.text(_en.discoveryLocationDeniedTitle), findsNothing);
      expect(find.text('Haifa'), findsOneWidget);
      expect(find.text(near.name), findsOneWidget);
      expect(fakes.venueSearchService.nearbyCalls, hasLength(1));
    });
  });
}

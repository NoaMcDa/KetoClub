// Flow test (FLOW_TEST_CONVENTIONS.md; issue #449): the user looks around
// a street of their own choosing. Open Explore with the device's own
// position, open the location picker, type a street, and see that typing
// alone sends nothing. Tap "Search streets", pick a match, and see the
// street named in the header and the restaurants around it in place of the
// ones around the device.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/models/place.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/place/place_search_service.dart';
import 'package:ketoclub/services/venue/venue_search_service.dart';
import 'package:ketoclub/widgets/location_picker_sheet.dart';
import 'package:ketoclub/widgets/venue_card.dart';

import 'flow_support.dart';

/// The English strings this test reads expected copy from.
final AppLocalizations _en = AppLocalizationsEn();

/// The street the journey chooses, as the street search names it.
const StreetPlace _herzl = StreetPlace(
  label: 'Herzl 10, Tel Aviv',
  city: 'Tel Aviv',
  latitude: 32.0625697,
  longitude: 34.7698648,
);

/// A Wolt venue addressed by [slug], at [latitude], [longitude].
Venue _venue(String slug, double latitude, double longitude) => Venue(
  ref: VenueRef(source: MenuSource.wolt, platformId: slug),
  name: 'Venue $slug',
  latitude: latitude,
  longitude: longitude,
);

/// The picker's search field.
Finder _pickerField() => find.descendant(
  of: find.byType(LocationPickerSheet),
  matching: find.byType(EditableText),
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Discovery choose-a-street flow', () {
    testWidgets('typing a street sends nothing; searching and picking one '
        'names it in the header and lists the restaurants around it', (
      tester,
    ) async {
      // Setup: one restaurant around the device, another near Herzl 10.
      final aroundDevice = _venue('rabin-square', 32.0809, 34.7806);
      final nearHerzl = _venue('herzl-corner', 32.0628, 34.7701);
      final fakes = FakeAppDependencies();
      fakes.venueSearchService.result = VenuesFound([aroundDevice]);
      fakes.placeSearchService.result = const PlacesFound(<StreetPlace>[
        _herzl,
        StreetPlace(
          label: 'Herzl 10, Ramat Gan',
          latitude: 32.08107,
          longitude: 34.8188628,
        ),
      ]);
      await pumpApp(tester, fakes);

      // Act: look around the device first.
      await tapAndSettle(tester, find.byTooltip(_en.discoveryUseLocation));

      // Assert
      expect(find.text(aroundDevice.name), findsOneWidget);
      expect(fakes.venueSearchService.nearbyCalls, hasLength(1));

      // Act: open the picker and type a street.
      await tapAndSettle(tester, find.byTooltip(_en.discoveryChooseLocation));
      await tester.enterText(_pickerField(), 'Herzl 10');
      await tester.pumpAndSettle();

      // Assert: the action and where it would send the text, and nothing
      // sent yet.
      final action = find.text(_en.locationPickerStreetSearch('Herzl 10'));
      expect(action, findsOneWidget);
      expect(find.text(_en.locationPickerStreetCaptionDirect), findsOneWidget);
      expect(fakes.placeSearchService.calls, isEmpty);

      // Act: search, then pick the Tel Aviv match.
      fakes.venueSearchService.result = VenuesFound([nearHerzl]);
      await tester.ensureVisible(action);
      await tester.pumpAndSettle();
      await tapAndSettle(tester, action);

      // Assert: one search, two matches.
      expect(fakes.placeSearchService.calls, <String>['Herzl 10']);
      final match = find.widgetWithText(ListTile, _herzl.label);
      expect(match, findsOneWidget);
      expect(
        find.widgetWithText(ListTile, 'Herzl 10, Ramat Gan'),
        findsOneWidget,
      );
      await tester.ensureVisible(match);
      await tester.pumpAndSettle();
      await tapAndSettle(tester, match);

      // Assert: the sheet is gone, the header names the street, and the
      // list is the one around it.
      expect(find.byType(LocationPickerSheet), findsNothing);
      final call = fakes.venueSearchService.nearbyCalls.last;
      expect(call.latitude, _herzl.latitude);
      expect(call.longitude, _herzl.longitude);
      expect(fakes.venueSearchService.nearbyCalls, hasLength(2));
      expect(find.text(_herzl.label), findsOneWidget);
      expect(find.text(nearHerzl.name), findsOneWidget);
      expect(find.text(aroundDevice.name), findsNothing);
      expect(find.byType(VenueCard), findsOneWidget);

      // Assert: the choice is kept on the device for the next launch.
      final saved = await fakes.settingsStore.read();
      expect(saved.discoveryStreet?.label, _herzl.label);
      expect(saved.discoveryPlaceId, isNull);
    });
  });
}

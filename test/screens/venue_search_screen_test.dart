import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/screens/drinks_guide_screen.dart';
import 'package:ketoclub/screens/venue_search_screen.dart';
import 'package:ketoclub/services/location/location_service.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/services/platform/connectivity.dart';
import 'package:ketoclub/services/storage/menu_cache.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/services/venue/venue_search_service.dart';
import 'package:ketoclub/state/venue_search_controller.dart';
import 'package:ketoclub/theme/app_theme.dart';
import 'package:ketoclub/utils/constants.dart';
import 'package:ketoclub/widgets/content_width.dart';
import 'package:ketoclub/widgets/engine_chip.dart';
import 'package:ketoclub/widgets/failure_copy.dart';
import 'package:ketoclub/widgets/offline_banner.dart';
import 'package:ketoclub/widgets/photo_tile.dart';
import 'package:ketoclub/widgets/skeletons.dart';
import 'package:ketoclub/widgets/venue_card.dart';
import 'package:ketoclub/widgets/venue_grid.dart';
import 'package:provider/provider.dart';

import '../fakes/fake_connectivity.dart';
import '../fakes/fake_location_service.dart';
import '../fakes/fake_menu_classifier.dart';
import '../fakes/fake_menu_repository.dart';
import '../fakes/fake_settings_store.dart';
import '../fakes/fake_venue_search_service.dart';

/// Gives the test a surface tall enough that a short venue list is laid
/// out in full, the same helper `menu_screen_test.dart` uses.
void _useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Pumps the real [VenueSearchScreen] over a real
/// [VenueSearchController], recording every route name pushed via
/// [Navigator.pushNamed] into [pushedNames].
Future<void> _pump(
  WidgetTester tester, {
  required VenueSearchController controller,
  required List<String> pushedNames,
  Locale locale = const Locale('en'),
  Connectivity? connectivity,
  ThemeData? theme,
  LocationService? locationService,
  SettingsStore? settingsStore,
}) {
  _useTallSurface(tester);
  return tester.pumpWidget(
    ChangeNotifierProvider<VenueSearchController>.value(
      value: controller,
      child: MaterialApp(
        theme: theme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        home: VenueSearchScreen(
          connectivity: connectivity ?? FakeConnectivity(),
          locationService: locationService ?? FakeLocationService(),
          // Fresh install (D16, issue #167) → the disclosure banner is
          // visible on the first frame. Every existing test in this
          // file wrote AI copy that assumed the banner absent; seed a
          // "seen" store here so the banner hides itself and this
          // file's older assertions keep passing. Individual tests for
          // the banner override this with a virgin store.
          settingsStore:
              settingsStore ??
              FakeSettingsStore(
                initial: const AppSettings(disclosureSeen: true),
              ),
        ),
        onGenerateRoute: (settings) {
          pushedNames.add(settings.name ?? '');
          return MaterialPageRoute<void>(
            builder: (_) => const SizedBox.shrink(),
            settings: settings,
          );
        },
      ),
    ),
  );
}

/// Types [text] into the search field and waits out the search debounce,
/// so no timer is left pending when the test ends.
Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pump(venueSearchDebounce);
  await tester.pump();
}

/// The localised strings of the pumped screen.
AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(VenueSearchScreen)))!;

/// A Wolt venue addressed by [slug].
Venue _venue(String slug, {bool? isOnline, String? address}) => Venue(
  ref: VenueRef(source: MenuSource.wolt, platformId: slug),
  name: 'Venue $slug',
  isOnline: isOnline,
  address: address,
);

void main() {
  group('VenueSearchScreen', () {
    late FakeSettingsStore settingsStore;
    late FakeMenuRepository repository;
    late FakeLocationService location;
    late FakeVenueSearchService search;
    late FakeMenuClassifier estimator;
    late VenueSearchController controller;
    late List<String> pushedNames;

    setUp(() {
      settingsStore = FakeSettingsStore();
      repository = FakeMenuRepository();
      location = FakeLocationService();
      search = FakeVenueSearchService();
      estimator = FakeMenuClassifier();
      controller = VenueSearchController(
        settingsStore,
        repository,
        locationService: location,
        venueSearchService: search,
        estimateClassifier: estimator,
      );
      pushedNames = <String>[];
    });

    /// Taps the header's location button and settles.
    Future<void> locate(WidgetTester tester) async {
      await tester.tap(find.byTooltip(_l10n(tester).discoveryUseLocation));
      await tester.pumpAndSettle();
    }

    for (final entry in {
      'light': AppTheme.light(),
      'dark': AppTheme.dark(),
    }.entries) {
      testWidgets('tapping the location button shows three VenueCardSkeletons '
          'under the ${entry.key} theme while locating (issue #63)', (
        tester,
      ) async {
        // Arrange: hold the locate call open so the transient
        // DiscoveryPhase.locating state stays on screen.
        final gate = Completer<void>();
        location.gate = gate.future;
        await _pump(
          tester,
          controller: controller,
          pushedNames: pushedNames,
          theme: entry.value,
        );
        final l10n = _l10n(tester);

        // Act
        await tester.tap(find.byTooltip(l10n.discoveryUseLocation));
        await tester.pump();

        // Assert: the skeletons stand in for the old spinner, announced
        // once through a Semantics label.
        expect(find.byType(VenueCardSkeleton), findsNWidgets(3));
        expect(find.bySemanticsLabel(l10n.discoveryLocating), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);

        // Cleanup: release the gate so no timer/future is left pending.
        gate.complete();
        await tester.pumpAndSettle();
      });

      testWidgets('typing a name shows three VenueCardSkeletons under the '
          '${entry.key} theme while searching (issue #63)', (tester) async {
        // Arrange: hold the byName call open so the transient
        // DiscoveryPhase.searching state stays on screen.
        final gate = Completer<void>();
        search.gate = gate.future;
        await _pump(
          tester,
          controller: controller,
          pushedNames: pushedNames,
          theme: entry.value,
        );
        final l10n = _l10n(tester);

        // Act
        await tester.enterText(find.byType(TextField), 'sushi');
        await tester.pump(venueSearchDebounce);
        await tester.pump();

        // Assert
        expect(find.byType(VenueCardSkeleton), findsNWidgets(3));
        expect(find.bySemanticsLabel(l10n.discoverySearching), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);

        // Cleanup
        gate.complete();
        await tester.pumpAndSettle();
      });
    }

    testWidgets('build renders the logo mark, the title and the search field', (
      tester,
    ) async {
      // Act
      await _pump(tester, controller: controller, pushedNames: pushedNames);
      final l10n = _l10n(tester);

      // Assert: the brand is a logo mark, not a text label (#232).
      final handle = tester.ensureSemantics();
      expect(find.bySemanticsLabel(appName), findsOneWidget);
      expect(find.text(appName), findsNothing);
      handle.dispose();
      expect(find.text(l10n.discoveryTitle), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text(l10n.venueSearchLabel), findsOneWidget);
    });

    testWidgets('build has no app bar: Settings is reached from the bottom nav '
        'shell, not a duplicate icon here', (tester) async {
      // Act
      await _pump(tester, controller: controller, pushedNames: pushedNames);

      // Assert
      expect(find.byType(AppBar), findsNothing);
      expect(find.byIcon(Icons.settings), findsNothing);
    });

    testWidgets('the empty state shows the drinks guide card under the search '
        'field, and tapping it pushes /drinks (issue #257)', (tester) async {
      // Arrange
      await _pump(tester, controller: controller, pushedNames: pushedNames);
      await tester.pumpAndSettle();
      final l10n = _l10n(tester);

      // Assert: the card sits below the field.
      expect(find.byIcon(Icons.local_bar), findsOneWidget);
      expect(find.text(l10n.discoveryDrinksGuideCard), findsOneWidget);
      expect(
        tester.getTopLeft(find.byType(Card)).dy,
        greaterThan(tester.getBottomLeft(find.byType(TextField)).dy),
      );

      // Act
      await tester.tap(find.text(l10n.discoveryDrinksGuideCard));
      await tester.pumpAndSettle();

      // Assert
      expect(pushedNames, contains(drinksRoutePath));
    });

    testWidgets('the drinks guide card stays above the results (issue #257)', (
      tester,
    ) async {
      // Arrange
      search.queueFound([_venue('ember-vine')]);
      await _pump(tester, controller: controller, pushedNames: pushedNames);

      // Act
      await locate(tester);

      // Assert
      final card = find.text(_l10n(tester).discoveryDrinksGuideCard);
      expect(card, findsOneWidget);
      expect(
        tester.getTopLeft(card).dy,
        lessThan(tester.getTopLeft(find.byType(VenueCard)).dy),
      );
    });

    testWidgets('the drinks guide card is hidden while locating or searching '
        'and returns once the answer lands (issue #257)', (tester) async {
      // Arrange: hold the locate call open.
      final gate = Completer<void>();
      location.gate = gate.future;
      await _pump(tester, controller: controller, pushedNames: pushedNames);
      final l10n = _l10n(tester);
      expect(find.text(l10n.discoveryDrinksGuideCard), findsOneWidget);

      // Act
      await tester.tap(find.byTooltip(l10n.discoveryUseLocation));
      await tester.pump();

      // Assert
      expect(find.byType(VenueCardSkeleton), findsNWidgets(3));
      expect(find.text(l10n.discoveryDrinksGuideCard), findsNothing);

      // Act
      gate.complete();
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(l10n.discoveryDrinksGuideCard), findsOneWidget);
    });

    testWidgets('before anything is asked, the header invites a tap and the '
        'empty state offers the ways in without a second locate button', (
      tester,
    ) async {
      // Act
      await _pump(tester, controller: controller, pushedNames: pushedNames);
      await tester.pumpAndSettle();
      final l10n = _l10n(tester);

      // Assert: an invitation, not an error-looking "Location not set".
      expect(find.text(l10n.discoveryLocationInvite), findsOneWidget);
      expect(
        find.text(l10n.discoveryLookingAround.toUpperCase()),
        findsNothing,
      );
      expect(find.text(l10n.discoveryEmptyTitle), findsOneWidget);
      expect(find.text(l10n.discoveryEmptyBody), findsOneWidget);
      // Exactly one visible location action: the header's, not the body's.
      expect(find.byIcon(Icons.my_location), findsOneWidget);
      expect(find.byTooltip(l10n.discoveryUseLocation), findsOneWidget);
      expect(find.text(l10n.discoveryUseLocation), findsNothing);
      // No location prompt on open: the user has to ask.
      expect(location.currentCallCount, 0);
      expect(find.byType(FilterChip), findsNothing);
    });

    testWidgets('tapping the invitation text asks for the location', (
      tester,
    ) async {
      // Arrange
      location.result = const LocationFound(
        latitude: 32,
        longitude: 34.7,
        accuracyMetres: 10,
      );
      search.queueFound([_venue('ember-vine')]);
      await _pump(tester, controller: controller, pushedNames: pushedNames);

      // Act
      await tester.tap(find.text(_l10n(tester).discoveryLocationInvite));
      await tester.pumpAndSettle();

      // Assert
      expect(location.currentCallCount, 1);
      expect(find.byType(VenueCard), findsOneWidget);
    });

    testWidgets('after a position the header reads "Looking around {address}" '
        'and keeps the one locate button', (tester) async {
      // Arrange
      location.result = const LocationFound(
        latitude: 32,
        longitude: 34.7,
        accuracyMetres: 10,
      );
      search.queueFound([_venue('ember-vine', address: 'Rothschild 22')]);
      await _pump(tester, controller: controller, pushedNames: pushedNames);

      // Act
      await locate(tester);
      final l10n = _l10n(tester);

      // Assert
      expect(find.text(l10n.discoveryLocationInvite), findsNothing);
      expect(
        find.text(l10n.discoveryLookingAround.toUpperCase()),
        findsOneWidget,
      );
      expect(find.text('Rothschild 22'), findsOneWidget);
      expect(find.byTooltip(l10n.discoveryUseLocation), findsOneWidget);
    });

    testWidgets('a denied location hands the one action to the denied card '
        'and hides the header invitation', (tester) async {
      // Arrange
      location.result = const LocationDenied(permanently: false);
      await _pump(tester, controller: controller, pushedNames: pushedNames);

      // Act
      await locate(tester);
      final l10n = _l10n(tester);

      // Assert: the card's Retry is the only way to ask again.
      expect(find.text(l10n.discoveryLocationDeniedTitle), findsOneWidget);
      expect(find.text(l10n.discoveryLocationInvite), findsNothing);
      expect(find.byTooltip(l10n.discoveryUseLocation), findsNothing);
      expect(find.text(l10n.actionRetry), findsOneWidget);
    });

    testWidgets('typing nonsense shows the venueSearchInvalid message', (
      tester,
    ) async {
      // Arrange
      await _pump(tester, controller: controller, pushedNames: pushedNames);

      // Act
      await tester.enterText(
        find.byType(TextField),
        // Not a Wolt venue page; Wolt keeps priority over websites (D19).
        'https://wolt.com/en/discovery',
      );
      await tester.pump();

      // Assert
      expect(find.text(_l10n(tester).venueSearchInvalid), findsOneWidget);
      expect(search.byNameCalls, isEmpty);
    });

    testWidgets('an empty field shows no invalid message', (tester) async {
      // Arrange
      await _pump(tester, controller: controller, pushedNames: pushedNames);

      // Assert: nothing typed yet.
      expect(find.text(_l10n(tester).venueSearchInvalid), findsNothing);
    });

    testWidgets('a controller that already holds a query and results puts '
        'them back in the field and the list (issue #233)', (tester) async {
      // Arrange: the app-lifetime controller, searched before the screen
      // was last left.
      search.queueFound([_venue('sushi-bar')]);
      controller.search('sushi', language: 'en', immediate: true);
      await tester.pumpAndSettle();

      // Act
      await _pump(tester, controller: controller, pushedNames: pushedNames);
      await tester.pumpAndSettle();

      // Assert
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller?.text,
        'sushi',
      );
      expect(find.text('Venue sushi-bar'), findsOneWidget);
      expect(search.byNameCalls, hasLength(1));
    });

    testWidgets('there is no standing open button, and none for a plain name', (
      tester,
    ) async {
      // Arrange
      await _pump(tester, controller: controller, pushedNames: pushedNames);

      // Assert: nothing typed yet.
      expect(find.byType(FilledButton), findsNothing);
      expect(find.byTooltip(_l10n(tester).venueSearchOpenLink), findsNothing);

      // Act
      await _type(tester, 'pizza');

      // Assert: a bare word offers no open action either.
      expect(find.byType(FilledButton), findsNothing);
      expect(find.byTooltip(_l10n(tester).venueSearchOpenLink), findsNothing);
    });

    testWidgets('a hyphenated bare slug is a name: no open icon', (
      tester,
    ) async {
      // Arrange
      await _pump(tester, controller: controller, pushedNames: pushedNames);

      // Act
      await _type(tester, 'vitrina-lilinblum');

      // Assert
      expect(find.byTooltip(_l10n(tester).venueSearchOpenLink), findsNothing);
    });

    testWidgets('a pasted link shows the open icon, which goes away when '
        'the text stops being a link', (tester) async {
      // Arrange
      await _pump(tester, controller: controller, pushedNames: pushedNames);

      // Act
      await _type(tester, 'wolt.com/en/isr/tel-aviv/restaurant/vitrina');

      // Assert
      final open = find.byTooltip(_l10n(tester).venueSearchOpenLink);
      expect(open, findsOneWidget);

      // Act
      await _type(tester, 'vitrina');

      // Assert
      expect(open, findsNothing);
    });

    testWidgets(
      'tapping the open icon pushes the venue route path for a Wolt link',
      (tester) async {
        // Arrange
        await _pump(tester, controller: controller, pushedNames: pushedNames);
        await _type(
          tester,
          'https://wolt.com/en/isr/tel-aviv/restaurant/vitrina-lilinblum',
        );

        // Act
        await tester.tap(find.byTooltip(_l10n(tester).venueSearchOpenLink));
        await tester.pumpAndSettle();

        // Assert
        expect(pushedNames, contains('/venue/wolt/vitrina-lilinblum'));
      },
    );

    testWidgets(
      'a pasted 10bis id resolves and pushes a tenbis venue route — the '
      "unsupportedSource message it hits from there is MenuScreen's job, "
      'not this one',
      (tester) async {
        // Arrange
        await _pump(tester, controller: controller, pushedNames: pushedNames);
        await tester.enterText(find.byType(TextField), '123456');
        await tester.pump();

        // Act
        await tester.tap(find.byTooltip(_l10n(tester).venueSearchOpenLink));
        await tester.pumpAndSettle();

        // Assert
        expect(pushedNames, contains('/venue/tenbis/123456'));
      },
    );

    testWidgets('submitting a pasted Wolt link from the keyboard opens it '
        'without searching', (tester) async {
      // Arrange
      await _pump(tester, controller: controller, pushedNames: pushedNames);
      await tester.enterText(
        find.byType(TextField),
        'https://wolt.com/en/isr/tel-aviv/restaurant/vitrina',
      );

      // Act
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      // Assert
      expect(pushedNames, contains('/venue/wolt/vitrina'));
      expect(search.byNameCalls, isEmpty);
    });

    testWidgets('typing a name searches after the debounce, in the UI '
        'language, and lists what it finds', (tester) async {
      // Arrange
      search.queueFound([_venue('sushi-bar')]);
      await _pump(tester, controller: controller, pushedNames: pushedNames);

      // Act
      await tester.enterText(find.byType(TextField), 'sushi');
      await tester.pump(venueSearchDebounce - const Duration(milliseconds: 1));

      // Assert: not yet.
      expect(search.byNameCalls, isEmpty);

      // Act
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pumpAndSettle();

      // Assert
      expect(search.byNameCalls.single.query, 'sushi');
      expect(search.byNameCalls.single.language, 'en');
      expect(find.text('Venue sushi-bar'), findsOneWidget);
    });

    testWidgets('locate → list → tapping a card opens its menu route', (
      tester,
    ) async {
      // Arrange
      search.queueFound([
        _venue('ember-vine', address: 'Rothschild 22'),
        _venue('salt-stone'),
      ]);
      await _pump(tester, controller: controller, pushedNames: pushedNames);

      // Act
      await locate(tester);

      // Assert: the list, and the nearest address in the header.
      expect(location.currentCallCount, 1);
      expect(search.nearbyCalls.single.language, 'en');
      expect(find.byType(VenueCard), findsNWidgets(2));
      expect(find.text('Rothschild 22'), findsOneWidget);

      // Act
      await tester.tap(find.widgetWithText(VenueCard, 'Venue salt-stone'));
      await tester.pumpAndSettle();

      // Assert
      expect(pushedNames, contains('/venue/wolt/salt-stone'));
    });

    testWidgets('a located list with no address reads "Your location"', (
      tester,
    ) async {
      // Arrange
      search.queueFound([_venue('a')]);
      await _pump(tester, controller: controller, pushedNames: pushedNames);

      // Act
      await locate(tester);

      // Assert
      expect(find.text(_l10n(tester).discoveryAroundYou), findsOneWidget);
    });

    testWidgets('loading the list never fetches a menu (D13)', (tester) async {
      // Arrange
      search.queueFound([_venue('a'), _venue('b'), _venue('c')]);
      await _pump(tester, controller: controller, pushedNames: pushedNames);

      // Act
      await locate(tester);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
      await tester.pumpAndSettle();

      // Assert
      expect(find.byType(VenueCard), findsNWidgets(3));
      expect(repository.loadCalls, isEmpty);
    });

    testWidgets('a denied location explains itself and "Type a name '
        'instead" focuses the search field', (tester) async {
      // Arrange
      location.result = const LocationDenied(permanently: false);
      await _pump(tester, controller: controller, pushedNames: pushedNames);
      final l10n = _l10n(tester);

      // Act
      await locate(tester);

      // Assert
      expect(find.text(l10n.discoveryLocationDeniedTitle), findsOneWidget);
      expect(find.text(l10n.discoveryLocationDeniedBody), findsOneWidget);
      expect(find.text(l10n.actionRetry), findsOneWidget);
      expect(search.nearbyCalls, isEmpty);

      // Act
      await tester.tap(find.text(l10n.discoveryTypeNameInstead));
      await tester.pump();

      // Assert
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.focusNode?.hasFocus, isTrue);
    });

    testWidgets('a permanent denial offers no retry, only a name search and '
        'Open Settings', (tester) async {
      // Arrange
      location.result = const LocationDenied(permanently: true);
      await _pump(
        tester,
        controller: controller,
        pushedNames: pushedNames,
        locationService: location,
      );
      final l10n = _l10n(tester);

      // Act
      await locate(tester);

      // Assert
      expect(
        find.text(l10n.discoveryLocationDeniedForeverBody),
        findsOneWidget,
      );
      expect(find.text(l10n.discoveryTypeNameInstead), findsOneWidget);
      expect(find.text(l10n.actionRetry), findsNothing);
      expect(find.text(l10n.discoveryOpenSettings), findsOneWidget);

      // Act: tapping it opens the app's own permission settings.
      await tester.tap(find.text(l10n.discoveryOpenSettings));
      await tester.pump();

      // Assert
      expect(location.openSettingsCalls, [false]);
    });

    testWidgets('Open Settings says where to go when the settings page '
        'cannot be opened, as in a browser', (tester) async {
      // Arrange
      location
        ..result = const LocationDenied(permanently: true)
        ..openSettingsResult = false;
      await _pump(
        tester,
        controller: controller,
        pushedNames: pushedNames,
        locationService: location,
      );
      final l10n = _l10n(tester);
      await locate(tester);

      // Act
      await tester.tap(find.text(l10n.discoveryOpenSettings));
      await tester.pump();
      await tester.pump();

      // Assert: the tap is never a silent no-op.
      expect(location.openSettingsCalls, [false]);
      expect(find.text(l10n.discoveryOpenSettingsUnavailable), findsOneWidget);
    });

    testWidgets('a non-permanent denial offers no Open Settings action', (
      tester,
    ) async {
      // Arrange
      location.result = const LocationDenied(permanently: false);
      await _pump(
        tester,
        controller: controller,
        pushedNames: pushedNames,
        locationService: location,
      );
      final l10n = _l10n(tester);

      // Act
      await locate(tester);

      // Assert
      expect(find.text(l10n.discoveryOpenSettings), findsNothing);
    });

    testWidgets('an unavailable location shows the copy for its reason and '
        'offers Turn on location', (tester) async {
      // Arrange
      location.result = const LocationUnavailable(
        reason: LocationUnavailableReason.servicesOff,
      );
      await _pump(
        tester,
        controller: controller,
        pushedNames: pushedNames,
        locationService: location,
      );
      final l10n = _l10n(tester);

      // Act
      await locate(tester);

      // Assert
      expect(find.text(l10n.discoveryLocationUnavailableTitle), findsOneWidget);
      expect(find.text(l10n.discoveryLocationServicesOff), findsOneWidget);
      expect(find.text(l10n.discoveryTypeNameInstead), findsOneWidget);
      expect(find.text(l10n.discoveryTurnOnLocation), findsOneWidget);

      // Act: tapping it opens the device's location-services toggle.
      await tester.tap(find.text(l10n.discoveryTurnOnLocation));
      await tester.pump();

      // Assert
      expect(location.openSettingsCalls, [true]);
    });

    testWidgets('an unsupported location offers no Turn on location action', (
      tester,
    ) async {
      // Arrange
      location.result = const LocationUnavailable(
        reason: LocationUnavailableReason.unsupported,
      );
      await _pump(tester, controller: controller, pushedNames: pushedNames);
      final l10n = _l10n(tester);

      // Act
      await locate(tester);

      // Assert
      expect(find.text(l10n.discoveryTurnOnLocation), findsNothing);
    });

    testWidgets('a failed search shows its reason, and Retry searches '
        'again', (tester) async {
      // Arrange
      search
        ..queueFailed(VenueSearchFailureReason.timeout)
        ..queueFound([_venue('a')]);
      await _pump(tester, controller: controller, pushedNames: pushedNames);
      final l10n = _l10n(tester);

      // Act
      await locate(tester);

      // Assert
      expect(
        find.text(
          venueSearchFailureMessage(VenueSearchFailureReason.timeout, l10n),
        ),
        findsOneWidget,
      );

      // Act
      await tester.tap(find.text(l10n.actionRetry));
      await tester.pumpAndSettle();

      // Assert
      expect(search.nearbyCalls, hasLength(2));
      expect(find.byType(VenueCard), findsOneWidget);
    });

    testWidgets('a search that finds nothing says so, and clearing it '
        'empties the field', (tester) async {
      // Arrange
      await _pump(tester, controller: controller, pushedNames: pushedNames);
      final l10n = _l10n(tester);
      await _type(tester, 'nothing-here');

      // Assert
      expect(find.text(l10n.discoveryNoResultsTitle), findsOneWidget);

      // Act
      await tester.tap(find.text(l10n.discoveryClearSearch));
      await tester.pumpAndSettle();

      // Assert
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller?.text,
        isEmpty,
      );
      expect(find.text(l10n.discoveryEmptyTitle), findsOneWidget);
    });

    testWidgets('Open now hides a closed venue, and tapping it again brings '
        'it back', (tester) async {
      // Arrange
      search.queueFound([
        _venue('open', isOnline: true),
        _venue('closed', isOnline: false),
      ]);
      await _pump(tester, controller: controller, pushedNames: pushedNames);
      await locate(tester);
      final l10n = _l10n(tester);

      // Act
      await tester.tap(
        find.widgetWithText(FilterChip, l10n.discoveryChipOpenNow),
      );
      await tester.pumpAndSettle();

      // Assert
      expect(find.text('Venue open'), findsOneWidget);
      expect(find.text('Venue closed'), findsNothing);

      // Act
      await tester.tap(
        find.widgetWithText(FilterChip, l10n.discoveryChipOpenNow),
      );
      await tester.pumpAndSettle();

      // Assert
      expect(find.text('Venue closed'), findsOneWidget);
    });

    testWidgets('Keto 8+ is always there, disabled with a tooltip, while no '
        'card has numbers (D13, issue #231)', (tester) async {
      // Arrange
      search.queueFound([_venue('a')]);
      await _pump(tester, controller: controller, pushedNames: pushedNames);

      // Act
      await locate(tester);

      // Assert: no Nearby chip; Keto 8+ present but not tappable.
      final l10n = _l10n(tester);
      expect(find.text('Nearby'), findsNothing);
      final keto = find.widgetWithText(
        FilterChip,
        l10n.discoveryChipKetoEightPlus,
      );
      expect(keto, findsOneWidget);
      expect(tester.widget<FilterChip>(keto).onSelected, isNull);
      expect(
        find.byTooltip(l10n.discoveryChipKetoEightPlusHint),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilterChip>(
              find.widgetWithText(FilterChip, l10n.discoveryChipOpenNow),
            )
            .onSelected,
        isNotNull,
      );
    });

    testWidgets('Open now and Keto 8+ combine, and each chip shows its own '
        'selected state', (tester) async {
      // Arrange: both venues are scored 10.0; only one is open.
      final open = _venue('open', isOnline: true);
      final closed = _venue('closed', isOnline: false);
      for (final venue in [open, closed]) {
        repository.seedCache(
          CachedMenu(
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
                  why: 'why',
                ),
              ],
              unclassified: const <String>[],
              engine: const LlmEngine(model: 'test-model'),
              analysedAt: DateTime.utc(2026),
            ),
          ),
        );
      }
      search.queueFound([open, closed]);
      await _pump(tester, controller: controller, pushedNames: pushedNames);
      await locate(tester);
      final l10n = _l10n(tester);
      final keto = find.widgetWithText(
        FilterChip,
        l10n.discoveryChipKetoEightPlus,
      );
      final openNow = find.widgetWithText(
        FilterChip,
        l10n.discoveryChipOpenNow,
      );
      expect(tester.widget<FilterChip>(keto).onSelected, isNotNull);
      expect(find.byTooltip(l10n.discoveryChipKetoEightPlusHint), findsNothing);

      // Act
      await tester.tap(keto);
      await tester.pumpAndSettle();
      await tester.tap(openNow);
      await tester.pumpAndSettle();

      // Assert: both chips are selected at once, and both filters apply.
      expect(tester.widget<FilterChip>(keto).selected, isTrue);
      expect(tester.widget<FilterChip>(openNow).selected, isTrue);
      expect(find.text('Venue open'), findsOneWidget);
      expect(find.text('Venue closed'), findsNothing);

      // Act: turn Keto 8+ off; Open now stays.
      await tester.tap(keto);
      await tester.pumpAndSettle();

      // Assert
      expect(tester.widget<FilterChip>(keto).selected, isFalse);
      expect(tester.widget<FilterChip>(openNow).selected, isTrue);
    });

    testWidgets('Keto 8+ turns on once a cached analysis scores a card, and '
        'keeps only the 8+ venues', (tester) async {
      // Arrange: 'high' is cached at 10.0; 'plain' has nothing cached.
      final high = _venue('high');
      repository.seedCache(
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
                why: 'why',
              ),
            ],
            unclassified: const <String>[],
            engine: const LlmEngine(model: 'test-model'),
            analysedAt: DateTime.utc(2026),
          ),
        ),
      );
      search.queueFound([high, _venue('plain')]);
      await _pump(tester, controller: controller, pushedNames: pushedNames);
      await locate(tester);
      final l10n = _l10n(tester);

      // Assert: the cached venue's card shows its score.
      expect(find.text('10.0'), findsOneWidget);

      // Act
      await tester.tap(
        find.widgetWithText(FilterChip, l10n.discoveryChipKetoEightPlus),
      );
      await tester.pumpAndSettle();

      // Assert
      expect(find.text('Venue high'), findsOneWidget);
      expect(find.text('Venue plain'), findsNothing);
      expect(repository.loadCalls, isEmpty);
    });

    testWidgets('under Hebrew the screen lays out right-to-left and searches '
        'in Hebrew', (tester) async {
      // Arrange
      search.queueFound([_venue('a', isOnline: true)]);
      await _pump(
        tester,
        controller: controller,
        pushedNames: pushedNames,
        locale: const Locale('he'),
      );

      // Act
      await locate(tester);

      // Assert
      final context = tester.element(find.byType(VenueCard));
      expect(Directionality.of(context), TextDirection.rtl);
      expect(search.nearbyCalls.single.language, 'he');
      expect(find.text(_l10n(tester).discoveryChipOpenNow), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'build shows the offline banner while Connectivity reports offline '
      '(issue #68)',
      (tester) async {
        // Act
        await _pump(
          tester,
          controller: controller,
          pushedNames: pushedNames,
          connectivity: FakeConnectivity(online: false),
        );
        await tester.pumpAndSettle();
        final l10n = _l10n(tester);

        // Assert
        expect(find.byType(OfflineBanner), findsOneWidget);
        expect(find.text(l10n.offlineBannerMessage), findsOneWidget);
      },
    );

    testWidgets(
      'build shows no offline banner while Connectivity reports online '
      '(issue #68)',
      (tester) async {
        // Act
        await _pump(
          tester,
          controller: controller,
          pushedNames: pushedNames,
          connectivity: FakeConnectivity(),
        );
        await tester.pumpAndSettle();

        // Assert
        expect(find.text(_l10n(tester).offlineBannerMessage), findsNothing);
      },
    );

    testWidgets('no lastVenue stored shows no Continue row (issue #55)', (
      tester,
    ) async {
      // Act
      await _pump(tester, controller: controller, pushedNames: pushedNames);
      await tester.pumpAndSettle();

      // Assert
      expect(find.byIcon(Icons.history), findsNothing);
    });

    testWidgets(
      'launch with a stored lastVenue shows the Continue row and tapping '
      'it navigates to the venue route (issue #55)',
      (tester) async {
        // Arrange
        const ref = VenueRef(source: MenuSource.wolt, platformId: 'vitrina');
        await settingsStore.write(const AppSettings(lastVenue: ref));
        repository.seedCache(
          CachedMenu(
            menu: Menu(
              venueRef: ref,
              venueName: 'Vitrina',
              currency: 'ILS',
              fetchedAt: DateTime.utc(2026),
              categories: const <MenuCategory>[],
            ),
          ),
        );

        // Act
        await _pump(tester, controller: controller, pushedNames: pushedNames);
        await tester.pumpAndSettle();
        final l10n = _l10n(tester);

        // Assert: the row shows the cached venue name.
        expect(
          find.text(l10n.venueSearchContinueWith('Vitrina')),
          findsOneWidget,
        );

        // Act: tap it.
        await tester.tap(find.text(l10n.venueSearchContinueWith('Vitrina')));
        await tester.pumpAndSettle();

        // Assert
        expect(pushedNames, contains('/venue/wolt/vitrina'));
      },
    );

    group('content width on a wide window (issue #221)', () {
      /// Pumps the screen, locates, and lays the two-venue list out at
      /// [width] logical pixels.
      Future<void> listAt(WidgetTester tester, double width) async {
        search.queueFound([_venue('ember-vine'), _venue('salt-stone')]);
        await _pump(tester, controller: controller, pushedNames: pushedNames);
        await locate(tester);
        tester.view.physicalSize = Size(width, 2400);
        await tester.pumpAndSettle();
      }

      testWidgets('at 1440px the Discovery column is no wider than its own '
          'grid cap and sits centred in the window (issue #222)', (
        tester,
      ) async {
        // Arrange + Act
        await listAt(tester, 1440);

        // Assert: the column is capped at discoveryMaxWidth, not the
        // reading screens' 680, and centred, with the 20px gutters
        // inside it.
        final field = tester.getRect(find.byType(TextField));
        expect(field.width, discoveryMaxWidth - 40);
        expect(field.width, greaterThan(contentMaxWidth));
        expect(field.center.dx, closeTo(720, 0.01));
        final cards = find.byType(VenueCard);
        expect(cards, findsNWidgets(2));
        expect(tester.getRect(cards.first).left, field.left);
        expect(tester.takeException(), isNull);
      });

      testWidgets('at 390px a venue card spans the phone width inside the '
          '20px gutters, as before the cap', (tester) async {
        // Arrange + Act
        await listAt(tester, 390);

        // Assert
        final rect = tester.getRect(find.byType(VenueCard).first);
        expect(rect.left, 20);
        expect(rect.width, 350);
        expect(tester.takeException(), isNull);
      });
    });

    group('venue grid (issue #222)', () {
      /// The cards laid out in the first row: every card whose top edge
      /// is the first card's.
      int firstRowCount(WidgetTester tester, Finder cards) {
        final top = tester.getRect(cards.first).top;
        return cards
            .evaluate()
            .where((e) => tester.getRect(find.byWidget(e.widget)).top == top)
            .length;
      }

      /// Pumps the screen, locates, and lays a four-venue list out at
      /// [width] logical pixels.
      Future<void> fourAt(WidgetTester tester, double width) async {
        search.queueFound([
          _venue('ember-vine'),
          _venue('salt-stone'),
          _venue('olive-row'),
          _venue('cedar-hall'),
        ]);
        await _pump(tester, controller: controller, pushedNames: pushedNames);
        await locate(tester);
        tester.view.physicalSize = Size(width, 2400);
        await tester.pumpAndSettle();
      }

      for (final (width, perRow) in [(390.0, 1), (800.0, 2), (1200.0, 3)]) {
        testWidgets('at ${width.toInt()}px shows $perRow venue card(s) per '
            'row', (tester) async {
          // Arrange + Act
          await fourAt(tester, width);

          // Assert
          final cards = find.byType(VenueCard);
          expect(cards, findsNWidgets(4));
          expect(firstRowCount(tester, cards), perRow);
          expect(tester.takeException(), isNull);
        });
      }

      testWidgets("at 390px the photo keeps the artboard's fixed-height "
          'banner, and at 1200px it is 3:2', (tester) async {
        // Arrange + Act
        await fourAt(tester, 390);

        // Assert
        final phone = tester.getSize(find.byType(PhotoTile).first);
        expect(phone, const Size(350, VenueCard.photoHeight));

        // Act
        tester.view.physicalSize = const Size(1200, 2400);
        await tester.pumpAndSettle();

        // Assert
        final grid = tester.getSize(find.byType(PhotoTile).first);
        expect(
          grid.width / grid.height,
          closeTo(VenueCard.gridPhotoAspectRatio, 0.01),
        );
      });

      testWidgets('cards in one row share a height, so their surfaces line '
          'up', (tester) async {
        // Arrange: one venue with a blurb, so its card is taller.
        search.queueFound([
          const Venue(
            ref: VenueRef(source: MenuSource.wolt, platformId: 'long'),
            name: 'Venue long',
            shortDescription: 'A long blurb that adds a line to this card.',
          ),
          _venue('short'),
        ]);
        await _pump(tester, controller: controller, pushedNames: pushedNames);
        await locate(tester);

        // Act: 800px, two per row.
        tester.view.physicalSize = const Size(800, 2400);
        await tester.pumpAndSettle();

        // Assert
        final cards = find.byType(VenueCard);
        expect(
          tester.getSize(cards.at(0)).height,
          tester.getSize(cards.at(1)).height,
        );
      });

      testWidgets('the loading skeletons follow the same grid at 1200px', (
        tester,
      ) async {
        // Arrange: hold the locate call open on the skeletons.
        final gate = Completer<void>();
        location.gate = gate.future;
        await _pump(tester, controller: controller, pushedNames: pushedNames);
        tester.view.physicalSize = const Size(1200, 2400);
        await tester.pumpAndSettle();

        // Act
        await tester.tap(find.byTooltip(_l10n(tester).discoveryUseLocation));
        await tester.pump();

        // Assert: three skeletons, side by side in one row.
        final skeletons = find.byType(VenueCardSkeleton);
        expect(skeletons, findsNWidgets(3));
        expect(firstRowCount(tester, skeletons), 3);

        // Cleanup
        gate.complete();
        await tester.pumpAndSettle();
      });
    });

    group('Estimate this list (issue #42)', () {
      /// Scripts [venues] to load a one-dish menu each.
      void stubMenus(List<Venue> venues) {
        for (final venue in venues) {
          repository.stub(
            venue.ref,
            MenuFetched(
              menu: Menu(
                venueRef: venue.ref,
                currency: 'ILS',
                fetchedAt: DateTime.utc(2026),
                categories: const <MenuCategory>[
                  MenuCategory(
                    id: 'mains',
                    name: 'Mains',
                    dishes: <Dish>[
                      Dish(
                        id: 'steak',
                        name: 'Steak',
                        description: '',
                        price: 80,
                        options: <DishOption>[],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }
      }

      testWidgets('is offered, with its rules-not-AI copy, while a card has '
          'no numbers, and fetches nothing until tapped', (tester) async {
        // Arrange
        search.queueFound([_venue('a'), _venue('b')]);
        await _pump(tester, controller: controller, pushedNames: pushedNames);

        // Act
        await locate(tester);

        // Assert
        final l10n = _l10n(tester);
        expect(find.text(l10n.discoveryEstimateList), findsOneWidget);
        expect(find.text(l10n.discoveryEstimateHint), findsOneWidget);
        expect(repository.loadCalls, isEmpty);
        expect(estimator.calls, isEmpty);
      });

      testWidgets('tapping it shows progress with the button disabled, then '
          'numbers marked as rules estimates', (tester) async {
        // Arrange
        final venues = [_venue('a'), _venue('b')];
        stubMenus(venues);
        search.queueFound(venues);
        await _pump(tester, controller: controller, pushedNames: pushedNames);
        await locate(tester);
        final l10n = _l10n(tester);
        final gate = Completer<void>();
        repository.loadGate = gate.future;

        // Act
        await tester.tap(find.text(l10n.discoveryEstimateList));
        await tester.pump();

        // Assert: progress, and no second run can be started.
        final progress = find.text(l10n.discoveryEstimating(0, 2));
        expect(progress, findsOneWidget);
        final button = tester.widget<ButtonStyleButton>(
          find.ancestor(
            of: progress,
            matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
          ),
        );
        expect(button.onPressed, isNull);

        // Act
        gate.complete();
        await tester.pumpAndSettle();

        // Assert: both cards scored, each with the rules marker, and the
        // action gone now that no card lacks numbers.
        expect(find.text('10.0'), findsNWidgets(2));
        expect(find.byType(EngineChip), findsNWidgets(2));
        expect(find.text(l10n.discoveryEstimateList), findsNothing);
        expect(estimator.calls, hasLength(2));
      });

      testWidgets('is not offered when every card already has numbers', (
        tester,
      ) async {
        // Arrange
        final venue = _venue('scored');
        repository.seedCache(
          CachedMenu(
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
                  why: 'why',
                ),
              ],
              unclassified: const <String>[],
              engine: const LlmEngine(model: 'test-model'),
              analysedAt: DateTime.utc(2026),
            ),
          ),
        );
        search.queueFound([venue]);
        await _pump(tester, controller: controller, pushedNames: pushedNames);

        // Act
        await locate(tester);

        // Assert
        expect(find.text(_l10n(tester).discoveryEstimateList), findsNothing);
      });

      testWidgets('under Hebrew the action reads in Hebrew', (tester) async {
        // Arrange
        search.queueFound([_venue('a')]);
        await _pump(
          tester,
          controller: controller,
          pushedNames: pushedNames,
          locale: const Locale('he'),
        );

        // Act
        await locate(tester);

        // Assert
        final l10n = _l10n(tester);
        expect(l10n.localeName, 'he');
        expect(find.text(l10n.discoveryEstimateList), findsOneWidget);
        expect(find.text(l10n.discoveryEstimateHint), findsOneWidget);
      });
    });
  });
}

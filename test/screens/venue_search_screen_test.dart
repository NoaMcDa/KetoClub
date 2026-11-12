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
import 'package:ketoclub/services/storage/visit_history_store.dart';
import 'package:ketoclub/services/venue/venue_search_service.dart';
import 'package:ketoclub/state/venue_search_controller.dart';
import 'package:ketoclub/theme/app_theme.dart';
import 'package:ketoclub/utils/constants.dart';
import 'package:ketoclub/utils/known_places.dart';
import 'package:ketoclub/utils/venue_route.dart';
import 'package:ketoclub/widgets/content_width.dart';
import 'package:ketoclub/widgets/engine_chip.dart';
import 'package:ketoclub/widgets/failure_copy.dart';
import 'package:ketoclub/widgets/keto_loader.dart';
import 'package:ketoclub/widgets/location_picker_sheet.dart';
import 'package:ketoclub/widgets/offline_banner.dart';
import 'package:ketoclub/widgets/photo_tile.dart';
import 'package:ketoclub/widgets/skeletons.dart';
import 'package:ketoclub/widgets/venue_card.dart';
import 'package:ketoclub/widgets/venue_grid.dart';
import 'package:provider/provider.dart';

import '../fakes/fake_clock.dart';
import '../fakes/fake_connectivity.dart';
import '../fakes/fake_location_service.dart';
import '../fakes/fake_menu_classifier.dart';
import '../fakes/fake_menu_repository.dart';
import '../fakes/fake_settings_store.dart';
import '../fakes/fake_venue_search_service.dart';
import '../fakes/fake_visit_history_store.dart';

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
/// [Navigator.pushNamed] into [pushedNames], and each push's arguments
/// into [pushedArguments] when given.
Future<void> _pump(
  WidgetTester tester, {
  required VenueSearchController controller,
  required List<String> pushedNames,
  List<Object?>? pushedArguments,
  Locale locale = const Locale('en'),
  Connectivity? connectivity,
  ThemeData? theme,
  LocationService? locationService,
  SettingsStore? settingsStore,
  bool? autofocusSearch,
  bool directToGoogle = false,
  bool backendConfigured = false,
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
          autofocusSearch: autofocusSearch,
          directToGoogle: directToGoogle,
          backendConfigured: backendConfigured,
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
          pushedArguments?.add(settings.arguments);
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
Venue _venue(
  String slug, {
  bool? isOnline,
  String? address,
  double? latitude,
  double? longitude,
}) => Venue(
  ref: VenueRef(source: MenuSource.wolt, platformId: slug),
  name: 'Venue $slug',
  isOnline: isOnline,
  address: address,
  latitude: latitude,
  longitude: longitude,
);

/// A fetched menu for [ref] holding one dish, so the quick score has
/// something to place (the default [FakeMenuClassifier] answer marks it
/// green, scoring 10.0).
MenuFetched _fetchedWithOneDish(VenueRef ref) => MenuFetched(
  menu: Menu(
    venueRef: ref,
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
);

void main() {
  group('VenueSearchScreen', () {
    late FakeSettingsStore settingsStore;
    late FakeMenuRepository repository;
    late FakeLocationService location;
    late FakeVenueSearchService search;
    late FakeMenuClassifier estimator;
    late FakeVisitHistoryStore history;
    late VenueSearchController controller;
    late List<String> pushedNames;

    /// A controller with the automatic quick score (D21) off unless
    /// [autoEstimateLimit] says otherwise, so a test sees only the
    /// fetches it asks for.
    VenueSearchController buildController({int autoEstimateLimit = 0}) =>
        VenueSearchController(
          settingsStore,
          repository,
          locationService: location,
          venueSearchService: search,
          estimateClassifier: estimator,
          autoEstimateLimit: autoEstimateLimit,
          visitHistory: history,
        );

    setUp(() {
      history = FakeVisitHistoryStore(FakeClock(DateTime.utc(2026)));
      settingsStore = FakeSettingsStore();
      repository = FakeMenuRepository();
      location = FakeLocationService();
      search = FakeVenueSearchService();
      estimator = FakeMenuClassifier();
      controller = buildController();
      pushedNames = <String>[];
    });

    /// Taps the header's location button and settles.
    Future<void> locate(WidgetTester tester) async {
      await tester.tap(find.byTooltip(_l10n(tester).discoveryUseLocation));
      await tester.pumpAndSettle();
    }

    testWidgets('on a phone with a backend the first-launch disclosure '
        'says the server comes first (issue #331)', (tester) async {
      // Arrange: a fresh install, so the banner shows.
      await _pump(
        tester,
        controller: controller,
        pushedNames: pushedNames,
        settingsStore: FakeSettingsStore(),
        directToGoogle: true,
        backendConfigured: true,
      );
      await tester.pumpAndSettle();
      final l10n = _l10n(tester);

      // Assert
      expect(
        find.text(l10n.settingsConsentBodyDirectViaBackend),
        findsOneWidget,
      );
      expect(find.text(l10n.settingsConsentBodyDirect), findsNothing);
    });

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

        // Assert: the orbit says what it is waiting for, over the
        // skeletons, announced once through its Semantics label (#450).
        expect(find.byType(KetoLoader), findsOneWidget);
        expect(find.byType(KetoOrbit), findsOneWidget);
        expect(find.text(l10n.discoveryLocating), findsOneWidget);
        expect(find.byType(VenueCardSkeleton), findsNWidgets(3));
        expect(find.bySemanticsLabel(l10n.discoveryLocating), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(
          tester.getCenter(find.byType(KetoOrbit)).dy,
          lessThan(tester.getTopLeft(find.byType(VenueCardSkeleton).first).dy),
        );

        // Cleanup: release the gate so no timer/future is left pending,
        // and the loader goes with the wait.
        gate.complete();
        await tester.pumpAndSettle();
        expect(find.byType(KetoLoader), findsNothing);
        expect(tester.binding.hasScheduledFrame, isFalse);
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
      // The device-location action is the header's alone, never repeated
      // in the body; "Choose a location" sits beside it (issue #443).
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

    testWidgets('typing a plain name shows no invalid message and searches '
        'by name (issue #481)', (tester) async {
      // Arrange
      search.queueFound([_venue('sushi-bar')]);
      await _pump(tester, controller: controller, pushedNames: pushedNames);

      // Act
      await tester.enterText(find.byType(TextField), 'sushi');
      await tester.pump(const Duration(seconds: 1));

      // Assert
      expect(find.text(_l10n(tester).venueSearchInvalid), findsNothing);
      expect(search.byNameCalls, isNotEmpty);
    });

    testWidgets('a name search with no location names the place it '
        'searched around (issue #466)', (tester) async {
      // Arrange
      search.queueFound([_venue('sushi-bar')]);
      await _pump(tester, controller: controller, pushedNames: pushedNames);

      // Act
      await tester.enterText(find.byType(TextField), 'sushi');
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();

      // Assert
      expect(
        find.text(
          _l10n(tester).discoveryNameSearchAround(defaultSearchPlace.nameEn),
        ),
        findsOneWidget,
      );
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

    testWidgets('loading the list scores its first cards on its own with the '
        'rule engine, marked as estimates, and scrolling fetches nothing '
        '(D13, D21)', (tester) async {
      // Arrange: three venues, a cap of two, each with a one-dish menu.
      controller = buildController(autoEstimateLimit: 2);
      final venues = [_venue('a'), _venue('b'), _venue('c')];
      for (final venue in venues) {
        repository.stub(venue.ref, _fetchedWithOneDish(venue.ref));
      }
      search.queueFound(venues);
      await _pump(tester, controller: controller, pushedNames: pushedNames);

      // Act
      await locate(tester);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
      await tester.pumpAndSettle();

      // Assert: two cards scored with the rules marker, no AI, and the
      // third on offer for "Quick score the rest".
      expect(find.byType(VenueCard), findsNWidgets(3));
      expect(find.text('10.0'), findsNWidgets(2));
      expect(find.byType(EngineChip), findsNWidgets(2));
      expect(
        repository.loadCalls.map((call) => call.ref),
        venues.take(2).map((venue) => venue.ref),
      );
      expect(estimator.calls, hasLength(2));
      expect(find.text(_l10n(tester).discoveryEstimateList), findsOneWidget);
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

    testWidgets('the Continue row names the venue from the visit history '
        'and passes its name and city to the route (issue #312)', (
      tester,
    ) async {
      // Arrange: no cached menu; only the history remembers the venue.
      const ref = VenueRef(source: MenuSource.wolt, platformId: 'vitrina');
      await settingsStore.write(const AppSettings(lastVenue: ref));
      history.seed(
        VisitEntry(
          ref: ref,
          name: 'Vitrina',
          city: 'Tel Aviv',
          firstOpenedAt: DateTime.utc(2026),
          lastOpenedAt: DateTime.utc(2026),
          openCount: 2,
        ),
      );
      final arguments = <Object?>[];
      await _pump(
        tester,
        controller: controller,
        pushedNames: pushedNames,
        pushedArguments: arguments,
      );
      await tester.pumpAndSettle();
      final l10n = _l10n(tester);

      // Act
      await tester.tap(find.text(l10n.venueSearchContinueWith('Vitrina')));
      await tester.pumpAndSettle();

      // Assert
      expect(pushedNames.last, '/venue/wolt/vitrina');
      expect(
        arguments.last,
        const VenueOpenHint(name: 'Vitrina', city: 'Tel Aviv'),
      );
    });

    testWidgets('a Continue row known by its slug alone passes no name to '
        'the route (issue #312)', (tester) async {
      // Arrange
      const ref = VenueRef(source: MenuSource.wolt, platformId: 'vitrina');
      await settingsStore.write(const AppSettings(lastVenue: ref));
      final arguments = <Object?>[];
      await _pump(
        tester,
        controller: controller,
        pushedNames: pushedNames,
        pushedArguments: arguments,
      );
      await tester.pumpAndSettle();
      final l10n = _l10n(tester);

      // Act
      await tester.tap(find.text(l10n.venueSearchContinueWith('vitrina')));
      await tester.pumpAndSettle();

      // Assert: the slug is shown, never recorded as the venue's name.
      expect(arguments.last, const VenueOpenHint());
    });

    testWidgets('tapping a card passes its name and city to the route '
        '(issue #312)', (tester) async {
      // Arrange
      search.queueFound([
        const Venue(
          ref: VenueRef(source: MenuSource.wolt, platformId: 'ember'),
          name: 'Ember',
          city: 'Haifa',
        ),
      ]);
      final arguments = <Object?>[];
      await _pump(
        tester,
        controller: controller,
        pushedNames: pushedNames,
        pushedArguments: arguments,
      );
      await locate(tester);

      // Act
      await tester.tap(find.widgetWithText(VenueCard, 'Ember'));
      await tester.pumpAndSettle();

      // Assert
      expect(pushedNames.last, '/venue/wolt/ember');
      expect(arguments.last, const VenueOpenHint(name: 'Ember', city: 'Haifa'));
    });

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

    group('Quick score the rest (issue #42), the automatic run off', () {
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
        // The foods circle as dots in the button, and a segment per
        // restaurant waits to fill (issue #451).
        expect(
          find.descendant(
            of: find.byWidgetPredicate((w) => w is ButtonStyleButton),
            matching: find.byType(KetoOrbit),
          ),
          findsOneWidget,
        );
        final bar = tester.widget<EstimateProgress>(
          find.byType(EstimateProgress),
        );
        expect((bar.done, bar.total), (0, 2));

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

    group('choose a location (issue #443)', () {
      final haifa = knownPlaceById('haifa')!;

      /// Taps the header's "Choose a location" button and settles on the
      /// open sheet.
      Future<void> openPicker(WidgetTester tester) async {
        await tester.tap(find.byTooltip(_l10n(tester).discoveryChooseLocation));
        await tester.pumpAndSettle();
      }

      /// Taps the row of the open sheet naming [name] and settles.
      Future<void> pick(WidgetTester tester, String name) async {
        await tester.tap(find.widgetWithText(ListTile, name));
        await tester.pumpAndSettle();
      }

      testWidgets('before a position the header offers "Choose a location" '
          'beside the location button, and opens nothing by itself', (
        tester,
      ) async {
        // Act
        await _pump(tester, controller: controller, pushedNames: pushedNames);
        await tester.pumpAndSettle();
        final l10n = _l10n(tester);

        // Assert
        expect(find.byTooltip(l10n.discoveryChooseLocation), findsOneWidget);
        expect(find.byTooltip(l10n.discoveryUseLocation), findsOneWidget);
        expect(find.byType(LocationPickerSheet), findsNothing);
        expect(search.nearbyCalls, isEmpty);
      });

      testWidgets('picking a city lists the restaurants around it and names '
          'it in the header, without asking the device', (tester) async {
        // Arrange
        search.queueFound([_venue('haifa-grill', address: 'Ben Gurion 12')]);
        await _pump(tester, controller: controller, pushedNames: pushedNames);
        await tester.pumpAndSettle();
        final l10n = _l10n(tester);

        // Act
        await openPicker(tester);
        await pick(tester, 'Haifa');

        // Assert: the city, not the nearest venue's address.
        expect(find.byType(LocationPickerSheet), findsNothing);
        expect(search.nearbyCalls.single.latitude, haifa.latitude);
        expect(search.nearbyCalls.single.longitude, haifa.longitude);
        expect(search.nearbyCalls.single.language, 'en');
        expect(location.currentCallCount, 0);
        expect(
          find.text(l10n.discoveryLookingAround.toUpperCase()),
          findsOneWidget,
        );
        expect(find.text('Haifa'), findsOneWidget);
        expect(find.text('Ben Gurion 12'), findsNothing);
        expect(find.text('Venue haifa-grill'), findsOneWidget);
        expect(find.text(l10n.discoveryLocationInvite), findsNothing);
        // Both actions stay, to change the place or go back to the device.
        expect(find.byTooltip(l10n.discoveryChooseLocation), findsOneWidget);
        expect(find.byTooltip(l10n.discoveryUseLocation), findsOneWidget);
      });

      testWidgets('picking a city saves it', (tester) async {
        // Arrange
        await _pump(tester, controller: controller, pushedNames: pushedNames);
        await tester.pumpAndSettle();

        // Act
        await openPicker(tester);
        await pick(tester, 'Haifa');

        // Assert
        expect((await settingsStore.read()).discoveryPlaceId, 'haifa');
      });

      testWidgets('under Hebrew the sheet and the header name the city in '
          'Hebrew, and the search is made in Hebrew', (tester) async {
        // Arrange
        search.queueFound([_venue('haifa-grill')]);
        await _pump(
          tester,
          controller: controller,
          pushedNames: pushedNames,
          locale: const Locale('he'),
        );
        await tester.pumpAndSettle();
        final l10n = _l10n(tester);

        // Act
        await openPicker(tester);

        // Assert
        expect(l10n.localeName, 'he');
        expect(find.text(l10n.locationPickerTitle), findsOneWidget);

        // Act
        await pick(tester, 'חיפה');

        // Assert
        expect(find.text('חיפה'), findsOneWidget);
        expect(find.text('Haifa'), findsNothing);
        expect(search.nearbyCalls.single.language, 'he');
      });

      testWidgets('"Use my current location" in the sheet asks the device', (
        tester,
      ) async {
        // Arrange
        search.queueFound([_venue('ember-vine')]);
        await _pump(tester, controller: controller, pushedNames: pushedNames);
        await tester.pumpAndSettle();
        final l10n = _l10n(tester);

        // Act
        await openPicker(tester);
        await tester.tap(find.text(l10n.locationPickerUseDevice));
        await tester.pumpAndSettle();

        // Assert
        expect(location.currentCallCount, 1);
        expect(controller.chosenPlace, isNull);
        expect(find.byType(VenueCard), findsOneWidget);
      });

      testWidgets('dismissing the sheet changes nothing', (tester) async {
        // Arrange
        await _pump(tester, controller: controller, pushedNames: pushedNames);
        await tester.pumpAndSettle();
        final l10n = _l10n(tester);

        // Act
        await openPicker(tester);
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();

        // Assert
        expect(find.byType(LocationPickerSheet), findsNothing);
        expect(search.nearbyCalls, isEmpty);
        expect(location.currentCallCount, 0);
        expect(find.text(l10n.discoveryLocationInvite), findsOneWidget);
      });

      testWidgets('tapping the place in the header opens the sheet with the '
          'chosen city marked', (tester) async {
        // Arrange
        await _pump(tester, controller: controller, pushedNames: pushedNames);
        await tester.pumpAndSettle();
        await openPicker(tester);
        await pick(tester, 'Haifa');

        // Act
        await tester.tap(find.text('Haifa'));
        await tester.pumpAndSettle();

        // Assert
        expect(find.byType(LocationPickerSheet), findsOneWidget);
        expect(
          tester
              .widget<ListTile>(
                find.descendant(
                  of: find.byType(LocationPickerSheet),
                  matching: find.widgetWithText(ListTile, 'Haifa'),
                ),
              )
              .selected,
          isTrue,
        );
      });

      testWidgets('picking another city replaces the first', (tester) async {
        // Arrange
        await _pump(tester, controller: controller, pushedNames: pushedNames);
        await tester.pumpAndSettle();
        await openPicker(tester);
        await pick(tester, 'Haifa');

        // Act
        await openPicker(tester);
        await pick(tester, 'Jerusalem');

        // Assert
        expect(find.text('Jerusalem'), findsOneWidget);
        expect(find.text('Haifa'), findsNothing);
        expect(search.nearbyCalls, hasLength(2));
        expect((await settingsStore.read()).discoveryPlaceId, 'jerusalem');
      });

      testWidgets('a city saved by an earlier launch is listed on open, with '
          'no tap and no location prompt', (tester) async {
        // Arrange
        await settingsStore.write(const AppSettings(discoveryPlaceId: 'haifa'));
        search.queueFound([_venue('haifa-grill')]);

        // Act
        await _pump(tester, controller: controller, pushedNames: pushedNames);
        await tester.pumpAndSettle();

        // Assert
        expect(find.text('Haifa'), findsOneWidget);
        expect(find.text('Venue haifa-grill'), findsOneWidget);
        expect(search.nearbyCalls.single.latitude, haifa.latitude);
        expect(location.currentCallCount, 0);
      });

      testWidgets('the denied card offers "Choose a location", and picking a '
          'city replaces the card with its restaurants', (tester) async {
        // Arrange
        location.result = const LocationDenied(permanently: true);
        search.queueFound([_venue('haifa-grill')]);
        await _pump(tester, controller: controller, pushedNames: pushedNames);
        await locate(tester);
        final l10n = _l10n(tester);
        expect(find.text(l10n.discoveryLocationDeniedTitle), findsOneWidget);

        // Act: the card's action, since the header has stepped aside.
        expect(find.byTooltip(l10n.discoveryChooseLocation), findsNothing);
        await tester.tap(find.text(l10n.discoveryChooseLocation));
        await tester.pumpAndSettle();
        await pick(tester, 'Haifa');

        // Assert
        expect(find.text(l10n.discoveryLocationDeniedTitle), findsNothing);
        expect(find.text('Venue haifa-grill'), findsOneWidget);
        expect(find.text('Haifa'), findsOneWidget);
      });

      testWidgets('the unavailable card offers "Choose a location" too', (
        tester,
      ) async {
        // Arrange
        location.result = const LocationUnavailable(
          reason: LocationUnavailableReason.unsupported,
        );
        await _pump(tester, controller: controller, pushedNames: pushedNames);
        await locate(tester);
        final l10n = _l10n(tester);

        // Act
        await tester.tap(find.text(l10n.discoveryChooseLocation));
        await tester.pumpAndSettle();

        // Assert
        expect(find.byType(LocationPickerSheet), findsOneWidget);
      });

      for (final entry in <LocationResult, String Function(AppLocalizations)>{
        const LocationDenied(permanently: false): (l10n) =>
            l10n.discoveryLocationDeniedTitle,
        const LocationUnavailable(reason: LocationUnavailableReason.timeout): (
          l10n,
        ) => l10n.discoveryLocationUnavailableTitle,
      }.entries) {
        testWidgets("with a city's list on screen, a location that comes "
            'back ${entry.key} says so in a snack bar and keeps the list', (
          tester,
        ) async {
          // Arrange
          search.queueFound([_venue('haifa-grill')]);
          await _pump(tester, controller: controller, pushedNames: pushedNames);
          await tester.pumpAndSettle();
          await openPicker(tester);
          await pick(tester, 'Haifa');
          final l10n = _l10n(tester);
          location.result = entry.key;

          // Act
          await tester.tap(find.byTooltip(l10n.discoveryUseLocation));
          await tester.pump();
          await tester.pump();

          // Assert: the tap is never a silent no-op, and nothing is lost.
          expect(
            find.widgetWithText(SnackBar, entry.value(l10n)),
            findsOneWidget,
          );
          expect(find.text('Venue haifa-grill'), findsOneWidget);
          expect(find.text('Haifa'), findsOneWidget);
        });
      }

      testWidgets('a refused location with nothing on screen shows the '
          'card, not a snack bar', (tester) async {
        // Arrange
        location.result = const LocationDenied(permanently: false);
        await _pump(tester, controller: controller, pushedNames: pushedNames);

        // Act
        await locate(tester);

        // Assert
        expect(find.byType(SnackBar), findsNothing);
        expect(
          find.text(_l10n(tester).discoveryLocationDeniedTitle),
          findsOneWidget,
        );
      });
    });

    group('distance filter (issue #443)', () {
      final telAviv = knownPlaceById('tel-aviv')!;

      /// A venue [km] kilometres due north of Tel Aviv's centre.
      Venue at(String slug, double km) => _venue(
        slug,
        // One degree of latitude is about 111.2 km.
        latitude: telAviv.latitude + km / 111.2,
        longitude: telAviv.longitude,
      );

      /// The distance chip, whatever it reads.
      Finder distanceChip(WidgetTester tester) =>
          find.byTooltip(_l10n(tester).discoveryChipDistanceTooltip);

      /// Lists [venues] around Tel Aviv, as picking it in the sheet does.
      Future<void> listAround(WidgetTester tester, List<Venue> venues) async {
        search.queueFound(venues);
        await _pump(tester, controller: controller, pushedNames: pushedNames);
        await tester.pumpAndSettle();
        await controller.choosePlace(telAviv, language: 'en');
        await tester.pumpAndSettle();
      }

      /// Opens the chip's menu and taps the entry reading [label].
      Future<void> choose(WidgetTester tester, String label) async {
        await tester.tap(distanceChip(tester));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(MenuItemButton, label));
        await tester.pumpAndSettle();
      }

      testWidgets('reads "Any distance", unselected, once a list around a '
          'place is showing', (tester) async {
        // Act
        await listAround(tester, [at('near', 0.5), at('far', 20)]);
        final l10n = _l10n(tester);

        // Assert
        final chip = find.widgetWithText(
          FilterChip,
          l10n.discoveryChipAnyDistance,
        );
        expect(chip, findsOneWidget);
        expect(tester.widget<FilterChip>(chip).selected, isFalse);
        expect(find.byType(MenuItemButton), findsNothing);
      });

      testWidgets('is the first chip in the row', (tester) async {
        // Act
        await listAround(tester, [at('near', 0.5)]);
        final l10n = _l10n(tester);

        // Assert
        final chips = tester.widgetList<FilterChip>(find.byType(FilterChip));
        expect(chips.first.tooltip, l10n.discoveryChipDistanceTooltip);
      });

      testWidgets('is absent while there is no position to measure from', (
        tester,
      ) async {
        // Arrange
        search.queueFound([at('near', 0.5)]);
        await _pump(tester, controller: controller, pushedNames: pushedNames);

        // Act: a search by name, before any position.
        await _type(tester, 'sushi');
        await tester.pumpAndSettle();

        // Assert: the other chips are there; this one is not.
        expect(find.byType(VenueCard), findsOneWidget);
        expect(
          find.widgetWithText(FilterChip, _l10n(tester).discoveryChipOpenNow),
          findsOneWidget,
        );
        expect(distanceChip(tester), findsNothing);
      });

      testWidgets('is there after the device gives a position, too', (
        tester,
      ) async {
        // Arrange
        search.queueFound([_venue('ember-vine')]);
        await _pump(tester, controller: controller, pushedNames: pushedNames);

        // Act
        await locate(tester);

        // Assert
        expect(distanceChip(tester), findsOneWidget);
      });

      testWidgets('tapping it opens a menu of "Any distance" and every '
          'offered distance, with the current one ticked', (tester) async {
        // Arrange
        await listAround(tester, [at('near', 0.5)]);
        final l10n = _l10n(tester);

        // Act
        await tester.tap(distanceChip(tester));
        await tester.pumpAndSettle();

        // Assert
        expect(
          find.widgetWithText(MenuItemButton, l10n.discoveryChipAnyDistance),
          findsOneWidget,
        );
        for (final km in discoveryRadiusOptionsKm) {
          expect(
            find.widgetWithText(MenuItemButton, l10n.discoveryChipWithinKm(km)),
            findsOneWidget,
          );
        }
        final ticks = tester
            .widgetList<Visibility>(
              find.descendant(
                of: find.byType(MenuItemButton),
                matching: find.byType(Visibility),
              ),
            )
            .map((v) => v.visible)
            .toList();
        expect(ticks, [true, false, false, false, false]);
      });

      testWidgets('picking a distance keeps only the restaurants within it, '
          'and the chip says which', (tester) async {
        // Arrange
        await listAround(tester, [
          at('near', 0.5),
          at('walk', 1.5),
          at('far', 20),
        ]);
        final l10n = _l10n(tester);

        // Act
        await choose(tester, l10n.discoveryChipWithinKm(2));

        // Assert
        expect(find.byType(MenuItemButton), findsNothing);
        expect(find.text('Venue near'), findsOneWidget);
        expect(find.text('Venue walk'), findsOneWidget);
        expect(find.text('Venue far'), findsNothing);
        final chip = find.widgetWithText(
          FilterChip,
          l10n.discoveryChipWithinKm(2),
        );
        expect(tester.widget<FilterChip>(chip).selected, isTrue);
        expect(find.text(l10n.discoveryChipAnyDistance), findsNothing);
      });

      testWidgets('picking "Any distance" again puts every restaurant '
          'back', (tester) async {
        // Arrange
        await listAround(tester, [at('near', 0.5), at('far', 20)]);
        final l10n = _l10n(tester);
        await choose(tester, l10n.discoveryChipWithinKm(1));
        expect(find.text('Venue far'), findsNothing);

        // Act
        await choose(tester, l10n.discoveryChipAnyDistance);

        // Assert
        expect(find.text('Venue near'), findsOneWidget);
        expect(find.text('Venue far'), findsOneWidget);
        expect(
          tester
              .widget<FilterChip>(
                find.widgetWithText(FilterChip, l10n.discoveryChipAnyDistance),
              )
              .selected,
          isFalse,
        );
      });

      testWidgets('combines with Open now', (tester) async {
        // Arrange
        search.queueFound([
          _venue(
            'near-open',
            isOnline: true,
            latitude: telAviv.latitude,
            longitude: telAviv.longitude,
          ),
          _venue(
            'near-closed',
            isOnline: false,
            latitude: telAviv.latitude,
            longitude: telAviv.longitude,
          ),
          _venue(
            'far-open',
            isOnline: true,
            latitude: telAviv.latitude + 0.5,
            longitude: telAviv.longitude,
          ),
        ]);
        await _pump(tester, controller: controller, pushedNames: pushedNames);
        await tester.pumpAndSettle();
        await controller.choosePlace(telAviv, language: 'en');
        await tester.pumpAndSettle();
        final l10n = _l10n(tester);

        // Act
        await choose(tester, l10n.discoveryChipWithinKm(5));
        await tester.tap(
          find.widgetWithText(FilterChip, l10n.discoveryChipOpenNow),
        );
        await tester.pumpAndSettle();

        // Assert
        expect(find.text('Venue near-open'), findsOneWidget);
        expect(find.text('Venue near-closed'), findsNothing);
        expect(find.text('Venue far-open'), findsNothing);
      });

      testWidgets('a distance nothing is within says so, with the chip '
          'still there to widen it', (tester) async {
        // Arrange
        await listAround(tester, [at('far', 20)]);
        final l10n = _l10n(tester);

        // Act
        await choose(tester, l10n.discoveryChipWithinKm(1));

        // Assert
        expect(find.byType(VenueCard), findsNothing);
        expect(find.text(l10n.discoveryNoChipResults), findsOneWidget);
        expect(distanceChip(tester), findsOneWidget);
      });

      testWidgets('under Hebrew the chip and its menu read in Hebrew', (
        tester,
      ) async {
        // Arrange
        search.queueFound([at('near', 0.5)]);
        await _pump(
          tester,
          controller: controller,
          pushedNames: pushedNames,
          locale: const Locale('he'),
        );
        await tester.pumpAndSettle();
        await controller.choosePlace(telAviv, language: 'he');
        await tester.pumpAndSettle();
        final l10n = _l10n(tester);

        // Act
        await choose(tester, l10n.discoveryChipWithinKm(5));

        // Assert
        expect(l10n.localeName, 'he');
        expect(l10n.discoveryChipWithinKm(5), 'עד 5 ק״מ');
        expect(
          find.widgetWithText(FilterChip, l10n.discoveryChipWithinKm(5)),
          findsOneWidget,
        );
        expect(controller.radiusKm, 5);
      });
    });

    group('lazy venue list (issue #446)', () {
      /// Every venue card in the element tree, on screen or in the scroll
      /// view's cache beyond it.
      final builtCards = find.byType(VenueCard, skipOffstage: false);

      /// Lists [count] venues named `Venue v0`, `Venue v1`, … on a
      /// phone-sized surface: one column, an 800px-tall window.
      Future<void> listMany(WidgetTester tester, int count) async {
        search.queueFound([for (var i = 0; i < count; i++) _venue('v$i')]);
        await _pump(tester, controller: controller, pushedNames: pushedNames);
        await locate(tester);
        tester.view.physicalSize = const Size(390, 800);
        await tester.pumpAndSettle();
      }

      testWidgets('a list of hundreds builds only the cards on or near the '
          'screen', (tester) async {
        // Act
        await listMany(tester, 334);

        // Assert: the controller holds them all; the page built a
        // screenful and the cache beyond it.
        expect(controller.visibleResults, hasLength(334));
        final built = builtCards.evaluate().length;
        expect(built, greaterThan(0));
        expect(built, lessThan(30));
        expect(find.text('Venue v0'), findsOneWidget);
        expect(find.text('Venue v333', skipOffstage: false), findsNothing);
        expect(tester.takeException(), isNull);
      });

      testWidgets('only the built cards have a photo tile, so only their '
          'photos are asked for', (tester) async {
        // Act
        await listMany(tester, 334);

        // Assert
        expect(
          find.byType(PhotoTile, skipOffstage: false).evaluate().length,
          builtCards.evaluate().length,
        );
      });

      testWidgets('scrolling down builds the cards that come into view and '
          'lets go of the ones left behind', (tester) async {
        // Arrange
        await listMany(tester, 334);
        expect(find.text('Venue v40', skipOffstage: false), findsNothing);

        // Act: fling far down the list.
        await tester.fling(
          find.byType(CustomScrollView),
          const Offset(0, -3000),
          6000,
        );
        await tester.pumpAndSettle();

        // Assert: later cards exist now, the first is gone, and the page
        // still holds a bounded number.
        expect(find.text('Venue v0', skipOffstage: false), findsNothing);
        final lastBuilt = tester
            .widgetList<VenueCard>(builtCards)
            .map((card) => int.parse(card.venue.name.split('v').last))
            .reduce((a, b) => a > b ? a : b);
        expect(lastBuilt, greaterThan(20));
        expect(builtCards.evaluate().length, lessThan(30));
        expect(tester.takeException(), isNull);
      });

      testWidgets('the page scrolls as one: the header and the search field '
          'leave with the cards', (tester) async {
        // Arrange
        await listMany(tester, 60);
        expect(find.text(_l10n(tester).discoveryTitle), findsOneWidget);

        // Act
        await tester.drag(
          find.byType(CustomScrollView),
          const Offset(0, -1500),
        );
        await tester.pumpAndSettle();

        // Assert
        expect(find.text(_l10n(tester).discoveryTitle), findsNothing);
        expect(find.byType(TextField), findsNothing);
        expect(find.byType(VenueCard), findsWidgets);
      });

      testWidgets('a card scrolled into view opens its own venue', (
        tester,
      ) async {
        // Arrange
        await listMany(tester, 60);

        // Act: scroll until a card far down the list is built, then tap.
        // It is first built in the cache below the fold, so bring it on
        // screen, and let a frame lay the page out, before the tap.
        await tester.scrollUntilVisible(
          find.text('Venue v25'),
          400,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.ensureVisible(find.text('Venue v25'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Venue v25'));
        await tester.pumpAndSettle();

        // Assert
        expect(pushedNames, contains('/venue/wolt/v25'));
      });

      testWidgets('a chip that narrows the list rebuilds it from the top of '
          'what is left', (tester) async {
        // Arrange: every third venue is open.
        search.queueFound([
          for (var i = 0; i < 90; i++) _venue('v$i', isOnline: i % 3 == 0),
        ]);
        await _pump(tester, controller: controller, pushedNames: pushedNames);
        await locate(tester);
        final l10n = _l10n(tester);

        // Act
        await tester.tap(
          find.widgetWithText(FilterChip, l10n.discoveryChipOpenNow),
        );
        await tester.pumpAndSettle();

        // Assert: only open venues among the built cards.
        final names = tester
            .widgetList<VenueCard>(builtCards)
            .map((card) => card.venue.name)
            .toList();
        expect(names.take(3), ['Venue v0', 'Venue v3', 'Venue v6']);
        expect(controller.visibleResults, hasLength(30));
      });

      testWidgets('a quick score landing while the list shows updates the '
          'card on screen and builds no more cards', (tester) async {
        // Arrange: the automatic run scores the first venue.
        controller = buildController(autoEstimateLimit: 1);
        final venues = [for (var i = 0; i < 200; i++) _venue('v$i')];
        repository.stub(
          venues.first.ref,
          _fetchedWithOneDish(venues.first.ref),
        );
        search.queueFound(venues);
        await _pump(tester, controller: controller, pushedNames: pushedNames);

        // Act
        await locate(tester);

        // Assert
        expect(find.text('10.0'), findsOneWidget);
        expect(builtCards.evaluate().length, lessThan(40));
      });
    });

    group('search autofocus (issue #264)', () {
      /// Whether the pumped screen's search field holds primary focus.
      bool searchFocused(WidgetTester tester) => tester
          .widget<TextField>(find.byType(TextField))
          .focusNode!
          .hasPrimaryFocus;

      testWidgets('takes focus on open when autofocusSearch is on', (
        tester,
      ) async {
        // Arrange & Act
        await _pump(
          tester,
          controller: controller,
          pushedNames: pushedNames,
          autofocusSearch: true,
        );
        await tester.pump();

        // Assert
        expect(searchFocused(tester), isTrue);
      });

      testWidgets('leaves focus alone when autofocusSearch is off, so a '
          'phone shows no keyboard', (tester) async {
        // Arrange & Act
        await _pump(
          tester,
          controller: controller,
          pushedNames: pushedNames,
          autofocusSearch: false,
        );
        await tester.pump();

        // Assert
        expect(searchFocused(tester), isFalse);
      });

      testWidgets('defaults to off outside the web build', (tester) async {
        // Arrange & Act: the flutter_tester VM is not `kIsWeb`.
        await _pump(tester, controller: controller, pushedNames: pushedNames);
        await tester.pump();

        // Assert
        expect(searchFocused(tester), isFalse);
      });
    });
  });
}

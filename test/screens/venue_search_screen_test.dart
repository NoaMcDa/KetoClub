import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/screens/venue_search_screen.dart';
import 'package:ketoclub/services/location/location_service.dart';
import 'package:ketoclub/services/platform/connectivity.dart';
import 'package:ketoclub/services/storage/menu_cache.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/services/venue/venue_search_service.dart';
import 'package:ketoclub/state/venue_search_controller.dart';
import 'package:ketoclub/theme/app_theme.dart';
import 'package:ketoclub/utils/constants.dart';
import 'package:ketoclub/widgets/failure_copy.dart';
import 'package:ketoclub/widgets/offline_banner.dart';
import 'package:ketoclub/widgets/skeletons.dart';
import 'package:ketoclub/widgets/venue_card.dart';
import 'package:provider/provider.dart';

import '../fakes/fake_connectivity.dart';
import '../fakes/fake_location_service.dart';
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
    late VenueSearchController controller;
    late List<String> pushedNames;

    setUp(() {
      settingsStore = FakeSettingsStore();
      repository = FakeMenuRepository();
      location = FakeLocationService();
      search = FakeVenueSearchService();
      controller = VenueSearchController(
        settingsStore,
        repository,
        locationService: location,
        venueSearchService: search,
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

    testWidgets('build renders the brand, the title and the search field', (
      tester,
    ) async {
      // Act
      await _pump(tester, controller: controller, pushedNames: pushedNames);
      final l10n = _l10n(tester);

      // Assert
      expect(find.text(appName), findsOneWidget);
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

    testWidgets('before anything is asked, the header says no location is '
        'set and the empty state offers the three ways in', (tester) async {
      // Act
      await _pump(tester, controller: controller, pushedNames: pushedNames);
      await tester.pumpAndSettle();
      final l10n = _l10n(tester);

      // Assert
      expect(find.text(l10n.discoveryLocationNotSet), findsOneWidget);
      expect(find.text(l10n.discoveryEmptyTitle), findsOneWidget);
      expect(find.text(l10n.discoveryEmptyBody), findsOneWidget);
      expect(find.text(l10n.discoveryUseLocation), findsOneWidget);
      // No location prompt on open: the user has to ask.
      expect(location.currentCallCount, 0);
      expect(find.byType(ChoiceChip), findsNothing);
    });

    testWidgets('typing nonsense shows the venueSearchInvalid message', (
      tester,
    ) async {
      // Arrange
      await _pump(tester, controller: controller, pushedNames: pushedNames);

      // Act
      await tester.enterText(
        find.byType(TextField),
        'https://example.com/nope',
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

    testWidgets('typing a valid slug enables the submit affordance', (
      tester,
    ) async {
      // Arrange
      await _pump(tester, controller: controller, pushedNames: pushedNames);

      // Assert: disabled before anything resolves.
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );

      // Act
      await _type(tester, 'vitrina-lilinblum');

      // Assert
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
    });

    testWidgets(
      'tapping the submit affordance pushes the venue route path for a '
      'Wolt slug',
      (tester) async {
        // Arrange
        await _pump(tester, controller: controller, pushedNames: pushedNames);
        await _type(tester, 'vitrina-lilinblum');

        // Act
        await tester.tap(find.byType(FilledButton));
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
        await tester.tap(find.byType(FilledButton));
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
      await tester.tap(find.text('Venue salt-stone'));
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

    testWidgets('a permanent denial offers no retry, only a name search', (
      tester,
    ) async {
      // Arrange
      location.result = const LocationDenied(permanently: true);
      await _pump(tester, controller: controller, pushedNames: pushedNames);
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
    });

    testWidgets('an unavailable location shows the copy for its reason', (
      tester,
    ) async {
      // Arrange
      location.result = const LocationUnavailable(
        reason: LocationUnavailableReason.servicesOff,
      );
      await _pump(tester, controller: controller, pushedNames: pushedNames);
      final l10n = _l10n(tester);

      // Act
      await locate(tester);

      // Assert
      expect(find.text(l10n.discoveryLocationUnavailableTitle), findsOneWidget);
      expect(find.text(l10n.discoveryLocationServicesOff), findsOneWidget);
      expect(find.text(l10n.discoveryTypeNameInstead), findsOneWidget);
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
        find.widgetWithText(ChoiceChip, l10n.discoveryChipOpenNow),
      );
      await tester.pumpAndSettle();

      // Assert
      expect(find.text('Venue open'), findsOneWidget);
      expect(find.text('Venue closed'), findsNothing);

      // Act
      await tester.tap(
        find.widgetWithText(ChoiceChip, l10n.discoveryChipOpenNow),
      );
      await tester.pumpAndSettle();

      // Assert
      expect(find.text('Venue closed'), findsOneWidget);
    });

    testWidgets('Keto 8+ is hidden while no card has numbers (D13)', (
      tester,
    ) async {
      // Arrange
      search.queueFound([_venue('a')]);
      await _pump(tester, controller: controller, pushedNames: pushedNames);

      // Act
      await locate(tester);

      // Assert
      final l10n = _l10n(tester);
      expect(find.text(l10n.discoveryChipNearby), findsOneWidget);
      expect(find.text(l10n.discoveryChipKetoEightPlus), findsNothing);
    });

    testWidgets('Keto 8+ appears once a cached analysis scores a card, and '
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
        find.widgetWithText(ChoiceChip, l10n.discoveryChipKetoEightPlus),
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
      expect(find.text(_l10n(tester).discoveryChipNearby), findsOneWidget);
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

    testWidgets('build under Locale(he) renders the Hebrew title', (
      tester,
    ) async {
      // Act
      await _pump(
        tester,
        controller: controller,
        pushedNames: pushedNames,
        locale: const Locale('he'),
      );
      final l10n = _l10n(tester);

      // Assert
      expect(find.text(l10n.venueSearchLabel), findsOneWidget);
      expect(find.text(l10n.discoveryTitle), findsOneWidget);
      expect(find.text(l10n.discoveryEmptyBody), findsOneWidget);
    });

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
  });
}

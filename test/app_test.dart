import 'package:flutter/material.dart'
    show MaterialApp, NavigationBar, TextDirection, TextField, ThemeMode;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/app.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/models/scanned_menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/screens/drinks_guide_screen.dart' show drinksRoutePath;
import 'package:ketoclub/screens/scan_screen.dart';
import 'package:ketoclub/screens/settings_screen.dart';
import 'package:ketoclub/screens/venue_search_screen.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/state/app_dependencies.dart';
import 'package:ketoclub/state/scan_controller.dart';
import 'package:ketoclub/state/venue_search_controller.dart';
import 'package:ketoclub/utils/constants.dart';
import 'package:ketoclub/utils/venue_route.dart';
import 'package:ketoclub/widgets/app_shell.dart';
import 'package:ketoclub/widgets/route_title.dart';
import 'package:provider/provider.dart';

import 'fakes/fake_app_dependencies.dart';

/// The English strings this file reads expected copy from.
final AppLocalizations _en = AppLocalizationsEn();

void main() {
  group('KetoClubApp', () {
    testWidgets('shows the app name on launch', (tester) async {
      // Arrange: the real app on top of faked services.
      await tester.pumpWidget(
        KetoClubApp(dependencies: FakeAppDependencies().dependencies),
      );
      // Assert
      expect(find.text(appName), findsOneWidget);
    });

    testWidgets('the Explore tab is selected on launch', (tester) async {
      // Arrange / Act
      await tester.pumpWidget(
        KetoClubApp(dependencies: FakeAppDependencies().dependencies),
      );
      await tester.pumpAndSettle();

      // Assert
      final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(bar.selectedIndex, equals(AppShell.exploreIndex));
    });

    testWidgets('follows the device locale before any tag has loaded', (
      tester,
    ) async {
      // Arrange / Act: the very first frame, before `LocaleController.load`
      // has resolved — an accepted one-frame lag (issue #8), not a crash.
      await tester.pumpWidget(
        KetoClubApp(dependencies: FakeAppDependencies().dependencies),
      );

      // Assert: still renders something sensible immediately.
      expect(find.text(appName), findsOneWidget);
    });

    testWidgets('renders RTL once a stored Hebrew language tag has loaded', (
      tester,
    ) async {
      // Arrange: pre-seeding the store the way a completed
      // `SettingsController.setLanguage('he')` write would leave it, so
      // this exercises `LocaleController.load` without driving the
      // Settings screen (issue #8).
      final fakes = FakeAppDependencies();
      await fakes.settingsStore.write(const AppSettings(languageTag: 'he'));

      // Act
      await tester.pumpWidget(KetoClubApp(dependencies: fakes.dependencies));
      await tester.pumpAndSettle();

      // Assert: appName is untranslated (CLAUDE.md), so it is still on
      // screen and a stable anchor to read the ambient direction from.
      final context = tester.element(find.text(appName));
      expect(Directionality.of(context), TextDirection.rtl);
    });

    testWidgets('renders LTR once a stored English language tag has loaded', (
      tester,
    ) async {
      // Arrange
      final fakes = FakeAppDependencies();
      await fakes.settingsStore.write(const AppSettings(languageTag: 'en'));

      // Act
      await tester.pumpWidget(KetoClubApp(dependencies: fakes.dependencies));
      await tester.pumpAndSettle();

      // Assert
      final context = tester.element(find.text(appName));
      expect(Directionality.of(context), TextDirection.ltr);
    });

    testWidgets('uses ThemeMode.system before any mode has loaded', (
      tester,
    ) async {
      // Arrange / Act: the very first frame, before
      // `ThemeModeController.load` has resolved — mirrors the locale
      // test above (issue #8, #58).
      await tester.pumpWidget(
        KetoClubApp(dependencies: FakeAppDependencies().dependencies),
      );

      // Assert
      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.themeMode, equals(ThemeMode.system));
    });

    testWidgets('applies a previously stored dark theme mode on launch', (
      tester,
    ) async {
      // Arrange: pre-seeding the store the way a completed
      // `SettingsController.setThemeMode(AppThemeMode.dark)` write would
      // leave it, exactly as the stored-locale tests above do.
      final fakes = FakeAppDependencies();
      await fakes.settingsStore.write(
        const AppSettings(themeMode: AppThemeMode.dark),
      );

      // Act
      await tester.pumpWidget(KetoClubApp(dependencies: fakes.dependencies));
      await tester.pumpAndSettle();

      // Assert
      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.themeMode, equals(ThemeMode.dark));
    });

    testWidgets('choosing Dark in Settings changes MaterialApp.themeMode', (
      tester,
    ) async {
      // Arrange: a real navigation into Settings, the same way the
      // direct-route test below reaches it.
      await tester.pumpWidget(
        KetoClubApp(dependencies: FakeAppDependencies().dependencies),
      );
      await tester.pumpAndSettle();
      final navigatorFinder = find.byType(Navigator).first;
      tester
          .state<NavigatorState>(navigatorFinder)
          .pushReplacementNamed(settingsRoutePath);
      await tester.pumpAndSettle();

      // Act: scoped to the appearance radio group, so a label the
      // language and appearance sections happen to share can never make
      // this finder ambiguous (settings_screen.dart's
      // `appearanceRadioGroupKey`).
      final dark = find.descendant(
        of: find.byKey(appearanceRadioGroupKey),
        matching: find.text(_en.settingsAppearanceDark),
      );
      await tester.ensureVisible(dark);
      await tester.tap(dark);
      await tester.pumpAndSettle();

      // Assert
      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.themeMode, equals(ThemeMode.dark));
    });

    testWidgets('Estimate this list reaches the rule engine alone, never the '
        'routing classifier (issue #42, D13)', (tester) async {
      // Arrange: the real Explore route over faked services, so this
      // checks the wiring in generateRoute, not a controller built by
      // hand.
      final fakes = FakeAppDependencies();
      const ref = VenueRef(source: MenuSource.wolt, platformId: 'ember');
      fakes.venueSearchService.queueFound(const [
        Venue(ref: ref, name: 'Ember'),
      ]);
      await tester.pumpWidget(KetoClubApp(dependencies: fakes.dependencies));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(_en.discoveryUseLocation));
      await tester.pumpAndSettle();

      // Assert: listing fetched nothing.
      expect(fakes.repository.loadCalls, isEmpty);

      // Act
      final estimate = find.text(_en.discoveryEstimateList);
      await tester.ensureVisible(estimate);
      await tester.tap(estimate);
      await tester.pumpAndSettle();

      // Assert
      expect(fakes.repository.loadCalls.single.ref, ref);
      expect(fakes.estimateClassifier.calls, hasLength(1));
      expect(fakes.classifier.calls, isEmpty);
    });

    testWidgets('the Explore controller, query and results survive a tab '
        'switch and the route rebuild it causes (issue #233)', (tester) async {
      // Arrange: a name search answered on Explore.
      final fakes = FakeAppDependencies();
      fakes.venueSearchService.queueFound(const [
        Venue(
          ref: VenueRef(source: MenuSource.wolt, platformId: 'sushi-bar'),
          name: 'Sushi Bar',
        ),
      ]);
      await tester.pumpWidget(KetoClubApp(dependencies: fakes.dependencies));
      await tester.pumpAndSettle();
      VenueSearchController explore() => Provider.of<VenueSearchController>(
        tester.element(find.byType(VenueSearchScreen)),
        listen: false,
      );
      final before = explore();
      await tester.enterText(find.byType(TextField), 'sushi');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(find.text('Sushi Bar'), findsOneWidget);

      // Act: away to Saved, which disposes the Explore route, and back.
      Finder tab(String label) => find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text(label),
      );
      await tester.tap(tab(_en.navSaved));
      await tester.pumpAndSettle();
      expect(find.byType(VenueSearchScreen), findsNothing);
      await tester.tap(tab(_en.navExplore));
      await tester.pumpAndSettle();

      // Assert: the same controller, its query in a new field, its list.
      expect(explore(), same(before));
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller?.text,
        'sushi',
      );
      expect(find.text('Sushi Bar'), findsOneWidget);
      expect(fakes.venueSearchService.byNameCalls, hasLength(1));
    });

    testWidgets('a direct route to /settings lands on the Settings tab', (
      tester,
    ) async {
      // Arrange: a real navigation, not a call to generateRoute in
      // isolation, so this exercises the same Navigator the app bar's
      // settings action and the bottom nav both use.
      await tester.pumpWidget(
        KetoClubApp(dependencies: FakeAppDependencies().dependencies),
      );
      await tester.pumpAndSettle();
      final navigatorFinder = find.byType(Navigator).first;

      // Act
      tester
          .state<NavigatorState>(navigatorFinder)
          .pushReplacementNamed(settingsRoutePath);
      await tester.pumpAndSettle();

      // Assert
      expect(find.byType(AppShell), findsOneWidget);
      final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(bar.selectedIndex, equals(AppShell.settingsIndex));
    });
  });

  group('browser tab title (issue #226)', () {
    testWidgets('follows the route: tab label, drinks guide, then back', (
      tester,
    ) async {
      // Arrange: record what the app tells the platform the title is.
      final titles = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method ==
                'SystemChrome.setApplicationSwitcherDescription') {
              final args = call.arguments as Map<Object?, Object?>;
              titles.add(args['label']! as String);
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      await tester.pumpWidget(
        KetoClubApp(dependencies: FakeAppDependencies().dependencies),
      );
      await tester.pumpAndSettle();
      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );

      // Assert: the Explore tab names itself.
      expect(titles.last, documentTitle(_en.navExplore));

      // Act / Assert: a pushed tab root, then the drinks guide.
      navigator.pushReplacementNamed(settingsRoutePath);
      await tester.pumpAndSettle();
      expect(titles.last, documentTitle(_en.navSettings));
      navigator.pushNamed(drinksRoutePath);
      await tester.pumpAndSettle();
      expect(titles.last, documentTitle(_en.drinksGuideTitle));
      navigator.pop();
      await tester.pumpAndSettle();
      expect(titles.last, documentTitle(_en.navSettings));

      // Act / Assert: a venue route is titled with the name the card passed.
      navigator.pushNamed('/venue/wolt/hamosad', arguments: 'Hamosad');
      await tester.pumpAndSettle();
      expect(titles.last, documentTitle('Hamosad'));
      navigator.pop();
      await tester.pumpAndSettle();
      expect(titles.last, documentTitle(_en.navSettings));
    });
  });

  group('venueRefFromPath', () {
    test('parses a venue path into a ref', () {
      // Act
      final ref = venueRefFromPath('/venue/wolt/vitrina-lilinblum');

      // Assert
      expect(
        ref,
        const VenueRef(
          source: MenuSource.wolt,
          platformId: 'vitrina-lilinblum',
        ),
      );
    });

    test('matches the source by name, not by ordinal', () {
      // Assert: a saved link must survive a reordering of MenuSource.
      expect(
        venueRefFromPath('/venue/tenbis/12345')?.source,
        MenuSource.tenbis,
      );
      expect(venueRefFromPath('/venue/0/12345'), isNull);
    });

    test('reads back a website ref, whose URL is one encoded segment', () {
      // Arrange
      const ref = VenueRef(
        source: MenuSource.website,
        platformId: 'https://cafe-noir.co.il/menu?lang=he',
      );

      // Act
      final path = venueRoutePath(ref);

      // Assert
      expect(path, startsWith('/venue/website/https%3A%2F%2F'));
      expect(venueRefFromPath(path), ref);
      expect(
        venueRoutePath(
          const VenueRef(source: MenuSource.wolt, platformId: 'a-b'),
        ),
        '/venue/wolt/a-b',
      );
    });

    test('rejects a path that is not a venue route', () {
      // Assert
      expect(venueRefFromPath('/'), isNull);
      expect(venueRefFromPath('/settings'), isNull);
      expect(venueRefFromPath('/venue/wolt'), isNull);
      expect(venueRefFromPath('/venue/wolt/'), isNull);
      expect(venueRefFromPath('/venue/nosuch/slug'), isNull);
    });
  });

  group('generateRoute', () {
    test('builds a route for the home, settings and venue paths', () {
      // Arrange
      final dependencies = FakeAppDependencies().dependencies;

      // Assert
      for (final path in <String>[
        '/',
        scanRoutePath,
        savedRoutePath,
        settingsRoutePath,
        '/venue/wolt/vitrina-lilinblum',
      ]) {
        expect(
          generateRoute(RouteSettings(name: path), dependencies),
          isNotNull,
          reason: 'no route for $path',
        );
      }
    });

    testWidgets('the scan route hands ScanController the scanned-menu '
        'classifier and the pages registry from the dependencies '
        '(issue #89)', (tester) async {
      // Arrange
      final fakes = FakeAppDependencies();
      await tester.pumpWidget(KetoClubApp(dependencies: fakes.dependencies));
      await tester.pumpAndSettle();

      // Act
      tester
          .state<NavigatorState>(find.byType(Navigator).first)
          .pushNamed(scanRoutePath);
      await tester.pumpAndSettle();

      // Assert
      final controller = Provider.of<ScanController>(
        tester.element(find.byType(ScanScreen)),
        listen: false,
      );
      expect(controller.classifier, same(fakes.scannedMenuClassifier));
      // The registry is private; a read proves it is the dependencies' one,
      // which the menu screen reads for "View pages".
      final page = ScannedPage(
        mimeType: ScannedPage.jpeg,
        bytes: Uint8List.fromList(<int>[1, 2, 3]),
      );
      controller.addPages(<ScannedPage>[page]);
      final ref = await controller.analysePages();
      expect(ref, isNotNull);
      expect(
        fakes.scannedPages.get(ref!),
        ScannedMenu(pages: <ScannedPage>[page]),
      );
    });

    testWidgets('the scan route hands ScanController the QR scanner '
        '(issue #182)', (tester) async {
      // Arrange
      final fakes = FakeAppDependencies();
      fakes.qrScanner.queuePayload('Table 12');
      await tester.pumpWidget(KetoClubApp(dependencies: fakes.dependencies));
      await tester.pumpAndSettle();

      // Act
      tester
          .state<NavigatorState>(find.byType(Navigator).first)
          .pushNamed(scanRoutePath);
      await tester.pumpAndSettle();
      final controller = Provider.of<ScanController>(
        tester.element(find.byType(ScanScreen)),
        listen: false,
      );
      await controller.scanQr();

      // Assert
      expect(controller.qrScanner, same(fakes.qrScanner));
      expect(fakes.qrScanner.scanCallCount, 1);
    });

    testWidgets('MaterialApp uses the navigator key from the dependencies '
        '(issue #182)', (tester) async {
      // Arrange
      final key = GlobalKey<NavigatorState>();
      final base = FakeAppDependencies().dependencies;
      final dependencies = AppDependencies(
        menuRepository: base.menuRepository,
        menuClassifier: base.menuClassifier,
        estimateClassifier: base.estimateClassifier,
        settingsStore: base.settingsStore,
        notesStore: base.notesStore,
        clock: base.clock,
        logger: base.logger,
        connectivity: base.connectivity,
        externalLinkOpener: base.externalLinkOpener,
        menuSharer: base.menuSharer,
        locationService: base.locationService,
        venueSearchService: base.venueSearchService,
        scannedPages: base.scannedPages,
        navigatorKey: key,
      );

      // Act
      await tester.pumpWidget(KetoClubApp(dependencies: dependencies));
      await tester.pumpAndSettle();

      // Assert
      expect(key.currentState, isNotNull);
      expect(
        key.currentState,
        same(tester.state<NavigatorState>(find.byType(Navigator).first)),
      );
    });

    test('returns null for an unknown path rather than a blank screen', () {
      // Arrange
      final dependencies = FakeAppDependencies().dependencies;

      // Assert
      expect(
        generateRoute(const RouteSettings(name: '/nope'), dependencies),
        isNull,
      );
    });
  });
}

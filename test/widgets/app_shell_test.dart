import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/l10n/generated/app_localizations_he.dart';
import 'package:ketoclub/theme/app_theme.dart';
import 'package:ketoclub/theme/app_tokens.dart';
import 'package:ketoclub/widgets/app_shell.dart';

/// The English strings a test can read expected copy from.
final AppLocalizations _en = AppLocalizationsEn();

/// The Hebrew strings a right-to-left test can read expected copy from.
final AppLocalizations _he = AppLocalizationsHe();

/// Maps a route name to the tab index it should show, mirroring
/// `generateRoute`'s own mapping in `app.dart`. This test cannot import
/// `app.dart` to reuse that mapping directly — `widgets/` sits below
/// `app.dart` in the layer order (architecture.md §5) — so this is the
/// test-side half of the same coupling `AppShell`'s own class doc names.
int _indexFor(String? name) {
  switch (name) {
    case '/scan':
      return AppShell.scanIndex;
    case '/saved':
      return AppShell.savedIndex;
    case '/settings':
      return AppShell.settingsIndex;
    default:
      return AppShell.exploreIndex;
  }
}

/// The one route [_pump]'s app builds without an [AppShell] — a stand-in
/// for the menu screen, the pushed detail route Settings can be opened
/// from (audit G8).
const String _detailRoute = '/detail';

/// Pumps a tiny app whose every route but [_detailRoute] is an [AppShell]
/// wrapping a [Text] naming the route, wired through a real [Navigator] the
/// same way `generateRoute` wires the four tab-root routes in `app.dart`.
/// That lets a tab tap be followed end to end, rather than only asserting
/// on the [NavigationBar] in isolation. [locale] and [theme] default to the
/// bare English app every phone-width test below uses.
Future<void> _pump(
  WidgetTester tester, {
  String initialRoute = '/',
  Locale? locale,
  ThemeData? theme,
}) {
  return tester.pumpWidget(
    MaterialApp(
      locale: locale,
      theme: theme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      initialRoute: initialRoute,
      onGenerateRoute: (settings) => MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => settings.name == _detailRoute
            ? const Text('screen:$_detailRoute')
            : AppShell(
                currentIndex: _indexFor(settings.name),
                child: Text('screen:${settings.name}'),
              ),
      ),
    ),
  );
}

/// Sizes the test window to [width] logical pixels wide (and a fixed,
/// comfortable height), restoring the default once the test ends.
void _setWidth(WidgetTester tester, double width) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 900);
  addTearDown(tester.view.reset);
}

/// The navigator the shell under test lives in.
NavigatorState _navigator(WidgetTester tester) =>
    tester.state<NavigatorState>(find.byType(Navigator));

/// Records every `SystemNavigator.pop` — what the framework calls when
/// nothing in the app handled Back, i.e. when Back leaves the app (on web,
/// the site) — for the rest of the test.
List<String> _recordAppExits() {
  final exits = <String>[];
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'SystemNavigator.pop') exits.add(call.method);
        return null;
      });
  addTearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null),
  );
  return exits;
}

/// Presses the platform's Back — the browser's Back button on web, the
/// system back on Android — the way the engine reports it, and settles.
/// Returns whether the app handled it rather than exiting.
Future<bool> _pressBack(WidgetTester tester) async {
  final handled = await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
  return handled;
}

void main() {
  group('AppShell', () {
    testWidgets('shows all four destinations with localized labels', (
      tester,
    ) async {
      // Act
      await _pump(tester);
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(_en.navExplore), findsOneWidget);
      expect(find.text(_en.navScan), findsOneWidget);
      expect(find.text(_en.navSaved), findsOneWidget);
      expect(find.text(_en.navSettings), findsOneWidget);
    });

    testWidgets('the Recent tab uses a history icon, not a bookmark', (
      tester,
    ) async {
      // Act
      await _pump(tester);
      await tester.pumpAndSettle();

      // Assert
      expect(find.byIcon(Icons.history), findsOneWidget);
      expect(find.byIcon(Icons.bookmark_border), findsNothing);
      expect(find.byIcon(Icons.bookmark), findsNothing);
    });

    testWidgets('the tab matching the current route is selected', (
      tester,
    ) async {
      // Act
      await _pump(tester, initialRoute: '/saved');
      await tester.pumpAndSettle();

      // Assert
      final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(bar.selectedIndex, equals(AppShell.savedIndex));
    });

    testWidgets('tapping Scan navigates to /scan and selects that tab', (
      tester,
    ) async {
      // Arrange
      await _pump(tester);
      await tester.pumpAndSettle();

      // Act
      await tester.tap(find.text(_en.navScan));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text('screen:/scan'), findsOneWidget);
      final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(bar.selectedIndex, equals(AppShell.scanIndex));
    });

    testWidgets('switching tabs then back to Explore returns to /', (
      tester,
    ) async {
      // Arrange
      await _pump(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.text(_en.navSaved));
      await tester.pumpAndSettle();
      expect(find.text('screen:/saved'), findsOneWidget);

      // Act
      await tester.tap(find.text(_en.navExplore));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text('screen:/'), findsOneWidget);
      final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(bar.selectedIndex, equals(AppShell.exploreIndex));
    });

    testWidgets('tapping the already-active tab does not navigate away', (
      tester,
    ) async {
      // Arrange
      await _pump(tester);
      await tester.pumpAndSettle();

      // Act
      await tester.tap(find.text(_en.navExplore));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text('screen:/'), findsOneWidget);
    });

    testWidgets('the navigation stack never grows across tab switches', (
      tester,
    ) async {
      // Arrange
      await _pump(tester);
      await tester.pumpAndSettle();

      // Act: three switches in a row.
      await tester.tap(find.text(_en.navScan));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_en.navSaved));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_en.navSettings));
      await tester.pumpAndSettle();

      // Assert: each tab replaced the last, so nothing is left to pop to.
      expect(_navigator(tester).canPop(), isFalse);
    });

    testWidgets('Back after switching to Saved returns to Explore, not out '
        'of the app (issue #262)', (tester) async {
      // Arrange
      final exits = _recordAppExits();
      await _pump(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.text(_en.navSaved));
      await tester.pumpAndSettle();

      // Act
      final handled = await _pressBack(tester);

      // Assert
      expect(handled, isTrue);
      expect(exits, isEmpty);
      expect(find.text('screen:/'), findsOneWidget);
      expect(find.text('screen:/saved'), findsNothing);
      final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(bar.selectedIndex, equals(AppShell.exploreIndex));
    });

    testWidgets('Back from any tab other than Explore returns to Explore', (
      tester,
    ) async {
      // Arrange: Explore, Scan, then Settings — Back goes home, as
      // Material's bottom navigation prescribes, not one tab back.
      await _pump(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.text(_en.navScan));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_en.navSettings));
      await tester.pumpAndSettle();

      // Act
      final handled = await _pressBack(tester);

      // Assert
      expect(handled, isTrue);
      expect(find.text('screen:/'), findsOneWidget);
      expect(_navigator(tester).canPop(), isFalse);
    });

    testWidgets('Back from Explore leaves the app', (tester) async {
      // Arrange
      final exits = _recordAppExits();
      await _pump(tester);
      await tester.pumpAndSettle();

      // Act
      final handled = await _pressBack(tester);

      // Assert
      expect(handled, isFalse);
      expect(exits, ['SystemNavigator.pop']);
    });

    testWidgets('a tab pushed over a detail route pops back to it', (
      tester,
    ) async {
      // Arrange: Explore, a detail route, then Settings over it — the
      // menu screen's Settings action.
      await _pump(tester);
      await tester.pumpAndSettle();
      _navigator(tester).pushNamed(_detailRoute);
      await tester.pumpAndSettle();
      _navigator(tester).pushNamed('/settings');
      await tester.pumpAndSettle();

      // Act
      final handled = await _pressBack(tester);

      // Assert
      expect(handled, isTrue);
      expect(find.text('screen:$_detailRoute'), findsOneWidget);
      expect(find.byType(AppShell), findsNothing);
    });

    testWidgets('a tab tap from a tab pushed over a detail route leaves no '
        'detail route beneath (audit G8)', (tester) async {
      // Arrange: Explore, a detail route, then Settings over it.
      await _pump(tester);
      await tester.pumpAndSettle();
      _navigator(tester).pushNamed(_detailRoute);
      await tester.pumpAndSettle();
      _navigator(tester).pushNamed('/settings');
      await tester.pumpAndSettle();

      // Act
      await tester.tap(find.text(_en.navSaved));
      await tester.pumpAndSettle();

      // Assert: only the new tab is left, so the detail route is gone from
      // the tree and the stack.
      expect(find.text('screen:/saved'), findsOneWidget);
      expect(
        find.text('screen:$_detailRoute', skipOffstage: false),
        findsNothing,
      );
      expect(_navigator(tester).canPop(), isFalse);
    });

    testWidgets('a deep-linked tab, stacked over Explore, pops back to it', (
      tester,
    ) async {
      // Arrange: Flutter pushes `/` under an initial `/saved`.
      await _pump(tester, initialRoute: '/saved');
      await tester.pumpAndSettle();

      // Act
      final handled = await _pressBack(tester);

      // Assert
      expect(handled, isTrue);
      expect(find.text('screen:/'), findsOneWidget);
      expect(_navigator(tester).canPop(), isFalse);
    });
  });

  group('AppShell at 840px and wider (issue #223)', () {
    for (final (:width, :rail) in [
      (width: 390.0, rail: false),
      (width: 839.0, rail: false),
      (width: AppShell.railBreakpoint, rail: true),
      (width: 1200.0, rail: true),
    ]) {
      testWidgets('at ${width.toInt()}px shows '
          '${rail ? 'a rail and no bottom bar' : 'the bottom bar, no rail'}', (
        tester,
      ) async {
        // Arrange
        _setWidth(tester, width);

        // Act
        await _pump(tester);
        await tester.pumpAndSettle();

        // Assert
        expect(
          find.byType(NavigationRail),
          rail ? findsOneWidget : findsNothing,
        );
        expect(
          find.byType(NavigationBar),
          rail ? findsNothing : findsOneWidget,
        );
      });
    }

    testWidgets('the rail is compact, shows every label, and selects the '
        "current route's tab", (tester) async {
      // Arrange
      _setWidth(tester, 1200);

      // Act
      await _pump(tester, initialRoute: '/saved');
      await tester.pumpAndSettle();

      // Assert
      final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
      expect(rail.extended, isFalse);
      expect(rail.labelType, NavigationRailLabelType.all);
      expect(rail.selectedIndex, equals(AppShell.savedIndex));
      for (final label in [
        _en.navExplore,
        _en.navScan,
        _en.navSaved,
        _en.navSettings,
      ]) {
        expect(
          find.descendant(
            of: find.byType(NavigationRail),
            matching: find.text(label),
          ),
          findsOneWidget,
        );
      }
    });

    testWidgets('the active tab is drawn in the accent, the rest in ink3', (
      tester,
    ) async {
      // Arrange
      _setWidth(tester, 1200);

      // Act
      await _pump(tester, theme: AppTheme.light());
      await tester.pumpAndSettle();

      // Assert: Explore is active (its filled icon), Scan is not.
      final active = IconTheme.of(tester.element(find.byIcon(Icons.explore)));
      final inactive = IconTheme.of(
        tester.element(find.byIcon(Icons.document_scanner_outlined)),
      );
      expect(active.color, AppTokens.lightAccent);
      expect(inactive.color, AppTokens.lightInk3);
    });

    testWidgets('in English the rail sits on the left, beside the content', (
      tester,
    ) async {
      // Arrange
      _setWidth(tester, 1200);

      // Act
      await _pump(tester);
      await tester.pumpAndSettle();

      // Assert
      final rail = tester.getRect(find.byType(NavigationRail));
      expect(rail.left, 0);
      expect(tester.getRect(find.text('screen:/')).left, rail.right);
    });

    testWidgets('in Hebrew the rail mirrors to the right edge', (tester) async {
      // Arrange
      _setWidth(tester, 1200);

      // Act
      await _pump(tester, locale: const Locale('he'));
      await tester.pumpAndSettle();

      // Assert
      final rail = tester.getRect(find.byType(NavigationRail));
      expect(rail.right, 1200);
      expect(tester.getRect(find.text('screen:/')).right, rail.left);
      expect(
        find.descendant(
          of: find.byType(NavigationRail),
          matching: find.text(_he.navSaved),
        ),
        findsOneWidget,
      );
    });

    testWidgets('in Hebrew at phone width the bottom bar is unchanged', (
      tester,
    ) async {
      // Arrange
      _setWidth(tester, 390);

      // Act
      await _pump(tester, locale: const Locale('he'));
      await tester.pumpAndSettle();

      // Assert
      expect(find.byType(NavigationRail), findsNothing);
      expect(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text(_he.navSaved),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a rail tap replaces the tab, exactly as a bar tap does', (
      tester,
    ) async {
      // Arrange
      _setWidth(tester, 1200);
      await _pump(tester);
      await tester.pumpAndSettle();

      // Act
      await tester.tap(find.text(_en.navScan));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_en.navSaved));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text('screen:/saved'), findsOneWidget);
      final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
      expect(rail.selectedIndex, equals(AppShell.savedIndex));
      expect(_navigator(tester).canPop(), isFalse);
    });

    testWidgets('Back from a tab beside the rail returns to Explore', (
      tester,
    ) async {
      // Arrange
      _setWidth(tester, 1200);
      await _pump(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.text(_en.navSettings));
      await tester.pumpAndSettle();

      // Act
      final handled = await _pressBack(tester);

      // Assert
      expect(handled, isTrue);
      expect(find.text('screen:/'), findsOneWidget);
    });

    testWidgets('a rail tap from a tab pushed over a detail route leaves no '
        'detail route beneath (audit G8)', (tester) async {
      // Arrange
      _setWidth(tester, 1200);
      await _pump(tester);
      await tester.pumpAndSettle();
      _navigator(tester).pushNamed(_detailRoute);
      await tester.pumpAndSettle();
      _navigator(tester).pushNamed('/settings');
      await tester.pumpAndSettle();

      // Act
      await tester.tap(find.text(_en.navSaved));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text('screen:/saved'), findsOneWidget);
      expect(_navigator(tester).canPop(), isFalse);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/widgets/app_shell.dart';

/// The English strings a test can read expected copy from.
final AppLocalizations _en = AppLocalizationsEn();

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

/// Pumps a tiny app whose every route is an [AppShell] wrapping a [Text]
/// naming the route, wired through a real [Navigator] the same way
/// `generateRoute` wires the four tab-root routes in `app.dart`. That lets a
/// tab tap be followed end to end, rather than only asserting on the
/// [NavigationBar] in isolation.
Future<void> _pump(WidgetTester tester, {String initialRoute = '/'}) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      initialRoute: initialRoute,
      onGenerateRoute: (settings) => MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => AppShell(
          currentIndex: _indexFor(settings.name),
          child: Text('screen:${settings.name}'),
        ),
      ),
    ),
  );
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

      // Act: three replacements in a row.
      await tester.tap(find.text(_en.navScan));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_en.navSaved));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_en.navSettings));
      await tester.pumpAndSettle();

      // Assert: pushReplacementNamed means there is nothing left to pop to.
      final context = tester.element(find.byType(AppShell));
      expect(Navigator.of(context).canPop(), isFalse);
    });
  });
}

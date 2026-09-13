import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/screens/venue_search_screen.dart';
import 'package:ketoclub/state/venue_search_controller.dart';
import 'package:ketoclub/utils/constants.dart';
import 'package:provider/provider.dart';

/// Pumps the real [VenueSearchScreen] over a real
/// [VenueSearchController], recording every route name pushed via
/// [Navigator.pushNamed] into [pushedNames].
Future<void> _pump(
  WidgetTester tester, {
  required VenueSearchController controller,
  required List<String> pushedNames,
  Locale locale = const Locale('en'),
}) {
  return tester.pumpWidget(
    ChangeNotifierProvider<VenueSearchController>.value(
      value: controller,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        home: const VenueSearchScreen(),
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

void main() {
  group('VenueSearchScreen', () {
    late VenueSearchController controller;
    late List<String> pushedNames;

    setUp(() {
      controller = VenueSearchController();
      pushedNames = <String>[];
    });

    testWidgets('build renders the title and the search field', (tester) async {
      // Act
      await _pump(tester, controller: controller, pushedNames: pushedNames);

      // Assert
      expect(find.text(appName), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('typing nonsense shows the venueSearchInvalid message', (
      tester,
    ) async {
      // Arrange
      await _pump(tester, controller: controller, pushedNames: pushedNames);
      final context = tester.element(find.byType(VenueSearchScreen));
      final l10n = AppLocalizations.of(context)!;

      // Act
      await tester.enterText(
        find.byType(TextField),
        'https://example.com/nope',
      );
      await tester.pump();

      // Assert
      expect(find.text(l10n.venueSearchInvalid), findsOneWidget);
    });

    testWidgets('an empty field shows no invalid message', (tester) async {
      // Arrange
      await _pump(tester, controller: controller, pushedNames: pushedNames);
      final context = tester.element(find.byType(VenueSearchScreen));
      final l10n = AppLocalizations.of(context)!;

      // Assert: nothing typed yet.
      expect(find.text(l10n.venueSearchInvalid), findsNothing);
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
      await tester.enterText(find.byType(TextField), 'vitrina-lilinblum');
      await tester.pump();

      // Assert
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
    });

    testWidgets('tapping the submit affordance pushes the venue route path', (
      tester,
    ) async {
      // Arrange
      await _pump(tester, controller: controller, pushedNames: pushedNames);
      await tester.enterText(find.byType(TextField), '123456');
      await tester.pump();

      // Act
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();

      // Assert
      expect(pushedNames, contains('/venue/tenbis/123456'));
    });

    testWidgets('tapping the settings action pushes the settings route', (
      tester,
    ) async {
      // Arrange
      await _pump(tester, controller: controller, pushedNames: pushedNames);

      // Act
      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();

      // Assert
      expect(pushedNames, contains('/settings'));
    });

    testWidgets('build under Locale(he) renders the Hebrew label', (
      tester,
    ) async {
      // Act
      await _pump(
        tester,
        controller: controller,
        pushedNames: pushedNames,
        locale: const Locale('he'),
      );
      final context = tester.element(find.byType(VenueSearchScreen));
      final l10n = AppLocalizations.of(context)!;

      // Assert
      expect(find.text(l10n.venueSearchLabel), findsOneWidget);
      expect(find.text(appName), findsOneWidget);
    });
  });
}

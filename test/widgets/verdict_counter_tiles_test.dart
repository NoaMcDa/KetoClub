import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/widgets/verdict_counter_tiles.dart';

/// Pumps [child] inside a localised [MaterialApp] and a [Scaffold], the
/// shape every widget test in `test/widgets/` uses.
Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Locale locale = const Locale('en'),
}) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  group('VerdictCounterTiles', () {
    testWidgets('build shows each count and its label', (tester) async {
      // Arrange & Act
      await _pump(
        tester,
        VerdictCounterTiles(
          greenCount: 9,
          yellowCount: 5,
          redCount: 24,
          filter: MenuFilter.all,
          onFilterChanged: (_) {},
        ),
      );

      // Assert
      expect(find.text('9'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      expect(find.text('24'), findsOneWidget);
      expect(find.text('ORDER AS-IS'), findsOneWidget);
      expect(find.text('WITH CHANGES'), findsOneWidget);
      expect(find.text('SKIP'), findsOneWidget);
    });

    testWidgets(
      "tapping an inactive tile reports that tile's single-verdict filter",
      (tester) async {
        // Arrange
        MenuFilter? reported;
        await _pump(
          tester,
          VerdictCounterTiles(
            greenCount: 1,
            yellowCount: 2,
            redCount: 3,
            filter: MenuFilter.all,
            onFilterChanged: (filter) => reported = filter,
          ),
        );

        // Act
        await tester.tap(find.text('WITH CHANGES'));
        await tester.pump();

        // Assert
        expect(reported, MenuFilter.yellowOnly);
      },
    );

    testWidgets('tapping the already-active tile reports MenuFilter.all', (
      tester,
    ) async {
      // Arrange
      MenuFilter? reported;
      await _pump(
        tester,
        VerdictCounterTiles(
          greenCount: 1,
          yellowCount: 2,
          redCount: 3,
          filter: MenuFilter.redOnly,
          onFilterChanged: (filter) => reported = filter,
        ),
      );

      // Act: the Skip tile is the active one under redOnly.
      await tester.tap(find.text('SKIP'));
      await tester.pump();

      // Assert
      expect(reported, MenuFilter.all);
    });

    testWidgets('each tile carries a semantic label naming its count', (
      tester,
    ) async {
      // Arrange
      await _pump(
        tester,
        VerdictCounterTiles(
          greenCount: 7,
          yellowCount: 0,
          redCount: 0,
          filter: MenuFilter.all,
          onFilterChanged: (_) {},
        ),
      );

      // Assert
      expect(find.bySemanticsLabel('Order as-is: 7'), findsOneWidget);
    });

    testWidgets('build shows the Hebrew labels in the he locale', (
      tester,
    ) async {
      // Arrange
      await _pump(
        tester,
        VerdictCounterTiles(
          greenCount: 1,
          yellowCount: 1,
          redCount: 1,
          filter: MenuFilter.all,
          onFilterChanged: (_) {},
        ),
        locale: const Locale('he'),
      );

      // Assert: Hebrew has no case, so toUpperCase() in the widget is a
      // no-op and the label reads exactly as stored.
      expect(find.text('לדלג'), findsOneWidget);
    });
  });
}

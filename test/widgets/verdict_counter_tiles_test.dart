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

    testWidgets(
      'every tile shows an icon beside its colour, never colour alone '
      '(architecture.md §6.6)',
      (tester) async {
        // Arrange & Act
        await _pump(
          tester,
          VerdictCounterTiles(
            greenCount: 1,
            yellowCount: 2,
            redCount: 3,
            filter: MenuFilter.all,
            onFilterChanged: (_) {},
          ),
        );

        // Assert: one icon per tile, plus its own text label — a
        // colour-blind user can read every tile from shape and text alone.
        expect(find.byType(Icon), findsNWidgets(3));
      },
    );

    testWidgets(
      'an inactive tile carries a "double tap to filter" semantics hint, '
      'an active one "double tap to clear the filter"',
      (tester) async {
        // Arrange
        final handle = tester.ensureSemantics();

        // Act
        await _pump(
          tester,
          VerdictCounterTiles(
            greenCount: 1,
            yellowCount: 2,
            redCount: 3,
            filter: MenuFilter.redOnly,
            onFilterChanged: (_) {},
          ),
        );

        // Assert: the Skip tile is active under redOnly, so it alone
        // carries the "clear" hint, and reports selected — the other two
        // tiles carry the "filter" hint and report not selected.
        expect(
          tester.getSemantics(find.text('SKIP')).getSemanticsData(),
          matchesSemantics(
            label: 'Skip: 3',
            hint: 'Double tap to clear the filter',
            isButton: true,
            isSelected: true,
            hasTapAction: true,
          ),
        );
        expect(
          tester.getSemantics(find.text('ORDER AS-IS')).getSemanticsData(),
          matchesSemantics(
            label: 'Order as-is: 1',
            hint: 'Double tap to filter',
            isButton: true,
            hasTapAction: true,
          ),
        );
        handle.dispose();
      },
    );

    testWidgets(
      'build does not overflow at a 2x text scale with three-digit counts '
      'on a narrow phone width (architecture.md §8.3)',
      (tester) async {
        // Arrange: a 340-wide surface (a small phone) and a 2x text scale
        // together squeeze each tile — one third of the row minus its
        // gaps — the least room a real device gives this widget.
        tester.view.physicalSize = const Size(340, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        // Act
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Builder(
                builder: (context) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: const TextScaler.linear(2)),
                  child: VerdictCounterTiles(
                    greenCount: 128,
                    yellowCount: 46,
                    redCount: 999,
                    filter: MenuFilter.all,
                    onFilterChanged: (_) {},
                  ),
                ),
              ),
            ),
          ),
        );

        // Assert
        expect(tester.takeException(), isNull);
      },
    );

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

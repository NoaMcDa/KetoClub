import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/theme/verdict_colors.dart';
import 'package:ketoclub/utils/price_format.dart';
import 'package:ketoclub/widgets/dish_card.dart';
import 'package:ketoclub/widgets/status_badge.dart';
import 'package:ketoclub/widgets/waiter_script_widget.dart';

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

Dish _dish({String description = ''}) => Dish(
  id: 'dish_1',
  name: 'Grilled Salmon',
  description: description,
  price: 64,
  options: const [],
);

void main() {
  group('DishCard', () {
    testWidgets('build shows the dish price formatted with formatPrice', (
      tester,
    ) async {
      // Arrange
      final row = DishRow(dish: _dish(), category: 'Mains');

      // Act
      await _pump(
        tester,
        DishCard(row: row, localeTag: 'en', onShowScript: (_) {}),
      );

      // Assert
      expect(find.text(formatPrice(64, localeTag: 'en')), findsOneWidget);
    });

    testWidgets(
      'build starts a modifiable row collapsed, with the full-sheet button '
      'visible either way',
      (tester) async {
        // Arrange
        const script = 'Replace the mashed potatoes with a green salad.';
        final row = DishRow(
          dish: _dish(),
          category: 'Mains',
          analysis: const AnalysedDish(
            dishId: 'dish_1',
            name: 'Grilled Salmon',
            verdict: DishVerdict.modifiable,
            why: 'Mostly protein, with a starchy side to swap.',
            modification: script,
          ),
        );

        // Act
        await _pump(
          tester,
          DishCard(row: row, localeTag: 'en', onShowScript: (_) {}),
        );

        // Assert: collapsed by default (architecture.md §6.6, issue #30's
        // expandable script), so the script itself is not yet built, but
        // the summary CTA, the badge and the always-visible full-sheet
        // button are.
        expect(find.byType(WaiterScriptWidget), findsNothing);
        expect(find.text(script), findsNothing);
        expect(find.text('Ask your waiter'), findsOneWidget);
        expect(find.byType(StatusBadge), findsOneWidget);
        expect(find.text('Show the waiter card'), findsOneWidget);
      },
    );

    testWidgets('tapping the summary row expands the script, and tapping again '
        'collapses it', (tester) async {
      // Arrange
      const script = 'Replace the mashed potatoes with a green salad.';
      final row = DishRow(
        dish: _dish(),
        category: 'Mains',
        analysis: const AnalysedDish(
          dishId: 'dish_1',
          name: 'Grilled Salmon',
          verdict: DishVerdict.modifiable,
          why: 'Mostly protein, with a starchy side to swap.',
          modification: script,
        ),
      );
      await _pump(
        tester,
        DishCard(row: row, localeTag: 'en', onShowScript: (_) {}),
      );

      // Act: expand
      await tester.tap(find.text('Ask your waiter'));
      await tester.pump();

      // Assert: constraint 7 (CLAUDE.md) — a modifiable dish always
      // carries script text, and it is now on screen.
      expect(find.byType(WaiterScriptWidget), findsOneWidget);
      expect(find.text(script), findsOneWidget);
      expect(find.text('Hide the waiter script'), findsOneWidget);

      // Act: collapse again
      await tester.tap(find.text('Hide the waiter script'));
      await tester.pump();

      // Assert
      expect(find.byType(WaiterScriptWidget), findsNothing);
      expect(find.text('Ask your waiter'), findsOneWidget);
      // The full-sheet button never depends on the disclosure state.
      expect(find.text('Show the waiter card'), findsOneWidget);
    });

    testWidgets(
      'build always carries non-empty script text for a modifiable row, '
      'even one built with no modification',
      (tester) async {
        // Arrange: AnalysedDish's own invariant (verdict modifiable implies
        // a non-null modification) is enforced by AnalysedDish.tryFrom,
        // not by this plain const constructor — so this deliberately
        // malformed value stands in for a value that reached DishCard some
        // other way, to prove the card's own fallback (constraint 7).
        final row = DishRow(
          dish: _dish(),
          category: 'Mains',
          analysis: const AnalysedDish(
            dishId: 'dish_1',
            name: 'Grilled Salmon',
            verdict: DishVerdict.modifiable,
            why: 'Mostly protein, with a starchy side to swap.',
          ),
        );
        await _pump(
          tester,
          DishCard(row: row, localeTag: 'en', onShowScript: (_) {}),
        );

        // Act
        await tester.tap(find.text('Ask your waiter'));
        await tester.pump();

        // Assert
        final scriptWidget = tester.widget<WaiterScriptWidget>(
          find.byType(WaiterScriptWidget),
        );
        expect(scriptWidget.script, isNotEmpty);
      },
    );

    testWidgets(
      'tapping the waiter card button invokes onShowScript with the row',
      (tester) async {
        // Arrange
        final row = DishRow(
          dish: _dish(),
          category: 'Mains',
          analysis: const AnalysedDish(
            dishId: 'dish_1',
            name: 'Grilled Salmon',
            verdict: DishVerdict.modifiable,
            why: 'Mostly protein, with a starchy side to swap.',
            modification: 'Ask for a side salad instead of fries.',
          ),
        );
        DishRow? shown;

        // Act
        await _pump(
          tester,
          DishCard(
            row: row,
            localeTag: 'en',
            onShowScript: (shownRow) => shown = shownRow,
          ),
        );
        await tester.tap(find.text('Show the waiter card'));
        await tester.pumpAndSettle();

        // Assert
        expect(shown, row);
      },
    );

    testWidgets('build shows no waiter script for a non-keto row', (
      tester,
    ) async {
      // Arrange
      final row = DishRow(
        dish: _dish(),
        category: 'Mains',
        analysis: const AnalysedDish(
          dishId: 'dish_1',
          name: 'Spaghetti Carbonara',
          verdict: DishVerdict.nonKeto,
          why: 'Pasta is a non-keto base.',
        ),
      );

      // Act
      await _pump(
        tester,
        DishCard(row: row, localeTag: 'en', onShowScript: (_) {}),
      );

      // Assert
      expect(find.byType(WaiterScriptWidget), findsNothing);
      expect(find.byType(StatusBadge), findsOneWidget);
      expect(find.text('Show the waiter card'), findsNothing);
    });

    testWidgets(
      'build shows no verdict claim and no script for an unanalysed row',
      (tester) async {
        // Arrange
        final row = DishRow(dish: _dish(), category: 'Mains');

        // Act
        await _pump(
          tester,
          DishCard(row: row, localeTag: 'en', onShowScript: (_) {}),
        );

        // Assert
        expect(find.byType(StatusBadge), findsNothing);
        expect(find.byType(WaiterScriptWidget), findsNothing);
        expect(find.text('Grilled Salmon'), findsOneWidget);
      },
    );

    testWidgets('build shows the dish description when present', (
      tester,
    ) async {
      // Arrange
      final row = DishRow(
        dish: _dish(description: '300g, served with lemon butter'),
        category: 'Mains',
      );

      // Act
      await _pump(
        tester,
        DishCard(row: row, localeTag: 'en', onShowScript: (_) {}),
      );

      // Assert
      expect(find.text('300g, served with lemon butter'), findsOneWidget);
    });

    testWidgets('build hides the net-carb chip when netCarbsEstimate is null', (
      tester,
    ) async {
      // Arrange
      final row = DishRow(
        dish: _dish(),
        category: 'Mains',
        analysis: const AnalysedDish(
          dishId: 'dish_1',
          name: 'Grilled Salmon',
          verdict: DishVerdict.orderAsIs,
          why: 'Plain grilled protein.',
        ),
      );

      // Act
      await _pump(
        tester,
        DishCard(row: row, localeTag: 'en', onShowScript: (_) {}),
      );

      // Assert: architecture.md §17.4 — no netCarbsEstimate, no chip.
      expect(find.textContaining('net carbs'), findsNothing);
    });

    testWidgets(
      'build shows the net-carb chip as an estimate, never a bare number, '
      'when netCarbsEstimate is set',
      (tester) async {
        // Arrange
        final row = DishRow(
          dish: _dish(),
          category: 'Mains',
          analysis: const AnalysedDish(
            dishId: 'dish_1',
            name: 'Grilled Salmon',
            verdict: DishVerdict.orderAsIs,
            why: 'Plain grilled protein.',
            netCarbsEstimate: 6.4,
          ),
        );

        // Act
        await _pump(
          tester,
          DishCard(row: row, localeTag: 'en', onShowScript: (_) {}),
        );

        // Assert: rounded, and framed as an estimate (issue #30 reversing
        // architecture.md §17.4).
        expect(find.text('~6g net carbs (estimate)'), findsOneWidget);
        expect(
          find.bySemanticsLabel('Estimated net carbs, not confirmed: 6 grams'),
          findsOneWidget,
        );
      },
    );

    testWidgets('build paints a green row on VerdictColors.green.tint, per the '
        'artboard verdictStyles table', (tester) async {
      // Arrange
      final row = DishRow(
        dish: _dish(),
        category: 'Mains',
        analysis: const AnalysedDish(
          dishId: 'dish_1',
          name: 'Grilled Salmon',
          verdict: DishVerdict.orderAsIs,
          why: 'Plain grilled protein.',
        ),
      );

      // Act
      await _pump(
        tester,
        DishCard(row: row, localeTag: 'en', onShowScript: (_) {}),
      );
      final decoration =
          tester
                  .widget<DecoratedBox>(find.byType(DecoratedBox).first)
                  .decoration
              as BoxDecoration;
      final tone = VerdictColors.light().green;

      // Assert: the card body is tinted (a uniform border cannot mix a
      // second colour with a BorderRadius, so the card's own edge is
      // painted in the same tint — see dish_card.dart's own note), and the
      // coloured rail is a separate leading strip in [tone.rail].
      expect(decoration.color, tone.tint);
      final rail = tester.widget<ColoredBox>(
        find.byKey(const ValueKey('dishCardRail')),
      );
      expect(rail.color, tone.rail);
    });

    testWidgets('build renders the Hebrew waiter-card label in the he locale', (
      tester,
    ) async {
      // Arrange
      final row = DishRow(
        dish: _dish(),
        category: 'Mains',
        analysis: const AnalysedDish(
          dishId: 'dish_1',
          name: 'Grilled Salmon',
          verdict: DishVerdict.modifiable,
          why: 'Mostly protein, with a starchy side to swap.',
          modification: 'Ask for a side salad instead of fries.',
        ),
      );

      // Act
      await _pump(
        tester,
        DishCard(row: row, localeTag: 'he', onShowScript: (_) {}),
        locale: const Locale('he'),
      );

      // Assert
      expect(find.text('הצג כרטיס למלצר'), findsOneWidget);
    });
  });
}

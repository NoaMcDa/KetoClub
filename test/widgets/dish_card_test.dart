import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/theme/app_theme.dart';
import 'package:ketoclub/theme/verdict_colors.dart';
import 'package:ketoclub/utils/price_format.dart';
import 'package:ketoclub/widgets/dish_card.dart';
import 'package:ketoclub/widgets/status_badge.dart';
import 'package:ketoclub/widgets/waiter_script_widget.dart';

/// Pumps [child] inside a localised [MaterialApp] and a [Scaffold], the
/// shape every widget test in `test/widgets/` uses. [theme] defaults to
/// null, the bare-[MaterialApp] shape most of this file's tests use.
Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Locale locale = const Locale('en'),
  ThemeData? theme,
}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: theme,
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

    for (final entry in {
      'light': AppTheme.light(),
      'dark': AppTheme.dark(),
    }.entries) {
      testWidgets("build paints a non-keto row on the ${entry.key} theme's "
          'NeutralSurfaces surface2/line2, not a Material 3 substitute', (
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
          theme: entry.value,
        );
        final decoration =
            tester
                    .widget<DecoratedBox>(find.byType(DecoratedBox).first)
                    .decoration
                as BoxDecoration;
        final neutral = entry.value.extension<NeutralSurfaces>()!;

        // Assert: the artboard's `--surface2` / `--line2`
        // (`.design/theme-snippet.txt`), not
        // `colorScheme.surfaceContainerHighest` /
        // `colorScheme.outlineVariant`.
        expect(decoration.color, neutral.surface2);
        expect(decoration.border, Border.all(color: neutral.line2));
      });
    }

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

    group('personal notes (issue #52)', () {
      testWidgets(
        'build renders no note affordance when onEditNote is not given',
        (tester) async {
          // Arrange
          final row = DishRow(dish: _dish(), category: 'Mains');

          // Act
          await _pump(
            tester,
            DishCard(row: row, localeTag: 'en', onShowScript: (_) {}),
          );

          // Assert: existing call sites that predate this field compile and
          // render unchanged.
          expect(find.text('Add a note'), findsNothing);
        },
      );

      testWidgets(
        'build shows "Add a note" when onEditNote is given but note is null',
        (tester) async {
          // Arrange
          final row = DishRow(dish: _dish(), category: 'Mains');

          // Act
          await _pump(
            tester,
            DishCard(
              row: row,
              localeTag: 'en',
              onShowScript: (_) {},
              onEditNote: (_) {},
            ),
          );

          // Assert
          expect(find.text('Add a note'), findsOneWidget);
        },
      );

      testWidgets('build shows the note text when one is given', (
        tester,
      ) async {
        // Arrange
        final row = DishRow(dish: _dish(), category: 'Mains');

        // Act
        await _pump(
          tester,
          DishCard(
            row: row,
            localeTag: 'en',
            onShowScript: (_) {},
            note: 'Waitstaff happily substituted cauliflower.',
            onEditNote: (_) {},
          ),
        );

        // Assert
        expect(
          find.text('Waitstaff happily substituted cauliflower.'),
          findsOneWidget,
        );
        expect(find.text('Add a note'), findsNothing);
      });

      testWidgets('tapping the note row calls onEditNote with this row', (
        tester,
      ) async {
        // Arrange
        final row = DishRow(dish: _dish(), category: 'Mains');
        DishRow? tapped;

        // Act
        await _pump(
          tester,
          DishCard(
            row: row,
            localeTag: 'en',
            onShowScript: (_) {},
            onEditNote: (edited) => tapped = edited,
          ),
        );
        await tester.tap(find.text('Add a note'));
        await tester.pump();

        // Assert
        expect(tapped, equals(row));
      });

      testWidgets(
        'build shows the note affordance for a non-keto dish too, unlike '
        'the waiter-script button',
        (tester) async {
          // Arrange: a note is the user's own annotation, not tied to a
          // verdict, so it must not be hidden the way the modifiable-only
          // waiter-script disclosure is.
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
            DishCard(
              row: row,
              localeTag: 'en',
              onShowScript: (_) {},
              note: 'Skip it.',
              onEditNote: (_) {},
            ),
          );

          // Assert
          expect(find.text('Skip it.'), findsOneWidget);
        },
      );
    });
  });
}

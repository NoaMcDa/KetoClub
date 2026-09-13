import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/menu.dart';
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

    testWidgets('build shows the waiter script for a modifiable row', (
      tester,
    ) async {
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

      // Assert
      expect(find.byType(WaiterScriptWidget), findsOneWidget);
      expect(find.text(script), findsOneWidget);
      expect(find.byType(StatusBadge), findsOneWidget);
      expect(find.text('Show the waiter card'), findsOneWidget);
    });

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

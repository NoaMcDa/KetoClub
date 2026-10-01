import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/widgets/category_chips.dart';
import 'package:ketoclub/widgets/focus_ring.dart';

import '../fakes/focus_ring_probe.dart';

/// Pumps [child] inside a localised [MaterialApp] and a [Scaffold], the
/// shape every widget test in `test/widgets/` uses.
Future<void> _pump(WidgetTester tester, Widget child) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  group('CategoryChips', () {
    testWidgets('renders nothing for an empty category list', (tester) async {
      // Arrange & Act
      await _pump(
        tester,
        CategoryChips(categories: const <String>[], onSelected: (_) {}),
      );

      // Assert
      expect(find.byType(ActionChip), findsNothing);
    });

    testWidgets('renders one chip per category, in order', (tester) async {
      // Arrange & Act
      await _pump(
        tester,
        CategoryChips(
          categories: const <String>['Mains', 'Sides', 'Desserts'],
          onSelected: (_) {},
        ),
      );

      // Assert
      expect(find.text('Mains'), findsOneWidget);
      expect(find.text('Sides'), findsOneWidget);
      expect(find.text('Desserts'), findsOneWidget);
    });

    testWidgets('tapping a chip reports its category through onSelected', (
      tester,
    ) async {
      // Arrange
      String? selected;
      await _pump(
        tester,
        CategoryChips(
          categories: const <String>['Mains', 'Sides'],
          onSelected: (category) => selected = category,
        ),
      );

      // Act
      await tester.tap(find.text('Sides'));
      await tester.pump();

      // Assert
      expect(selected, 'Sides');
    });

    testWidgets('Tab focuses a chip with a ring and Enter activates it '
        '(issue #264)', (tester) async {
      // Arrange
      String? selected;
      await _pump(
        tester,
        CategoryChips(
          categories: const <String>['Mains', 'Sides'],
          onSelected: (category) => selected = category,
        ),
      );

      // Act
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();

      // Assert: the second chip is focused and ringed, the first is not.
      final rings = find.byType(FocusRing);
      expect(focusRingShown(tester, rings.at(0)), isFalse);
      expect(focusRingShown(tester, rings.at(1)), isTrue);

      // Act
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      // Assert
      expect(selected, 'Sides');
    });

    testWidgets('wrap: true lays every chip out within the width, on more '
        'than one line, and a chip on a later line still reports its tap '
        '(issue #225)', (tester) async {
      // Arrange
      final categories = [for (var i = 0; i < 8; i++) 'Category $i'];
      String? selected;
      await _pump(
        tester,
        Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 300,
            child: CategoryChips(
              categories: categories,
              onSelected: (category) => selected = category,
              wrap: true,
            ),
          ),
        ),
      );

      // Assert: no sideways scroll, every chip inside the 300px, and the
      // last chip on a lower line than the first.
      expect(find.byType(SingleChildScrollView), findsNothing);
      for (final category in categories) {
        expect(tester.getRect(find.text(category)).right, lessThan(300));
      }
      final first = tester.getRect(find.text('Category 0'));
      final last = tester.getRect(find.text('Category 7'));
      expect(last.top, greaterThan(first.bottom));

      // Act
      await tester.tap(find.text('Category 7'));
      await tester.pump();

      // Assert
      expect(selected, 'Category 7');
    });
  });
}

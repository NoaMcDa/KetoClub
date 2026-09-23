import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/widgets/category_chips.dart';

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
  });
}

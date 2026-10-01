// Tests for the shared net-carb chip (issue #259).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/theme/verdict_colors.dart';
import 'package:ketoclub/widgets/net_carbs_chip.dart';

void main() {
  final colors = VerdictColors.light();

  group('NetCarbsChip', () {
    testWidgets('shows its label in the tone ink on its background and '
        'announces the semantic label instead', (tester) async {
      // Arrange
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          home: NetCarbsChip(
            label: '0–1 g',
            semanticLabel: 'about zero grams',
            tone: colors.amber,
            background: colors.amber.tint,
          ),
        ),
      );

      // Assert
      final text = tester.widget<Text>(find.text('0–1 g'));
      expect(text.style?.color, colors.amber.ink);
      final box = tester.widget<DecoratedBox>(find.byType(DecoratedBox));
      expect((box.decoration as BoxDecoration).color, colors.amber.tint);
      expect(find.bySemanticsLabel('about zero grams'), findsOneWidget);
      expect(find.bySemanticsLabel('0–1 g'), findsNothing);
      expect(find.byType(InkWell), findsNothing);
      handle.dispose();
    });
  });

  group('netCarbsChipBackground', () {
    final theme = ThemeData();

    test('green sits on the card surface', () {
      expect(
        netCarbsChipBackground(theme, DishVerdict.orderAsIs, colors.green),
        theme.cardColor,
      );
    });

    test('amber and red use their own tint', () {
      expect(
        netCarbsChipBackground(theme, DishVerdict.modifiable, colors.amber),
        colors.amber.tint,
      );
      expect(
        netCarbsChipBackground(theme, DishVerdict.nonKeto, colors.red),
        colors.red.tint,
      );
    });
  });
}

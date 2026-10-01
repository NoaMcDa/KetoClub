import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/widgets/focus_ring.dart';

import '../fakes/focus_ring_probe.dart';

/// Pumps one [FocusRing] around a button, beside a second plain button.
Future<void> _pump(WidgetTester tester) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            FocusRing(
              borderRadius: BorderRadius.circular(8),
              child: TextButton(onPressed: () {}, child: const Text('ringed')),
            ),
            TextButton(onPressed: () {}, child: const Text('plain')),
          ],
        ),
      ),
    ),
  );
}

void main() {
  group('FocusRing', () {
    testWidgets('draws no ring before anything is focused', (tester) async {
      // Arrange & Act
      await _pump(tester);

      // Assert
      expect(focusRingShown(tester, find.byType(Column)), isFalse);
    });

    testWidgets('draws a ring while a key-driven focus is inside it', (
      tester,
    ) async {
      // Arrange
      await _pump(tester);

      // Act
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();

      // Assert
      expect(focusRingShown(tester, find.byType(Column)), isTrue);
    });

    testWidgets('drops the ring once focus moves on', (tester) async {
      // Arrange
      await _pump(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();

      // Act
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();

      // Assert
      expect(focusRingShown(tester, find.byType(Column)), isFalse);
    });

    testWidgets('never takes a tab stop of its own', (tester) async {
      // Arrange
      await _pump(tester);

      // Act: one Tab lands on the button inside, not on the ring.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();

      // Assert
      final focus = FocusManager.instance.primaryFocus!;
      expect(
        find.descendant(
          of: find.byType(FocusRing),
          matching: find.byType(TextButton),
        ),
        findsOneWidget,
      );
      expect(
        focus.context!.findAncestorWidgetOfExactType<FocusRing>(),
        isNotNull,
      );
    });
  });
}

// Unit tests for [CarbBudgetController] (issue #215, architecture.md §6.6).
//
// Covers set/clear/clamp, notification behaviour, and the guarantee that
// no I/O or persistence is ever involved.

import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/state/carb_budget_controller.dart';

void main() {
  group('CarbBudgetController', () {
    late CarbBudgetController controller;

    setUp(() {
      controller = CarbBudgetController();
    });

    tearDown(() {
      controller.dispose();
    });

    test('budgetGrams is null before any call', () {
      expect(controller.budgetGrams, isNull);
    });

    test('hasBudget is false before any call', () {
      expect(controller.hasBudget, isFalse);
    });

    test('setBudget stores the value and sets hasBudget true', () {
      controller.setBudget(20);

      expect(controller.budgetGrams, equals(20));
      expect(controller.hasBudget, isTrue);
    });

    test('setBudget clamps values below 1 to 1', () {
      controller.setBudget(0);

      expect(controller.budgetGrams, equals(1));
    });

    test('setBudget clamps values above 150 to 150', () {
      controller.setBudget(200);

      expect(controller.budgetGrams, equals(150));
    });

    test('setBudget notifies listeners when the value changes', () {
      var notified = 0;
      controller
        ..addListener(() => notified++)
        ..setBudget(30);

      expect(notified, equals(1));
    });

    test('setBudget does not notify when the clamped value is unchanged', () {
      var notified = 0;
      controller
        ..setBudget(20)
        ..addListener(() => notified++)
        ..setBudget(20);

      expect(notified, isZero);
    });

    test('clear resets budgetGrams to null and clears hasBudget', () {
      controller
        ..setBudget(15)
        ..clear();

      expect(controller.budgetGrams, isNull);
      expect(controller.hasBudget, isFalse);
    });

    test('clear notifies listeners when a budget was set', () {
      var notified = 0;
      controller
        ..setBudget(10)
        ..addListener(() => notified++)
        ..clear();

      expect(notified, equals(1));
    });

    test('clear does not notify when no budget was set', () {
      var notified = 0;
      controller
        ..addListener(() => notified++)
        ..clear();

      expect(notified, isZero);
    });
  });
}

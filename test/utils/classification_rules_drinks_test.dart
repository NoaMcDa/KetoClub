// Table-driven tests for the drink vocabulary added in issue #216.
//
// Part A of #216 adds sugary drinks as non-keto bases (red) and coffee/tonic
// drinks as carb-modifier triggers (yellow with swap scripts), plus guards
// that rescue zero/diet variants.  These tests pin that behaviour; the
// existing classification_rules_test.dart's table-driven sweeps over every
// trigger already cover each new entry's basic match, so the cases here are
// focused on the guard interaction and the bilingual scripts.

import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/utils/classification_rules.dart';

void main() {
  group('ClassificationRules.match — drink bases (red, #216)', () {
    // -------------------------------------------------------------------------
    // English red bases
    // -------------------------------------------------------------------------

    test('Coca-Cola is red (sugary cola base)', () {
      // Act
      final result = ClassificationRules.match('Coca-Cola');
      // Assert
      expect(result.isNonKeto, isTrue);
    });

    test('Beer is red (sugary beer base)', () {
      // Act
      final result = ClassificationRules.match('Beer');
      // Assert
      expect(result.isNonKeto, isTrue);
    });

    // -------------------------------------------------------------------------
    // English drink guards
    // -------------------------------------------------------------------------

    test('Coca-Cola Zero is NOT red (zero guard rescues cola)', () {
      // Act
      final result = ClassificationRules.match('Coca-Cola Zero');
      // Assert — guard fires; cola is not flagged
      expect(result.isNonKeto, isFalse);
    });

    test('Diet Sprite is NOT red (diet guard rescues sprite)', () {
      // Act
      final result = ClassificationRules.match('Diet Sprite');
      // Assert
      expect(result.isNonKeto, isFalse);
    });

    // -------------------------------------------------------------------------
    // English yellow drink triggers (carb modifiers) with scripts
    // -------------------------------------------------------------------------

    test('Latte is yellow (carb-modifier trigger)', () {
      // Act
      final result = ClassificationRules.match('Latte');
      // Assert
      expect(result.isNonKeto, isFalse);
      expect(result.instructions, isNotEmpty);
    });

    test('Latte instruction mentions almond milk or black coffee', () {
      // Act
      final result = ClassificationRules.match('Latte');
      // Assert — the script must suggest a keto swap
      expect(
        result.instructions.join(' '),
        allOf(contains('almond milk'), contains('black coffee')),
      );
    });

    test('Iced coffee is yellow with a swap script', () {
      // Act
      final result = ClassificationRules.match('Iced coffee with oat milk');
      // Assert
      expect(result.isNonKeto, isFalse);
      expect(result.instructions, isNotEmpty);
    });

    test('Tonic water is yellow (tonic trigger matches)', () {
      // Act
      final result = ClassificationRules.match('Gin and tonic water');
      // Assert
      expect(result.isNonKeto, isFalse);
      expect(result.instructions.join(' '), contains('soda water'));
    });

    test('Diet tonic is NOT yellow (diet guard rescues tonic)', () {
      // Act
      final result = ClassificationRules.match('Diet tonic');
      // Assert — guard fires; tonic not flagged as carb-modifier
      expect(result.instructions, isEmpty);
      expect(result.isNonKeto, isFalse);
    });

    // -------------------------------------------------------------------------
    // Hebrew red bases
    // -------------------------------------------------------------------------

    test('פריגת תפוזים is red (Prigat juice brand, Hebrew)', () {
      // Act — compound name; bare פריגת fires the trigger
      final result = ClassificationRules.match('פריגת תפוזים');
      // Assert
      expect(result.isNonKeto, isTrue);
    });

    test('בירה שחורה is red (dark beer, Hebrew)', () {
      // Act
      final result = ClassificationRules.match('בירה שחורה');
      // Assert
      expect(result.isNonKeto, isTrue);
    });

    // -------------------------------------------------------------------------
    // Hebrew yellow drink triggers (carb modifiers)
    // -------------------------------------------------------------------------

    test('הפוך is yellow with a swap script (Israeli upside-down latte)', () {
      // Act — bare word, no prefix
      final result = ClassificationRules.match('הפוך');
      // Assert
      expect(result.isNonKeto, isFalse);
      expect(result.instructions, isNotEmpty);
      // The script must mention almond milk (חלב שקדים)
      expect(result.instructions.join(' '), contains('חלב שקדים'));
    });

    test(
      'להפוך (to-flip idiom) is NOT yellow — הפוך has no permissive prefix',
      () {
        // Act — grammatical prefixed form that means "to flip/reverse"
        final result = ClassificationRules.match('אי אפשר להפוך את זה');
        // Assert — strict match prevents false-yellow on the idiom
        expect(result.instructions, isEmpty);
        expect(result.isNonKeto, isFalse);
      },
    );

    test('קוקה קולה זירו is NOT red (זירו guard rescues קולה, Hebrew)', () {
      // Act
      final result = ClassificationRules.match('קוקה קולה זירו');
      // Assert — drink guard fires
      expect(result.isNonKeto, isFalse);
    });
  });
}

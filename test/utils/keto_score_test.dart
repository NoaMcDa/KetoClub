import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/utils/keto_score.dart';

void main() {
  group('ketoScore', () {
    test('is null when green, yellow and red are all zero', () {
      // Act
      final score = ketoScore(
        greenCount: 0,
        hiddenCarbYellowCount: 0,
        otherYellowCount: 0,
        redCount: 0,
      );
      // Assert
      expect(score, isNull);
    });

    test('is 10.0 for an all-green menu', () {
      // Act
      final score = ketoScore(
        greenCount: 4,
        hiddenCarbYellowCount: 0,
        otherYellowCount: 0,
        redCount: 0,
      );
      // Assert
      expect(score, equals(10.0));
    });

    test('is 0.0 for an all-red menu', () {
      // Act
      final score = ketoScore(
        greenCount: 0,
        hiddenCarbYellowCount: 0,
        otherYellowCount: 0,
        redCount: 4,
      );
      // Assert
      expect(score, equals(0.0));
    });

    test('weighs a regular yellow dish at half a green one', () {
      // Arrange: one green, one yellow (no hidden-carb flag), no red.
      // score = 10 * (1 + 0.5 * 1) / 2 = 7.5
      // Act
      final score = ketoScore(
        greenCount: 1,
        hiddenCarbYellowCount: 0,
        otherYellowCount: 1,
        redCount: 0,
      );
      // Assert
      expect(score, equals(7.5));
    });

    test('a red dish enlarges the denominator without adding to the '
        'numerator', () {
      // score = 10 * (1 + 0) / 2 = 5.0
      // Act
      final score = ketoScore(
        greenCount: 1,
        hiddenCarbYellowCount: 0,
        otherYellowCount: 0,
        redCount: 1,
      );
      // Assert
      expect(score, equals(5.0));
    });

    test('rounds to one decimal place', () {
      // score = 10 * 1 / 3 = 3.3333...
      // Act
      final score = ketoScore(
        greenCount: 1,
        hiddenCarbYellowCount: 0,
        otherYellowCount: 0,
        redCount: 2,
      );
      // Assert
      expect(score, equals(3.3));
    });

    test('weighs a hidden-carb-demoted yellow at 0.25 of a green', () {
      // Arrange: 1 green + 1 hidden-carb yellow, no red.
      // score = 10 * (1 + 0.25 * 1) / 2 = 6.25 → 6.3 (issue #213)
      // Act
      final score = ketoScore(
        greenCount: 1,
        hiddenCarbYellowCount: 1,
        otherYellowCount: 0,
        redCount: 0,
      );
      // Assert — 6.25 rounds to 6.3 at one decimal place
      expect(score, equals(6.3));
    });

    test('hidden-carb yellow and regular yellow combine correctly', () {
      // Arrange: 1 green, 1 hidden-carb yellow, 1 regular yellow, no red.
      // numerator = 1 + 0.25 + 0.5 = 1.75; denominator = 3
      // score = 10 * 1.75 / 3 = 5.833... → 5.8
      // Act
      final score = ketoScore(
        greenCount: 1,
        hiddenCarbYellowCount: 1,
        otherYellowCount: 1,
        redCount: 0,
      );
      // Assert
      expect(score, equals(5.8));
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/utils/keto_score.dart';

void main() {
  group('ketoScore', () {
    test('is null when green, yellow and red are all zero', () {
      // Act
      final score = ketoScore(greenCount: 0, yellowCount: 0, redCount: 0);
      // Assert
      expect(score, isNull);
    });

    test('is 10.0 for an all-green menu', () {
      // Act
      final score = ketoScore(greenCount: 4, yellowCount: 0, redCount: 0);
      // Assert
      expect(score, equals(10.0));
    });

    test('is 0.0 for an all-red menu', () {
      // Act
      final score = ketoScore(greenCount: 0, yellowCount: 0, redCount: 4);
      // Assert
      expect(score, equals(0.0));
    });

    test('weighs a yellow dish at half a green one', () {
      // Arrange: one green, one yellow, no red — a yellow dish should
      // count for half the numerator of a green one.
      // score = 10 * (1 + 0.5 * 1) / 2 = 7.5
      // Act
      final score = ketoScore(greenCount: 1, yellowCount: 1, redCount: 0);
      // Assert
      expect(score, equals(7.5));
    });

    test('a red dish enlarges the denominator without adding to the '
        'numerator', () {
      // score = 10 * (1 + 0) / 2 = 5.0
      // Act
      final score = ketoScore(greenCount: 1, yellowCount: 0, redCount: 1);
      // Assert
      expect(score, equals(5.0));
    });

    test('rounds to one decimal place', () {
      // score = 10 * 1 / 3 = 3.3333...
      // Act
      final score = ketoScore(greenCount: 1, yellowCount: 0, redCount: 2);
      // Assert
      expect(score, equals(3.3));
    });
  });
}

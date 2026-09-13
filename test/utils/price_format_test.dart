import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/utils/price_format.dart';

void main() {
  group('formatPrice', () {
    test('formatPrice for en places the shekel symbol before the amount', () {
      // Act
      final result = formatPrice(64, localeTag: 'en');
      // Assert
      expect(result, startsWith('₪'));
      expect(result, contains('64.00'));
    });

    test('formatPrice for he places the shekel symbol after the amount', () {
      // Act
      final result = formatPrice(64, localeTag: 'he');
      // Assert
      expect(result, endsWith('₪'));
      expect(result, contains('64.00'));
    });

    test('formatPrice formats zero with two decimal places', () {
      // Act
      final result = formatPrice(0, localeTag: 'en');
      // Assert
      expect(result, equals('₪0.00'));
    });

    test('formatPrice formats a fractional amount to two decimals', () {
      // Act
      final result = formatPrice(12.5, localeTag: 'en');
      // Assert
      expect(result, equals('₪12.50'));
    });

    test('formatPrice defaults to ILS when currency is omitted', () {
      // Act
      final withDefault = formatPrice(64, localeTag: 'en');
      final withExplicitIls = formatPrice(
        64,
        localeTag: 'en',
        // Deliberately explicit: this test's whole point is to prove the
        // default equals 'ILS'.
        // ignore: avoid_redundant_argument_values
        currency: 'ILS',
      );
      // Assert
      expect(withDefault, equals(withExplicitIls));
    });

    test('formatPrice honours an explicit non-default currency', () {
      // Act
      final result = formatPrice(64, localeTag: 'en', currency: 'USD');
      // Assert
      expect(result, contains(r'$'));
      expect(result, contains('64.00'));
    });
  });
}

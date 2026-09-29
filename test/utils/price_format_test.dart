import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/utils/price_format.dart';

void main() {
  group('formatPrice', () {
    test('formatPrice for en places the shekel symbol before the amount', () {
      // Act
      final result = formatPrice(64, localeTag: 'en');
      // Assert
      expect(result, startsWith('₪'));
      expect(result, contains('64'));
      // Issue #169: whole-shekel amounts render without .00.
      expect(result, isNot(contains('.00')));
    });

    test('formatPrice for he places the shekel symbol after the amount', () {
      // Act
      final result = formatPrice(64, localeTag: 'he');
      // Assert
      expect(result, endsWith('₪'));
      expect(result, contains('64'));
      expect(result, isNot(contains('.00')));
    });

    test('formatPrice omits decimals for a zero amount (whole)', () {
      // Act
      final result = formatPrice(0, localeTag: 'en');
      // Assert: issue #169 — no bare .00 on a whole-shekel price.
      expect(result, equals('₪0'));
    });

    test('formatPrice formats a fractional amount to two decimals', () {
      // Act
      final result = formatPrice(12.5, localeTag: 'en');
      // Assert
      expect(result, equals('₪12.50'));
    });

    test('formatPrice omits decimals for a whole en amount', () {
      // Act
      final result = formatPrice(38, localeTag: 'en');
      // Assert
      expect(result, equals('₪38'));
    });

    test('formatPrice omits decimals for a whole he amount', () {
      // Act
      final result = formatPrice(38, localeTag: 'he');
      // Assert: order of glyphs varies in RTL, but the ₪ and 38 must be
      // present without any `.00`.
      expect(result, contains('38'));
      expect(result, contains('₪'));
      expect(result, isNot(contains('.00')));
    });

    test('formatPrice keeps decimals for a fractional he amount', () {
      // Act
      final result = formatPrice(12.5, localeTag: 'he');
      // Assert
      expect(result, contains('12.50'));
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
      expect(result, contains('64'));
      // Whole-number amounts omit decimals for USD too (issue #169).
      expect(result, isNot(contains('.00')));
    });

    test(
      'formatPrice keeps decimals for a fractional non-default currency',
      () {
        // Act
        final result = formatPrice(12.5, localeTag: 'en', currency: 'USD');
        // Assert
        expect(result, contains(r'$'));
        expect(result, contains('12.50'));
      },
    );
  });
}

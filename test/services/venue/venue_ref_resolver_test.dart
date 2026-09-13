import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/venue/venue_ref_resolver.dart';

/// One accepted-input case: [input] must resolve to [expected].
class _Accepted {
  const new(this.description, this.input, this.expected);

  final String description;
  final String input;
  final VenueRef expected;
}

/// One rejected-input case: [input] must resolve to null.
class _Rejected {
  const new(this.description, this.input);

  final String description;
  final String input;
}

const _accepted = <_Accepted>[
  _Accepted(
    'a full Wolt venue URL',
    'https://wolt.com/en/isr/tel-aviv/restaurant/vitrina-lilinblum',
    VenueRef(source: MenuSource.wolt, platformId: 'vitrina-lilinblum'),
  ),
  _Accepted(
    'a Wolt venue URL with a different locale segment',
    'https://wolt.com/he/isr/tel-aviv/restaurant/vitrina-lilinblum',
    VenueRef(source: MenuSource.wolt, platformId: 'vitrina-lilinblum'),
  ),
  _Accepted(
    'a Wolt venue URL with a query string',
    'https://wolt.com/en/isr/tel-aviv/restaurant/vitrina-lilinblum?utm=x',
    VenueRef(source: MenuSource.wolt, platformId: 'vitrina-lilinblum'),
  ),
  _Accepted(
    'a Wolt venue URL with a fragment',
    'https://wolt.com/en/isr/tel-aviv/restaurant/vitrina-lilinblum#menu',
    VenueRef(source: MenuSource.wolt, platformId: 'vitrina-lilinblum'),
  ),
  _Accepted(
    'a scheme-less Wolt venue URL',
    'wolt.com/en/isr/tel-aviv/restaurant/vitrina-lilinblum',
    VenueRef(source: MenuSource.wolt, platformId: 'vitrina-lilinblum'),
  ),
  _Accepted(
    'a Wolt venue URL on a subdomain',
    'https://www.wolt.com/en/isr/tel-aviv/restaurant/vitrina-lilinblum',
    VenueRef(source: MenuSource.wolt, platformId: 'vitrina-lilinblum'),
  ),
  _Accepted(
    'a bare Wolt slug',
    'vitrina-lilinblum',
    VenueRef(source: MenuSource.wolt, platformId: 'vitrina-lilinblum'),
  ),
  _Accepted(
    'a bare Wolt slug with surrounding whitespace',
    '  vitrina-lilinblum  ',
    VenueRef(source: MenuSource.wolt, platformId: 'vitrina-lilinblum'),
  ),
  _Accepted(
    'a bare 10bis restaurant id',
    '123456',
    VenueRef(source: MenuSource.tenbis, platformId: '123456'),
  ),
];

const _rejected = <_Rejected>[
  _Rejected('empty input', ''),
  _Rejected('whitespace-only input', '   '),
  _Rejected(
    'a URL on an unrelated host',
    'https://example.com/restaurant/vitrina-lilinblum',
  ),
  _Rejected(
    'a wolt.com URL with no restaurant segment',
    'https://wolt.com/en/isr/tel-aviv',
  ),
  _Rejected(
    'a wolt.com URL whose restaurant segment has no slug after it',
    'https://wolt.com/en/isr/tel-aviv/restaurant/',
  ),
];

void main() {
  group('VenueRefResolver', () {
    for (final case_ in _accepted) {
      test('resolve accepts ${case_.description}', () {
        // Act
        final result = VenueRefResolver.resolve(case_.input);

        // Assert
        expect(result, equals(case_.expected));
      });
    }

    for (final case_ in _rejected) {
      test('resolve rejects ${case_.description}', () {
        // Act
        final result = VenueRefResolver.resolve(case_.input);

        // Assert
        expect(result, isNull);
      });
    }

    test('resolve treats digits-only input as a 10bis id, never a slug', () {
      // Act
      final result = VenueRefResolver.resolve('000123');

      // Assert
      expect(
        result,
        equals(const VenueRef(source: MenuSource.tenbis, platformId: '000123')),
      );
    });

    test('resolve is pure: the same input always resolves the same way', () {
      // Arrange
      const input =
          'https://wolt.com/en/isr/tel-aviv/restaurant/vitrina-lilinblum';

      // Act
      final first = VenueRefResolver.resolve(input);
      final second = VenueRefResolver.resolve(input);

      // Assert
      expect(first, equals(second));
    });
  });
}

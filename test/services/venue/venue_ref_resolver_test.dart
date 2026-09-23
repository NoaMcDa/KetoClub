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
  _Accepted(
    'a 10bis restaurant URL with www and mixed-case segments',
    'https://www.10bis.co.il/Restaurants/Menu/123456',
    VenueRef(source: MenuSource.tenbis, platformId: '123456'),
  ),
  _Accepted(
    'a 10bis restaurant URL with menu/delivery/slug segments after the id',
    'https://10bis.co.il/next/restaurants/menu/delivery/123456/pizza-hut',
    VenueRef(source: MenuSource.tenbis, platformId: '123456'),
  ),
  _Accepted(
    'a scheme-less 10bis restaurant URL',
    '10bis.co.il/Restaurants/123456',
    VenueRef(source: MenuSource.tenbis, platformId: '123456'),
  ),
  _Accepted(
    'a 10bis restaurant URL with a query string',
    'https://www.10bis.co.il/Restaurants/Menu/123456?utm=x',
    VenueRef(source: MenuSource.tenbis, platformId: '123456'),
  ),
  _Accepted(
    'a 10bis restaurant URL with a trailing slash',
    'https://www.10bis.co.il/Restaurants/Menu/123456/',
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
  _Rejected(
    'a lookalike wolt host with wolt.com as a prefix, not the domain',
    'https://wolt.com.evil.com/en/isr/tel-aviv/restaurant/vitrina-lilinblum',
  ),
  _Rejected(
    'a 10bis URL with no numeric id anywhere in the path',
    'https://www.10bis.co.il/Restaurants/Menu/',
  ),
  _Rejected(
    'a 10bis URL whose id segment is non-numeric',
    'https://www.10bis.co.il/Restaurants/Menu/abc123',
  ),
  _Rejected(
    'a lookalike 10bis host with 10bis.co.il as a prefix, not the domain',
    'https://10bis.co.il.evil.com/Restaurants/Menu/123456',
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

  group('VenueRefResolver.platformUrl (issue #53)', () {
    test('returns the Wolt venue page for a Wolt ref', () {
      // Arrange
      const ref = VenueRef(
        source: MenuSource.wolt,
        platformId: 'vitrina-lilinblum',
      );

      // Act
      final url = VenueRefResolver.platformUrl(ref);

      // Assert
      expect(
        url,
        equals(
          Uri.parse(
            'https://wolt.com/en/isr/tel-aviv/restaurant/vitrina-lilinblum',
          ),
        ),
      );
    });

    test('returns the 10bis venue page for a 10bis ref', () {
      // Arrange
      const ref = VenueRef(source: MenuSource.tenbis, platformId: '123456');

      // Act
      final url = VenueRefResolver.platformUrl(ref);

      // Assert
      expect(
        url,
        equals(
          Uri.parse(
            'https://www.10bis.co.il/next/restaurants/menu/delivery/123456',
          ),
        ),
      );
    });

    test('returns null for Tabit and Ontopo, which have no known URL form '
        'yet', () {
      for (final source in [MenuSource.tabit, MenuSource.ontopo]) {
        // Act
        final url = VenueRefResolver.platformUrl(
          VenueRef(source: source, platformId: 'anything'),
        );

        // Assert
        expect(url, isNull);
      }
    });

    test('round-trips through resolve for a Wolt ref: platformUrl then '
        'resolve gives back an equal ref', () {
      // Arrange
      const ref = VenueRef(
        source: MenuSource.wolt,
        platformId: 'vitrina-lilinblum',
      );

      // Act
      final url = VenueRefResolver.platformUrl(ref);
      final roundTripped = VenueRefResolver.resolve(url!.toString());

      // Assert
      expect(roundTripped, equals(ref));
    });

    test('round-trips through resolve for a 10bis ref: platformUrl then '
        'resolve gives back an equal ref', () {
      // Arrange
      const ref = VenueRef(source: MenuSource.tenbis, platformId: '123456');

      // Act
      final url = VenueRefResolver.platformUrl(ref);
      final roundTripped = VenueRefResolver.resolve(url!.toString());

      // Assert
      expect(roundTripped, equals(ref));
    });
  });
}

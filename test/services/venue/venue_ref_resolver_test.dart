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
  // Issue #181 (D19): any other http(s) URL is a restaurant's own site.
  _Accepted(
    'a restaurant homepage URL, as a website',
    'https://cafe-noir.co.il/',
    VenueRef(source: MenuSource.website, platformId: 'https://cafe-noir.co.il'),
  ),
  _Accepted(
    'a URL on an unrelated host, as a website with its path kept',
    'https://example.com/restaurant/vitrina-lilinblum',
    VenueRef(
      source: MenuSource.website,
      platformId: 'https://example.com/restaurant/vitrina-lilinblum',
    ),
  ),
  _Accepted(
    'a website URL with upper case, a fragment and a query, normalised',
    'HTTPS://Cafe-Noir.CO.IL/Menu/?lang=he#dinner',
    VenueRef(
      source: MenuSource.website,
      platformId: 'https://cafe-noir.co.il/Menu?lang=he',
    ),
  ),
  _Accepted(
    'a scheme-less website URL with a path',
    'cafe-noir.co.il/menu',
    VenueRef(
      source: MenuSource.website,
      platformId: 'https://cafe-noir.co.il/menu',
    ),
  ),
  _Accepted(
    'a plain http website keeps its scheme and a non-default port',
    'http://cafe-noir.co.il:8080/menu',
    VenueRef(
      source: MenuSource.website,
      platformId: 'http://cafe-noir.co.il:8080/menu',
    ),
  ),
  _Accepted(
    "a lookalike wolt host, which is someone else's website",
    'https://wolt.com.evil.com/en/isr/tel-aviv/restaurant/vitrina-lilinblum',
    VenueRef(
      source: MenuSource.website,
      platformId:
          'https://wolt.com.evil.com/en/isr/tel-aviv/restaurant/'
          'vitrina-lilinblum',
    ),
  ),
  _Accepted(
    "a lookalike 10bis host, which is someone else's website",
    'https://10bis.co.il.evil.com/Restaurants/Menu/123456',
    VenueRef(
      source: MenuSource.website,
      platformId: 'https://10bis.co.il.evil.com/Restaurants/Menu/123456',
    ),
  ),
];

const _rejected = <_Rejected>[
  _Rejected('empty input', ''),
  _Rejected('whitespace-only input', '   '),
  _Rejected('an ftp URL', 'ftp://cafe-noir.co.il/menu.pdf'),
  _Rejected('a URL whose host has no dot', 'http://localhost/menu'),
  _Rejected('a URL carrying user info', 'https://me:pw@cafe-noir.co.il/'),
  _Rejected('a mailto link', 'mailto:owner@cafe-noir.co.il'),
  _Rejected(
    'a wolt.com URL with no restaurant segment',
    'https://wolt.com/en/isr/tel-aviv',
  ),
  _Rejected(
    'a wolt.com URL whose restaurant segment has no slug after it',
    'https://wolt.com/en/isr/tel-aviv/restaurant/',
  ),
  _Rejected(
    'a 10bis URL with no numeric id anywhere in the path',
    'https://www.10bis.co.il/Restaurants/Menu/',
  ),
  _Rejected(
    'a 10bis URL whose id segment is non-numeric',
    'https://www.10bis.co.il/Restaurants/Menu/abc123',
  ),
  // Issue #169: a bare English word without a hyphen used to resolve as
  // a Wolt slug and be offered "Show the keto menu"; it now reads as
  // unrecognised so the user has to paste a real link or a hyphenated
  // slug.
  _Rejected('a bare English word (no hyphen)', 'pizza'),
  _Rejected('a bare Hebrew-looking word (no hyphen)', 'vitrina'),
  _Rejected('a two-character bare token', 'ab'),
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

    test("returns a website ref's own URL, which round-trips", () {
      // Arrange
      final ref = VenueRefResolver.resolve(
        'https://cafe-noir.co.il/%D7%AA%D7%A4%D7%A8%D7%99%D7%98?x=1',
      );

      // Act
      final url = VenueRefResolver.platformUrl(ref!);

      // Assert
      expect(ref.source, MenuSource.website);
      expect(url.toString(), ref.platformId);
      expect(VenueRefResolver.resolve(url.toString()), equals(ref));
    });

    test('returns null for Tabit, Ontopo and a scan, which have no known '
        'URL form', () {
      for (final source in [
        MenuSource.tabit,
        MenuSource.ontopo,
        MenuSource.scan,
      ]) {
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

  group('VenueRefResolver.websiteHost (D19)', () {
    test('is the host of a website ref', () {
      const ref = VenueRef(
        source: MenuSource.website,
        platformId: 'https://cafe-noir.co.il/menu',
      );
      expect(VenueRefResolver.websiteHost(ref), 'cafe-noir.co.il');
    });

    test('is null for any other source, or an id with no host', () {
      expect(
        VenueRefResolver.websiteHost(
          const VenueRef(source: MenuSource.wolt, platformId: 'a-b'),
        ),
        isNull,
      );
      expect(
        VenueRefResolver.websiteHost(
          const VenueRef(source: MenuSource.website, platformId: 'nothing'),
        ),
        isNull,
      );
    });
  });

  group('VenueRefResolver.parseUrl (issue #182)', () {
    test('reads a scheme-qualified URL', () {
      expect(
        VenueRefResolver.parseUrl('https://cafe.co.il/menu')?.host,
        'cafe.co.il',
      );
    });

    test('reads a scheme-less domain and path as https', () {
      expect(VenueRefResolver.parseUrl('cafe.co.il/menu')?.scheme, 'https');
    });

    test('trims surrounding whitespace', () {
      expect(
        VenueRefResolver.parseUrl('  https://cafe.co.il/menu\n')?.host,
        'cafe.co.il',
      );
    });

    test('is null for a bare token, plain text and blank input', () {
      for (final input in <String>['', '   ', 'vitrina-lilinblum', '123456']) {
        expect(VenueRefResolver.parseUrl(input), isNull, reason: input);
      }
      expect(VenueRefResolver.parseUrl('Table 12'), isNull);
    });
  });

  group('VenueRefResolver.normaliseWebsiteUrl (D19)', () {
    test('rejects a host that starts or ends with a dot', () {
      expect(
        VenueRefResolver.normaliseWebsiteUrl(Uri.parse('https://.co.il/')),
        isNull,
      );
      expect(
        VenueRefResolver.normaliseWebsiteUrl(Uri.parse('https://cafe.il./')),
        isNull,
      );
    });

    test('the same page pasted twice normalises the same', () {
      expect(
        VenueRefResolver.normaliseWebsiteUrl(
          Uri.parse('https://cafe.co.il:443/menu/'),
        ),
        VenueRefResolver.normaliseWebsiteUrl(
          Uri.parse('https://CAFE.co.il/menu#top'),
        ),
      );
    });
  });
}

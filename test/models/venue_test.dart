import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/venue.dart';

void main() {
  group('MenuSource', () {
    test('tryParse returns the source whose name matches the wire value', () {
      // Arrange
      const wire = 'wolt';

      // Act
      final result = MenuSource.tryParse(wire);

      // Assert
      expect(result, equals(MenuSource.wolt));
    });

    test('tryParse reads the scan source from its wire value', () {
      // Assert: a pasted menu's cache key and route both spell it `scan`.
      expect(MenuSource.tryParse('scan'), MenuSource.scan);
    });

    test('a scan VenueRef round-trips through its JSON form', () {
      // Arrange
      const ref = VenueRef(source: MenuSource.scan, platformId: '0badf00d');

      // Act
      final decoded = VenueRef.tryFrom(ref.toJson());

      // Assert
      expect(decoded, ref);
      expect(ref.cacheKey, 'scan/0badf00d');
    });

    test('tryParse returns null for an unknown string', () {
      // Arrange
      const wire = 'doordash';

      // Act
      final result = MenuSource.tryParse(wire);

      // Assert
      expect(result, isNull);
    });

    test('tryParse returns null for a name differing only in case', () {
      // Arrange
      const wire = 'WOLT';

      // Act
      final result = MenuSource.tryParse(wire);

      // Assert
      expect(result, isNull);
    });
  });

  group('VenueRef', () {
    test('tryFrom returns a VenueRef for a valid map', () {
      // Arrange
      final json = <String, Object?>{'source': 'wolt', 'platformId': 'abc'};

      // Act
      final result = VenueRef.tryFrom(json);

      // Assert
      expect(
        result,
        equals(const VenueRef(source: MenuSource.wolt, platformId: 'abc')),
      );
    });

    test('tryFrom(x.toJson()) round-trips to an equal VenueRef', () {
      // Arrange
      const ref = VenueRef(source: MenuSource.tenbis, platformId: '12345');

      // Act
      final result = VenueRef.tryFrom(ref.toJson());

      // Assert
      expect(result, equals(ref));
    });

    test('tryFrom returns null when source is missing', () {
      // Arrange
      final json = <String, Object?>{'platformId': 'abc'};

      // Act
      final result = VenueRef.tryFrom(json);

      // Assert
      expect(result, isNull);
    });

    test('tryFrom returns null when platformId is missing', () {
      // Arrange
      final json = <String, Object?>{'source': 'wolt'};

      // Act
      final result = VenueRef.tryFrom(json);

      // Assert
      expect(result, isNull);
    });

    test('tryFrom returns null when source is not a String', () {
      // Arrange
      final json = <String, Object?>{'source': 1, 'platformId': 'abc'};

      // Act
      final result = VenueRef.tryFrom(json);

      // Assert
      expect(result, isNull);
    });

    test('tryFrom returns null when platformId is not a String', () {
      // Arrange
      final json = <String, Object?>{'source': 'wolt', 'platformId': 1};

      // Act
      final result = VenueRef.tryFrom(json);

      // Assert
      expect(result, isNull);
    });

    test('tryFrom returns null when source is an unknown platform name', () {
      // Arrange
      final json = <String, Object?>{'source': 'doordash', 'platformId': 'abc'};

      // Act
      final result = VenueRef.tryFrom(json);

      // Assert
      expect(result, isNull);
    });

    test('tryFrom returns null when platformId is empty', () {
      // Arrange
      final json = <String, Object?>{'source': 'wolt', 'platformId': ''};

      // Act
      final result = VenueRef.tryFrom(json);

      // Assert
      expect(result, isNull);
    });

    test('cacheKey combines source name and platformId', () {
      // Arrange
      const ref = VenueRef(source: MenuSource.tabit, platformId: 'site-1');

      // Act
      final result = ref.cacheKey;

      // Assert
      expect(result, equals('tabit/site-1'));
    });

    test('== returns true for two refs with equal fields', () {
      // Arrange: built at run time, so == is exercised rather than const
      // canonicalisation.
      final ids = <String>['v1', 'v1'];
      final a = VenueRef(source: MenuSource.ontopo, platformId: ids[0]);
      final b = VenueRef(source: MenuSource.ontopo, platformId: ids[1]);

      // Act & Assert
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('== returns false for refs differing only in platformId', () {
      // Arrange
      const a = VenueRef(source: MenuSource.wolt, platformId: 'v1');
      const b = VenueRef(source: MenuSource.wolt, platformId: 'v2');

      // Act & Assert
      expect(a, isNot(equals(b)));
    });
  });

  group('Venue', () {
    test('== returns true for two non-const venues built separately with '
        'equal fields', () {
      // Arrange
      const ref = VenueRef(source: MenuSource.wolt, platformId: 'v1');
      final names = <String>['Diner', 'Diner'];
      final a = Venue(ref: ref, name: names[0]);
      final b = Venue(ref: ref, name: names[1]);

      // Act & Assert
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('== returns false for venues differing in name', () {
      // Arrange
      const ref = VenueRef(source: MenuSource.wolt, platformId: 'v1');
      const a = Venue(ref: ref, name: 'Diner');
      const b = Venue(ref: ref, name: 'Bistro');

      // Act & Assert
      expect(a, isNot(equals(b)));
    });

    test('== and hashCode cover every field added for venue search '
        '(issue #39)', () {
      // Arrange
      const ref = VenueRef(source: MenuSource.wolt, platformId: 'v1');
      Venue build({
        List<String> tags = const <String>['sushi'],
        bool? isOnline = true,
        String? imageUrl = 'https://example.test/v1.jpg',
        String? shortDescription = 'Sushi bar',
        double? platformRating = 9.1,
        int? estimateMinutes = 25,
        String? city = 'Tel Aviv',
      }) => Venue(
        ref: ref,
        name: 'Diner',
        cuisineTags: List<String>.of(tags),
        isOnline: isOnline,
        imageUrl: imageUrl,
        shortDescription: shortDescription,
        platformRating: platformRating,
        estimateMinutes: estimateMinutes,
        city: city,
      );
      final base = build();

      // Act & Assert: equal when built separately, with separate lists.
      expect(build(), equals(base));
      expect(build().hashCode, equals(base.hashCode));
      // Unequal when any one new field differs.
      expect(build(tags: <String>['ramen']), isNot(equals(base)));
      expect(build(isOnline: false), isNot(equals(base)));
      expect(build(imageUrl: null), isNot(equals(base)));
      expect(build(shortDescription: 'Other'), isNot(equals(base)));
      expect(build(platformRating: 8), isNot(equals(base)));
      expect(build(estimateMinutes: 30), isNot(equals(base)));
      expect(build(city: 'Haifa'), isNot(equals(base)));
      expect(build(city: null), isNot(equals(base)));
      expect(build(city: 'Haifa').hashCode, isNot(base.hashCode));
    });

    test('city defaults to null and toString names it', () {
      // Arrange
      const ref = VenueRef(source: MenuSource.wolt, platformId: 'v1');
      const bare = Venue(ref: ref, name: 'Diner');
      const placed = Venue(ref: ref, name: 'Diner', city: 'Tel Aviv');

      // Act & Assert
      expect(bare.city, isNull);
      expect(placed.city, 'Tel Aviv');
      expect(placed.toString(), contains('Tel Aviv'));
    });
  });

  group('Venue JSON', () {
    const ref = VenueRef(source: MenuSource.wolt, platformId: 'hamosad');
    const full = Venue(
      ref: ref,
      name: 'HaMosad',
      address: 'Dizengoff 1',
      latitude: 32.0853,
      longitude: 34.7818,
      sourceUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/hamosad',
      cuisineTags: <String>['steak', 'grill'],
      isOnline: true,
      imageUrl: 'https://imageproxy.wolt.com/venue/hamosad.jpg',
      shortDescription: 'Grill house',
      platformRating: 9.2,
      estimateMinutes: 35,
      city: 'Tel Aviv',
    );

    Map<String, Object?> fullJson() => full.toJson();

    test('toJson writes every key in the order the backend writes', () {
      // Arrange: the same bytes backend/tests/test_keto_models.py pins as
      // _FULL_VENUE (architecture.md D25).
      // Each break inside a value with a space falls after that space.
      const expected =
          '{"ref":{"source":"wolt","platformId":"hamosad"},"name":"HaMosad",'
          '"address":"Dizengoff '
          '1","latitude":32.0853,"longitude":34.7818,'
          '"sourceUrl":"https://wolt.com/en/isr/tel-aviv/restaurant/hamosad",'
          '"cuisineTags":["steak","grill"],"isOnline":true,'
          '"imageUrl":"https://imageproxy.wolt.com/venue/hamosad.jpg",'
          '"shortDescription":"Grill '
          'house","platformRating":9.2,'
          '"estimateMinutes":35,"city":"Tel Aviv"}';

      // Act
      final encoded = jsonEncode(full.toJson());

      // Assert
      expect(encoded, expected);
    });

    test('toJson keeps null keys for a venue with only a ref and name', () {
      // Arrange
      const bare = Venue(ref: ref, name: 'Diner');

      // Act
      final json = bare.toJson();

      // Assert
      expect(json.keys, fullJson().keys);
      expect(json['cuisineTags'], isEmpty);
      expect(json['city'], isNull);
      expect(json['platformRating'], isNull);
    });

    test('tryFrom(x.toJson()) round-trips a full and a bare venue', () {
      // Arrange
      const bare = Venue(ref: ref, name: 'Diner');

      // Act
      final decodedFull = Venue.tryFrom(fullJson());
      final decodedBare = Venue.tryFrom(bare.toJson());

      // Assert
      expect(decodedFull, full);
      expect(decodedBare, bare);
    });

    test('tryFrom round-trips through jsonEncode and jsonDecode', () {
      // Arrange
      final wire = jsonEncode(full.toJson());

      // Act
      final decoded = Venue.tryFrom(jsonDecode(wire) as Map<String, Object?>);

      // Assert
      expect(decoded, full);
    });

    test('tryFrom reads absent and null optional keys as their defaults', () {
      // Arrange
      final json = <String, Object?>{
        'ref': ref.toJson(),
        'name': 'Diner',
        'cuisineTags': null,
        'city': null,
      };

      // Act
      final venue = Venue.tryFrom(json);

      // Assert
      expect(venue, const Venue(ref: ref, name: 'Diner'));
      expect(venue?.cuisineTags, isEmpty);
    });

    test('tryFrom reads an integer coordinate or rating as a double', () {
      // Arrange
      final json = fullJson()
        ..['latitude'] = 32
        ..['platformRating'] = 9;

      // Act
      final venue = Venue.tryFrom(json);

      // Assert
      expect(venue?.latitude, 32.0);
      expect(venue?.platformRating, 9.0);
    });

    final badShapes = <String, Map<String, Object?> Function()>{
      'no ref': () => fullJson()..remove('ref'),
      'a ref that is not a map': () => fullJson()..['ref'] = 'wolt/x',
      'an invalid ref': () => fullJson()
        ..['ref'] = <String, Object?>{'source': 'doordash', 'platformId': 'x'},
      'no name': () => fullJson()..remove('name'),
      'an empty name': () => fullJson()..['name'] = '',
      'a non-string address': () => fullJson()..['address'] = 1,
      'a non-string city': () => fullJson()..['city'] = 7,
      'a string latitude': () => fullJson()..['latitude'] = '32.1',
      'a bool rating': () => fullJson()..['platformRating'] = true,
      'a double estimate': () => fullJson()..['estimateMinutes'] = 35.5,
      'a string isOnline': () => fullJson()..['isOnline'] = 'yes',
      'cuisineTags not a list': () => fullJson()..['cuisineTags'] = 'steak',
      'a non-string tag': () => fullJson()..['cuisineTags'] = <Object?>[1],
    };
    for (final entry in badShapes.entries) {
      test('tryFrom returns null for ${entry.key}', () {
        // Arrange
        final json = entry.value();

        // Act
        final venue = Venue.tryFrom(json);

        // Assert
        expect(venue, isNull);
      });
    }
  });
}

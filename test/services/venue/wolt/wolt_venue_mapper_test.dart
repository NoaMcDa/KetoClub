import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/venue/venue_ref_resolver.dart';
import 'package:ketoclub/services/venue/wolt/wolt_venue_mapper.dart';

/// Loads and decodes a fixture from `test/fixtures/` by file name.
Map<String, Object?> _loadFixture(String fileName) {
  final text = File('test/fixtures/$fileName').readAsStringSync();
  return jsonDecode(text) as Map<String, Object?>;
}

/// The synthetic `pages/restaurants` fixture (see `test/fixtures/README.md`).
Map<String, Object?> _restaurants() =>
    _loadFixture('wolt_pages_restaurants.json');

/// The synthetic `pages/search` fixture.
Map<String, Object?> _search() => _loadFixture('wolt_pages_search.json');

/// A page with one section holding [items].
Map<String, Object?> _page(List<Object?> items) => <String, Object?>{
  'sections': <Object?>[
    <String, Object?>{'items': items},
  ],
};

/// A list item wrapping [venue], with nothing else.
Map<String, Object?> _item(Map<String, Object?> venue) => <String, Object?>{
  'venue': venue,
};

/// The one venue mapping [venue] (wrapped in a page) produces.
Venue _single(Map<String, Object?> venue) {
  final venues = WoltVenueMapper.map(_page(<Object?>[_item(venue)]));
  expect(venues, hasLength(1));
  return venues!.single;
}

/// The venue with slug [slug] in [venues].
Venue _bySlug(List<Venue> venues, String slug) =>
    venues.singleWhere((v) => v.ref.platformId == slug);

void main() {
  group('WoltVenueMapper over the pages/restaurants fixture', () {
    test('ignores the leading _fixture_note key', () {
      // Arrange
      final json = _restaurants();

      // Act
      final venues = WoltVenueMapper.map(json);

      // Assert
      expect(json.keys.first, equals('_fixture_note'));
      expect(venues, isNotNull);
    });

    test('walks every section, keeps page order and drops the duplicate '
        'slug and the item with no venue', () {
      // Act
      final venues = WoltVenueMapper.map(_restaurants())!;

      // Assert
      expect(
        venues.map((v) => v.ref.platformId),
        orderedEquals(<String>[
          'vitrina-lilinblum',
          'hakosem',
          'shila-sharon-cohen',
          'mashya',
          'ghost-kitchen-tlv',
          'port-said',
        ]),
      );
    });

    test('keeps the first occurrence of a duplicated slug', () {
      // Act
      final venues = WoltVenueMapper.map(_restaurants())!;

      // Assert: the second section lists it as "Vitrina (listed again)".
      expect(_bySlug(venues, 'vitrina-lilinblum').name, equals('Vitrina'));
    });

    test('every venue is a Wolt ref', () {
      // Act
      final venues = WoltVenueMapper.map(_restaurants())!;

      // Assert
      for (final venue in venues) {
        expect(venue.ref.source, equals(MenuSource.wolt));
      }
    });

    test('keeps Hebrew names, tags and addresses intact', () {
      // Act
      final venues = WoltVenueMapper.map(_restaurants())!;
      final hakosem = _bySlug(venues, 'hakosem');

      // Assert
      expect(hakosem.name, equals('הקוסם'));
      expect(hakosem.cuisineTags, orderedEquals(<String>['falafel', 'מזרחי']));
      expect(hakosem.address, equals('שלמה המלך 1, תל אביב'));
      expect(hakosem.shortDescription, equals('פלאפל ושווארמה'));
      expect(_bySlug(venues, 'port-said').name, equals('פורט סעיד'));
    });

    test('reads location as [longitude, latitude]', () {
      // Act
      final venues = WoltVenueMapper.map(_restaurants())!;
      final vitrina = _bySlug(venues, 'vitrina-lilinblum');

      // Assert: the fixture holds [34.7702, 32.0625]; Tel Aviv is at
      // latitude 32, longitude 34.
      expect(vitrina.latitude, equals(32.0625));
      expect(vitrina.longitude, equals(34.7702));
    });

    test('leaves both coordinates null for a venue with no location', () {
      // Act
      final venues = WoltVenueMapper.map(_restaurants())!;
      final ghost = _bySlug(venues, 'ghost-kitchen-tlv');

      // Assert
      expect(ghost.latitude, isNull);
      expect(ghost.longitude, isNull);
    });

    test('reads online, rating, estimate and description', () {
      // Act
      final venues = WoltVenueMapper.map(_restaurants())!;
      final vitrina = _bySlug(venues, 'vitrina-lilinblum');
      final shila = _bySlug(venues, 'shila-sharon-cohen');

      // Assert
      expect(vitrina.isOnline, isTrue);
      expect(vitrina.platformRating, equals(9.2));
      expect(vitrina.estimateMinutes, equals(25));
      expect(vitrina.shortDescription, equals('Burgers and sandwiches'));
      expect(vitrina.address, equals('Lilienblum St 36, Tel Aviv'));
      expect(shila.isOnline, isFalse);
    });

    test('reads an integer rating score as a double', () {
      // Act
      final venues = WoltVenueMapper.map(_restaurants())!;

      // Assert
      expect(_bySlug(venues, 'mashya').platformRating, equals(9.0));
    });

    test('prefers the item image and has none when neither is given', () {
      // Act
      final venues = WoltVenueMapper.map(_restaurants())!;

      // Assert
      expect(
        _bySlug(venues, 'vitrina-lilinblum').imageUrl,
        equals('https://imageproxy.wolt.com/venue/vitrina-lilinblum.jpg'),
      );
      expect(_bySlug(venues, 'mashya').imageUrl, isNull);
    });

    test('links each venue to its Wolt page', () {
      // Act
      final venues = WoltVenueMapper.map(_restaurants())!;
      final vitrina = _bySlug(venues, 'vitrina-lilinblum');

      // Assert
      expect(
        vitrina.sourceUrl,
        equals(VenueRefResolver.platformUrl(vitrina.ref).toString()),
      );
    });
  });

  group('WoltVenueMapper over the pages/search fixture', () {
    test('keeps venue results and skips dish results', () {
      // Act
      final venues = WoltVenueMapper.map(_search())!;

      // Assert
      expect(
        venues.map((v) => v.ref.platformId),
        orderedEquals(<String>[
          'pizza-romana',
          'pizza-lena',
          'tony-vespa-allenby',
          'pizza-cloud',
        ]),
      );
      expect(_bySlug(venues, 'pizza-lena').name, equals('פיצה לנה'));
      expect(_bySlug(venues, 'tony-vespa-allenby').name, equals('Tony Vespa'));
    });
  });

  group('WoltVenueMapper tolerance', () {
    test('answers null for a body with no sections list', () {
      // Act & Assert
      expect(WoltVenueMapper.map(<String, Object?>{}), isNull);
      expect(
        WoltVenueMapper.map(<String, Object?>{'sections': 'nope'}),
        isNull,
      );
      expect(WoltVenueMapper.map(<String, Object?>{'error_code': 430}), isNull);
    });

    test('answers an empty list for an empty sections list', () {
      // Act
      final venues = WoltVenueMapper.map(<String, Object?>{
        'sections': <Object?>[],
      });

      // Assert
      expect(venues, isEmpty);
    });

    test('skips sections and items of the wrong shape', () {
      // Arrange
      final json = <String, Object?>{
        'sections': <Object?>[
          'not a section',
          <String, Object?>{'items': 'not a list'},
          <String, Object?>{'no_items': true},
          <String, Object?>{
            'items': <Object?>[
              42,
              <String, Object?>{'venue': 'not a map'},
              _item(<String, Object?>{'slug': 'ok', 'name': 'OK'}),
            ],
          },
        ],
      };

      // Act
      final venues = WoltVenueMapper.map(json)!;

      // Assert
      expect(venues.map((v) => v.ref.platformId), orderedEquals(['ok']));
    });

    test('skips a venue without a usable slug or name', () {
      // Arrange
      final json = _page(<Object?>[
        _item(<String, Object?>{'name': 'No slug'}),
        _item(<String, Object?>{'slug': 'no-name'}),
        _item(<String, Object?>{'slug': '', 'name': 'Empty slug'}),
        _item(<String, Object?>{'slug': 'blank-name', 'name': '  '}),
        _item(<String, Object?>{'slug': 7, 'name': 'Numeric slug'}),
      ]);

      // Act
      final venues = WoltVenueMapper.map(json);

      // Assert
      expect(venues, isEmpty);
    });

    test('a venue with only slug and name has every other field empty', () {
      // Act
      final venue = _single(<String, Object?>{'slug': 's', 'name': 'N'});

      // Assert
      expect(venue.name, equals('N'));
      expect(venue.address, isNull);
      expect(venue.latitude, isNull);
      expect(venue.longitude, isNull);
      expect(venue.cuisineTags, isEmpty);
      expect(venue.isOnline, isNull);
      expect(venue.imageUrl, isNull);
      expect(venue.shortDescription, isNull);
      expect(venue.platformRating, isNull);
      expect(venue.estimateMinutes, isNull);
      expect(venue.sourceUrl, isNotNull);
    });

    test('treats every optional field of the wrong type as absent', () {
      // Act
      final venue = _single(<String, Object?>{
        'slug': 's',
        'name': 'N',
        'address': 12,
        'location': 'here',
        'tags': 'sushi',
        'online': 'yes',
        'brand_image': 'https://example.test/logo.png',
        'short_description': <Object?>[],
        'rating': 9.1,
        'estimate': '25',
      });

      // Assert
      expect(venue.address, isNull);
      expect(venue.latitude, isNull);
      expect(venue.cuisineTags, isEmpty);
      expect(venue.isOnline, isNull);
      expect(venue.imageUrl, isNull);
      expect(venue.shortDescription, isNull);
      expect(venue.platformRating, isNull);
      expect(venue.estimateMinutes, isNull);
    });

    test('rejects a location that is short, non-numeric or out of '
        'range', () {
      // Arrange
      final locations = <Object?>[
        <Object?>[34.7],
        <Object?>['34.7', '32.0'],
        <Object?>[34.7, 132.0],
        <Object?>[234.7, 32.0],
        <Object?>[34.7, double.nan],
      ];

      for (final location in locations) {
        // Act
        final venue = _single(<String, Object?>{
          'slug': 's',
          'name': 'N',
          'location': location,
        });

        // Assert
        expect(venue.latitude, isNull, reason: '$location');
        expect(venue.longitude, isNull, reason: '$location');
      }
    });

    test('keeps only non-empty string tags', () {
      // Act
      final venue = _single(<String, Object?>{
        'slug': 's',
        'name': 'N',
        'tags': <Object?>['sushi', '', 3, null, 'ramen'],
      });

      // Assert
      expect(venue.cuisineTags, orderedEquals(<String>['sushi', 'ramen']));
    });

    test('falls back to the brand image when the item has none', () {
      // Act
      final venue = _single(<String, Object?>{
        'slug': 's',
        'name': 'N',
        'brand_image': <String, Object?>{'url': 'https://example.test/b.png'},
      });

      // Assert
      expect(venue.imageUrl, equals('https://example.test/b.png'));
    });

    test('rounds a fractional estimate and ignores a non-finite one', () {
      // Act
      final rounded = _single(<String, Object?>{
        'slug': 's',
        'name': 'N',
        'estimate': 24.6,
      });
      final infinite = _single(<String, Object?>{
        'slug': 's',
        'name': 'N',
        'estimate': double.infinity,
        'rating': <String, Object?>{'score': double.nan},
      });

      // Assert
      expect(rounded.estimateMinutes, equals(25));
      expect(infinite.estimateMinutes, isNull);
      expect(infinite.platformRating, isNull);
    });
  });
}

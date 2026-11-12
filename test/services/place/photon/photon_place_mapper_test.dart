import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/place.dart';
import 'package:ketoclub/services/place/photon/photon_place_mapper.dart';

/// Loads and decodes a recorded Photon reply from `test/fixtures/photon/`
/// (see `test/fixtures/README.md`).
Object? _fixture(String fileName) =>
    jsonDecode(File('test/fixtures/photon/$fileName').readAsStringSync());

/// A Photon feature of [type] with [properties] over the defaults, at
/// [coordinates] (`[longitude, latitude]`).
Map<String, Object?> _feature({
  String type = 'house',
  Map<String, Object?> properties = const <String, Object?>{},
  Object? coordinates = const <Object?>[34.77, 32.06],
}) => <String, Object?>{
  'type': 'Feature',
  'geometry': <String, Object?>{'type': 'Point', 'coordinates': coordinates},
  'properties': <String, Object?>{
    'countrycode': 'IL',
    'type': type,
    'street': 'Herzl',
    'housenumber': '10',
    'name': 'Herzl',
    'city': 'Tel Aviv',
    ...properties,
  },
};

/// The labels [PhotonPlaceMapper.map] gives for [features].
List<String> _labels(List<Object?> features) => PhotonPlaceMapper.map(
  <String, Object?>{'type': 'FeatureCollection', 'features': features},
)!.map((p) => p.label).toList();

void main() {
  group('PhotonPlaceMapper on recorded replies (issue #449)', () {
    test('a Hebrew house search: labels, deduplicated, first six', () {
      // Act
      final places = PhotonPlaceMapper.map(
        _fixture('photon_herzl_tel_aviv_default.json'),
      )!;

      // Assert: Herzl 10 under three spellings of Tel Aviv, all within
      // metres, is one row (the first); Herzl 10 in Ramat Gan is its own;
      // Herzl with no number does not merge with Herzl 10; the seventh
      // kept is cut.
      expect(places.map((p) => p.label).toList(), <String>[
        'הרצל 10, תל אביב',
        'רוזנבלום הרצל ד"ר 10, תל אביב–יפו',
        'הרצל 10, רמת גן',
        'הרצל, תל אביב–יפו',
        'הרצל 10/37, בת ים',
        'תל חי 10, הרצליה',
      ]);
      expect(places.first.city, 'תל אביב');
      expect(places.first.latitude, 32.0625697);
      expect(places.first.longitude, 34.7698648);
    });

    test('an English street search: one row per name, a house by its own '
        'street', () {
      // Act
      final places = PhotonPlaceMapper.map(
        _fixture('photon_dizengoff_en.json'),
      )!;

      // Assert: eight "Dizengoff" street segments collapse into the first.
      expect(places.map((p) => p.label).toList(), <String>[
        'Dizengoff, Tel Aviv',
        '1240, Tel Aviv',
        'Sderot Rothschild 16, Tel Aviv',
        'Dizengoff Square (tsina), Tel Aviv',
      ]);
      expect(
        places.first,
        const StreetPlace(
          label: 'Dizengoff, Tel Aviv',
          city: 'Tel Aviv',
          latitude: 32.0765505,
          longitude: 34.7746435,
        ),
      );
    });
  });

  group('PhotonPlaceMapper rules (issue #449)', () {
    test('builds "<street> <number>, <city>" and leaves out what is '
        'missing', () {
      // Act
      final labels = _labels(<Object?>[
        _feature(),
        _feature(properties: <String, Object?>{'housenumber': null}),
        _feature(
          properties: <String, Object?>{'city': null, 'district': null},
          coordinates: <Object?>[35.0, 31.0],
        ),
        _feature(
          properties: <String, Object?>{
            'street': 'Ibn Gabirol',
            'housenumber': '  ',
            'city': null,
            'district': null,
          },
        ),
      ]);

      // Assert
      expect(labels, <String>[
        'Herzl 10, Tel Aviv',
        'Herzl, Tel Aviv',
        'Herzl 10',
        'Ibn Gabirol',
      ]);
    });

    test('falls back to the district when there is no city, and keeps none '
        'when neither is there', () {
      // Act
      final places = PhotonPlaceMapper.map(<String, Object?>{
        'features': <Object?>[
          _feature(
            properties: <String, Object?>{'city': ' ', 'district': 'Florentin'},
          ),
          _feature(
            properties: <String, Object?>{
              'street': 'Allenby',
              'city': null,
              'district': null,
            },
          ),
        ],
      })!;

      // Assert
      expect(places[0].label, 'Herzl 10, Florentin');
      expect(places[0].city, 'Florentin');
      expect(places[1].label, 'Allenby 10');
      expect(places[1].city, isNull);
    });

    test('a street is named by its name and never carries a house '
        'number', () {
      // Act
      final labels = _labels(<Object?>[
        _feature(
          type: 'street',
          properties: <String, Object?>{
            'name': 'Rothschild',
            'street': 'ignored',
            'housenumber': '3',
          },
        ),
      ]);

      // Assert
      expect(labels, <String>['Rothschild, Tel Aviv']);
    });

    test('drops a house with no street and a street with no name', () {
      // Act
      final labels = _labels(<Object?>[
        _feature(properties: <String, Object?>{'street': null}),
        _feature(properties: <String, Object?>{'street': '   '}),
        _feature(type: 'street', properties: <String, Object?>{'name': ''}),
        _feature(type: 'street', properties: <String, Object?>{'name': 4}),
        _feature(properties: <String, Object?>{'street': 'Kept'}),
      ]);

      // Assert
      expect(labels, <String>['Kept 10, Tel Aviv']);
    });

    test('keeps Israel only, in any case', () {
      // Act
      final labels = _labels(<Object?>[
        _feature(properties: <String, Object?>{'countrycode': 'PS'}),
        _feature(properties: <String, Object?>{'countrycode': null}),
        _feature(
          properties: <String, Object?>{'street': 'Lower', 'countrycode': 'il'},
        ),
      ]);

      // Assert
      expect(labels, <String>['Lower 10, Tel Aviv']);
    });

    test('keeps houses and streets only', () {
      // Act
      final labels = _labels(<Object?>[
        _feature(type: 'city'),
        _feature(type: 'district'),
        _feature(type: 'House'),
        _feature(type: 'street', properties: <String, Object?>{'name': 'Kept'}),
      ]);

      // Assert
      expect(labels, <String>['Kept, Tel Aviv']);
    });

    test('drops a feature without two finite coordinates', () {
      // Act
      final labels = _labels(<Object?>[
        _feature(coordinates: null),
        _feature(coordinates: <Object?>[34.7]),
        _feature(coordinates: <Object?>[34.7, 32.0, 10.0]),
        _feature(coordinates: <Object?>['34.7', 32.0]),
        _feature(coordinates: <Object?>[34.7, double.nan]),
        _feature(coordinates: <Object?>[double.infinity, 32.0]),
        _feature(
          properties: <String, Object?>{'street': 'Kept'},
          coordinates: <Object?>[34, 32],
        ),
      ]);

      // Assert
      expect(labels, <String>['Kept 10, Tel Aviv']);
    });

    test('drops a feature that is not an object or has no properties or '
        'geometry', () {
      // Act
      final labels = _labels(<Object?>[
        'feature',
        null,
        <String, Object?>{'geometry': _feature()['geometry']},
        <String, Object?>{'properties': _feature()['properties']},
        _feature(properties: <String, Object?>{'street': 'Kept'}),
      ]);

      // Assert
      expect(labels, <String>['Kept 10, Tel Aviv']);
    });

    test('deduplicates by exact label wherever it is, the first occurrence '
        'winning', () {
      // Act
      final places = PhotonPlaceMapper.map(<String, Object?>{
        'features': <Object?>[
          _feature(coordinates: <Object?>[34.1, 32.1]),
          _feature(coordinates: <Object?>[34.9, 32.9]),
        ],
      })!;

      // Assert
      expect(places.map((p) => p.label), <String>['Herzl 10, Tel Aviv']);
      expect(places.first.longitude, 34.1);
    });

    test('one address under three spellings of its city, close by, is one '
        'row: the first', () {
      // Act
      final places = PhotonPlaceMapper.map(<String, Object?>{
        'features': <Object?>[
          _feature(
            properties: <String, Object?>{'city': 'תל אביב'},
            coordinates: <Object?>[34.7698648, 32.0625697],
          ),
          _feature(
            properties: <String, Object?>{'city': 'תל אביב-יפו'},
            coordinates: <Object?>[34.7699465, 32.0625439],
          ),
          _feature(
            properties: <String, Object?>{
              'street': ' HERZL ',
              'city': 'תל אביב–יפו',
            },
            coordinates: <Object?>[34.769931, 32.062416],
          ),
        ],
      })!;

      // Assert
      expect(places.map((p) => p.label), <String>['Herzl 10, תל אביב']);
    });

    test('the same street and number in two cities far apart stay two', () {
      // Act
      final labels = _labels(<Object?>[
        _feature(coordinates: <Object?>[34.7698, 32.0625]),
        _feature(
          properties: <String, Object?>{'city': 'Ramat Gan'},
          coordinates: <Object?>[34.8188, 32.0810],
        ),
      ]);

      // Assert
      expect(labels, <String>['Herzl 10, Tel Aviv', 'Herzl 10, Ramat Gan']);
    });

    test('a street with no number does not merge with a numbered house on '
        'it, however close', () {
      // Act
      final labels = _labels(<Object?>[
        _feature(coordinates: <Object?>[34.7698, 32.0625]),
        _feature(
          type: 'street',
          properties: <String, Object?>{'city': 'Tel Aviv-Yafo'},
          coordinates: <Object?>[34.7699, 32.0626],
        ),
      ]);

      // Assert
      expect(labels, <String>['Herzl 10, Tel Aviv', 'Herzl, Tel Aviv-Yafo']);
    });

    test('two segments of one street within 0.003 degrees merge, and one '
        'further away does not', () {
      // Act
      final labels = _labels(<Object?>[
        _feature(
          type: 'street',
          properties: <String, Object?>{'name': 'Dizengoff'},
          coordinates: <Object?>[34.7746, 32.0765],
        ),
        _feature(
          type: 'street',
          properties: <String, Object?>{
            'name': 'dizengoff',
            'city': null,
            'district': 'Old North',
          },
          coordinates: <Object?>[34.7770, 32.0790],
        ),
        _feature(
          type: 'street',
          properties: <String, Object?>{
            'name': 'Dizengoff',
            'city': null,
            'district': 'Lev Tel Aviv',
          },
          coordinates: <Object?>[34.7746, 32.0800],
        ),
      ]);

      // Assert: the second is 0.0025 and 0.0024 degrees off, the third
      // 0.0035 degrees north.
      expect(labels, <String>[
        'Dizengoff, Tel Aviv',
        'Dizengoff, Lev Tel Aviv',
      ]);
    });

    test('returns at most six', () {
      // Act
      final labels = _labels(<Object?>[
        for (var i = 1; i <= 10; i++)
          _feature(properties: <String, Object?>{'housenumber': '$i'}),
      ]);

      // Assert
      expect(labels, hasLength(6));
      expect(labels.last, 'Herzl 6, Tel Aviv');
    });

    test('an empty feature list is no places', () {
      // Assert
      expect(
        PhotonPlaceMapper.map(<String, Object?>{'features': <Object?>[]}),
        isEmpty,
      );
    });

    test('a reply that is not an object with a features list is null', () {
      for (final decoded in <Object?>[
        null,
        'features',
        <Object?>[],
        <String, Object?>{},
        <String, Object?>{'features': 'none'},
        <String, Object?>{'features': <String, Object?>{}},
      ]) {
        // Assert
        expect(PhotonPlaceMapper.map(decoded), isNull, reason: '$decoded');
      }
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/place.dart';

void main() {
  group('KnownPlace (issue #443)', () {
    const haifa = KnownPlace(
      id: 'haifa',
      nameEn: 'Haifa',
      nameHe: 'חיפה',
      latitude: 32.794,
      longitude: 34.9896,
    );

    test('nameFor gives the Hebrew name under Hebrew', () {
      // Assert
      expect(haifa.nameFor('he'), 'חיפה');
    });

    test('nameFor gives the English name under English and under any other '
        'language', () {
      // Assert
      expect(haifa.nameFor('en'), 'Haifa');
      expect(haifa.nameFor('fr'), 'Haifa');
    });

    test('two places with the same fields are equal and hash alike', () {
      // Arrange
      const same = KnownPlace(
        id: 'haifa',
        nameEn: 'Haifa',
        nameHe: 'חיפה',
        latitude: 32.794,
        longitude: 34.9896,
      );

      // Assert
      expect(same, equals(haifa));
      expect(same.hashCode, haifa.hashCode);
    });

    test('a place differing in any one field is not equal', () {
      // Arrange
      const others = <KnownPlace>[
        KnownPlace(
          id: 'other',
          nameEn: 'Haifa',
          nameHe: 'חיפה',
          latitude: 32.794,
          longitude: 34.9896,
        ),
        KnownPlace(
          id: 'haifa',
          nameEn: 'Other',
          nameHe: 'חיפה',
          latitude: 32.794,
          longitude: 34.9896,
        ),
        KnownPlace(
          id: 'haifa',
          nameEn: 'Haifa',
          nameHe: 'אחר',
          latitude: 32.794,
          longitude: 34.9896,
        ),
        KnownPlace(
          id: 'haifa',
          nameEn: 'Haifa',
          nameHe: 'חיפה',
          latitude: 31,
          longitude: 34.9896,
        ),
        KnownPlace(
          id: 'haifa',
          nameEn: 'Haifa',
          nameHe: 'חיפה',
          latitude: 32.794,
          longitude: 35,
        ),
      ];

      // Assert
      for (final other in others) {
        expect(other, isNot(equals(haifa)));
      }
    });

    test('toString names the place by its id', () {
      // Assert
      expect(haifa.toString(), 'KnownPlace(haifa)');
    });
  });

  group('StreetPlace (issue #449)', () {
    const herzl = StreetPlace(
      label: 'הרצל 10, תל אביב',
      city: 'תל אביב',
      latitude: 32.0625697,
      longitude: 34.7698648,
    );

    test('toJson stores the label and coordinates, never the city', () {
      // Assert
      expect(herzl.toJson(), <String, Object?>{
        'label': 'הרצל 10, תל אביב',
        'latitude': 32.0625697,
        'longitude': 34.7698648,
      });
    });

    test('tryFrom reads a search answer, city included, trimming text', () {
      // Act
      final read = StreetPlace.tryFrom(<String, Object?>{
        'label': '  Dizengoff, Tel Aviv ',
        'city': ' Tel Aviv ',
        'latitude': 32,
        'longitude': 34.77,
      });

      // Assert
      expect(read, isNotNull);
      expect(read!.label, 'Dizengoff, Tel Aviv');
      expect(read.city, 'Tel Aviv');
      expect(read.latitude, 32.0);
      expect(read.longitude, 34.77);
    });

    test('tryFrom reads a blank or non-string city as none', () {
      for (final city in <Object?>[null, '', '  ', 5]) {
        // Act
        final read = StreetPlace.tryFrom(<String, Object?>{
          'label': 'Herzl',
          'city': city,
          'latitude': 32.0,
          'longitude': 34.0,
        });

        // Assert
        expect(read!.city, isNull, reason: '$city');
      }
    });

    test('tryFrom rejects a missing or blank label and unusable '
        'coordinates', () {
      for (final json in <Map<String, Object?>>[
        <String, Object?>{'latitude': 32.0, 'longitude': 34.0},
        <String, Object?>{'label': ' ', 'latitude': 32.0, 'longitude': 34.0},
        <String, Object?>{'label': 3, 'latitude': 32.0, 'longitude': 34.0},
        <String, Object?>{'label': 'a', 'latitude': null, 'longitude': 34.0},
        <String, Object?>{'label': 'a', 'latitude': 32.0, 'longitude': '34'},
        <String, Object?>{
          'label': 'a',
          'latitude': double.nan,
          'longitude': 34.0,
        },
        <String, Object?>{
          'label': 'a',
          'latitude': 32.0,
          'longitude': double.infinity,
        },
        <String, Object?>{'label': 'a', 'latitude': -91.0, 'longitude': 34.0},
        <String, Object?>{'label': 'a', 'latitude': 32.0, 'longitude': 181.0},
      ]) {
        // Assert
        expect(StreetPlace.tryFrom(json), isNull, reason: '$json');
      }
    });

    test('two streets with the same fields are equal and hash alike, and '
        'toString does not reveal where', () {
      // Arrange
      const same = StreetPlace(
        label: 'הרצל 10, תל אביב',
        city: 'תל אביב',
        latitude: 32.0625697,
        longitude: 34.7698648,
      );
      const other = StreetPlace(
        label: 'הרצל 10, תל אביב',
        latitude: 32.0625697,
        longitude: 34.7698648,
      );

      // Assert
      expect(same, equals(herzl));
      expect(same.hashCode, herzl.hashCode);
      expect(other, isNot(equals(herzl)));
      expect(herzl.toString(), isNot(contains('הרצל')));
      expect(herzl.toString(), isNot(contains('32')));
    });
  });
}

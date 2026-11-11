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
}

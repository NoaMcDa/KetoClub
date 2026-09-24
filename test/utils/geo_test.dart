import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/utils/geo.dart';

/// A venue with slug [slug] at ([lat], [lon]), or unlocated when either
/// is null.
Venue _venue(String slug, {double? lat, double? lon}) => Venue(
  ref: VenueRef(source: MenuSource.wolt, platformId: slug),
  name: slug,
  latitude: lat,
  longitude: lon,
);

void main() {
  group('distanceKm', () {
    test('is about 54 km from Tel Aviv to Jerusalem', () {
      // Arrange: Tel Aviv City Hall and Jerusalem's Old City (Jaffa Gate).
      const telAvivLat = 32.0809;
      const telAvivLon = 34.7806;
      const jerusalemLat = 31.7767;
      const jerusalemLon = 35.2345;

      // Act
      final km = distanceKm(telAvivLat, telAvivLon, jerusalemLat, jerusalemLon);

      // Assert
      expect(km, closeTo(54, 1));
    });

    test('is zero between a point and itself', () {
      // Act
      final km = distanceKm(32.08, 34.78, 32.08, 34.78);

      // Assert
      expect(km, equals(0));
    });

    test('is symmetric', () {
      // Act
      final there = distanceKm(32.08, 34.78, 31.77, 35.23);
      final back = distanceKm(31.77, 35.23, 32.08, 34.78);

      // Assert
      expect(there, closeTo(back, 1e-9));
    });

    test('is about 111 km for one degree of latitude', () {
      // Act
      final km = distanceKm(0, 0, 1, 0);

      // Assert
      expect(km, closeTo(111.2, 0.1));
    });
  });

  group('walkingMinutes', () {
    test('is 12 minutes for one kilometre at 5 km/h', () {
      // Act & Assert
      expect(walkingMinutes(1), equals(12));
    });

    test('rounds a short walk up to one minute, never zero', () {
      // Act & Assert
      expect(walkingMinutes(0.01), equals(1));
    });

    test('is zero for no distance or a negative one', () {
      // Act & Assert
      expect(walkingMinutes(0), equals(0));
      expect(walkingMinutes(-3), equals(0));
    });
  });

  group('sortNearestFirst', () {
    test('orders located venues by distance from the position', () {
      // Arrange
      final venues = [
        _venue('far', lat: 32.2, lon: 34.8),
        _venue('near', lat: 32.081, lon: 34.781),
        _venue('middle', lat: 32.1, lon: 34.79),
      ];

      // Act
      final sorted = sortNearestFirst(
        venues,
        latitude: 32.08,
        longitude: 34.78,
      );

      // Assert
      expect(
        sorted.map((v) => v.ref.platformId),
        orderedEquals(<String>['near', 'middle', 'far']),
      );
    });

    test('puts unlocated venues last, in their original order', () {
      // Arrange
      final venues = [
        _venue('no-position-a'),
        _venue('located', lat: 32.1, lon: 34.79),
        _venue('only-lat', lat: 32.1),
        _venue('no-position-b'),
      ];

      // Act
      final sorted = sortNearestFirst(
        venues,
        latitude: 32.08,
        longitude: 34.78,
      );

      // Assert
      expect(
        sorted.map((v) => v.ref.platformId),
        orderedEquals(<String>[
          'located',
          'no-position-a',
          'only-lat',
          'no-position-b',
        ]),
      );
    });

    test('keeps the original order of venues at the same distance', () {
      // Arrange
      final venues = [
        _venue('first', lat: 32.1, lon: 34.79),
        _venue('second', lat: 32.1, lon: 34.79),
        _venue('third', lat: 32.1, lon: 34.79),
      ];

      // Act
      final sorted = sortNearestFirst(
        venues,
        latitude: 32.08,
        longitude: 34.78,
      );

      // Assert
      expect(sorted, orderedEquals(venues));
    });

    test('does not modify the list it is given', () {
      // Arrange
      final venues = [
        _venue('far', lat: 32.2, lon: 34.8),
        _venue('near', lat: 32.081, lon: 34.781),
      ];
      final before = List<Venue>.of(venues);

      // Act
      sortNearestFirst(venues, latitude: 32.08, longitude: 34.78);

      // Assert
      expect(venues, orderedEquals(before));
    });
  });
}

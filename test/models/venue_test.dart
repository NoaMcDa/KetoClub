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
      // Arrange
      const a = VenueRef(source: MenuSource.ontopo, platformId: 'v1');
      const b = VenueRef(source: MenuSource.ontopo, platformId: 'v1');

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

    test('toString mentions the cache key', () {
      // Arrange
      const ref = VenueRef(source: MenuSource.wolt, platformId: 'v1');

      // Act
      final result = ref.toString();

      // Assert
      expect(result, contains('wolt/v1'));
    });
  });

  group('Venue', () {
    test('== returns true for two venues with equal fields', () {
      // Arrange
      const ref = VenueRef(source: MenuSource.wolt, platformId: 'v1');
      const a = Venue(
        ref: ref,
        name: 'Diner',
        address: '1 Main St',
        latitude: 1,
        longitude: 2,
        sourceUrl: 'https://example.com',
      );
      const b = Venue(
        ref: ref,
        name: 'Diner',
        address: '1 Main St',
        latitude: 1,
        longitude: 2,
        sourceUrl: 'https://example.com',
      );

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

    test('== treats absent optional fields (all null) as equal', () {
      // Arrange
      const ref = VenueRef(source: MenuSource.wolt, platformId: 'v1');
      const a = Venue(ref: ref, name: 'Diner');
      const b = Venue(ref: ref, name: 'Diner');

      // Act & Assert
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });
}

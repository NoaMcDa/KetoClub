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

    test('== treats absent optional fields (all null) as equal', () {
      // Arrange
      const ref = VenueRef(source: MenuSource.wolt, platformId: 'v1');
      const a = Venue(ref: ref, name: 'Diner');
      const b = Venue(ref: ref, name: 'Diner');

      // Act & Assert
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
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
      }) => Venue(
        ref: ref,
        name: 'Diner',
        cuisineTags: List<String>.of(tags),
        isOnline: isOnline,
        imageUrl: imageUrl,
        shortDescription: shortDescription,
        platformRating: platformRating,
        estimateMinutes: estimateMinutes,
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
    });

    test('defaults the venue-search fields to empty or null', () {
      // Arrange
      const ref = VenueRef(source: MenuSource.wolt, platformId: 'v1');

      // Act
      const venue = Venue(ref: ref, name: 'Diner');

      // Assert
      expect(venue.cuisineTags, isEmpty);
      expect(venue.isOnline, isNull);
      expect(venue.imageUrl, isNull);
      expect(venue.shortDescription, isNull);
      expect(venue.platformRating, isNull);
      expect(venue.estimateMinutes, isNull);
    });

    test('toString mentions the cache key and the name', () {
      // Arrange
      const ref = VenueRef(source: MenuSource.wolt, platformId: 'v1');
      const venue = Venue(ref: ref, name: 'Diner');

      // Act
      final result = venue.toString();

      // Assert
      expect(result, contains('wolt/v1'));
      expect(result, contains('Diner'));
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/utils/venue_route.dart';

void main() {
  group('venueRoutePath', () {
    test('names the source and the encoded platform id', () {
      // Arrange
      const ref = VenueRef(
        source: MenuSource.website,
        platformId: 'https://example.com/menu',
      );

      // Act
      final path = venueRoutePath(ref);

      // Assert
      expect(path, '/venue/website/https%3A%2F%2Fexample.com%2Fmenu');
    });
  });

  group('VenueOpenHint', () {
    test('equal fields are equal, with equal hash codes', () {
      const a = VenueOpenHint(name: 'Vitrina', city: 'Tel Aviv');
      const b = VenueOpenHint(name: 'Vitrina', city: 'Tel Aviv');

      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('a different name or city is unequal', () {
      const a = VenueOpenHint(name: 'Vitrina', city: 'Tel Aviv');

      expect(a, isNot(const VenueOpenHint(name: 'Other', city: 'Tel Aviv')));
      expect(a, isNot(const VenueOpenHint(name: 'Vitrina')));
    });

    test('defaults both fields to null', () {
      const hint = VenueOpenHint();

      expect(hint.name, isNull);
      expect(hint.city, isNull);
    });

    test('toString names both fields', () {
      expect(
        const VenueOpenHint(name: 'Vitrina', city: 'Tel Aviv').toString(),
        'VenueOpenHint(name: Vitrina, city: Tel Aviv)',
      );
    });
  });
}

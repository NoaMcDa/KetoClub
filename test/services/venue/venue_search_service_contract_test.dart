import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/venue/venue_search_service.dart';

import '../../fakes/fake_venue_search_service.dart';
import 'venue_search_service_contract.dart';

/// A located Wolt venue with slug [slug].
Venue _venue(String slug, {double? lat, double? lon}) => Venue(
  ref: VenueRef(source: MenuSource.wolt, platformId: slug),
  name: slug,
  latitude: lat,
  longitude: lon,
);

void main() {
  runVenueSearchServiceContract(
    'FakeVenueSearchService',
    FakeVenueSearchService.new,
  );

  runVenueSearchServiceContract(
    'FakeVenueSearchService with a nearest-first list queued',
    () => FakeVenueSearchService()
      ..queueFound(<Venue>[
        _venue('near', lat: 32.081, lon: 34.781),
        _venue('far', lat: 32.2, lon: 34.8),
        _venue('nowhere'),
      ]),
  );

  runVenueSearchServiceContract(
    'FakeVenueSearchService with a failure queued',
    () =>
        FakeVenueSearchService()
          ..queueFailed(VenueSearchFailureReason.rateLimited),
  );

  group('FakeVenueSearchService', () {
    test('finds nothing until scripted', () async {
      // Arrange
      final fake = FakeVenueSearchService();

      // Act
      final result = await fake.nearby(
        latitude: 1,
        longitude: 2,
        language: 'en',
      );

      // Assert
      expect(result, equals(const VenuesFound(<Venue>[])));
    });

    test('returns queued results in order, then sticks on the last', () async {
      // Arrange
      final venues = <Venue>[_venue('a')];
      final fake = FakeVenueSearchService()
        ..queueFound(venues)
        ..queueFailed(VenueSearchFailureReason.offline);

      // Act
      final first = await fake.byName('a', language: 'en');
      final second = await fake.nearby(
        latitude: 1,
        longitude: 2,
        language: 'en',
      );
      final third = await fake.byName('b', language: 'en');

      // Assert
      expect(first, equals(VenuesFound(venues)));
      expect(
        second,
        equals(const VenueSearchFailed(VenueSearchFailureReason.offline)),
      );
      expect(third, equals(second));
    });

    test('records every call with its arguments', () async {
      // Arrange
      final fake = FakeVenueSearchService();

      // Act
      await fake.nearby(latitude: 32.1, longitude: 34.8, language: 'he');
      await fake.byName('sushi', latitude: 32.1, language: 'en');

      // Assert
      expect(fake.nearbyCalls, hasLength(1));
      expect(fake.nearbyCalls.single.latitude, equals(32.1));
      expect(fake.nearbyCalls.single.longitude, equals(34.8));
      expect(fake.nearbyCalls.single.language, equals('he'));
      expect(fake.byNameCalls, hasLength(1));
      expect(fake.byNameCalls.single.query, equals('sushi'));
      expect(fake.byNameCalls.single.latitude, equals(32.1));
      expect(fake.byNameCalls.single.longitude, isNull);
      expect(fake.byNameCalls.single.language, equals('en'));
    });

    test('a blank query does not consume a queued result', () async {
      // Arrange
      final fake = FakeVenueSearchService()
        ..queueFailed(VenueSearchFailureReason.timeout);

      // Act
      final blank = await fake.byName('  ', language: 'en');
      final real = await fake.byName('pizza', language: 'en');

      // Assert
      expect(blank, equals(const VenuesFound(<Venue>[])));
      expect(
        real,
        equals(const VenueSearchFailed(VenueSearchFailureReason.timeout)),
      );
      expect(fake.byNameCalls, hasLength(2));
    });
  });

  group('VenuesFound value semantics', () {
    test('equal venue lists make two instances equal', () {
      // Arrange
      final a = VenuesFound(<Venue>[_venue('x')]);
      final b = VenuesFound(<Venue>[_venue('x')]);

      // Assert
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a.toString(), contains('1 venues'));
    });

    test('a differing list makes two instances unequal', () {
      // Arrange
      final a = VenuesFound(<Venue>[_venue('x')]);
      final b = VenuesFound(<Venue>[_venue('y')]);

      // Assert
      expect(a, isNot(equals(b)));
    });
  });

  group('VenueSearchFailed value semantics', () {
    test('equal fields make two instances equal', () {
      // Arrange
      const a = VenueSearchFailed(
        VenueSearchFailureReason.platformChanged,
        statusCode: 410,
      );
      const b = VenueSearchFailed(
        VenueSearchFailureReason.platformChanged,
        statusCode: 410,
      );

      // Assert
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a.toString(), contains('platformChanged'));
    });

    test('a differing reason or status makes two instances unequal', () {
      // Arrange
      const a = VenueSearchFailed(VenueSearchFailureReason.offline);
      const b = VenueSearchFailed(VenueSearchFailureReason.timeout);
      const c = VenueSearchFailed(
        VenueSearchFailureReason.offline,
        statusCode: 502,
      );

      // Assert
      expect(a, isNot(equals(b)));
      expect(a, isNot(equals(c)));
    });
  });
}

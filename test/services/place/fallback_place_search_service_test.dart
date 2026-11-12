import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/place.dart';
import 'package:ketoclub/services/place/fallback_place_search_service.dart';
import 'package:ketoclub/services/place/place_search_service.dart';

import '../../fakes/fake_place_search_service.dart';

const StreetPlace _fromBackend = StreetPlace(
  label: 'Herzl 10, Tel Aviv',
  latitude: 32.06,
  longitude: 34.77,
);

const StreetPlace _fromPhoton = StreetPlace(
  label: 'הרצל 10, תל אביב',
  latitude: 32.06,
  longitude: 34.77,
);

void main() {
  group('FallbackPlaceSearchService (issue #449)', () {
    late FakePlaceSearchService primary;
    late FakePlaceSearchService fallback;
    late FallbackPlaceSearchService service;

    setUp(() {
      primary = FakePlaceSearchService();
      fallback = FakePlaceSearchService();
      service = FallbackPlaceSearchService(
        primary: primary,
        fallback: fallback,
      );
    });

    test('a backend answer is the answer, and Photon is not asked', () async {
      // Arrange
      primary.queueFound(const <StreetPlace>[_fromBackend]);

      // Act
      final result = await service.search('herzl', language: 'en');

      // Assert
      expect(result, const PlacesFound(<StreetPlace>[_fromBackend]));
      expect(primary.calls, <PlaceSearchCall>[
        (query: 'herzl', language: 'en'),
      ]);
      expect(fallback.calls, isEmpty);
    });

    test('an empty backend answer is the answer too', () async {
      // Arrange
      primary.queueFound(const <StreetPlace>[]);

      // Act
      final result = await service.search('herzl', language: 'en');

      // Assert
      expect(result, const PlacesFound(<StreetPlace>[]));
      expect(fallback.calls, isEmpty);
    });

    for (final reason in <PlaceSearchFailureReason>[
      PlaceSearchFailureReason.backendUnreachable,
      PlaceSearchFailureReason.timeout,
      PlaceSearchFailureReason.rateLimited,
    ]) {
      test('asks Photon with the same query when the backend says '
          '${reason.name}', () async {
        // Arrange
        primary.queueFailed(reason);
        fallback.queueFound(const <StreetPlace>[_fromPhoton]);

        // Act
        final result = await service.search('הרצל', language: 'he');

        // Assert
        expect(result, const PlacesFound(<StreetPlace>[_fromPhoton]));
        expect(fallback.calls, <PlaceSearchCall>[
          (query: 'הרצל', language: 'he'),
        ]);
      });
    }

    for (final reason in <PlaceSearchFailureReason>[
      PlaceSearchFailureReason.offline,
      PlaceSearchFailureReason.providerChanged,
    ]) {
      test('keeps the backend answer ${reason.name} without asking '
          'Photon', () async {
        // Arrange
        primary.queueFailed(reason, statusCode: 502);

        // Act
        final result = await service.search('herzl', language: 'en');

        // Assert
        expect(result, PlaceSearchFailed(reason, statusCode: 502));
        expect(fallback.calls, isEmpty);
      });
    }

    test('reports the backend failure when Photon fails too', () async {
      // Arrange
      primary.queueFailed(PlaceSearchFailureReason.backendUnreachable);
      fallback.queueFailed(PlaceSearchFailureReason.offline);

      // Act
      final result = await service.search('herzl', language: 'en');

      // Assert
      expect(
        result,
        const PlaceSearchFailed(PlaceSearchFailureReason.backendUnreachable),
      );
      expect(fallback.calls, hasLength(1));
    });
  });
}

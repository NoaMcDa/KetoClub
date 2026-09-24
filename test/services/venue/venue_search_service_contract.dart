// The shared VenueSearchService contract (architecture.md §18.1, Liskov).
//
// Every implementation of VenueSearchService, including the fake in
// test/fakes/, runs this suite from its own test file, so none can drift
// from the interface's documented promises. The suite asserts shape and
// ordering only: it never assumes whether a given search succeeds.

import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/venue/venue_search_service.dart';
import 'package:ketoclub/utils/geo.dart';

/// The position every contract search is made from (Rabin Square, Tel
/// Aviv).
const double _latitude = 32.0809;

/// See [_latitude].
const double _longitude = 34.7806;

/// Asserts that [venues] are nearest first from the contract position,
/// with every unlocated venue after every located one.
void _expectNearestFirst(List<Venue> venues) {
  var seenUnlocated = false;
  var lastKm = -1.0;
  for (final venue in venues) {
    final lat = venue.latitude;
    final lon = venue.longitude;
    if (lat == null || lon == null) {
      seenUnlocated = true;
      continue;
    }
    expect(
      seenUnlocated,
      isFalse,
      reason: '${venue.ref} has a position but follows an unlocated venue',
    );
    final km = distanceKm(_latitude, _longitude, lat, lon);
    expect(
      km,
      greaterThanOrEqualTo(lastKm),
      reason: '${venue.ref} is nearer than the venue before it',
    );
    lastKm = km;
  }
}

/// Asserts that no two of [venues] share a [Venue.ref] and every one has
/// a non-empty name and platform id.
void _expectWellFormed(List<Venue> venues) {
  final refs = venues.map((v) => v.ref).toList();
  expect(refs.toSet(), hasLength(refs.length), reason: 'duplicate refs');
  for (final venue in venues) {
    expect(venue.name.trim(), isNotEmpty);
    expect(venue.ref.platformId, isNotEmpty);
  }
}

/// Asserts the [VenueSearchService] contract against what [build]
/// returns.
void runVenueSearchServiceContract(
  String name,
  VenueSearchService Function() build,
) {
  group(name, () {
    test('nearby never throws', () async {
      final service = build();
      late final Future<VenueSearchResult> future;
      expect(
        () => future = service.nearby(
          latitude: _latitude,
          longitude: _longitude,
          language: 'en',
        ),
        returnsNormally,
      );
      await expectLater(future, completes);
    });

    test('byName never throws, with or without a position', () async {
      final service = build();
      late final Future<VenueSearchResult> withPosition;
      late final Future<VenueSearchResult> without;
      expect(
        () => withPosition = service.byName(
          'pizza',
          latitude: _latitude,
          longitude: _longitude,
          language: 'he',
        ),
        returnsNormally,
      );
      expect(
        () => without = service.byName('pizza', language: 'en'),
        returnsNormally,
      );
      await expectLater(withPosition, completes);
      await expectLater(without, completes);
    });

    test('byName with a blank query finds nothing', () async {
      final service = build();
      for (final query in <String>['', '   ']) {
        final result = await service.byName(query, language: 'en');
        expect(result, equals(const VenuesFound(<Venue>[])));
      }
    });

    test('nearby returns well-formed venues, nearest first', () async {
      final service = build();
      final result = await service.nearby(
        latitude: _latitude,
        longitude: _longitude,
        language: 'en',
      );
      if (result is VenuesFound) {
        _expectWellFormed(result.venues);
        _expectNearestFirst(result.venues);
      }
    });

    test('byName with a position returns well-formed venues, nearest '
        'first', () async {
      final service = build();
      final result = await service.byName(
        'pizza',
        latitude: _latitude,
        longitude: _longitude,
        language: 'en',
      );
      if (result is VenuesFound) {
        _expectWellFormed(result.venues);
        _expectNearestFirst(result.venues);
      }
    });
  });
}

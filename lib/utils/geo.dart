/// Distances between points on the Earth, for nearby venue search
/// (`phase2_discovery_research.md` §5, issue #39).
///
/// Pure functions only. Distance is deliberately not a field on `Venue`:
/// it depends on where the user is, so it is computed from the search
/// position when shown, and a cached venue list stays valid when the user
/// moves.
library;

import 'dart:math' as math;

import 'package:ketoclub/models/venue.dart';

/// The Earth's mean radius in kilometres (IUGG), the radius the haversine
/// formula below assumes.
const double earthRadiusKm = 6371.0088;

/// The walking speed [walkingMinutes] assumes, in km/h — a common figure
/// for an unhurried adult pace.
const double walkingSpeedKmh = 5;

/// The great-circle distance in kilometres between two points given in
/// degrees, by the haversine formula.
///
/// Accurate to well under 1% at city scale, which is all a "nearest
/// first" list needs; the Earth's flattening is ignored.
double distanceKm(double lat1, double lon1, double lat2, double lon2) {
  final dLat = _radians(lat2 - lat1);
  final dLon = _radians(lon2 - lon1);
  final a =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(_radians(lat1)) *
          math.cos(_radians(lat2)) *
          math.pow(math.sin(dLon / 2), 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return earthRadiusKm * c;
}

/// How many whole minutes walking [km] takes at [walkingSpeedKmh],
/// rounded up so a venue 10 metres away is still "1 min", never "0 min".
///
/// The fallback for a card whose platform gave no delivery estimate of
/// its own (`phase2_discovery_research.md` §5); a caller must label it as
/// walking time. A negative distance is treated as zero.
int walkingMinutes(double km) {
  if (km <= 0) return 0;
  return (km / walkingSpeedKmh * 60).ceil();
}

/// [venues] reordered nearest first from ([latitude], [longitude]).
///
/// Venues without both coordinates cannot be placed, so they follow every
/// located venue. The sort is stable: two venues at the same distance,
/// and all the unlocated ones, keep the order the platform gave them,
/// which is its own relevance ranking. [venues] itself is not modified.
List<Venue> sortNearestFirst(
  List<Venue> venues, {
  required double latitude,
  required double longitude,
}) {
  final keyed =
      <({int index, double? km, Venue venue})>[
        for (var i = 0; i < venues.length; i++)
          (
            index: i,
            km: _distanceTo(venues[i], latitude, longitude),
            venue: venues[i],
          ),
      ]..sort((a, b) {
        final aKm = a.km;
        final bKm = b.km;
        if (aKm != null && bKm != null) {
          final byDistance = aKm.compareTo(bKm);
          if (byDistance != 0) return byDistance;
        } else if (aKm != null) {
          return -1;
        } else if (bKm != null) {
          return 1;
        }
        return a.index.compareTo(b.index);
      });
  return <Venue>[for (final entry in keyed) entry.venue];
}

/// The distance from ([latitude], [longitude]) to [venue], or null when
/// the venue has no position.
double? _distanceTo(Venue venue, double latitude, double longitude) {
  final venueLat = venue.latitude;
  final venueLon = venue.longitude;
  if (venueLat == null || venueLon == null) return null;
  return distanceKm(latitude, longitude, venueLat, venueLon);
}

double _radians(double degrees) => degrees * math.pi / 180;

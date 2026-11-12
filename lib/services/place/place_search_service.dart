import 'package:flutter/foundation.dart';
import 'package:ketoclub/models/place.dart';

/// The most matches a street search answers with (issue #449): the
/// backend's contract and the direct Photon client's own cap.
const int placeSearchMaxResults = 6;

/// The shortest query, after trimming, a street search sends; anything
/// shorter finds nothing with no request (the backend's own floor).
const int placeSearchMinQueryLength = 2;

/// The longest query a street search sends, in Unicode code points; a
/// longer one is cut to this (the backend's own ceiling).
const int placeSearchMaxQueryLength = 120;

/// Why a street search produced no list (issue #449).
///
/// Its own enum rather than a reuse of `VenueSearchFailureReason`: the
/// provider is a geocoder, not Wolt, and a street search has no
/// "blocked by the browser" case (Photon grants CORS to every origin).
/// Each reason has its own copy (`widgets/failure_copy.dart`), and
/// collapsing two of them into one message is the bug architecture.md
/// §10 names.
enum PlaceSearchFailureReason {
  /// No network route to the geocoder: a socket or DNS error on a direct
  /// call, or the backend's own `502 offline` saying it could not reach
  /// it.
  offline,

  /// The geocoder, or the backend on its way there, took longer than the
  /// search's time budget (a client-side timeout, or the backend's `504`).
  timeout,

  /// Too many street searches: the geocoder's or the backend's own `429`.
  rateLimited,

  /// A backend is configured and could not be reached at all — or none is
  /// configured, which a caller treats the same way.
  backendUnreachable,

  /// The geocoder, or the backend, answered something other than a list
  /// of places: an unexpected status or a body this app cannot read.
  providerChanged,
}

/// The result of a street search (issue #449).
///
/// Not constructed directly; use [PlacesFound] or [PlaceSearchFailed].
@immutable
sealed class PlaceSearchResult {
  /// Subclasses only.
  const new();
}

/// The search answered with places, possibly none.
@immutable
final class PlacesFound extends PlaceSearchResult {
  /// Creates a result carrying [places], already in display order.
  const new(this.places);

  /// The matches, at most [placeSearchMaxResults], no two with the same
  /// label, best first.
  final List<StreetPlace> places;

  @override
  bool operator ==(Object other) =>
      other is PlacesFound && listEquals(other.places, places);

  @override
  int get hashCode => Object.hashAll(places);

  @override
  String toString() => 'PlacesFound(${places.length} places)';
}

/// No list of places could be produced, for [reason].
@immutable
final class PlaceSearchFailed extends PlaceSearchResult {
  /// Creates a failed result for [reason]. [statusCode] is the HTTP
  /// status behind it when there was one, for diagnosis, never for the
  /// user.
  const new(this.reason, {this.statusCode});

  /// Why the search failed.
  final PlaceSearchFailureReason reason;

  /// The HTTP status code that triggered [reason], when there is one.
  final int? statusCode;

  @override
  bool operator ==(Object other) =>
      other is PlaceSearchFailed &&
      other.reason == reason &&
      other.statusCode == statusCode;

  @override
  int get hashCode => Object.hash(reason, statusCode);

  @override
  String toString() => 'PlaceSearchFailed($reason)';
}

/// Turns what the user typed into streets in Israel (issue #449,
/// architecture.md D28).
///
/// One call per explicit "Search streets" tap, never per keystroke: the
/// text goes to an outside geocoder, so it leaves the device only when
/// the user asked for that. Nothing in this interface throws across its
/// boundary: every failure is a [PlaceSearchFailed].
abstract interface class PlaceSearchService {
  /// The streets and addresses matching [query], best first.
  ///
  /// [language] is the UI language code (`en`, `he`) the labels should be
  /// written in where the geocoder has a choice. A query shorter than
  /// [placeSearchMinQueryLength] once trimmed finds nothing and sends no
  /// request. Never throws.
  Future<PlaceSearchResult> search(String query, {required String language});
}

/// [query] trimmed and cut to [placeSearchMaxQueryLength] code points, or
/// null when it is shorter than [placeSearchMinQueryLength] once trimmed.
/// The rule every [PlaceSearchService] applies before it sends anything.
String? placeSearchQuery(String query) {
  final trimmed = query.trim();
  final runes = trimmed.runes;
  if (runes.length < placeSearchMinQueryLength) return null;
  if (runes.length <= placeSearchMaxQueryLength) return trimmed;
  return String.fromCharCodes(runes.take(placeSearchMaxQueryLength)).trim();
}

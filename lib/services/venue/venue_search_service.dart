import 'package:flutter/foundation.dart';
import 'package:ketoclub/models/venue.dart';

/// Why a venue search produced no list (`phase2_discovery_research.md`
/// §5, issue #39).
///
/// Deliberately its own enum rather than a reuse of
/// `MenuFetchFailureReason`: a search has no single venue to be "not
/// found", and a slow answer is worth telling apart from no network, so
/// the two sets of reasons differ even where the names overlap. Each
/// reason has its own copy (`widgets/failure_copy.dart`), and collapsing
/// two of them into one message is the bug architecture.md §10 names.
enum VenueSearchFailureReason {
  /// No network route to the platform: a socket or DNS error on a direct
  /// call, or the backend's own `502` saying it could not reach Wolt.
  offline,

  /// The platform took longer than the search's time budget to answer,
  /// or the backend's own `504` saying Wolt timed out.
  timeout,

  /// The platform throttled the search (HTTP `429`). Wolt throttles
  /// bursty callers, so waiting and retrying is the way out.
  rateLimited,

  /// The platform answered, but not with a venue list: any other non-2xx
  /// status (Wolt's `410`/`430` "update the app" among them), or a 2xx
  /// body that is not the page shape the mapper reads.
  platformChanged,

  /// The search would have run in a browser with no backend configured.
  /// Wolt's discovery endpoints only grant CORS to wolt.com itself, so
  /// no request is even attempted; the way out is the phone app.
  blockedByBrowser,

  /// A backend is configured and could not be reached at all — a socket
  /// or DNS error talking to KetoClub's own server, never a status Wolt
  /// returned.
  backendUnreachable,
}

/// The result of a venue search (`phase2_discovery_research.md` §5).
///
/// Not constructed directly; use [VenuesFound] or [VenueSearchFailed].
@immutable
sealed class VenueSearchResult {
  /// Subclasses only.
  const new();
}

/// The platform answered with a venue list, possibly empty.
@immutable
final class VenuesFound extends VenueSearchResult {
  /// Creates a result carrying [venues], already in display order.
  const new(this.venues);

  /// The venues, deduplicated by [Venue.ref] and in the order the search
  /// promises (nearest first when it was given a position).
  final List<Venue> venues;

  @override
  bool operator ==(Object other) =>
      other is VenuesFound && listEquals(other.venues, venues);

  @override
  int get hashCode => Object.hashAll(venues);

  @override
  String toString() => 'VenuesFound(${venues.length} venues)';
}

/// No venue list could be produced, for [reason].
@immutable
final class VenueSearchFailed extends VenueSearchResult {
  /// Creates a failed result for [reason]. [statusCode] is the HTTP
  /// status behind [VenueSearchFailureReason.platformChanged] when there
  /// was one, so a schema drift is diagnosable from a log.
  const new(this.reason, {this.statusCode});

  /// Why the search failed.
  final VenueSearchFailureReason reason;

  /// The HTTP status code that triggered [reason], when there is one.
  final int? statusCode;

  @override
  bool operator ==(Object other) =>
      other is VenueSearchFailed &&
      other.reason == reason &&
      other.statusCode == statusCode;

  @override
  int get hashCode => Object.hash(reason, statusCode);

  @override
  String toString() => 'VenueSearchFailed($reason)';
}

/// Finds venues near a position or by name (`phase2_discovery_research.md`
/// §5, issue #39).
///
/// One call per user action — a "near me" or a submitted query — and
/// never a fan-out over venues (`phase2_discovery_research.md` §2.3).
/// Nothing in this interface throws across its boundary: every failure is
/// a [VenueSearchFailed].
abstract interface class VenueSearchService {
  /// The venues around ([latitude], [longitude]), nearest first.
  ///
  /// [language] is the UI language code (`en`, `he`) the platform should
  /// name and describe venues in. Venues without a position follow every
  /// located one. Never throws.
  Future<VenueSearchResult> nearby({
    required double latitude,
    required double longitude,
    required String language,
  });

  /// The venues whose name matches [query].
  ///
  /// When both [latitude] and [longitude] are given, the platform ranks
  /// by proximity to them and the result is nearest first; otherwise the
  /// platform's own order is kept. A blank [query] finds nothing and
  /// sends no request. [language] is as for [nearby]. Never throws.
  Future<VenueSearchResult> byName(
    String query, {
    required String language,
    double? latitude,
    double? longitude,
  });
}

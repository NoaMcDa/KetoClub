import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/venue/venue_search_service.dart';

/// One call [FakeVenueSearchService.nearby] received.
typedef NearbyCall = ({double latitude, double longitude, String language});

/// One call [FakeVenueSearchService.byName] received.
typedef ByNameCall = ({
  String query,
  double? latitude,
  double? longitude,
  String language,
});

/// A scripted [VenueSearchService] for tests.
///
/// With nothing queued, both searches stand in for a working search that
/// found nothing: [VenuesFound] with an empty list. Queue a result with
/// [queueResult], [queueFound] or [queueFailed] to stand in for a real
/// list, a throttled search or an offline device instead: queued results
/// are returned in order, shared by both entry points, and the last one
/// queued then sticks for every call after the queue drains. Every call
/// is recorded in [nearbyCalls] or [byNameCalls].
///
/// A blank query to [byName] is recorded but answers an empty
/// [VenuesFound] without consuming the queue, as the interface promises.
/// Queued venues are returned exactly as given; a test that wants the
/// nearest-first order the interface promises queues them in that order.
class FakeVenueSearchService implements VenueSearchService {
  /// Creates a fake that finds nothing until scripted.
  new();

  final List<VenueSearchResult> _queue = <VenueSearchResult>[];

  VenueSearchResult _sticky = const VenuesFound(<Venue>[]);

  /// Every [nearby] call, in call order.
  final List<NearbyCall> nearbyCalls = <NearbyCall>[];

  /// Every [byName] call, in call order.
  final List<ByNameCall> byNameCalls = <ByNameCall>[];

  /// Queues [result] to be returned starting with the next search.
  void queueResult(VenueSearchResult result) => _queue.add(result);

  /// Queues a [VenuesFound] carrying [venues].
  void queueFound(List<Venue> venues) => queueResult(VenuesFound(venues));

  /// Queues a [VenueSearchFailed] for [reason].
  void queueFailed(VenueSearchFailureReason reason, {int? statusCode}) =>
      queueResult(VenueSearchFailed(reason, statusCode: statusCode));

  @override
  Future<VenueSearchResult> nearby({
    required double latitude,
    required double longitude,
    required String language,
  }) async {
    nearbyCalls.add((
      latitude: latitude,
      longitude: longitude,
      language: language,
    ));
    return _next();
  }

  @override
  Future<VenueSearchResult> byName(
    String query, {
    required String language,
    double? latitude,
    double? longitude,
  }) async {
    byNameCalls.add((
      query: query,
      latitude: latitude,
      longitude: longitude,
      language: language,
    ));
    // The interface's promise: a blank query finds nothing. It does not
    // consume a queued result.
    if (query.trim().isEmpty) return const VenuesFound(<Venue>[]);
    return _next();
  }

  VenueSearchResult _next() {
    if (_queue.isNotEmpty) _sticky = _queue.removeAt(0);
    return _sticky;
  }
}

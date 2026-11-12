import 'package:ketoclub/models/place.dart';
import 'package:ketoclub/services/place/place_search_service.dart';

/// One call [FakePlaceSearchService.search] received.
typedef PlaceSearchCall = ({String query, String language});

/// A scripted [PlaceSearchService] for tests (issue #449).
///
/// With nothing queued, a search stands in for a working one that found
/// nothing: an empty [PlacesFound]. Queue a result with [queueResult],
/// [queueFound] or [queueFailed]; queued results are returned in order,
/// and the last one queued then sticks for every call after the queue
/// drains. Every call is recorded in [calls].
///
/// A query shorter than [placeSearchMinQueryLength] once trimmed is
/// recorded but answers an empty [PlacesFound] without consuming the
/// queue, as the interface promises.
class FakePlaceSearchService implements PlaceSearchService {
  /// Creates a fake that finds nothing until scripted.
  new();

  final List<PlaceSearchResult> _queue = <PlaceSearchResult>[];

  PlaceSearchResult _sticky = const PlacesFound(<StreetPlace>[]);

  /// Every [search] call, in call order.
  final List<PlaceSearchCall> calls = <PlaceSearchCall>[];

  /// When non-null, every [search] waits for this future before it
  /// answers, so a test can look at the picker while a search is in
  /// flight.
  Future<void>? gate;

  /// Queues [result] to be returned starting with the next search.
  void queueResult(PlaceSearchResult result) => _queue.add(result);

  /// Queues a [PlacesFound] carrying [places].
  void queueFound(List<StreetPlace> places) => queueResult(PlacesFound(places));

  /// Queues a [PlaceSearchFailed] for [reason].
  void queueFailed(PlaceSearchFailureReason reason, {int? statusCode}) =>
      queueResult(PlaceSearchFailed(reason, statusCode: statusCode));

  @override
  Future<PlaceSearchResult> search(
    String query, {
    required String language,
  }) async {
    calls.add((query: query, language: language));
    if (placeSearchQuery(query) == null) {
      return const PlacesFound(<StreetPlace>[]);
    }
    final pending = gate;
    if (pending != null) await pending;
    if (_queue.isNotEmpty) _sticky = _queue.removeAt(0);
    return _sticky;
  }
}

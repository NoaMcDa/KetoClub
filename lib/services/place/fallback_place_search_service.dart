import 'package:ketoclub/services/place/place_search_service.dart';

/// Asks [primary] (KetoClub's backend) first and [fallback] (Photon,
/// directly) when the backend could not answer (issue #449,
/// architecture.md D28), as the D25 fallback chains do.
///
/// Falls through on [PlaceSearchFailureReason.backendUnreachable],
/// [PlaceSearchFailureReason.timeout] and
/// [PlaceSearchFailureReason.rateLimited] only — the reasons that say the
/// backend, not the geocoder, is the problem. `offline` and
/// `providerChanged` are an answer about the geocoder, reported through
/// the backend, and are the primary's. A success, empty or not, is the
/// primary's too. If the fallback also fails, the primary's failure is
/// reported, since it is the one the build's configuration chose.
final class FallbackPlaceSearchService implements PlaceSearchService {
  /// Creates a service that tries [primary], then [fallback].
  const new({required this.primary, required this.fallback});

  /// The service asked first.
  final PlaceSearchService primary;

  /// The service asked when [primary] could not answer.
  final PlaceSearchService fallback;

  @override
  Future<PlaceSearchResult> search(
    String query, {
    required String language,
  }) async {
    final first = await primary.search(query, language: language);
    switch (first) {
      case PlacesFound():
        return first;
      case PlaceSearchFailed(:final reason):
        if (!_fallsThrough(reason)) return first;
    }
    final second = await fallback.search(query, language: language);
    return second is PlacesFound ? second : first;
  }

  /// Whether a primary failure for [reason] is worth asking [fallback]
  /// about. An exhaustive switch with no `default`: a new reason has to
  /// be put on one side deliberately.
  static bool _fallsThrough(PlaceSearchFailureReason reason) =>
      switch (reason) {
        PlaceSearchFailureReason.backendUnreachable ||
        PlaceSearchFailureReason.timeout ||
        PlaceSearchFailureReason.rateLimited => true,
        PlaceSearchFailureReason.offline ||
        PlaceSearchFailureReason.providerChanged => false,
      };
}

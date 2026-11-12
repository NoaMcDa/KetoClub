import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:ketoclub/models/place.dart';
import 'package:ketoclub/services/llm/backend_chat_client.dart';
import 'package:ketoclub/services/place/place_search_service.dart';
import 'package:ketoclub/services/storage/install_id_store.dart';

/// Searches for streets through KetoClub's own backend (issue #449,
/// architecture.md D27): `POST /v1/places/search`, which asks Photon on
/// the server and maps its reply by the same rules as
/// `PhotonPlaceMapper`.
///
/// Sends `{query, language}` and KetoClub's install id header (the
/// route's rate-limit key), exactly as `BackendVenueSearchService` does,
/// and never a key or an `Authorization` header. The backend answers
/// `{places: [{label, city, latitude, longitude}]}`, at most six.
///
/// Failure mapping (the backend's own errors are `{reason, status_code}`):
///
/// - [baseUrl] null, a `ClientException`, `404` (a backend without the
///   route: older, or with `PLACE_SEARCH_ENABLED` off) or `400` (the
///   route's `badResponse` for a missing install id):
///   [PlaceSearchFailureReason.backendUnreachable], with no I/O for the
///   first. Each says the backend, not the geocoder, could not answer, so
///   it is what `FallbackPlaceSearchService` falls through to Photon on —
///   the same reading `BackendVenueSearchService` gives such statuses.
/// - `429`: [PlaceSearchFailureReason.rateLimited]; `504` and a
///   client-side timeout: [PlaceSearchFailureReason.timeout].
/// - `502` with reason `offline`: [PlaceSearchFailureReason.offline].
/// - Anything else — `502 providerChanged`, any other status, a 2xx body
///   without a `places` list, or an element that is not an object:
///   [PlaceSearchFailureReason.providerChanged]. An element that is an
///   object without a usable label and coordinates is skipped.
final class BackendPlaceSearchService implements PlaceSearchService {
  /// Creates a service that sends its requests through [client] to
  /// [baseUrl]; a null [baseUrl] means this build has no backend.
  ///
  /// [installIdStore] is read per request, never at construction.
  new({
    required http.Client client,
    required this.baseUrl,
    required InstallIdStore installIdStore,
    this.timeout = const Duration(seconds: 15),
  })
    // The fields are private and the parameters are not, so initializing
    // formals are not available.
    // ignore: prefer_initializing_formals
    : _client = client,
       // Same reason as above.
       // ignore: prefer_initializing_formals
       _installIdStore = installIdStore;

  /// KetoClub's backend, or null when this build has none.
  final Uri? baseUrl;

  /// How long a search waits for an answer before reporting
  /// [PlaceSearchFailureReason.timeout]: longer than the backend's own
  /// budget for Photon, so the backend's `504` arrives first.
  final Duration timeout;

  final http.Client _client;
  final InstallIdStore _installIdStore;

  static const PlaceSearchFailed _unreachable = PlaceSearchFailed(
    PlaceSearchFailureReason.backendUnreachable,
  );

  @override
  Future<PlaceSearchResult> search(
    String query, {
    required String language,
  }) async {
    final q = placeSearchQuery(query);
    if (q == null) return const PlacesFound(<StreetPlace>[]);
    final base = baseUrl;
    if (base == null) return _unreachable;
    final installId = await _installIdStore.id();
    final http.Response response;
    try {
      response = await _client
          .post(
            _uri(base, '/v1/places/search'),
            headers: <String, String>{
              'Accept': 'application/json',
              'Content-Type': 'application/json',
              BackendChatClient.installIdHeader: installId,
            },
            body: jsonEncode(<String, Object?>{
              'query': q,
              'language': language == 'he' ? 'he' : 'en',
            }),
          )
          .timeout(timeout);
    } on http.ClientException {
      return _unreachable;
    } on TimeoutException {
      return const PlaceSearchFailed(PlaceSearchFailureReason.timeout);
    }

    final status = response.statusCode;
    if (status == 404 || status == 400) {
      return PlaceSearchFailed(
        PlaceSearchFailureReason.backendUnreachable,
        statusCode: status,
      );
    }
    if (status == 429) {
      return const PlaceSearchFailed(
        PlaceSearchFailureReason.rateLimited,
        statusCode: 429,
      );
    }
    if (status == 504) {
      return const PlaceSearchFailed(
        PlaceSearchFailureReason.timeout,
        statusCode: 504,
      );
    }
    if (status == 502 && _errorReason(response.bodyBytes) == 'offline') {
      return const PlaceSearchFailed(
        PlaceSearchFailureReason.offline,
        statusCode: 502,
      );
    }
    if (status < 200 || status >= 300) {
      return PlaceSearchFailed(
        PlaceSearchFailureReason.providerChanged,
        statusCode: status,
      );
    }
    final places = _places(response.bodyBytes);
    if (places == null) {
      return const PlaceSearchFailed(PlaceSearchFailureReason.providerChanged);
    }
    return PlacesFound(List<StreetPlace>.unmodifiable(places));
  }

  /// The places in a 2xx [body], or null when it is not the contract's
  /// `{places: [...]}`.
  static List<StreetPlace>? _places(List<int> body) {
    final decoded = _decode(body);
    if (decoded is! Map<String, Object?>) return null;
    final raw = decoded['places'];
    if (raw is! List<Object?>) return null;
    final places = <StreetPlace>[];
    final seen = <String>{};
    for (final element in raw) {
      if (element is! Map<String, Object?>) return null;
      final place = StreetPlace.tryFrom(element);
      if (place == null || !seen.add(place.label)) continue;
      places.add(place);
      if (places.length == placeSearchMaxResults) break;
    }
    return places;
  }

  /// The `reason` of the backend's `{reason, status_code}` error [body],
  /// or null when it is not one.
  static String? _errorReason(List<int> body) {
    final decoded = _decode(body);
    if (decoded is! Map<String, Object?>) return null;
    final reason = decoded['reason'];
    return reason is String ? reason : null;
  }

  /// [body] decoded as UTF-8 JSON, or null when it is not. The backend
  /// sends `application/json` with no charset, which `Response.body` would
  /// read as Latin-1.
  static Object? _decode(List<int> body) {
    try {
      return jsonDecode(utf8.decode(body));
    } on FormatException {
      return null;
    }
  }

  /// [base] with [path] appended, whether or not [base] ends with a
  /// slash.
  static Uri _uri(Uri base, String path) {
    final rendered = base.toString();
    final trimmed = rendered.endsWith('/')
        ? rendered.substring(0, rendered.length - 1)
        : rendered;
    return Uri.parse('$trimmed$path');
  }
}

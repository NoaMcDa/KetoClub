import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/llm/backend_chat_client.dart';
import 'package:ketoclub/services/storage/install_id_store.dart';
import 'package:ketoclub/services/venue/venue_search_service.dart';
import 'package:ketoclub/utils/constants.dart';
import 'package:ketoclub/utils/geo.dart';

/// Searches for venues through KetoClub's own backend
/// (architecture.md D25, issue #329): `GET /v1/venues/nearby` and
/// `POST /v1/venues/search`.
///
/// The backend answers with normalised venues (`backend_plan.md` §3.3,
/// `{venues: [Venue JSON]}`, the Dart `Venue.toJson` shape, in Wolt's
/// order), so this class does no mapping beyond [Venue.tryFrom]. It sends
/// KetoClub's install id (the discovery bucket's limiter key) and nothing
/// else identifying, and sorts nearest first on the device exactly as
/// `WoltVenueSearchService` does.
///
/// Failure mapping (the backend's own errors are `{reason, status_code}`):
///
/// - [baseUrl] null: [VenueSearchFailureReason.backendUnreachable] at once,
///   with no I/O. "No backend" is the same situation to a caller as "the
///   backend is down", and it is the reason [FallbackVenueSearchService]
///   falls through on.
/// - `ClientException`, or any status the backend cannot have originated
///   for a well-formed request (400, 422, other 5xx, an unreadable 502
///   body): [VenueSearchFailureReason.backendUnreachable], the status kept.
/// - `429`: [VenueSearchFailureReason.rateLimited]; `504` and a client-side
///   timeout: [VenueSearchFailureReason.timeout].
/// - `502`: the body's `reason` names the cause, `offline` or
///   `platformChanged`; anything else is `backendUnreachable` (the contract
///   was broken, which is the backend's fault, not Wolt's).
/// - a 2xx whose `venues` is missing, not a list, or has an element that is
///   not an object: [VenueSearchFailureReason.platformChanged]. An element
///   [Venue.tryFrom] rejects is skipped.
final class BackendVenueSearchService implements VenueSearchService {
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
  /// [VenueSearchFailureReason.timeout].
  final Duration timeout;

  final http.Client _client;
  final InstallIdStore _installIdStore;

  @override
  Future<VenueSearchResult> nearby({
    required double latitude,
    required double longitude,
    required String language,
  }) async {
    final base = baseUrl;
    if (base == null) return _notConfigured;
    final uri = _uri(base, '/v1/venues/nearby').replace(
      queryParameters: <String, String>{
        'lat': '$latitude',
        'lon': '$longitude',
        'lang': language,
      },
    );
    final installId = await _installIdStore.id();
    final result = await _send(
      () => _client.get(uri, headers: _headers(installId, isPost: false)),
    );
    return _sorted(result, latitude, longitude);
  }

  @override
  Future<VenueSearchResult> byName(
    String query, {
    required String language,
    double? latitude,
    double? longitude,
  }) async {
    final q = _clip(query.trim());
    if (q.isEmpty) return const VenuesFound(<Venue>[]);
    final base = baseUrl;
    if (base == null) return _notConfigured;
    final hasPosition = latitude != null && longitude != null;
    final body = <String, Object?>{
      'query': q,
      'lang': language,
      if (hasPosition) 'lat': latitude,
      if (hasPosition) 'lon': longitude,
    };
    final uri = _uri(base, '/v1/venues/search');
    final installId = await _installIdStore.id();
    final result = await _send(
      () => _client.post(
        uri,
        headers: _headers(installId, isPost: true),
        body: jsonEncode(body),
      ),
    );
    if (latitude == null || longitude == null) return result;
    return _sorted(result, latitude, longitude);
  }

  static const VenueSearchFailed _notConfigured = VenueSearchFailed(
    VenueSearchFailureReason.backendUnreachable,
  );

  static Map<String, String> _headers(
    String installId, {
    required bool isPost,
  }) => <String, String>{
    'Accept': 'application/json',
    if (isPost) 'Content-Type': 'application/json',
    BackendChatClient.installIdHeader: installId,
  };

  /// Sends one request and maps every outcome to a result. Never throws.
  Future<VenueSearchResult> _send(
    Future<http.Response> Function() request,
  ) async {
    final http.Response response;
    try {
      response = await request().timeout(timeout);
    } on http.ClientException {
      return _notConfigured;
    } on TimeoutException {
      return const VenueSearchFailed(VenueSearchFailureReason.timeout);
    }

    final status = response.statusCode;
    if (status == 429) {
      return const VenueSearchFailed(VenueSearchFailureReason.rateLimited);
    }
    if (status == 504) {
      return const VenueSearchFailed(VenueSearchFailureReason.timeout);
    }
    if (status == 502) {
      return switch (_errorReason(response.body)) {
        'offline' => const VenueSearchFailed(VenueSearchFailureReason.offline),
        'platformChanged' => VenueSearchFailed(
          VenueSearchFailureReason.platformChanged,
          statusCode: status,
        ),
        _ => VenueSearchFailed(
          VenueSearchFailureReason.backendUnreachable,
          statusCode: status,
        ),
      };
    }
    if (status < 200 || status >= 300) {
      return VenueSearchFailed(
        VenueSearchFailureReason.backendUnreachable,
        statusCode: status,
      );
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      return const VenueSearchFailed(VenueSearchFailureReason.platformChanged);
    }
    final rawVenues = decoded is Map<String, Object?>
        ? decoded['venues']
        : null;
    if (rawVenues is! List<Object?>) {
      return const VenueSearchFailed(VenueSearchFailureReason.platformChanged);
    }
    final venues = <Venue>[];
    final seen = <VenueRef>{};
    for (final raw in rawVenues) {
      if (raw is! Map<String, Object?>) {
        return const VenueSearchFailed(
          VenueSearchFailureReason.platformChanged,
        );
      }
      final venue = Venue.tryFrom(raw);
      if (venue != null && seen.add(venue.ref)) venues.add(venue);
    }
    return VenuesFound(List<Venue>.unmodifiable(venues));
  }

  /// The `reason` of the backend's `{reason, status_code}` error body, or
  /// null when [body] is not one.
  static String? _errorReason(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, Object?>) {
        final reason = decoded['reason'];
        if (reason is String) return reason;
      }
    } on FormatException {
      return null;
    }
    return null;
  }

  /// [result] with its venues nearest first from ([latitude],
  /// [longitude]); a failure is returned unchanged.
  static VenueSearchResult _sorted(
    VenueSearchResult result,
    double latitude,
    double longitude,
  ) => switch (result) {
    VenuesFound(:final venues) => VenuesFound(
      List<Venue>.unmodifiable(
        sortNearestFirst(venues, latitude: latitude, longitude: longitude),
      ),
    ),
    VenueSearchFailed() => result,
  };

  /// [query] cut to [venueSearchMaxQueryLength] characters (Unicode code
  /// points, as the backend counts them).
  static String _clip(String query) {
    final runes = query.runes;
    if (runes.length <= venueSearchMaxQueryLength) return query;
    return String.fromCharCodes(runes.take(venueSearchMaxQueryLength)).trim();
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

/// Asks [primary] (the backend) first and [fallback] (the direct Wolt
/// search) when the primary could not be used (issue #329).
///
/// Falls through on [VenueSearchFailureReason.backendUnreachable],
/// [VenueSearchFailureReason.timeout] and
/// [VenueSearchFailureReason.rateLimited] — the reasons that say the
/// backend, not the platform, is the problem. Any other result, success
/// or failure (`offline`, `platformChanged`: the backend reached Wolt and
/// that is what Wolt did), is the primary's. If the fallback fails too,
/// the primary's failure is reported, since it is the one the user's
/// configuration chose.
final class FallbackVenueSearchService implements VenueSearchService {
  /// Creates a service that tries [primary], then [fallback].
  const new({required this.primary, required this.fallback});

  /// The service asked first.
  final VenueSearchService primary;

  /// The service asked when [primary] fails for a reason in
  /// [_fallThrough].
  final VenueSearchService fallback;

  static const Set<VenueSearchFailureReason> _fallThrough =
      <VenueSearchFailureReason>{
        VenueSearchFailureReason.backendUnreachable,
        VenueSearchFailureReason.timeout,
        VenueSearchFailureReason.rateLimited,
      };

  @override
  Future<VenueSearchResult> nearby({
    required double latitude,
    required double longitude,
    required String language,
  }) async {
    final first = await primary.nearby(
      latitude: latitude,
      longitude: longitude,
      language: language,
    );
    if (!_shouldFallBack(first)) return first;
    final second = await fallback.nearby(
      latitude: latitude,
      longitude: longitude,
      language: language,
    );
    return second is VenuesFound ? second : first;
  }

  @override
  Future<VenueSearchResult> byName(
    String query, {
    required String language,
    double? latitude,
    double? longitude,
  }) async {
    final first = await primary.byName(
      query,
      language: language,
      latitude: latitude,
      longitude: longitude,
    );
    if (!_shouldFallBack(first)) return first;
    final second = await fallback.byName(
      query,
      language: language,
      latitude: latitude,
      longitude: longitude,
    );
    return second is VenuesFound ? second : first;
  }

  static bool _shouldFallBack(VenueSearchResult result) =>
      result is VenueSearchFailed && _fallThrough.contains(result.reason);
}

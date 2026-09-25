import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/llm/backend_chat_client.dart';
import 'package:ketoclub/services/storage/install_id_store.dart';
import 'package:ketoclub/services/venue/venue_search_service.dart';
import 'package:ketoclub/services/venue/wolt/wolt_venue_mapper.dart';
import 'package:ketoclub/utils/constants.dart';
import 'package:ketoclub/utils/geo.dart';
import 'package:ketoclub/utils/wolt_headers.dart';

/// Searches Wolt's discovery endpoints for venues
/// (`phase2_discovery_research.md` §2, §5, issue #39).
///
/// This class does HTTP and the failure mapping only; turning a page into
/// venues is entirely [WoltVenueMapper]'s job, so a change to Wolt's JSON
/// shape never touches this file.
///
/// Routing follows `WoltMenuAdapter` (architecture.md §13, D11):
///
/// - [proxyBase] null, native: straight to Wolt —
///   `GET consumer-api.wolt.com/v1/pages/restaurants?lat=&lon=` and
///   `POST restaurant-api.wolt.com/v1/pages/search` — with the header set
///   wolt.com itself sends (§2.2), including a browser `User-Agent`.
/// - [proxyBase] set: KetoClub's backend at
///   `{proxyBase}/v1/proxy/wolt/pages/restaurants?lat=&lon=&lang=` and
///   `POST {proxyBase}/v1/proxy/wolt/pages/search` (§3). The backend
///   builds Wolt's headers itself, so none are sent from here — only
///   KetoClub's own install id, which both discovery routes require for
///   their per-install rate limit (a request without it is refused with
///   `400 badResponse`, `backend/app/routers/discovery.py`).
/// - [proxyBase] null in a browser: Wolt grants CORS only to wolt.com, so
///   the request could never succeed; it is not sent, and the search
///   answers [VenueSearchFailureReason.blockedByBrowser] at once.
final class WoltVenueSearchService implements VenueSearchService {
  /// Creates a service that sends its requests through [client].
  ///
  /// [runsInBrowser] defaults to [kIsWeb] and exists so a test can
  /// exercise the browser rule on any platform. [random] is the source of
  /// the per-instance web client id and defaults to [Random.secure];
  /// nothing is drawn from it until the first direct request, so the
  /// constructor performs no work at all.
  new({
    required http.Client client,
    this.proxyBase,
    this.runsInBrowser = kIsWeb,
    Random? random,
    InstallIdStore? installIdStore,
  })
    // The fields are private and the parameters are not, so initializing
    // formals are not available.
    // ignore: prefer_initializing_formals
    : _client = client,
       // Same reason as above: a private field, a public parameter name.
       // ignore: prefer_initializing_formals
       _random = random,
       // Same reason as above.
       // ignore: prefer_initializing_formals
       _installIdStore = installIdStore;

  /// How long a search waits for an answer before reporting
  /// [VenueSearchFailureReason.timeout]; the same budget as the menu
  /// adapter's.
  static const Duration _timeout = Duration(seconds: 15);

  final http.Client _client;

  final Random? _random;

  /// Where the `X-KetoClub-Install-Id` header's value comes from on a
  /// request through [proxyBase] — the same store, and the same header,
  /// `BackendChatClient` uses. Null sends no install id (a direct call
  /// never sends one: it is for KetoClub's backend and nowhere else,
  /// D12).
  final InstallIdStore? _installIdStore;

  /// The install id to send with a proxied request, or null for a direct
  /// one. Read per request, like `BackendChatClient`'s, so the first read
  /// — which touches plugin storage — never happens at construction.
  Future<String?> _installId() async {
    if (proxyBase == null) return null;
    return await _installIdStore?.id();
  }

  /// KetoClub's own backend, when searches go through it rather than
  /// straight to Wolt. Null means direct.
  final Uri? proxyBase;

  /// Whether requests would go out through a browser, where a direct call
  /// to Wolt is refused by CORS.
  final bool runsInBrowser;

  /// The `x-wolt-web-clientid` value: a random UUID generated once per
  /// service instance, the way wolt.com keeps one per browser.
  ///
  /// Deliberately **not** KetoClub's install id, which is sent to
  /// KetoClub's backend and nowhere else (D12,
  /// `phase2_discovery_research.md` §2.2).
  late final String _webClientId = woltWebClientId(_random ?? Random.secure());

  @override
  Future<VenueSearchResult> nearby({
    required double latitude,
    required double longitude,
    required String language,
  }) async {
    final proxyBase = this.proxyBase;
    if (proxyBase == null && runsInBrowser) {
      return const VenueSearchFailed(VenueSearchFailureReason.blockedByBrowser);
    }
    final Uri uri;
    if (proxyBase != null) {
      uri = _proxyUri(proxyBase, 'restaurants').replace(
        queryParameters: <String, String>{
          'lat': '$latitude',
          'lon': '$longitude',
          'lang': language,
        },
      );
    } else {
      uri = Uri.https('consumer-api.wolt.com', '/v1/pages/restaurants', {
        'lat': '$latitude',
        'lon': '$longitude',
      });
    }
    final installId = await _installId();
    final result = await _send(
      () => _client.get(
        uri,
        headers: _headers(language, isPost: false, installId: installId),
      ),
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
    final proxyBase = this.proxyBase;
    if (proxyBase == null && runsInBrowser) {
      return const VenueSearchFailed(VenueSearchFailureReason.blockedByBrowser);
    }
    final hasPosition = latitude != null && longitude != null;
    final body = <String, Object?>{
      'q': q,
      if (proxyBase == null) 'target': 'venues',
      if (hasPosition) 'lat': latitude,
      if (hasPosition) 'lon': longitude,
      if (proxyBase != null) 'lang': language,
    };
    final uri = proxyBase != null
        ? _proxyUri(proxyBase, 'search')
        : Uri.https('restaurant-api.wolt.com', '/v1/pages/search');
    final installId = await _installId();
    final result = await _send(
      () => _client.post(
        uri,
        headers: _headers(language, isPost: true, installId: installId),
        body: jsonEncode(body),
      ),
    );
    if (latitude == null || longitude == null) return result;
    return _sorted(result, latitude, longitude);
  }

  /// The request headers: §2.2's web set ([woltWebHeaders]) on a direct
  /// call, only `Accept`/`Content-Type` and the [installId] through the
  /// proxy, which sets Wolt's headers itself and must receive nothing it
  /// would have to strip.
  Map<String, String> _headers(
    String language, {
    required bool isPost,
    String? installId,
  }) => <String, String>{
    'Accept': 'application/json',
    if (isPost) 'Content-Type': 'application/json',
    BackendChatClient.installIdHeader: ?installId,
    // A direct call only ever happens natively (a browser is refused
    // above), where the User-Agent is ours to set.
    if (proxyBase == null)
      ...woltWebHeaders(language: language, webClientId: _webClientId),
  };

  /// Sends one request and maps every outcome to a result. Never throws.
  Future<VenueSearchResult> _send(
    Future<http.Response> Function() request,
  ) async {
    final http.Response response;
    try {
      response = await request().timeout(_timeout);
    } on http.ClientException {
      return VenueSearchFailed(
        proxyBase != null
            ? VenueSearchFailureReason.backendUnreachable
            : VenueSearchFailureReason.offline,
      );
    } on TimeoutException {
      return const VenueSearchFailed(VenueSearchFailureReason.timeout);
    }

    final statusCode = response.statusCode;
    if (proxyBase != null && statusCode == 502) {
      // The backend's own "Wolt was unreachable" (§3).
      return const VenueSearchFailed(VenueSearchFailureReason.offline);
    }
    if (proxyBase != null && statusCode == 504) {
      // The backend's own "Wolt timed out" (§3).
      return const VenueSearchFailed(VenueSearchFailureReason.timeout);
    }
    if (statusCode == 429) {
      return const VenueSearchFailed(VenueSearchFailureReason.rateLimited);
    }
    if (statusCode < 200 || statusCode >= 300) {
      // Wolt's 410/430 "update the app" land here, as does any other
      // status a working search never answers with.
      return VenueSearchFailed(
        VenueSearchFailureReason.platformChanged,
        statusCode: statusCode,
      );
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      return const VenueSearchFailed(VenueSearchFailureReason.platformChanged);
    }
    if (decoded is! Map<String, Object?>) {
      return const VenueSearchFailed(VenueSearchFailureReason.platformChanged);
    }
    final venues = WoltVenueMapper.map(decoded);
    if (venues == null) {
      return const VenueSearchFailed(VenueSearchFailureReason.platformChanged);
    }
    return VenuesFound(List<Venue>.unmodifiable(venues));
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

  /// `{base}/v1/proxy/wolt/pages/{page}`, whether or not [base] ends
  /// with a slash.
  static Uri _proxyUri(Uri base, String page) {
    final rendered = base.toString();
    final trimmed = rendered.endsWith('/')
        ? rendered.substring(0, rendered.length - 1)
        : rendered;
    return Uri.parse('$trimmed/v1/proxy/wolt/pages/$page');
  }
}

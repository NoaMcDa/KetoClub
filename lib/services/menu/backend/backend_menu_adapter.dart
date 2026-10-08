import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/classifier/menu_classifier.dart';
import 'package:ketoclub/services/classifier/menu_response_parser.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/services/menu/website/backend_website_fetcher.dart';
import 'package:ketoclub/services/storage/install_id_store.dart';

/// Reads a complete menu, and usually its analysis, from KetoClub's
/// backend in one request (architecture.md D25, issue #327;
/// `backend_plan.md` §3.3).
///
/// One instance serves one [MenuSource]:
///
/// - [MenuSource.wolt] and [MenuSource.tenbis] are read with
///   `GET {base}/v1/venue-menus/{source}/{platformId}?classify=true`, the
///   options travelling as `netCarbLimitGrams` and one repeated
///   `constraints` parameter per dietary prompt fragment (repeated, never
///   comma-joined, because a fragment contains commas).
/// - [MenuSource.website] is read with `POST {base}/v1/website-menu`,
///   `{url, options: {netCarbLimitGrams, dietaryConstraints}}`; the ref's
///   `platformId` is the URL.
///
/// **The analysis is a hint, never trusted blindly.** It rides on
/// [MenuFetched.analysis] only when it was made under the options
/// `readOptions` answers now and at the current
/// [MenuResponseParser.schemaVersion]; otherwise it is dropped and the
/// device classifies the menu as it would any other.
///
/// **No credentials.** The only identifying value sent is the anonymous
/// install id, as `X-KetoClub-Install-Id`; never an `Authorization`
/// header.
///
/// **Failures are mapped for [shouldFallBack].** A request the backend
/// could not serve — no answer, a timeout, or an answer outside the route
/// contract (an older backend without the route, a 5xx with no `reason`,
/// a rate limit on a venue route) — is
/// [MenuFetchFailureReason.backendUnreachable], so a `FallbackMenuAdapter`
/// reads the menu the device's own way instead. Never throws.
final class BackendMenuAdapter implements PlatformMenuAdapter {
  /// Creates an adapter for [source] that asks [baseUrl] through [client].
  ///
  /// A null [baseUrl] means this build has no backend: [canHandle] is then
  /// false for every ref and [fetch] performs no I/O. [readOptions]
  /// supplies the options to classify under — the ones the menu screen
  /// builds from Settings, so the analysis returned is one it reuses.
  /// [timeout] bounds the single request; exceeding it is
  /// [MenuFetchFailureReason.backendUnreachable].
  new({
    required http.Client client,
    required this.baseUrl,
    required InstallIdStore installIdStore,
    required this.source,
    required Future<ClassificationOptions> Function() readOptions,
    this.timeout = const Duration(seconds: 25),
  })
    // Private fields, public parameter names.
    // ignore: prefer_initializing_formals
    : _client = client,
       // Same reason: a private field, a public parameter name.
       // ignore: prefer_initializing_formals
       _installIdStore = installIdStore,
       // Same reason: a private field, a public parameter name.
       // ignore: prefer_initializing_formals
       _readOptions = readOptions;

  /// The header carrying the anonymous install id (`backend_plan.md`
  /// §3.4).
  static const String installIdHeader = 'X-KetoClub-Install-Id';

  /// KetoClub's backend, or null when this build has none.
  final Uri? baseUrl;

  /// How long the single HTTP request is given before it is abandoned.
  final Duration timeout;

  @override
  final MenuSource source;

  final http.Client _client;
  final InstallIdStore _installIdStore;
  final Future<ClassificationOptions> Function() _readOptions;

  /// The sources the backend serves complete menus for.
  static const Set<MenuSource> _served = <MenuSource>{
    MenuSource.wolt,
    MenuSource.tenbis,
    MenuSource.website,
  };

  /// The website fetch route's reasons the website route passes through
  /// unchanged, read by [BackendWebsiteFetcher.reasonFor].
  static const Set<String> _websiteFetchReasons = <String>{
    'invalidUrl',
    'disallowedByRobots',
    'aiReserved',
    'jsOnlyPage',
    'tooLarge',
    'unsupportedContent',
    'notFound',
    'offline',
    'timeout',
    'upstreamStatus',
    'rateLimited',
  };

  /// The scan route's reasons the website route answers with a 502 when a
  /// linked PDF could not be read (`offline` is absent: it is the site
  /// fetch's own reason too, and reads as the site not answering).
  static const Set<String> _pdfReasons = <String>{
    'notConfigured',
    'badResponse',
    'timeout',
    'rateLimited',
  };

  /// Whether a `FallbackMenuAdapter` should try the device's own adapter
  /// after this adapter failed with [reason].
  ///
  /// True for [MenuFetchFailureReason.backendUnreachable] — the backend
  /// did not serve the request, which says nothing about the platform —
  /// and for [MenuFetchFailureReason.offline], which this adapter reports
  /// only when the *server* could not reach Wolt or 10bis: a device on
  /// another network (a phone in Israel, a backend host the platform
  /// blocks) may still reach it. Every other reason is the platform's or
  /// the site's own answer, which the device would only hear again.
  static bool shouldFallBack(MenuFetchFailureReason reason) =>
      reason == MenuFetchFailureReason.backendUnreachable ||
      reason == MenuFetchFailureReason.offline;

  @override
  bool canHandle(VenueRef ref) =>
      baseUrl != null && _served.contains(source) && ref.source == source;

  @override
  Future<MenuFetchResult> fetch(VenueRef ref) async {
    final baseUrl = this.baseUrl;
    if (baseUrl == null || !canHandle(ref)) return _unsupported;
    final isWebsite = source == MenuSource.website;
    if (isWebsite && !_isWebUrl(ref.platformId)) return _unsupported;

    final options = await _readOptions();
    final headers = <String, String>{
      'Accept': 'application/json',
      installIdHeader: await _installIdStore.id(),
    };
    final http.Response response;
    try {
      final Future<http.Response> request;
      if (isWebsite) {
        request = _client.post(
          Uri.parse('${_trimmed(baseUrl)}/v1/website-menu'),
          headers: <String, String>{
            ...headers,
            'Content-Type': 'application/json',
          },
          body: jsonEncode(<String, Object?>{
            'url': ref.platformId,
            'options': _optionsJson(options),
          }),
        );
      } else {
        request = _client.get(
          venueMenuUri(baseUrl, ref, options),
          headers: headers,
        );
      }
      response = await request.timeout(timeout);
    } on http.ClientException {
      return _unreachable;
    } on TimeoutException {
      return _unreachable;
    }

    final decoded = _decode(response);
    final statusCode = response.statusCode;
    if (statusCode != 200) {
      final rawReason = decoded is Map<String, Object?>
          ? decoded['reason']
          : null;
      final reason = rawReason is String ? rawReason : null;
      return MenuFetchFailed(
        reason: isWebsite
            ? websiteReasonFor(statusCode, reason)
            : venueReasonFor(reason),
        statusCode: statusCode,
      );
    }
    return _fetched(ref, decoded, options);
  }

  /// The `GET` URL for [ref] under [base], asking for an analysis under
  /// [options]: `{base}/v1/venue-menus/{source}/{platformId}` with the
  /// platform id percent-encoded as one path segment, then `classify`,
  /// `netCarbLimitGrams` and one `constraints` per dietary constraint.
  static Uri venueMenuUri(
    Uri base,
    VenueRef ref,
    ClassificationOptions options,
  ) {
    final path =
        '${_trimmed(base)}/v1/venue-menus/${ref.source.name}/'
        '${Uri.encodeComponent(ref.platformId)}';
    return Uri.parse(path).replace(
      queryParameters: <String, Object>{
        'classify': 'true',
        'netCarbLimitGrams': '${options.netCarbLimitGrams}',
        if (options.dietaryConstraints.isNotEmpty)
          'constraints': options.dietaryConstraints,
      },
    );
  }

  /// The [MenuFetchFailureReason] for a non-200 answer from the venue
  /// route whose error body named [reason] (null when it named none).
  ///
  /// `notFound` (the platform's 404) and `platformChanged` keep their
  /// names; `offline` and `timeout` (the server could not reach the
  /// platform) are [MenuFetchFailureReason.offline]. Anything else — a
  /// rate limit, a refused header, a validation 422, a route this backend
  /// does not have, an unknown name — means the backend did not serve the
  /// request: [MenuFetchFailureReason.backendUnreachable].
  static MenuFetchFailureReason venueReasonFor(String? reason) =>
      switch (reason) {
        'notFound' => MenuFetchFailureReason.notFound,
        'platformChanged' => MenuFetchFailureReason.platformChanged,
        'offline' || 'timeout' => MenuFetchFailureReason.offline,
        _ => MenuFetchFailureReason.backendUnreachable,
      };

  /// The [MenuFetchFailureReason] for a non-200 [statusCode] from the
  /// website route whose error body named [reason] (null when none).
  ///
  /// `menuNotFound` keeps its name and `noDishesFound` is
  /// [MenuFetchFailureReason.websitePdfUnread]; a 502 naming one of the
  /// scan route's reasons is the linked PDF going unread, also
  /// [MenuFetchFailureReason.websitePdfUnread]; every website fetch route
  /// reason reads as [BackendWebsiteFetcher.reasonFor] reads it (so a 429
  /// `rateLimited` is [MenuFetchFailureReason.websiteRateLimited]).
  /// Anything else — a refused header (400 `badResponse`), a validation
  /// 422, a route this backend does not have, an unknown name — is
  /// [MenuFetchFailureReason.backendUnreachable].
  static MenuFetchFailureReason websiteReasonFor(
    int statusCode,
    String? reason,
  ) {
    if (reason == null) return MenuFetchFailureReason.backendUnreachable;
    if (reason == 'menuNotFound') return MenuFetchFailureReason.menuNotFound;
    if (reason == 'noDishesFound' ||
        (statusCode == 502 && _pdfReasons.contains(reason))) {
      return MenuFetchFailureReason.websitePdfUnread;
    }
    if (_websiteFetchReasons.contains(reason)) {
      return BackendWebsiteFetcher.reasonFor(reason);
    }
    return MenuFetchFailureReason.backendUnreachable;
  }

  /// A 200 body [decoded] as a [MenuFetched] for [ref], or
  /// [MenuFetchFailureReason.platformChanged] when its menu is unreadable.
  ///
  /// The menu is re-addressed to [ref]: the server may normalise a
  /// website URL differently, and the ref is how the app keys the venue.
  MenuFetchResult _fetched(
    VenueRef ref,
    Object? decoded,
    ClassificationOptions options,
  ) {
    final rawMenu = decoded is Map<String, Object?> ? decoded['menu'] : null;
    final menu = rawMenu is Map<String, Object?> ? Menu.tryFrom(rawMenu) : null;
    if (decoded is! Map<String, Object?> || menu == null) {
      return const MenuFetchFailed(
        reason: MenuFetchFailureReason.platformChanged,
        statusCode: 200,
      );
    }
    final rawAnalysis = decoded['analysis'];
    final analysis = rawAnalysis is Map<String, Object?>
        ? MenuAnalysed.tryFrom(rawAnalysis)
        : null;
    return MenuFetched(
      menu: Menu(
        venueRef: ref,
        currency: menu.currency,
        fetchedAt: menu.fetchedAt,
        categories: menu.categories,
        venueName: menu.venueName,
      ),
      analysis: _reusable(analysis, options) ? analysis : null,
    );
  }

  /// Whether [analysis] answers the user's [options] at the current
  /// schema version, as `MenuController` would accept a cached one.
  static bool _reusable(
    MenuAnalysed? analysis,
    ClassificationOptions options,
  ) =>
      analysis != null &&
      analysis.schemaVersion == MenuResponseParser.schemaVersion &&
      options.matches(analysis.options);

  static Map<String, Object?> _optionsJson(ClassificationOptions options) =>
      <String, Object?>{
        'netCarbLimitGrams': options.netCarbLimitGrams,
        'dietaryConstraints': options.dietaryConstraints,
      };

  static bool _isWebUrl(String raw) {
    final url = Uri.tryParse(raw);
    return url != null &&
        (url.scheme == 'http' || url.scheme == 'https') &&
        url.host.isNotEmpty;
  }

  /// [base] rendered without a trailing slash.
  static String _trimmed(Uri base) {
    final rendered = base.toString();
    return rendered.endsWith('/')
        ? rendered.substring(0, rendered.length - 1)
        : rendered;
  }

  /// [response]'s body decoded as JSON, or null when it is not JSON.
  static Object? _decode(http.Response response) {
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      return null;
    }
  }

  static const MenuFetchFailed _unreachable = MenuFetchFailed(
    reason: MenuFetchFailureReason.backendUnreachable,
  );

  static const MenuFetchFailed _unsupported = MenuFetchFailed(
    reason: MenuFetchFailureReason.unsupportedSource,
  );
}

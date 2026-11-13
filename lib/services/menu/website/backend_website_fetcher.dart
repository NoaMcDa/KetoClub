import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/services/menu/website/website_fetcher.dart';
import 'package:ketoclub/services/storage/install_id_store.dart';
import 'package:ketoclub/utils/constants.dart';

/// Fetches a restaurant's page through KetoClub's backend: the web build,
/// where the browser refuses to read another site (architecture.md D11,
/// D19).
///
/// Posts `{"url": …}` to `{proxyBase}/v1/website/fetch` with the install
/// id header the backend rate-limits by, and maps its answer: a
/// `{kind, content_type, body, final_url}` document, or a
/// `{reason, status_code}` failure whose `reason` names one
/// [MenuFetchFailureReason] (see [reasonFor]). The backend applies every
/// crawl-hygiene rule (`backend/README.md`); this class only carries the
/// request. Never throws.
final class BackendWebsiteFetcher implements WebsiteFetcher {
  /// Creates a fetcher posting to [proxyBase] through [client].
  new({
    required http.Client client,
    required this.proxyBase,
    required InstallIdStore installIdStore,
  })
    // Private fields, public parameter names.
    // ignore: prefer_initializing_formals
    : _client = client,
       // Same reason: a private field, a public parameter name.
       // ignore: prefer_initializing_formals
       _installIdStore = installIdStore;

  final http.Client _client;
  final InstallIdStore _installIdStore;

  /// KetoClub's backend.
  final Uri proxyBase;

  @override
  Future<WebsiteFetchResult> fetch(Uri url) async {
    final rendered = proxyBase.toString();
    final base = rendered.endsWith('/')
        ? rendered.substring(0, rendered.length - 1)
        : rendered;
    final http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse('$base/v1/website/fetch'),
            headers: <String, String>{
              'Accept': 'application/json',
              'Content-Type': 'application/json',
              'X-KetoClub-Install-Id': await _installIdStore.id(),
            },
            body: jsonEncode(<String, String>{'url': url.toString()}),
          )
          .timeout(websiteBackendTimeout);
    } on TimeoutException {
      return const WebsiteFetchFailed(
        reason: MenuFetchFailureReason.websiteUnreachable,
      );
    } on Exception {
      // http.ClientException, and what IOClient lets through unwrapped: a
      // TLS HandshakeException, a SocketException while the body is read
      // (issue #278). `services/` may not import dart:io to name them.
      return const WebsiteFetchFailed(
        reason: MenuFetchFailureReason.backendUnreachable,
      );
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      return _offContract(response.statusCode);
    }
    if (decoded is! Map<String, Object?>) {
      return _offContract(response.statusCode);
    }
    if (response.statusCode != 200) {
      return WebsiteFetchFailed(
        reason: reasonFor(decoded['reason']),
        statusCode: response.statusCode,
      );
    }
    return _document(decoded, url, response.statusCode);
  }

  /// A body that is not the backend's JSON. On a 200 the backend and the
  /// app disagree about the contract: [MenuFetchFailureReason.platformChanged].
  /// On any other status it is not the backend's answer at all — a proxy
  /// or load balancer in front of it, an HTML 502 page (issue #284) — so
  /// KetoClub's server could not be reached:
  /// [MenuFetchFailureReason.backendUnreachable].
  static WebsiteFetchFailed _offContract(int statusCode) => WebsiteFetchFailed(
    reason: statusCode == 200
        ? MenuFetchFailureReason.platformChanged
        : MenuFetchFailureReason.backendUnreachable,
    statusCode: statusCode,
  );

  /// The [MenuFetchFailureReason] for a backend failure [reason]; an
  /// unknown one is [MenuFetchFailureReason.platformChanged], since the
  /// backend and the app disagree about the contract. The site's budget
  /// (`siteRateLimited`) and this install's (`rateLimited`) are told
  /// apart (issue #284): the first is
  /// [MenuFetchFailureReason.websiteRateLimited], the second
  /// [MenuFetchFailureReason.backendRateLimited].
  static MenuFetchFailureReason reasonFor(Object? reason) => switch (reason) {
    'invalidUrl' => MenuFetchFailureReason.unsupportedSource,
    'disallowedByRobots' ||
    'aiReserved' => MenuFetchFailureReason.disallowedByRobots,
    'jsOnlyPage' => MenuFetchFailureReason.jsOnlyPage,
    'tooLarge' => MenuFetchFailureReason.websiteTooLarge,
    'unsupportedContent' => MenuFetchFailureReason.menuNotFound,
    'notFound' => MenuFetchFailureReason.notFound,
    'offline' ||
    'timeout' ||
    'upstreamStatus' => MenuFetchFailureReason.websiteUnreachable,
    'siteRateLimited' => MenuFetchFailureReason.websiteRateLimited,
    'rateLimited' => MenuFetchFailureReason.backendRateLimited,
    _ => MenuFetchFailureReason.platformChanged,
  };

  static WebsiteFetchResult _document(
    Map<String, Object?> json,
    Uri requested,
    int statusCode,
  ) {
    final kind = json['kind'];
    final body = json['body'];
    final rawFinalUrl = json['final_url'];
    final finalUrl =
        (rawFinalUrl is String ? Uri.tryParse(rawFinalUrl) : null) ?? requested;
    if (body is! String) {
      return WebsiteFetchFailed(
        reason: MenuFetchFailureReason.platformChanged,
        statusCode: statusCode,
      );
    }
    if (kind == 'html') return WebsitePage(html: body, finalUrl: finalUrl);
    if (kind == 'pdf') {
      try {
        return WebsitePdf(bytes: base64Decode(body), finalUrl: finalUrl);
      } on FormatException {
        // Falls through to the contract failure below.
      }
    }
    return WebsiteFetchFailed(
      reason: MenuFetchFailureReason.platformChanged,
      statusCode: statusCode,
    );
  }
}

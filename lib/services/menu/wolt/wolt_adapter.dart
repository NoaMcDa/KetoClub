import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/services/menu/wolt/wolt_menu_mapper.dart';
import 'package:ketoclub/utils/constants.dart';

/// Fetches menus from Wolt's public `menu/data` endpoint
/// (architecture.md §6.1, §8).
///
/// This class does one thing: an HTTP GET, with the failure mapping
/// architecture.md §8 and §10 specify. Turning the response body into a
/// menu is entirely [WoltMenuMapper]'s job, so a change to Wolt's JSON
/// shape never touches this file (architecture.md §18.1).
///
/// **Web caveat:** Wolt does not send CORS headers for foreign origins,
/// so a request made from a browser is blocked before this class ever
/// sees a response. There are two ways that ends:
///
/// * With no [proxyBase], the browser surfaces the block as the same
///   [http.ClientException] a dead network would raise, so [fetch]
///   reports it as [MenuFetchFailureReason.blockedByBrowser] rather than
///   `offline` whenever it [runsInBrowser]: the user's way out is the
///   phone app, not a retry (architecture.md §10, §13).
/// * With a [proxyBase], the request goes to the KetoClub backend
///   instead, which makes the same call from a server where CORS does
///   not apply and returns Wolt's answer unchanged. The browser is then
///   no longer the thing that fails, so `blockedByBrowser` cannot arise
///   and [MenuFetchFailureReason.backendUnreachable] takes its place
///   (`backend_plan.md` §4).
final class WoltMenuAdapter implements PlatformMenuAdapter {
  /// Creates an adapter that sends its requests through [client].
  ///
  /// The parameter is named `client`, not `_client`, so it cannot be an
  /// initializing formal (`this._client`) and is assigned explicitly.
  ///
  /// [proxyBase] is the root of a KetoClub backend, or null to call Wolt
  /// directly. Only `di.dart` decides which, and it chooses a proxy only
  /// for the web build (`backend_plan.md` §4).
  ///
  /// [runsInBrowser] defaults to [kIsWeb] and exists so a test can
  /// exercise both the browser and the native mapping of a failed
  /// request on one platform.
  new({
    required http.Client client,
    this.proxyBase,
    this.runsInBrowser = kIsWeb,
  })
    // The field is private and the parameter is not, so `this._client` is
    // not available; see the constructor doc above.
    // ignore: prefer_initializing_formals
    : _client = client;

  /// How long [fetch] waits for a response before giving up. Wolt's
  /// endpoint is normally fast; a slower answer than this is treated the
  /// same as no network at all, since neither is diagnosable further
  /// from here (architecture.md §10, `MenuFetch.offline`).
  static const Duration _timeout = Duration(seconds: 15);

  /// Wolt's own host, used when there is no [proxyBase].
  static const String _woltHost = 'restaurant-api.wolt.com';

  /// The menu path, appended to Wolt's host or to [proxyBase] unchanged.
  /// The backend route deliberately mirrors Wolt's own path so that
  /// switching between them is a change of origin and nothing else.
  static String _menuPath(String slug) => '/v4/venues/slug/$slug/menu/data';

  /// The backend's prefix in front of [_menuPath]. It names this adapter's
  /// platform, so a second platform's proxy route never collides with it.
  static const String _proxyPathPrefix = '/v1/proxy/wolt';

  /// Statuses the backend answers with on its own behalf rather than
  /// relaying: 502 when it could not reach Wolt, 504 when Wolt was too
  /// slow. Both mean try again, which is what `offline` already says, and
  /// neither is a claim about Wolt's payload, which is what
  /// `platformChanged` would wrongly imply (`backend_plan.md` §3.3).
  static const Set<int> _proxyOwnFailureStatuses = {502, 504};

  final http.Client _client;

  /// The root of the KetoClub backend to route through, or null to call
  /// Wolt directly. A base with a path is respected, so a backend hosted
  /// under a sub-path works without further configuration.
  final Uri? proxyBase;

  /// Whether requests go out through a browser. A browser forbids a page
  /// from setting `User-Agent`, so the header is omitted there, and it
  /// turns Wolt's missing CORS headers into a request failure that
  /// [fetch] must not confuse with being offline (architecture.md §13).
  final bool runsInBrowser;

  @override
  MenuSource get source => MenuSource.wolt;

  @override
  bool canHandle(VenueRef ref) => ref.source == MenuSource.wolt;

  /// The URL one fetch of [slug] is sent to.
  Uri _uriFor(String slug) {
    final proxy = proxyBase;
    if (proxy == null) {
      return Uri.https(_woltHost, _menuPath(slug));
    }
    final root = proxy.path.endsWith('/')
        ? proxy.path.substring(0, proxy.path.length - 1)
        : proxy.path;
    return proxy.replace(path: '$root$_proxyPathPrefix${_menuPath(slug)}');
  }

  @override
  Future<MenuFetchResult> fetch(VenueRef ref) async {
    final usesProxy = proxyBase != null;

    http.Response response;
    try {
      response = await _client
          .get(
            _uriFor(ref.platformId),
            headers: <String, String>{
              if (!runsInBrowser) 'User-Agent': browserUserAgent,
              'Accept': 'application/json',
            },
          )
          .timeout(_timeout);
    } on http.ClientException {
      // Through a proxy this is the backend failing to answer — usually
      // it is simply not running — and a retry helps once it does. Going
      // to Wolt directly from a browser it is the CORS block, which no
      // retry can fix, and Wolt refuses every foreign origin, so there it
      // is reported as the block rather than as the network
      // (architecture.md §13; `backend_plan.md` §4).
      if (usesProxy) {
        return const MenuFetchFailed(
          reason: MenuFetchFailureReason.backendUnreachable,
        );
      }
      return MenuFetchFailed(
        reason: runsInBrowser
            ? MenuFetchFailureReason.blockedByBrowser
            : MenuFetchFailureReason.offline,
      );
    } on TimeoutException {
      return const MenuFetchFailed(reason: MenuFetchFailureReason.offline);
    }

    final statusCode = response.statusCode;
    if (statusCode == 404) {
      return const MenuFetchFailed(
        reason: MenuFetchFailureReason.notFound,
        statusCode: 404,
      );
    }
    if (usesProxy && _proxyOwnFailureStatuses.contains(statusCode)) {
      return MenuFetchFailed(
        reason: MenuFetchFailureReason.offline,
        statusCode: statusCode,
      );
    }
    if (statusCode < 200 || statusCode >= 300) {
      return MenuFetchFailed(
        reason: MenuFetchFailureReason.platformChanged,
        statusCode: statusCode,
      );
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      return const MenuFetchFailed(
        reason: MenuFetchFailureReason.platformChanged,
      );
    }
    if (decoded is! Map<String, Object?>) {
      return const MenuFetchFailed(
        reason: MenuFetchFailureReason.platformChanged,
      );
    }

    return WoltMenuMapper.toMenu(decoded, ref: ref, fetchedAt: DateTime.now());
  }
}

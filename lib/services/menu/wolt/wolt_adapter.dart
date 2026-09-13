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
/// sees a response. The browser surfaces that block as the same
/// [http.ClientException] a dead network would raise, so [fetch] reports
/// it as [MenuFetchFailureReason.blockedByBrowser] rather than `offline`
/// whenever it [runsInBrowser]: the user's way out is the phone app, not
/// a retry (architecture.md §10, §13). This adapter is a mobile-first
/// path; the web build takes menus by paste instead.
final class WoltMenuAdapter implements PlatformMenuAdapter {
  /// Creates an adapter that sends its requests through [client]. The
  /// parameter is named `client`, not `_client`, so it cannot be an
  /// initializing formal (`this._client`) and is assigned explicitly.
  ///
  /// [runsInBrowser] defaults to [kIsWeb] and exists so a test can
  /// exercise both the browser and the native mapping of a failed
  /// request on one platform.
  new({required http.Client client, this.runsInBrowser = kIsWeb})
    // The field is private and the parameter is not, so `this._client` is
    // not available; see the constructor doc above.
    // ignore: prefer_initializing_formals
    : _client = client;

  /// How long [fetch] waits for a response before giving up. Wolt's
  /// endpoint is normally fast; a slower answer than this is treated the
  /// same as no network at all, since neither is diagnosable further
  /// from here (architecture.md §10, `MenuFetch.offline`).
  static const Duration _timeout = Duration(seconds: 15);

  final http.Client _client;

  /// Whether requests go out through a browser. A browser forbids a page
  /// from setting `User-Agent`, so the header is omitted there, and it
  /// turns Wolt's missing CORS headers into a request failure that
  /// [fetch] must not confuse with being offline (architecture.md §13).
  final bool runsInBrowser;

  @override
  MenuSource get source => MenuSource.wolt;

  @override
  bool canHandle(VenueRef ref) => ref.source == MenuSource.wolt;

  @override
  Future<MenuFetchResult> fetch(VenueRef ref) async {
    final uri = Uri.https(
      'restaurant-api.wolt.com',
      '/v4/venues/slug/${ref.platformId}/menu/data',
    );

    http.Response response;
    try {
      response = await _client
          .get(
            uri,
            headers: <String, String>{
              if (!runsInBrowser) 'User-Agent': browserUserAgent,
              'Accept': 'application/json',
            },
          )
          .timeout(_timeout);
    } on http.ClientException {
      // A browser reports a CORS refusal exactly as it reports a dead
      // network, and Wolt refuses every foreign origin, so in a browser a
      // client-side failure is the block, not the network
      // (architecture.md §13).
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

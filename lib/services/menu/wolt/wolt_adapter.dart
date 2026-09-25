import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/services/menu/wolt/wolt_menu_mapper.dart';
import 'package:ketoclub/utils/wolt_headers.dart';

/// Fetches menus from Wolt's consumer-assortment endpoint, the one
/// wolt.com's own web app reads a venue's menu from (architecture.md
/// §6.1, §8; issue #168).
///
/// This class does one thing: an HTTP GET, with the failure mapping
/// architecture.md §8 and §10 specify. Turning the response body into a
/// menu is entirely [WoltMenuMapper]'s job, so a change to Wolt's JSON
/// shape never touches this file (architecture.md §18.1).
///
/// A direct request carries the header set wolt.com sends
/// ([woltWebHeaders]): the assortment endpoint answers an anonymous
/// caller with that set, and Wolt's older menu endpoint answered every
/// anonymous caller with a zero-byte body, with or without it. An empty
/// or non-JSON 2xx body is still [MenuFetchFailureReason.platformChanged]
/// — never an empty menu — so if this endpoint goes the same way, the
/// user is told the platform changed rather than shown nothing.
///
/// **Web caveat:** Wolt does not send CORS headers for foreign origins,
/// so a request made from a browser is blocked before this class ever
/// sees a response. The browser surfaces that block as the same
/// [http.ClientException] a dead network would raise, so [fetch] reports
/// it as [MenuFetchFailureReason.blockedByBrowser] rather than `offline`
/// whenever it [runsInBrowser] and no [proxyBase] is configured: the
/// user's way out is the phone app, not a retry (architecture.md §10,
/// §13). When [proxyBase] is set — the web build routes through
/// KetoClub's own CORS-forwarding backend (`backend_plan.md` §4.1) — that
/// caveat no longer applies: the browser talks to KetoClub's own origin,
/// which grants itself CORS, and a request failure there is reported as
/// [MenuFetchFailureReason.backendUnreachable] instead.
final class WoltMenuAdapter implements PlatformMenuAdapter {
  /// Creates an adapter that sends its requests through [client]. The
  /// parameter is named `client`, not `_client`, so it cannot be an
  /// initializing formal (`this._client`) and is assigned explicitly.
  ///
  /// [runsInBrowser] defaults to [kIsWeb] and exists so a test can
  /// exercise both the browser and the native mapping of a failed
  /// request on one platform.
  ///
  /// [proxyBase] is null by default, meaning every request goes straight
  /// to Wolt. When set, [fetch] instead asks KetoClub's own backend at
  /// [proxyBase] to fetch the menu on the client's behalf
  /// (`backend_plan.md` §3.3, §4.1), which is how the web build works
  /// around Wolt's missing CORS headers.
  ///
  /// [random] is the source of the per-instance web client id and
  /// defaults to [Random.secure]; nothing is drawn from it until the
  /// first direct request, so the constructor performs no work at all.
  new({
    required http.Client client,
    this.proxyBase,
    this.runsInBrowser = kIsWeb,
    Random? random,
  })
    // The fields are private and the parameters are not, so `this._client`
    // is not available; see the constructor doc above.
    // ignore: prefer_initializing_formals
    : _client = client,
       // Same reason as above: a private field, a public parameter name.
       // ignore: prefer_initializing_formals
       _random = random;

  /// How long [fetch] waits for a response before giving up. Wolt's
  /// endpoint is normally fast; a slower answer than this is treated the
  /// same as no network at all, since neither is diagnosable further
  /// from here (architecture.md §10, `MenuFetch.offline`).
  static const Duration _timeout = Duration(seconds: 15);

  final http.Client _client;

  final Random? _random;

  /// Whether requests go out through a browser. A browser forbids a page
  /// from setting `User-Agent`, so the header is omitted there, and it
  /// turns Wolt's missing CORS headers into a request failure that
  /// [fetch] must not confuse with being offline (architecture.md §13).
  final bool runsInBrowser;

  /// KetoClub's own backend, when [fetch] should go through it rather
  /// than straight to Wolt (`backend_plan.md` §3.3, §4.1). Null means
  /// direct to Wolt.
  final Uri? proxyBase;

  /// The `x-wolt-web-clientid` value: a random UUID generated once per
  /// adapter, the way wolt.com keeps one per browser. Deliberately not
  /// KetoClub's install id, which goes to KetoClub's backend only (D12).
  late final String _webClientId = woltWebClientId(_random ?? Random.secure());

  @override
  MenuSource get source => MenuSource.wolt;

  @override
  bool canHandle(VenueRef ref) => ref.source == MenuSource.wolt;

  @override
  Future<MenuFetchResult> fetch(VenueRef ref) async {
    final proxyBase = this.proxyBase;
    final uri = proxyBase != null
        ? _proxyUri(proxyBase, ref.platformId)
        : Uri.https(
            'consumer-api.wolt.com',
            '/consumer-api/consumer-assortment/v1/venues/slug/'
                '${ref.platformId}/assortment',
          );
    final headers = proxyBase != null
        // The backend builds Wolt's headers itself (`backend_plan.md`
        // §3.3) and must receive nothing it would have to strip.
        ? const <String, String>{'Accept': 'application/json'}
        : woltWebHeaders(
            language: woltDefaultAppLanguage,
            webClientId: _webClientId,
            // A browser could not set a User-Agent regardless.
            includeUserAgent: !runsInBrowser,
          );

    http.Response response;
    try {
      response = await _client.get(uri, headers: headers).timeout(_timeout);
    } on http.ClientException {
      if (proxyBase != null) {
        // KetoClub's own backend could not be reached at all — distinct
        // from Wolt being unreachable, which the backend reports as a
        // 502/504 status below, not an exception here.
        return const MenuFetchFailed(
          reason: MenuFetchFailureReason.backendUnreachable,
        );
      }
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
    if (proxyBase != null && (statusCode == 502 || statusCode == 504)) {
      // The backend's own proxy-originated statuses for "Wolt was
      // unreachable" and "Wolt timed out" (`backend_plan.md` §3.3): both
      // are the same "try again" story as a direct offline result.
      return const MenuFetchFailed(reason: MenuFetchFailureReason.offline);
    }
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

    // An empty body — what Wolt's retired menu endpoint answers every
    // anonymous caller with — fails the decode below like any other
    // non-JSON body: platformChanged, never an empty menu.
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

  /// The proxied request URL for [platformId] under [base]
  /// (`backend_plan.md` §3.3): `{base}/v1/proxy/wolt/venues/slug/
  /// {platformId}/assortment`, whether or not [base] itself ends with a
  /// trailing slash.
  static Uri _proxyUri(Uri base, String platformId) {
    final rendered = base.toString();
    final trimmed = rendered.endsWith('/')
        ? rendered.substring(0, rendered.length - 1)
        : rendered;
    return Uri.parse(
      '$trimmed/v1/proxy/wolt/venues/slug/$platformId/assortment',
    );
  }
}

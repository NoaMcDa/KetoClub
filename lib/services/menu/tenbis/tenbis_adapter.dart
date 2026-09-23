import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/services/menu/tenbis/tenbis_menu_mapper.dart';
import 'package:ketoclub/utils/constants.dart';

/// Fetches menus from 10bis's `Restaurants/{id}/Menu` endpoint
/// (architecture.md §6.1, §8, issue #46).
///
/// This class mirrors `wolt_adapter.dart`'s `WoltMenuAdapter` on purpose:
/// an HTTP GET plus the failure mapping architecture.md §8 and §10
/// specify, nothing else. Turning the response body into a menu is
/// entirely [TenBisMenuMapper]'s job, so a schema change touches only
/// that file (architecture.md §18.1). The two adapters are kept as
/// separate files rather than sharing a base class, the same trade the
/// issue accepts: duplicating this fetch-and-map shape is cheaper to
/// keep obviously correct than a shared abstraction would be, and a URL
/// change for one platform still touches exactly one file.
///
/// **Web caveat:** `www.10bis.co.il` sends no CORS headers for foreign
/// origins (`menu_api_research` §3.2, unverified — see the class doc on
/// [TenBisMenuMapper]), so a request made from a browser is blocked
/// before this class ever sees a response. The browser surfaces that
/// block as the same [http.ClientException] a dead network would raise,
/// so [fetch] reports it as [MenuFetchFailureReason.blockedByBrowser]
/// rather than `offline` whenever it [runsInBrowser] and no [proxyBase]
/// is configured. When [proxyBase] is set — the web build routes
/// through KetoClub's own CORS-forwarding backend (`backend_plan.md`
/// §4.1, issue #122) — that caveat no longer applies: the browser talks
/// to KetoClub's own origin, which grants itself CORS, and a request
/// failure there is reported as
/// [MenuFetchFailureReason.backendUnreachable] instead.
final class TenBisAdapter implements PlatformMenuAdapter {
  /// Creates an adapter that sends its requests through `client`. The
  /// parameter is named `client`, not `_client`, so it cannot be an
  /// initializing formal (`this._client`) and is assigned explicitly.
  ///
  /// [runsInBrowser] defaults to [kIsWeb] and exists so a test can
  /// exercise both the browser and the native mapping of a failed
  /// request on one platform.
  ///
  /// [proxyBase] is null by default, meaning every request goes straight
  /// to 10bis exactly as before this parameter existed. When set,
  /// [fetch] instead asks KetoClub's own backend at [proxyBase] to fetch
  /// the menu on the client's behalf (`backend_plan.md` §3.3, §4.1,
  /// issue #122), which is how the web build works around 10bis's
  /// missing CORS headers.
  new({
    required http.Client client,
    this.proxyBase,
    this.runsInBrowser = kIsWeb,
  })
    // The field is private and the parameter is not, so `this._client` is
    // not available; see the constructor doc above.
    // ignore: prefer_initializing_formals
    : _client = client;

  /// How long [fetch] waits for a response before giving up. Mirrors
  /// `WoltMenuAdapter`'s own timeout: a slower answer than this is
  /// treated the same as no network at all, since neither is
  /// diagnosable further from here (architecture.md §10,
  /// `MenuFetch.offline`).
  static const Duration _timeout = Duration(seconds: 15);

  final http.Client _client;

  /// Whether requests go out through a browser. A browser forbids a page
  /// from setting `User-Agent`, so the header is omitted there, and it
  /// turns 10bis's missing CORS headers into a request failure that
  /// [fetch] must not confuse with being offline (architecture.md §13).
  final bool runsInBrowser;

  /// KetoClub's own backend, when [fetch] should go through it rather
  /// than straight to 10bis (`backend_plan.md` §3.3, §4.1, issue #122).
  /// Null means direct to 10bis, the only behaviour this adapter had
  /// before this field existed.
  final Uri? proxyBase;

  @override
  MenuSource get source => MenuSource.tenbis;

  @override
  bool canHandle(VenueRef ref) => ref.source == MenuSource.tenbis;

  @override
  Future<MenuFetchResult> fetch(VenueRef ref) async {
    final proxyBase = this.proxyBase;
    final uri = proxyBase != null
        ? _proxyUri(proxyBase, ref.platformId)
        : Uri.https(
            'www.10bis.co.il',
            '/api/v1.0/Restaurants/${ref.platformId}/Menu',
          );

    http.Response response;
    try {
      response = await _client
          .get(
            uri,
            headers: <String, String>{
              // The backend sets its own User-Agent (`backend_plan.md`
              // §3.3); a browser could not set one here regardless.
              if (proxyBase == null && !runsInBrowser)
                'User-Agent': browserUserAgent,
              'Accept': 'application/json',
            },
          )
          .timeout(_timeout);
    } on http.ClientException {
      if (proxyBase != null) {
        // KetoClub's own backend could not be reached at all — distinct
        // from 10bis being unreachable, which the backend reports as a
        // 502/504 status below, not an exception here.
        return const MenuFetchFailed(
          reason: MenuFetchFailureReason.backendUnreachable,
        );
      }
      // A browser reports a CORS refusal exactly as it reports a dead
      // network, and 10bis is assumed to refuse every foreign origin
      // the same way Wolt does, so in a browser a client-side failure
      // is the block, not the network (architecture.md §13).
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
      // The backend's own proxy-originated statuses for "10bis was
      // unreachable" and "10bis timed out" (`backend_plan.md` §3.3,
      // issue #122): both are the same "try again" story as a direct
      // offline result.
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

    return TenBisMenuMapper.toMenu(
      decoded,
      ref: ref,
      fetchedAt: DateTime.now(),
    );
  }

  /// The proxied request URL for [platformId] under [base]
  /// (`backend_plan.md` §3.3, issue #122): `{base}/v1/proxy/tenbis/
  /// api/v1.0/Restaurants/{platformId}/Menu`, whether or not [base]
  /// itself ends with a trailing slash.
  static Uri _proxyUri(Uri base, String platformId) {
    final rendered = base.toString();
    final trimmed = rendered.endsWith('/')
        ? rendered.substring(0, rendered.length - 1)
        : rendered;
    return Uri.parse(
      '$trimmed/v1/proxy/tenbis/api/v1.0/Restaurants/$platformId/Menu',
    );
  }
}

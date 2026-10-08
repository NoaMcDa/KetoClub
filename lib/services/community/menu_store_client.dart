import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show immutable;
import 'package:http/http.dart' as http;
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/platform/app_logger.dart';
import 'package:ketoclub/services/storage/install_id_store.dart';

/// The largest encoded [MenuUpload] body, in UTF-8 bytes, that
/// [BackendMenuStoreClient] will send (issue #309).
///
/// A body over this size is refused on the device as
/// [MenuStoreFailureReason.tooLarge], with no request made; the backend
/// enforces the same cap and answers 413 to anything over it.
const int maxMenuUploadBytes = 768 * 1024;

/// Contributes one fetched menu, and its analysis, to KetoClub's shared
/// menu store on the backend (issue #309).
///
/// Interface only: `di.dart` is the only file that constructs a concrete
/// implementation. Every implementation answers with a [MenuStoreResult]
/// and never throws.
abstract interface class MenuStoreClient {
  /// Whether this client can reach a menu store at all.
  ///
  /// False means every [upload] resolves to
  /// [MenuStoreFailureReason.notConfigured] without any I/O, so a caller
  /// may skip building a [MenuUpload] altogether.
  bool get isConfigured;

  /// Sends [upload] to the menu store: exactly one request, no retries.
  ///
  /// Never throws; every failure is a [MenuStoreFailed] naming why.
  Future<MenuStoreResult> upload(MenuUpload upload);
}

/// One menu to contribute to the shared menu store, with the analysis
/// the device made of it when there is one.
///
/// What leaves the device is exactly [toJson]: the venue reference, the
/// optional venue name and city, the menu, and the analysis **without**
/// its `options` — the user's own net-carb limit and dietary rules are
/// personal settings and never travel with a contribution.
@immutable
final class MenuUpload {
  /// Creates an upload of [menu] for the venue [ref], named [venueName]
  /// in [city] when either is known, with the [analysis] made of it.
  const new({
    required this.ref,
    required this.menu,
    this.venueName,
    this.city,
    this.analysis,
  });

  /// The venue this menu belongs to, on its platform.
  final VenueRef ref;

  /// The venue's display name, when the caller knows one.
  final String? venueName;

  /// The city the venue is in, when the caller knows one.
  final String? city;

  /// The menu itself, as fetched.
  final Menu menu;

  /// The analysis the device made of [menu], or null when there is none
  /// to share.
  final MenuAnalysed? analysis;

  /// The request body `POST /v1/menus` takes.
  ///
  /// `analysis` is [MenuAnalysed.toJson] with its `options` key removed,
  /// or null when [analysis] is null.
  Map<String, Object?> toJson() => <String, Object?>{
    'source': ref.source.name,
    'platform_id': ref.platformId,
    'venue_name': venueName,
    'city': city,
    'menu': menu.toJson(),
    'analysis': _sharedAnalysis(analysis),
  };

  /// [analysis] as it may be shared: its JSON form without the user's
  /// `options`, or null when there is none.
  static Map<String, Object?>? _sharedAnalysis(MenuAnalysed? analysis) {
    if (analysis == null) return null;
    return analysis.toJson()..remove('options');
  }
}

/// What a [MenuStoreClient.upload] call came to.
@immutable
sealed class MenuStoreResult {
  /// Const constructor so subclasses can be const.
  const new();
}

/// The menu store accepted the upload.
@immutable
final class MenuStored extends MenuStoreResult {
  /// Creates a success; [created] says whether the store had no copy of
  /// this menu before.
  const new({required this.created});

  /// True when the store saved a new entry (HTTP 201); false when it
  /// already held this menu and kept or refreshed it (HTTP 200).
  final bool created;

  @override
  bool operator ==(Object other) =>
      other is MenuStored && other.created == created;

  @override
  int get hashCode => Object.hash(MenuStored, created);

  @override
  String toString() => 'MenuStored(created: $created)';
}

/// The upload did not land, for [reason].
@immutable
final class MenuStoreFailed extends MenuStoreResult {
  /// Creates a failure for [reason].
  const new({required this.reason});

  /// Why the upload did not land.
  final MenuStoreFailureReason reason;

  @override
  bool operator ==(Object other) =>
      other is MenuStoreFailed && other.reason == reason;

  @override
  int get hashCode => Object.hash(MenuStoreFailed, reason);

  @override
  String toString() => 'MenuStoreFailed(reason: ${reason.name})';
}

/// Why a [MenuStoreClient.upload] did not land. Every reason is
/// distinct, and none is collapsed into another (architecture.md §10).
enum MenuStoreFailureReason {
  /// This build has no backend configured, so there is no store to send
  /// to; nothing was sent.
  notConfigured,

  /// The encoded upload is over [maxMenuUploadBytes]: refused on the
  /// device with no request made, or answered 413 by the backend.
  tooLarge,

  /// The request did not complete within the client's timeout.
  timeout,

  /// The backend could not be reached at all: a socket, DNS or TLS
  /// failure before any HTTP status came back.
  backendUnreachable,

  /// The backend answered 429: this install has sent too many uploads
  /// recently.
  rateLimited,

  /// The backend answered 400 or 422: it read the upload and refused its
  /// content or shape.
  rejected,

  /// The backend answered with any other status, or a success status
  /// this client does not expect.
  badResponse,
}

/// The [MenuStoreFailureReason]s a backend error body's `reason` may name
/// for a status this client does not map on its own.
///
/// [MenuStoreFailureReason.backendUnreachable] is deliberately absent: it
/// describes this client failing to reach the server at all, so a body
/// claiming it is not one this client trusts, and reads as
/// [MenuStoreFailureReason.badResponse] instead.
const Set<MenuStoreFailureReason> _wireReasons = <MenuStoreFailureReason>{
  MenuStoreFailureReason.notConfigured,
  MenuStoreFailureReason.tooLarge,
  MenuStoreFailureReason.timeout,
  MenuStoreFailureReason.rateLimited,
  MenuStoreFailureReason.rejected,
  MenuStoreFailureReason.badResponse,
};

/// [MenuStoreClient] backed by KetoClub's own backend: one
/// `POST {base}/v1/menus` per [upload].
///
/// **No credentials on the device.** This client sends no
/// `Authorization` header and no key of any kind; the only identifying
/// value it sends is the anonymous install id, as
/// `X-KetoClub-Install-Id`, read from the store on every call and used
/// by the backend for rate-limiting alone (architecture.md D8).
///
/// **No retries, no pre-check.** One [upload] is exactly one request;
/// the call is the probe (architecture.md §14 D10).
///
/// **Nothing personal leaves, nothing private is logged.** The body is
/// [MenuUpload.toJson], which drops the analysis's `options`. Each
/// failure logs one line naming the reason and, when there is one, the
/// HTTP status: never a body, never the install id.
final class BackendMenuStoreClient implements MenuStoreClient {
  /// Creates a client that posts to [baseUrl]'s `/v1/menus` through
  /// [client], identifying the install with [installIdStore]'s id and
  /// logging failures through [logger].
  ///
  /// A null [baseUrl] means this build has no backend configured: every
  /// [upload] then resolves to [MenuStoreFailureReason.notConfigured]
  /// without any I/O at all — not even reading the install id.
  ///
  /// [timeout] bounds the single HTTP request; exceeding it is
  /// [MenuStoreFailureReason.timeout].
  ///
  /// `client`, `installIdStore` and `logger` are assigned explicitly
  /// rather than as initializing formals, which would make the parameter
  /// names themselves private.
  new({
    required http.Client client,
    required this.baseUrl,
    required InstallIdStore installIdStore,
    required AppLogger logger,
    this.timeout = const Duration(seconds: 20),
  }) : // See the constructor doc for why this is not an initializing
       // formal.
       // ignore: prefer_initializing_formals
       _client = client,
       // Same reason as `_client` above.
       // ignore: prefer_initializing_formals
       _installIdStore = installIdStore,
       // Same reason as `_client` above.
       // ignore: prefer_initializing_formals
       _logger = logger;

  /// The header carrying the anonymous install id (`backend_plan.md`
  /// §3.4).
  static const String installIdHeader = 'X-KetoClub-Install-Id';

  /// KetoClub's backend, or null when this build has none.
  final Uri? baseUrl;

  /// How long the single HTTP request is given before it is abandoned.
  final Duration timeout;

  final http.Client _client;
  final InstallIdStore _installIdStore;
  final AppLogger _logger;

  @override
  bool get isConfigured => baseUrl != null;

  @override
  Future<MenuStoreResult> upload(MenuUpload upload) async {
    final baseUrl = this.baseUrl;
    if (baseUrl == null) {
      return _fail(MenuStoreFailureReason.notConfigured);
    }

    final body = jsonEncode(upload.toJson());
    if (utf8.encode(body).length > maxMenuUploadBytes) {
      return _fail(MenuStoreFailureReason.tooLarge);
    }

    final installId = await _installIdStore.id();
    final http.Response response;
    try {
      response = await _client
          .post(
            _menusUri(baseUrl),
            headers: <String, String>{
              'Content-Type': 'application/json',
              installIdHeader: installId,
            },
            body: body,
          )
          .timeout(timeout);
    } on TimeoutException {
      return _fail(MenuStoreFailureReason.timeout);
    } on http.ClientException {
      return _fail(MenuStoreFailureReason.backendUnreachable);
    }

    final statusCode = response.statusCode;
    return switch (statusCode) {
      201 => const MenuStored(created: true),
      200 => const MenuStored(created: false),
      429 => _fail(MenuStoreFailureReason.rateLimited, statusCode),
      413 => _fail(MenuStoreFailureReason.tooLarge, statusCode),
      400 || 422 => _fail(MenuStoreFailureReason.rejected, statusCode),
      _ => _fail(_reasonFrom(response), statusCode),
    };
  }

  /// Logs one line for [reason] (and [statusCode], when the backend
  /// answered) and returns the matching failure.
  MenuStoreFailed _fail(MenuStoreFailureReason reason, [int? statusCode]) {
    final status = statusCode == null ? '' : ' (HTTP $statusCode)';
    _logger.warn('Menu upload failed: ${reason.name}$status');
    return MenuStoreFailed(reason: reason);
  }

  /// The menu-store endpoint under [base]: `{base}/v1/menus`, whether or
  /// not [base] itself ends with a trailing slash.
  static Uri _menusUri(Uri base) {
    final rendered = base.toString();
    final trimmed = rendered.endsWith('/')
        ? rendered.substring(0, rendered.length - 1)
        : rendered;
    return Uri.parse('$trimmed/v1/menus');
  }

  /// The wire reason an error [response]'s body names in its `reason`
  /// field, or [MenuStoreFailureReason.badResponse] when it names none
  /// this client trusts: a non-JSON body, an unknown name, or a
  /// client-only one.
  static MenuStoreFailureReason _reasonFrom(http.Response response) {
    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      return MenuStoreFailureReason.badResponse;
    }
    if (decoded is! Map<String, Object?>) {
      return MenuStoreFailureReason.badResponse;
    }
    final name = decoded['reason'];
    if (name is! String) return MenuStoreFailureReason.badResponse;
    for (final reason in _wireReasons) {
      if (reason.name == name) return reason;
    }
    return MenuStoreFailureReason.badResponse;
  }
}

/// A [MenuStoreClient] for a build with no menu store: never configured,
/// and every [upload] is [MenuStoreFailureReason.notConfigured] with no
/// I/O and nothing logged.
final class NoMenuStoreClient implements MenuStoreClient {
  /// Creates the client.
  const new();

  @override
  bool get isConfigured => false;

  @override
  Future<MenuStoreResult> upload(MenuUpload upload) async =>
      const MenuStoreFailed(reason: MenuStoreFailureReason.notConfigured);
}

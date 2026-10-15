import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show immutable;
import 'package:http/http.dart' as http;
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/platform/app_logger.dart';
import 'package:ketoclub/services/storage/install_id_store.dart';

/// What a kitchen told the user about one restriction in one dish
/// (ALG-14, issue #356).
enum ConfirmationPolarity {
  /// The staff confirmed the restriction's ingredient is in the dish.
  present,

  /// The staff confirmed the restriction's ingredient is not in the dish.
  absent,
}

/// What a dish fingerprint may look like: an opaque token of 1 to 64
/// letters, digits and `._:-`, never prose.
///
/// The same pattern the backend checks. A fingerprint that does not match
/// is refused on the device as [ConfirmationFailureReason.rejected], with
/// no request made, so a free-text note cannot ride in the field.
final RegExp dishFingerprintPattern = RegExp(r'^[A-Za-z0-9._:\-]{1,64}$');

/// Contributes one post-meal fact to KetoClub's community confirmations on
/// the backend (ALG-14, issue #356): "the kitchen confirmed this dish does
/// (not) contain this restriction's ingredient".
///
/// Interface only: `di.dart` is the only file that constructs a concrete
/// implementation. Every implementation answers with a
/// [ConfirmationResult] and never throws.
abstract interface class ConfirmationClient {
  /// Whether this client can reach the backend at all.
  ///
  /// False means every [confirm] resolves to
  /// [ConfirmationFailureReason.notConfigured] without any I/O.
  bool get isConfigured;

  /// Sends one confirmation: exactly one request, no retries.
  ///
  /// [ref] is the venue, [dishFingerprint] names the dish on that venue's
  /// menu, [restrictionId] is the taxonomy id the question was about and
  /// [polarity] is the answer. Nothing else is sent: no note, and nothing
  /// about the user.
  ///
  /// Never throws; every failure is a [ConfirmationFailed] naming why.
  Future<ConfirmationResult> confirm({
    required VenueRef ref,
    required String dishFingerprint,
    required String restrictionId,
    required ConfirmationPolarity polarity,
  });
}

/// What a [ConfirmationClient.confirm] call came to.
@immutable
sealed class ConfirmationResult {
  /// Const constructor so subclasses can be const.
  const new();
}

/// The backend accepted the confirmation.
@immutable
final class ConfirmationRecorded extends ConfirmationResult {
  /// Creates a success; [counted] says whether it was new.
  const new({required this.counted});

  /// True when the confirmation was counted (HTTP 201); false when this
  /// install had already confirmed the same fact (HTTP 200).
  final bool counted;

  @override
  bool operator ==(Object other) =>
      other is ConfirmationRecorded && other.counted == counted;

  @override
  int get hashCode => Object.hash(ConfirmationRecorded, counted);

  @override
  String toString() => 'ConfirmationRecorded(counted: $counted)';
}

/// The confirmation did not land, for [reason].
@immutable
final class ConfirmationFailed extends ConfirmationResult {
  /// Creates a failure for [reason].
  const new({required this.reason});

  /// Why the confirmation did not land.
  final ConfirmationFailureReason reason;

  @override
  bool operator ==(Object other) =>
      other is ConfirmationFailed && other.reason == reason;

  @override
  int get hashCode => Object.hash(ConfirmationFailed, reason);

  @override
  String toString() => 'ConfirmationFailed(reason: ${reason.name})';
}

/// Why a [ConfirmationClient.confirm] did not land. Every reason is
/// distinct, and none is collapsed into another (architecture.md §10).
enum ConfirmationFailureReason {
  /// This build has no backend configured; nothing was sent.
  notConfigured,

  /// The request did not complete within the client's timeout.
  timeout,

  /// The backend could not be reached at all: a socket, DNS or TLS
  /// failure before any HTTP status came back.
  backendUnreachable,

  /// The backend answered 429: this install has sent too many
  /// confirmations recently.
  rateLimited,

  /// The device or the backend refused the confirmation's content or
  /// shape: a fingerprint that is not a token, an unknown restriction id,
  /// or an HTTP 400, 413 or 422.
  rejected,

  /// The backend answered with any other status, or a success status
  /// this client does not expect.
  badResponse,
}

/// The [ConfirmationFailureReason]s a backend error body's `reason` may
/// name for a status this client does not map on its own.
///
/// [ConfirmationFailureReason.backendUnreachable] is deliberately absent:
/// it describes this client failing to reach the server at all, so a body
/// claiming it is not one this client trusts.
const Set<ConfirmationFailureReason> _wireReasons = <ConfirmationFailureReason>{
  ConfirmationFailureReason.notConfigured,
  ConfirmationFailureReason.timeout,
  ConfirmationFailureReason.rateLimited,
  ConfirmationFailureReason.rejected,
  ConfirmationFailureReason.badResponse,
};

/// [ConfirmationClient] backed by KetoClub's own backend: one
/// `POST {base}/v1/confirmations` per [confirm].
///
/// **No credentials on the device.** This client sends no
/// `Authorization` header and no key of any kind; the only identifying
/// value it sends is the anonymous install id, as
/// `X-KetoClub-Install-Id`, read from the store on every call. The
/// backend uses it for rate limiting and for telling a repeat from a new
/// confirmer, and stores it nowhere.
///
/// **No retries, no pre-check.** One [confirm] is exactly one request;
/// the call is the probe (architecture.md §14 D10).
///
/// **Nothing private is logged.** Each failure logs one line naming the
/// reason and, when there is one, the HTTP status: never a body, never
/// the venue, the dish, the restriction or the install id.
final class BackendConfirmationClient implements ConfirmationClient {
  /// Creates a client that posts to [baseUrl]'s `/v1/confirmations`
  /// through [client], identifying the install with [installIdStore]'s id
  /// and logging failures through [logger].
  ///
  /// A null [baseUrl] means this build has no backend configured: every
  /// [confirm] then resolves to [ConfirmationFailureReason.notConfigured]
  /// without any I/O at all, not even reading the install id.
  ///
  /// [timeout] bounds the single HTTP request; exceeding it is
  /// [ConfirmationFailureReason.timeout].
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
  Future<ConfirmationResult> confirm({
    required VenueRef ref,
    required String dishFingerprint,
    required String restrictionId,
    required ConfirmationPolarity polarity,
  }) async {
    final baseUrl = this.baseUrl;
    if (baseUrl == null) {
      return _fail(ConfirmationFailureReason.notConfigured);
    }
    if (restrictionId.isEmpty ||
        !dishFingerprintPattern.hasMatch(dishFingerprint)) {
      return _fail(ConfirmationFailureReason.rejected);
    }

    final body = jsonEncode(<String, Object?>{
      'venue': <String, Object?>{
        'source': ref.source.name,
        'platformId': ref.platformId,
      },
      'dishFingerprint': dishFingerprint,
      'restrictionId': restrictionId,
      'polarity': polarity.name,
    });

    final installId = await _installIdStore.id();
    final http.Response response;
    try {
      response = await _client
          .post(
            _confirmationsUri(baseUrl),
            headers: <String, String>{
              'Content-Type': 'application/json',
              installIdHeader: installId,
            },
            body: body,
          )
          .timeout(timeout);
    } on TimeoutException {
      return _fail(ConfirmationFailureReason.timeout);
    } on http.ClientException {
      return _fail(ConfirmationFailureReason.backendUnreachable);
    }

    final statusCode = response.statusCode;
    return switch (statusCode) {
      201 => const ConfirmationRecorded(counted: true),
      200 => const ConfirmationRecorded(counted: false),
      429 => _fail(ConfirmationFailureReason.rateLimited, statusCode),
      400 ||
      413 ||
      422 => _fail(ConfirmationFailureReason.rejected, statusCode),
      _ => _fail(_reasonFrom(response), statusCode),
    };
  }

  /// Logs one line for [reason] (and [statusCode], when the backend
  /// answered) and returns the matching failure.
  ConfirmationFailed _fail(
    ConfirmationFailureReason reason, [
    int? statusCode,
  ]) {
    final status = statusCode == null ? '' : ' (HTTP $statusCode)';
    _logger.warn('Confirmation failed: ${reason.name}$status');
    return ConfirmationFailed(reason: reason);
  }

  /// The confirmations endpoint under [base]: `{base}/v1/confirmations`,
  /// whether or not [base] itself ends with a trailing slash.
  static Uri _confirmationsUri(Uri base) {
    final rendered = base.toString();
    final trimmed = rendered.endsWith('/')
        ? rendered.substring(0, rendered.length - 1)
        : rendered;
    return Uri.parse('$trimmed/v1/confirmations');
  }

  /// The wire reason an error [response]'s body names in its `reason`
  /// field, or [ConfirmationFailureReason.badResponse] when it names none
  /// this client trusts.
  static ConfirmationFailureReason _reasonFrom(http.Response response) {
    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      return ConfirmationFailureReason.badResponse;
    }
    if (decoded is! Map<String, Object?>) {
      return ConfirmationFailureReason.badResponse;
    }
    final name = decoded['reason'];
    if (name is! String) return ConfirmationFailureReason.badResponse;
    for (final reason in _wireReasons) {
      if (reason.name == name) return reason;
    }
    return ConfirmationFailureReason.badResponse;
  }
}

/// A [ConfirmationClient] for a build with no backend: never configured,
/// and every [confirm] is [ConfirmationFailureReason.notConfigured] with
/// no I/O and nothing logged.
final class NoConfirmationClient implements ConfirmationClient {
  /// Creates the client.
  const new();

  @override
  bool get isConfigured => false;

  @override
  Future<ConfirmationResult> confirm({
    required VenueRef ref,
    required String dishFingerprint,
    required String restrictionId,
    required ConfirmationPolarity polarity,
  }) async =>
      const ConfirmationFailed(reason: ConfirmationFailureReason.notConfigured);
}

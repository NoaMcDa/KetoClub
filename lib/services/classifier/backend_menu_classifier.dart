/// The classifier that sends a menu the app already holds to KetoClub's
/// backend, `POST /v1/classify`, and reads back a complete analysis
/// (architecture.md D25, `backend_plan.md` §3.3; issue #328).
///
/// Also home to the wire helpers both D25 classifiers share — the route
/// address, the install-id header and the error-body mapping — so
/// `backend_scanned_menu_classifier.dart` reads an error exactly as this
/// file does. Each route's path is named only in its own file, as the
/// network-boundary test in `test/architecture/import_rules_test.dart`
/// requires.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/services/classifier/menu_classifier.dart';
import 'package:ketoclub/services/storage/install_id_store.dart';
import 'package:ketoclub/utils/constants.dart';

/// The header carrying the anonymous install id on every D25 analysis
/// route (`backend_plan.md` §3.4). The only identifying value either
/// backend classifier sends; neither ever sends `Authorization`.
const String backendInstallIdHeader = 'X-KetoClub-Install-Id';

/// The only [MenuAnalysisFailureReason] values KetoClub's backend sends as
/// the `reason` of an error body on its analysis routes (`backend_plan.md`
/// §3.3).
///
/// The client-only reasons are deliberately absent:
/// [MenuAnalysisFailureReason.backendUnreachable] describes the client
/// failing to reach the server at all, and `consentWithheld`,
/// `apiKeyMissing` and `apiKeyRejected` describe this device. A body
/// claiming one of them is not a body this client trusts, and reads as
/// [MenuAnalysisFailureReason.badResponse] instead.
const Set<MenuAnalysisFailureReason> _wireReasons = <MenuAnalysisFailureReason>{
  MenuAnalysisFailureReason.notConfigured,
  MenuAnalysisFailureReason.offline,
  MenuAnalysisFailureReason.timeout,
  MenuAnalysisFailureReason.rateLimited,
  MenuAnalysisFailureReason.badResponse,
  MenuAnalysisFailureReason.noDishesFound,
};

/// The route [path] (which starts with `/`) under [base], whether or not
/// [base] itself ends with a trailing slash.
Uri backendRouteUri(Uri base, String path) {
  final rendered = base.toString();
  final trimmed = rendered.endsWith('/')
      ? rendered.substring(0, rendered.length - 1)
      : rendered;
  return Uri.parse('$trimmed$path');
}

/// [response]'s body decoded as JSON, or null when it is not JSON at all —
/// including a body whose bytes are not valid in its declared encoding,
/// which [http.Response.body] reports as a [FormatException] too.
Object? decodeBackendBody(http.Response response) {
  try {
    return jsonDecode(response.body);
  } on FormatException {
    return null;
  }
}

/// The reason an error body from KetoClub's backend names, mapped by name
/// onto [MenuAnalysisFailureReason] (`backend_plan.md` §3.3).
///
/// [decoded] is the body as [decodeBackendBody] read it. Anything that
/// does not name a reason this client trusts — a non-JSON body, FastAPI's
/// `{"detail": …}` 422, `payloadTooLarge`, an unknown name or a
/// client-only one — is [MenuAnalysisFailureReason.badResponse]. Nothing
/// else from the body reaches the caller.
MenuAnalysisFailureReason backendFailureReasonFrom(Object? decoded) {
  if (decoded is! Map<String, Object?>) {
    return MenuAnalysisFailureReason.badResponse;
  }
  final name = decoded['reason'];
  if (name is! String) return MenuAnalysisFailureReason.badResponse;
  for (final reason in _wireReasons) {
    if (reason.name == name) return reason;
  }
  return MenuAnalysisFailureReason.badResponse;
}

/// The `options` object of a D25 analysis request: `{netCarbLimitGrams,
/// dietaryConstraints}`, the verdict-shaping half of [options] and so
/// exactly the snapshot the server echoes back on the analysis.
Map<String, Object?> backendOptionsJson(ClassificationOptions options) =>
    options.snapshot.toJson();

/// [MenuClassifier] backed by KetoClub's backend (architecture.md D25,
/// `backend_plan.md` §3.3): one `POST /v1/classify` per menu, answered
/// with a complete analysis the server made.
///
/// **One request, no retries.** Each [classify] call is exactly one
/// request; nothing pre-checks whether the server is up, so the call is
/// the probe (D10, D11). A socket or DNS failure is
/// [MenuAnalysisFailureReason.backendUnreachable] and exceeding [timeout]
/// is [MenuAnalysisFailureReason.timeout].
///
/// **The server's own fallback stands.** A Gemini failure on the server
/// is not an error: the server answers 200 with its ported rule engine's
/// analysis stamped `{"kind": "rules", "reason": …}`, and that analysis is
/// returned as it came. Only an empty analysis bucket (429 `rateLimited`),
/// a menu with no dish (422 `noDishesFound`) and refusals of the request
/// itself arrive as errors; each is mapped by its `reason` name.
///
/// **No credentials, and no consent check.** The request carries the
/// anonymous install id as [backendInstallIdHeader] and never an
/// `Authorization` header. Calling the route *is* the consent
/// (`backend_plan.md` §3.3), so this class must sit behind a router that
/// asks for consent first, as `RoutingMenuClassifier` does for its LLM
/// slot.
///
/// Announces [ClassifyingEngine.llm] through
/// [ClassificationOptions.onEngineStarted] as it starts a request — not
/// when there is no backend to ask. Never throws.
@immutable
final class BackendMenuClassifier implements MenuClassifier {
  /// Creates a classifier that posts to [baseUrl]'s `/v1/classify` through
  /// `client`, identifying the install with `installIdStore`'s id.
  ///
  /// A null [baseUrl] means this build has no backend configured: every
  /// [classify] call then resolves to
  /// [MenuAnalysisFailureReason.notConfigured] without any I/O at all —
  /// not even reading the install id.
  const new({
    required this._client,
    required this.baseUrl,
    required this._installIdStore,
    this.timeout = llmRequestTimeout,
  });

  /// The route this classifier posts to.
  static const String path = '/v1/classify';

  /// KetoClub's backend, or null when this build has none.
  final Uri? baseUrl;

  /// How long the single HTTP request is given before it is abandoned.
  final Duration timeout;

  final http.Client _client;
  final InstallIdStore _installIdStore;

  @override
  Future<MenuAnalysis> classify(
    Menu menu, {
    ClassificationOptions options = const ClassificationOptions(),
  }) async {
    final baseUrl = this.baseUrl;
    if (baseUrl == null) {
      return const MenuAnalysisFailed(
        reason: MenuAnalysisFailureReason.notConfigured,
      );
    }
    // Announced before any await, as the on-device engines do (#65).
    options.onEngineStarted?.call(ClassifyingEngine.llm);

    final http.Response response;
    try {
      final installId = await _installIdStore.id();
      response = await _client
          .post(
            backendRouteUri(baseUrl, path),
            headers: <String, String>{
              'Content-Type': 'application/json',
              backendInstallIdHeader: installId,
            },
            body: jsonEncode(<String, Object?>{
              'menu': menu.toJson(),
              'options': backendOptionsJson(options),
            }),
          )
          .timeout(timeout);
    } on TimeoutException {
      return const MenuAnalysisFailed(
        reason: MenuAnalysisFailureReason.timeout,
      );
    } on http.ClientException {
      return const MenuAnalysisFailed(
        reason: MenuAnalysisFailureReason.backendUnreachable,
      );
    }
    return _read(response, menu);
  }

  /// The analysis [response] carries for [menu], or the failure it names.
  static MenuAnalysis _read(http.Response response, Menu menu) {
    final statusCode = response.statusCode;
    final decoded = decodeBackendBody(response);
    if (statusCode < 200 || statusCode >= 300) {
      return MenuAnalysisFailed(reason: backendFailureReasonFrom(decoded));
    }
    final analysis = _analysisFrom(decoded);
    if (analysis == null || !_namesOnlyDishesOf(analysis, menu)) {
      return const MenuAnalysisFailed(
        reason: MenuAnalysisFailureReason.badResponse,
      );
    }
    return analysis;
  }

  /// The `analysis` of a success body, or null when it has none this
  /// client can read.
  static MenuAnalysed? _analysisFrom(Object? decoded) {
    if (decoded is! Map<String, Object?>) return null;
    final raw = decoded['analysis'];
    if (raw is! Map<String, Object?>) return null;
    return MenuAnalysed.tryFrom(raw);
  }

  /// Whether every verdict in [analysis] is for a dish [menu] contains.
  ///
  /// The server's parser already drops an invented dish (§9.4); a reply
  /// that still names one is not a reply this client shows.
  static bool _namesOnlyDishesOf(MenuAnalysed analysis, Menu menu) {
    final ids = <String>{for (final dish in menu.allDishes) dish.id};
    return analysis.dishes.every((dish) => ids.contains(dish.dishId));
  }
}

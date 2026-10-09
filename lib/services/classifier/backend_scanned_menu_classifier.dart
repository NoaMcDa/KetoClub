/// The scanned-menu classifier that sends a scan's pages to KetoClub's
/// backend, `POST /v1/scan`, and reads back the menu and its analysis
/// (architecture.md D15, D25, `backend_plan.md` §3.3; issue #328).
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/scanned_menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/classifier/backend_menu_classifier.dart';
import 'package:ketoclub/services/classifier/menu_classifier.dart';
import 'package:ketoclub/services/classifier/scanned_menu_classifier.dart';
import 'package:ketoclub/services/storage/install_id_store.dart';
import 'package:ketoclub/utils/constants.dart';

/// [ScannedMenuClassifier] backed by KetoClub's backend (architecture.md
/// D25, `backend_plan.md` §3.3): every page of one scan, base64-encoded,
/// in one `POST /v1/scan`, answered with the transcribed menu and its
/// analysis.
///
/// **One request for the whole scan** (D6), no retries, and no
/// pre-check: the call is the probe. A socket or DNS failure is
/// [MenuAnalysisFailureReason.backendUnreachable]; exceeding [timeout] is
/// [MenuAnalysisFailureReason.timeout]; an error body is mapped by its
/// `reason` name exactly as `BackendMenuClassifier` maps one
/// ([backendFailureReasonFrom]). There is no rules fallback on the server
/// or here (D15): the rule engine needs text a photograph does not have.
///
/// **Pages leave the device only here.** Each page is sent as
/// `{mimeType, data}` with `data` the page's bytes in base64; nothing of
/// them is logged, cached or kept. The request carries the anonymous
/// install id as [backendInstallIdHeader] and never an `Authorization`
/// header. Calling the route is the consent (`backend_plan.md` §3.3), so
/// this class must sit behind a router that asks for consent first, as
/// `RoutingScannedMenuClassifier` does.
///
/// A read is checked before it is returned: its menu must be addressed
/// to [MenuSource.scan] and every verdict must name a dish of that menu,
/// the two promises [ScannedMenuRead] makes; a reply that breaks either is
/// [MenuAnalysisFailureReason.badResponse].
///
/// Announces [ClassifyingEngine.llm] through
/// [ClassificationOptions.onEngineStarted] as it starts a request — not
/// for an empty scan or when there is no backend. Never throws.
@immutable
final class BackendScannedMenuClassifier implements ScannedMenuClassifier {
  /// Creates a classifier that posts to [baseUrl]'s `/v1/scan` through
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
  static const String path = '/v1/scan';

  /// KetoClub's backend, or null when this build has none.
  final Uri? baseUrl;

  /// How long the single HTTP request is given before it is abandoned.
  final Duration timeout;

  final http.Client _client;
  final InstallIdStore _installIdStore;

  @override
  Future<ScannedMenuResult> classify(
    ScannedMenu scan, {
    required ClassificationOptions options,
  }) async {
    final baseUrl = this.baseUrl;
    if (baseUrl == null) {
      return const ScannedMenuFailed(
        reason: MenuAnalysisFailureReason.notConfigured,
      );
    }
    // Nothing to read: no request, and no call spent on an empty one.
    if (scan.pages.isEmpty) {
      return const ScannedMenuFailed(
        reason: MenuAnalysisFailureReason.noDishesFound,
      );
    }
    // Announced before any await, as the vision engine does (#65).
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
              'pages': <Object?>[
                for (final page in scan.pages)
                  <String, Object?>{
                    'mimeType': page.mimeType,
                    'data': base64Encode(page.bytes),
                  },
              ],
              'options': backendOptionsJson(options),
            }),
          )
          .timeout(timeout);
    } on TimeoutException {
      return const ScannedMenuFailed(reason: MenuAnalysisFailureReason.timeout);
    } on http.ClientException {
      return const ScannedMenuFailed(
        reason: MenuAnalysisFailureReason.backendUnreachable,
      );
    }
    return _read(response);
  }

  /// The read [response] carries, or the failure it names.
  static ScannedMenuResult _read(http.Response response) {
    final statusCode = response.statusCode;
    final decoded = decodeBackendBody(response);
    if (statusCode < 200 || statusCode >= 300) {
      return ScannedMenuFailed(reason: backendFailureReasonFrom(decoded));
    }
    return _readFrom(decoded) ??
        const ScannedMenuFailed(reason: MenuAnalysisFailureReason.badResponse);
  }

  /// The [ScannedMenuRead] a success body holds, or null when it holds no
  /// menu and analysis this client can read and trust.
  static ScannedMenuRead? _readFrom(Object? decoded) {
    if (decoded is! Map<String, Object?>) return null;
    final rawMenu = decoded['menu'];
    final rawAnalysis = decoded['analysis'];
    if (rawMenu is! Map<String, Object?>) return null;
    if (rawAnalysis is! Map<String, Object?>) return null;
    final menu = Menu.tryFrom(rawMenu);
    final analysis = MenuAnalysed.tryFrom(rawAnalysis);
    if (menu == null || analysis == null) return null;
    if (menu.venueRef.source != MenuSource.scan) return null;
    final ids = <String>{for (final dish in menu.allDishes) dish.id};
    if (!analysis.dishes.every((dish) => ids.contains(dish.dishId))) {
      return null;
    }
    return ScannedMenuRead(menu: menu, analysis: analysis);
  }
}

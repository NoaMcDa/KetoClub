import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/services/menu/website/robots_txt.dart';
import 'package:ketoclub/services/menu/website/website_fetcher.dart';
import 'package:ketoclub/utils/constants.dart';
import 'package:ketoclub/utils/public_web_address.dart';

/// The User-Agent a phone sends to a restaurant's site: it names the
/// fetcher (the `robots.txt` token [robotsToken]) and a contact URL, the
/// same string the backend sends (`WEBSITE_USER_AGENT`).
const String websiteUserAgent =
    'KetoClubBot/1.0 (+https://github.com/NoaMcDa/KetoClub; menu reader)';

/// Fetches a restaurant's page straight from the site: iOS and Android
/// (architecture.md D17, D19), and a web build with no backend, where the
/// browser's cross-origin block is reported as
/// [MenuFetchFailureReason.blockedByBrowser].
///
/// The rules the backend route applies, applied here: logged out (the
/// client carries no cookie), [websiteUserAgent] where the platform lets a
/// request set it, public hosts on the default port only ([isPublicWebUrl],
/// checked on every hop), `robots.txt` read once per site per session (up
/// to [websiteMaxRobotsBytes]) and honoured (a 4xx means no rules; a 5xx
/// or no answer means the page is not fetched), `X-Robots-Tag: noai` and
/// `tdm-reservation: 1` honoured, at most [maxRedirects] redirects each
/// checked against the new site's `robots.txt`, and [websiteMaxHtmlBytes] /
/// [maxScanPageBytes] caps. One paste reads at most two pages, so no
/// per-site spacing is kept here; the backend, which serves many installs,
/// keeps one. Never throws: an error `package:http` does not wrap in a
/// `ClientException` (a TLS failure) is
/// [MenuFetchFailureReason.websiteUnreachable].
final class DirectWebsiteFetcher implements WebsiteFetcher {
  /// Creates a fetcher over [client]. [runsInBrowser] exists so a test can
  /// exercise the browser mapping of a failed request on any platform.
  new({required http.Client client, this.runsInBrowser = kIsWeb})
    // A private field, a public parameter name.
    // ignore: prefer_initializing_formals
    : _client = client;

  /// The most redirects one fetch follows.
  static const int maxRedirects = 5;

  final http.Client _client;

  /// Whether requests go out through a browser, which forbids setting a
  /// User-Agent and reports a cross-origin block as a failed request.
  final bool runsInBrowser;

  final Map<String, RobotsRules> _robots = <String, RobotsRules>{};

  @override
  Future<WebsiteFetchResult> fetch(Uri url) async {
    try {
      return await _fetch(url);
    } on Object {
      // The contract is "never throws"; whatever slipped past the
      // per-request catches below is the site's failure, not a crash.
      return _unreachable;
    }
  }

  Future<WebsiteFetchResult> _fetch(Uri url) async {
    var current = url;
    for (var hop = 0; hop <= maxRedirects; hop++) {
      // The backend's `invalidUrl`, which the web build also reads as
      // unsupportedSource: not http(s), user info, another port, or a
      // host on a private network.
      if (!isPublicWebUrl(current)) {
        return const WebsiteFetchFailed(
          reason: MenuFetchFailureReason.unsupportedSource,
        );
      }
      final robots = await _robotsFor(current);
      if (robots is WebsiteFetchFailed) return robots;
      if (robots is RobotsRules && !robots.allows(current)) {
        return const WebsiteFetchFailed(
          reason: MenuFetchFailureReason.disallowedByRobots,
        );
      }

      final http.StreamedResponse response;
      try {
        response = await _client
            .send(_request(current, accept: _accept))
            .timeout(websiteFetchTimeout);
      } on http.ClientException {
        return _clientFailure();
      } on Object {
        // A timeout, or a TLS failure `package:http` does not wrap.
        return _unreachable;
      }

      final location = response.headers['location'];
      if (response.statusCode >= 300 &&
          response.statusCode < 400 &&
          location != null) {
        unawaited(response.stream.drain<void>().catchError((Object _) {}));
        try {
          current = current.resolve(location);
        } on FormatException {
          return _unreachable;
        }
        continue;
      }
      return await _read(response, current);
    }
    return _unreachable;
  }

  static const String _accept =
      'text/html,application/xhtml+xml,application/pdf;q=0.9,*/*;q=0.1';

  http.Request _request(Uri url, {required String accept}) =>
      http.Request('GET', url)
        ..followRedirects = false
        ..headers.addAll(<String, String>{
          'Accept': accept,
          'Accept-Language': 'he,en;q=0.8',
          if (!runsInBrowser) 'User-Agent': websiteUserAgent,
        });

  /// The site's rules, or the failure that stops the fetch: a `robots.txt`
  /// that errs or does not answer means the site is not read.
  Future<Object> _robotsFor(Uri url) async {
    final origin = '${url.scheme}://${url.authority}';
    final cached = _robots[origin];
    if (cached != null) return cached;
    final http.StreamedResponse response;
    final Uint8List body;
    try {
      response = await _client
          .send(_request(Uri.parse('$origin/robots.txt'), accept: 'text/plain'))
          .timeout(websiteFetchTimeout);
      // Only the first websiteMaxRobotsBytes are read and parsed, as the
      // backend does: an endless robots.txt cannot exhaust the phone.
      body = await _readPrefix(
        response.stream,
        websiteMaxRobotsBytes,
      ).timeout(websiteFetchTimeout);
    } on http.ClientException {
      return _clientFailure();
    } on Object {
      return _unreachable;
    }
    if (response.statusCode >= 500) {
      return WebsiteFetchFailed(
        reason: MenuFetchFailureReason.websiteUnreachable,
        statusCode: response.statusCode,
      );
    }
    final rules = response.statusCode >= 200 && response.statusCode < 300
        ? RobotsRules.parse(utf8.decode(body, allowMalformed: true))
        : const RobotsRules();
    _robots[origin] = rules;
    return rules;
  }

  static const WebsiteFetchFailed _unreachable = WebsiteFetchFailed(
    reason: MenuFetchFailureReason.websiteUnreachable,
  );

  WebsiteFetchFailed _clientFailure() {
    // A browser reports a cross-origin refusal exactly as it reports a
    // dead network, and almost no restaurant site allows KetoClub's
    // origin, so in a browser a failed request is the block (§13).
    return WebsiteFetchFailed(
      reason: runsInBrowser
          ? MenuFetchFailureReason.blockedByBrowser
          : MenuFetchFailureReason.offline,
    );
  }

  Future<WebsiteFetchResult> _read(
    http.StreamedResponse response,
    Uri url,
  ) async {
    final status = response.statusCode;
    if (status == 404 || status == 410) {
      unawaited(response.stream.drain<void>().catchError((Object _) {}));
      return WebsiteFetchFailed(
        reason: MenuFetchFailureReason.notFound,
        statusCode: status,
      );
    }
    if (status < 200 || status >= 300) {
      unawaited(response.stream.drain<void>().catchError((Object _) {}));
      return WebsiteFetchFailed(
        reason: MenuFetchFailureReason.websiteUnreachable,
        statusCode: status,
      );
    }
    final headers = response.headers;
    if (_reservesAi(headers)) {
      unawaited(response.stream.drain<void>().catchError((Object _) {}));
      return const WebsiteFetchFailed(
        reason: MenuFetchFailureReason.disallowedByRobots,
      );
    }

    const limit = websiteMaxHtmlBytes > maxScanPageBytes
        ? websiteMaxHtmlBytes
        : maxScanPageBytes;
    final Uint8List bytes;
    try {
      final read = await _readCapped(
        response.stream,
        limit,
      ).timeout(websiteFetchTimeout);
      if (read == null) {
        return const WebsiteFetchFailed(
          reason: MenuFetchFailureReason.websiteTooLarge,
        );
      }
      bytes = read;
    } on http.ClientException {
      return _clientFailure();
    } on Object {
      return _unreachable;
    }

    final contentType = (headers['content-type'] ?? '').toLowerCase();
    final media = contentType.split(';').first.trim();
    if (media == 'application/pdf' || _startsWithPdfSignature(bytes)) {
      if (bytes.length > maxScanPageBytes) {
        return const WebsiteFetchFailed(
          reason: MenuFetchFailureReason.websiteTooLarge,
        );
      }
      return WebsitePdf(bytes: bytes, finalUrl: url);
    }
    if (media != 'text/html' && media != 'application/xhtml+xml') {
      return const WebsiteFetchFailed(
        reason: MenuFetchFailureReason.menuNotFound,
      );
    }
    if (bytes.length > websiteMaxHtmlBytes) {
      return const WebsiteFetchFailed(
        reason: MenuFetchFailureReason.websiteTooLarge,
      );
    }
    return WebsitePage(html: decodePage(bytes, contentType), finalUrl: url);
  }

  static Future<Uint8List?> _readCapped(
    Stream<List<int>> stream,
    int cap,
  ) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in stream) {
      if (builder.length + chunk.length > cap) return null;
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  /// At most the first [cap] bytes of [stream]; the rest is never read.
  static Future<Uint8List> _readPrefix(
    Stream<List<int>> stream,
    int cap,
  ) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in stream) {
      final room = cap - builder.length;
      if (chunk.length >= room) {
        builder.add(chunk.sublist(0, room));
        break;
      }
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  static bool _reservesAi(Map<String, String> headers) {
    final robotsTag = (headers['x-robots-tag'] ?? '').toLowerCase();
    if (robotsTag.split(',').map((part) => part.trim()).contains('noai')) {
      return true;
    }
    return (headers['tdm-reservation'] ?? '').trim() == '1';
  }

  static bool _startsWithPdfSignature(Uint8List bytes) =>
      bytes.length >= 5 &&
      bytes[0] == 0x25 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x44 &&
      bytes[3] == 0x46 &&
      bytes[4] == 0x2D;

  /// [bytes] decoded by [contentType]'s charset: UTF-8 by default, and the
  /// two legacy Hebrew code pages (`windows-1255`, `iso-8859-8`) that older
  /// Israeli sites still serve, whose letters sit at 0xE0–0xFA.
  static String decodePage(Uint8List bytes, String contentType) {
    final charset = RegExp(r'charset\s*=\s*"?([\w-]+)')
        .firstMatch(contentType)
        ?.group(1)
        ?.toLowerCase();
    if (charset == 'windows-1255' || charset == 'iso-8859-8') {
      return String.fromCharCodes(<int>[
        for (final byte in bytes)
          if (byte >= 0xE0 && byte <= 0xFA)
            0x05D0 + byte - 0xE0
          else if (byte == 0xA4)
            0x20AA
          else
            byte,
      ]);
    }
    return utf8.decode(bytes, allowMalformed: true);
  }
}

// A CORS-forwarding proxy for local web development (architecture.md §13).
//
// The restaurant platforms answer browser requests from foreign origins
// without `Access-Control-Allow-Origin`, so a web build cannot read a menu
// straight from them. This script forwards `GET /?url=<upstream>` to
// <upstream> and returns the platform's status, content type and body with
// that header added. It also answers the browser's preflight OPTIONS.
//
// It listens on 127.0.0.1 only and forwards only to the hosts in
// [allowedHosts], so it is not an open proxy. `tool/run_web.sh` starts it
// and points the app at it through `--dart-define=KETOCLUB_MENU_PROXY_URL`
// (see `lib/di.dart` and `CorsProxyClient`).
//
// Usage: dart run tool/cors_proxy.dart [--port <port>]

import 'dart:async';
import 'dart:io';

import 'package:ketoclub/utils/constants.dart';

/// Upstream hosts this proxy forwards to: the restaurant platforms
/// architecture.md §6.1 names. Any other host is refused.
const Set<String> allowedHosts = <String>{
  'restaurant-api.wolt.com',
  'www.10bis.co.il',
  'tgp-api.tabit.cloud',
};

/// The port used when `--port` is not given. Matches `tool/run_web.sh`.
const int defaultPort = 8787;

/// The query parameter carrying the upstream URL. Must match
/// `CorsProxyClient.urlParameter`.
const String urlParameter = 'url';

/// How long a forwarded request may take before the proxy answers 504.
const Duration upstreamTimeout = Duration(seconds: 20);

/// Starts the proxy and serves until the process is stopped.
Future<void> main(List<String> args) async {
  final port = _portFrom(args);
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
  stdout
    ..writeln('KetoClub CORS proxy listening on http://127.0.0.1:$port/')
    ..writeln('Forwarding to: ${allowedHosts.join(', ')}');

  final client = HttpClient();
  await for (final request in server) {
    unawaited(_handle(request, client));
  }
}

/// Reads `--port <n>` from [args], or [defaultPort].
int _portFrom(List<String> args) {
  final index = args.indexOf('--port');
  if (index == -1 || index + 1 >= args.length) return defaultPort;
  final parsed = int.tryParse(args[index + 1]);
  if (parsed == null || parsed < 1 || parsed > 65535) {
    stderr.writeln('Invalid --port value: ${args[index + 1]}');
    exit(64);
  }
  return parsed;
}

/// Answers one browser request: a preflight, a forwarded GET, or a refusal.
Future<void> _handle(HttpRequest request, HttpClient client) async {
  final response = request.response;
  response.headers.set('Access-Control-Allow-Origin', '*');

  if (request.method == 'OPTIONS') {
    response.headers
      ..set('Access-Control-Allow-Methods', 'GET, OPTIONS')
      ..set(
        'Access-Control-Allow-Headers',
        request.headers.value('access-control-request-headers') ?? '*',
      )
      ..set('Access-Control-Max-Age', '86400');
    response.statusCode = HttpStatus.noContent;
    await response.close();
    return;
  }

  if (request.method != 'GET') {
    await _refuse(
      response,
      HttpStatus.methodNotAllowed,
      'Only GET is proxied.',
    );
    return;
  }

  final upstream = Uri.tryParse(
    request.uri.queryParameters[urlParameter] ?? '',
  );
  if (upstream == null || upstream.scheme != 'https' || upstream.host.isEmpty) {
    await _refuse(
      response,
      HttpStatus.badRequest,
      'Pass an absolute https URL in the "$urlParameter" query parameter.',
    );
    return;
  }
  if (!allowedHosts.contains(upstream.host)) {
    await _refuse(
      response,
      HttpStatus.forbidden,
      '${upstream.host} is not a restaurant platform this proxy forwards to.',
    );
    return;
  }

  stdout.writeln('GET $upstream');
  try {
    final forwarded = await client.getUrl(upstream);
    forwarded.headers
      ..set(HttpHeaders.userAgentHeader, browserUserAgent)
      ..set(
        HttpHeaders.acceptHeader,
        request.headers.value(HttpHeaders.acceptHeader) ?? 'application/json',
      );
    final answer = await forwarded.close().timeout(upstreamTimeout);
    response.statusCode = answer.statusCode;
    final contentType = answer.headers.contentType;
    if (contentType != null) response.headers.contentType = contentType;
    await answer.pipe(response);
  } on TimeoutException {
    await _refuse(
      response,
      HttpStatus.gatewayTimeout,
      '${upstream.host} did not answer within ${upstreamTimeout.inSeconds}s.',
    );
  } on IOException catch (error) {
    await _refuse(
      response,
      HttpStatus.badGateway,
      'Could not reach ${upstream.host}: $error',
    );
  }
}

/// Ends [response] with [status] and a one-line plain-text [message].
Future<void> _refuse(HttpResponse response, int status, String message) async {
  stderr.writeln('$status $message');
  response
    ..statusCode = status
    ..headers.contentType = ContentType.text
    ..write(message);
  await response.close();
}

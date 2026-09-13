import 'package:http/http.dart' as http;

/// An [http.Client] that sends every request through a CORS-forwarding
/// proxy instead of straight to the request's own host (architecture.md
/// §13).
///
/// A browser refuses a restaurant platform's response because the
/// platform sends no `Access-Control-Allow-Origin` header. The fix the
/// architecture names is a proxy that forwards the request unchanged and
/// adds that header; this client is the app's half of it. The request's
/// URL is moved into the proxy's [urlParameter] query parameter, so the
/// proxy learns exactly what the platform would have: the venue
/// identifier and nothing else (architecture.md §11).
///
/// Native builds never need this — their HTTP stacks do not enforce CORS
/// — so the composition root wraps the menu client only when a proxy is
/// configured. `tool/cors_proxy.dart` is the matching development proxy.
final class CorsProxyClient extends http.BaseClient {
  /// Creates a client that forwards through [proxy] over [inner].
  new({required this.inner, required this.proxy});

  /// The query parameter the proxy reads the upstream URL from.
  static const String urlParameter = 'url';

  /// The client that actually talks to the proxy.
  final http.Client inner;

  /// The proxy's own URL, e.g. `http://localhost:8787/`. Any query
  /// parameters it already carries are kept beside [urlParameter].
  final Uri proxy;

  /// Where a request for [upstream] is actually sent: the proxy, with
  /// [upstream] in its [urlParameter] query parameter.
  Uri proxiedUrl(Uri upstream) => proxy.replace(
    queryParameters: <String, String>{
      ...proxy.queryParameters,
      urlParameter: upstream.toString(),
    },
  );

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final proxied = http.Request(request.method, proxiedUrl(request.url))
      ..headers.addAll(request.headers)
      ..followRedirects = request.followRedirects
      ..maxRedirects = request.maxRedirects
      ..persistentConnection = request.persistentConnection
      ..bodyBytes = await request.finalize().toBytes();
    return await inner.send(proxied);
  }

  @override
  void close() => inner.close();
}

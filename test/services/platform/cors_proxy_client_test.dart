import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ketoclub/services/platform/cors_proxy_client.dart';

/// The proxy every test forwards through.
final Uri _proxy = Uri.parse('http://localhost:8787/');

/// A platform URL of the shape the Wolt adapter sends.
final Uri _upstream = Uri.https(
  'restaurant-api.wolt.com',
  '/v4/venues/slug/vitrina-lilinblum/menu/data',
);

/// An inner client that records the one request it receives into
/// [captured] and answers it with [body].
http.Client _recording(List<http.Request> captured, {String body = '{}'}) =>
    MockClient((request) async {
      captured.add(request);
      return http.Response(body, 200);
    });

void main() {
  group('CorsProxyClient', () {
    test('proxiedUrl puts the upstream URL in the url query parameter', () {
      // Arrange
      final client = CorsProxyClient(
        inner: _recording(<http.Request>[]),
        proxy: _proxy,
      );

      // Act
      final proxied = client.proxiedUrl(_upstream);

      // Assert
      expect(proxied.scheme, equals('http'));
      expect(proxied.host, equals('localhost'));
      expect(proxied.port, equals(8787));
      expect(
        proxied.queryParameters[CorsProxyClient.urlParameter],
        equals(_upstream.toString()),
      );
    });

    test('proxiedUrl keeps query parameters the proxy URL already has', () {
      // Arrange
      final client = CorsProxyClient(
        inner: _recording(<http.Request>[]),
        proxy: Uri.parse('https://proxy.example/forward?token=abc'),
      );

      // Act
      final proxied = client.proxiedUrl(_upstream);

      // Assert
      expect(proxied.queryParameters['token'], equals('abc'));
      expect(
        proxied.queryParameters[CorsProxyClient.urlParameter],
        equals(_upstream.toString()),
      );
      expect(proxied.path, equals('/forward'));
    });

    test('get sends the request to the proxy not the upstream host', () async {
      // Arrange
      final captured = <http.Request>[];
      final client = CorsProxyClient(
        inner: _recording(captured),
        proxy: _proxy,
      );

      // Act
      await client.get(_upstream);

      // Assert
      expect(captured, hasLength(1));
      expect(captured.single.url, equals(client.proxiedUrl(_upstream)));
      expect(captured.single.url.host, equals('localhost'));
    });

    test('get forwards the method and headers unchanged', () async {
      // Arrange
      final captured = <http.Request>[];
      final client = CorsProxyClient(
        inner: _recording(captured),
        proxy: _proxy,
      );

      // Act
      await client.get(
        _upstream,
        headers: const <String, String>{'Accept': 'application/json'},
      );

      // Assert
      expect(captured.single.method, equals('GET'));
      expect(captured.single.headers['Accept'], equals('application/json'));
    });

    test('post forwards the body unchanged', () async {
      // Arrange
      final captured = <http.Request>[];
      final client = CorsProxyClient(
        inner: _recording(captured),
        proxy: _proxy,
      );

      // Act
      await client.post(_upstream, body: jsonEncode(<String, int>{'a': 1}));

      // Assert
      expect(captured.single.method, equals('POST'));
      expect(captured.single.body, equals('{"a":1}'));
    });

    test('get returns the response the proxy answered with', () async {
      // Arrange
      final client = CorsProxyClient(
        inner: _recording(<http.Request>[], body: '{"currency":"ILS"}'),
        proxy: _proxy,
      );

      // Act
      final response = await client.get(_upstream);

      // Assert
      expect(response.statusCode, equals(200));
      expect(response.body, equals('{"currency":"ILS"}'));
    });

    test('close closes the inner client', () {
      // Arrange
      final inner = _ClosableClient();

      // Act
      CorsProxyClient(inner: inner, proxy: _proxy).close();

      // Assert
      expect(inner.closed, isTrue);
    });
  });
}

/// An inner client that only records whether [close] was called.
final class _ClosableClient extends http.BaseClient {
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(const Stream<List<int>>.empty(), 200);

  @override
  void close() => closed = true;
}

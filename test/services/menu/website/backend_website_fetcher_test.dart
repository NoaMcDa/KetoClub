import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/services/menu/website/backend_website_fetcher.dart';
import 'package:ketoclub/services/menu/website/website_fetcher.dart';

import '../../../fakes/fake_install_id_store.dart';

final Uri _page = Uri.parse('https://cafe.example/menu');

http.Response _json(Object body, int status) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: {'content-type': 'application/json'},
);

Future<WebsiteFetchResult> _fetch(
  http.Client client, {
  String base = 'http://localhost:8000/',
}) => BackendWebsiteFetcher(
  client: client,
  proxyBase: Uri.parse(base),
  installIdStore: FakeInstallIdStore(installId: 'a' * 32),
).fetch(_page);

void main() {
  group('BackendWebsiteFetcher (issue #181)', () {
    test('posts the URL in the body with the install id', () async {
      // Arrange
      late http.Request sent;
      final client = MockClient((request) async {
        sent = request;
        return _json(<String, Object?>{
          'kind': 'html',
          'content_type': 'text/html',
          'body': '<p>סלט</p>',
          'final_url': 'https://cafe.example/he/menu',
        }, 200);
      });

      // Act
      final result = await _fetch(client);

      // Assert
      expect(sent.method, 'POST');
      expect(sent.url, Uri.parse('http://localhost:8000/v1/website/fetch'));
      expect(sent.headers['X-KetoClub-Install-Id'], 'a' * 32);
      expect(jsonDecode(sent.body), {'url': 'https://cafe.example/menu'});
      expect((result as WebsitePage).html, '<p>סלט</p>');
      expect(result.finalUrl, Uri.parse('https://cafe.example/he/menu'));
    });

    test('a PDF comes back as its decoded bytes', () async {
      final result = await _fetch(
        MockClient(
          (_) async => _json(<String, Object?>{
            'kind': 'pdf',
            'content_type': 'application/pdf',
            'body': base64Encode(utf8.encode('%PDF-1.7')),
            'final_url': 42,
          }, 200),
        ),
        base: 'http://localhost:8000',
      );

      expect(utf8.decode((result as WebsitePdf).bytes), '%PDF-1.7');
      expect(result.finalUrl, _page);
    });

    test('each backend reason maps to its own failure', () async {
      const expected = <String, MenuFetchFailureReason>{
        'invalidUrl': MenuFetchFailureReason.unsupportedSource,
        'disallowedByRobots': MenuFetchFailureReason.disallowedByRobots,
        'aiReserved': MenuFetchFailureReason.disallowedByRobots,
        'jsOnlyPage': MenuFetchFailureReason.jsOnlyPage,
        'tooLarge': MenuFetchFailureReason.websiteTooLarge,
        'unsupportedContent': MenuFetchFailureReason.menuNotFound,
        'notFound': MenuFetchFailureReason.notFound,
        'offline': MenuFetchFailureReason.websiteUnreachable,
        'timeout': MenuFetchFailureReason.websiteUnreachable,
        'upstreamStatus': MenuFetchFailureReason.websiteUnreachable,
        'rateLimited': MenuFetchFailureReason.websiteRateLimited,
        'somethingNew': MenuFetchFailureReason.platformChanged,
      };
      for (final MapEntry(key: wire, value: reason) in expected.entries) {
        final result = await _fetch(
          MockClient(
            (_) async => _json(<String, Object?>{
              'reason': wire,
              'status_code': 403,
            }, 403),
          ),
        );
        expect(result, isA<WebsiteFetchFailed>(), reason: wire);
        final failed = result as WebsiteFetchFailed;
        expect(failed.reason, reason, reason: wire);
        expect(failed.statusCode, 403);
        expect(failed.toString(), contains('WebsiteFetchFailed'));
      }
    });

    test('an unreachable backend is backendUnreachable', () async {
      final result = await _fetch(
        MockClient((_) async => throw http.ClientException('refused')),
      );
      expect(
        (result as WebsiteFetchFailed).reason,
        MenuFetchFailureReason.backendUnreachable,
      );
    });

    test('a timeout is websiteUnreachable', () async {
      final result = await _fetch(
        MockClient((_) async => throw TimeoutException('slow')),
      );
      expect(
        (result as WebsiteFetchFailed).reason,
        MenuFetchFailureReason.websiteUnreachable,
      );
    });

    test('a body off the contract is platformChanged', () async {
      for (final response in [
        http.Response('not json', 200),
        _json(<Object?>[1, 2], 200),
        _json(<String, Object?>{'kind': 'html'}, 200),
        _json(<String, Object?>{'kind': 'pdf', 'body': '!!!'}, 200),
        _json(<String, Object?>{'kind': 'gif', 'body': 'x'}, 200),
      ]) {
        final result = await _fetch(MockClient((_) async => response));
        expect(
          (result as WebsiteFetchFailed).reason,
          MenuFetchFailureReason.platformChanged,
          reason: response.body,
        );
      }
    });
  });
}

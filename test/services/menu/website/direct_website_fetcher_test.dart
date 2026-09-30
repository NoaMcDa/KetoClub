import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/services/menu/website/direct_website_fetcher.dart';
import 'package:ketoclub/services/menu/website/website_fetcher.dart';
import 'package:ketoclub/utils/constants.dart';

final Uri _home = Uri.parse('https://cafe.example/');
const String _page = '<p>Caesar salad 52</p>';
final Uint8List _pdf = Uint8List.fromList(utf8.encode('%PDF-1.7 menu'));

/// A site answering from [routes] by path; robots.txt is a 404 unless
/// [robots] is given. Every request is recorded in [seen].
MockClient _site(
  Map<String, http.Response Function()> routes, {
  http.Response Function()? robots,
  List<http.BaseRequest>? seen,
}) => MockClient((request) async {
  seen?.add(request);
  if (request.url.path == '/robots.txt') {
    return robots?.call() ?? http.Response('', 404);
  }
  final route = routes[request.url.path];
  return route == null ? http.Response('', 404) : route();
});

http.Response _html(String body, {Map<String, String> headers = const {}}) =>
    http.Response.bytes(
      utf8.encode(body),
      200,
      headers: <String, String>{
        'content-type': 'text/html; charset=utf-8',
        ...headers,
      },
    );

Future<WebsiteFetchResult> _fetch(
  http.Client client, {
  Uri? url,
  bool runsInBrowser = false,
}) => DirectWebsiteFetcher(
  client: client,
  runsInBrowser: runsInBrowser,
).fetch(url ?? _home);

MenuFetchFailureReason? _reason(WebsiteFetchResult result) =>
    result is WebsiteFetchFailed ? result.reason : null;

void main() {
  group('DirectWebsiteFetcher (issue #181)', () {
    test(
      'reads a page with the named User-Agent and no redirect-follow',
      () async {
        // Arrange
        final seen = <http.BaseRequest>[];
        final client = _site({'/': () => _html(_page)}, seen: seen);

        // Act
        final result = await _fetch(client);

        // Assert
        expect(result, isA<WebsitePage>());
        expect((result as WebsitePage).html, _page);
        expect(result.finalUrl, _home);
        final page = seen.last;
        expect(page.headers['User-Agent'], websiteUserAgent);
        expect(websiteUserAgent, contains('KetoClubBot/1.0 (+https://'));
        expect(page.followRedirects, isFalse);
        expect(page.headers.containsKey('Cookie'), isFalse);
      },
    );

    test('a browser sends no User-Agent of its own', () async {
      final seen = <http.BaseRequest>[];
      await _fetch(
        _site({'/': () => _html(_page)}, seen: seen),
        runsInBrowser: true,
      );
      expect(seen.last.headers.containsKey('User-Agent'), isFalse);
    });

    test('a PDF is returned as bytes, by type or by signature', () async {
      final byType = await _fetch(
        _site({
          '/m.pdf': () => http.Response.bytes(
            _pdf,
            200,
            headers: {'content-type': 'application/pdf'},
          ),
        }),
        url: Uri.parse('https://cafe.example/m.pdf'),
      );
      final bySignature = await _fetch(
        _site({
          '/dl': () => http.Response.bytes(
            _pdf,
            200,
            headers: {'content-type': 'application/octet-stream'},
          ),
        }),
        url: Uri.parse('https://cafe.example/dl'),
      );

      expect((byType as WebsitePdf).bytes, _pdf);
      expect((bySignature as WebsitePdf).bytes, _pdf);
    });

    test('a redirect is followed and reported as the final URL', () async {
      final result = await _fetch(
        _site({
          '/': () => http.Response('', 301, headers: {'location': '/he/'}),
          '/he/': () => _html(_page),
        }),
      );

      expect((result as WebsitePage).finalUrl.path, '/he/');
    });

    test('endless redirects give up as unreachable', () async {
      final result = await _fetch(
        _site({
          '/': () => http.Response('', 302, headers: {'location': '/'}),
        }),
      );
      expect(_reason(result), MenuFetchFailureReason.websiteUnreachable);
    });

    test('a redirect off http(s) is unsupported', () async {
      final result = await _fetch(
        _site({
          '/': () => http.Response(
            '',
            302,
            headers: {'location': 'ftp://cafe.example/m'},
          ),
        }),
      );
      expect(_reason(result), MenuFetchFailureReason.unsupportedSource);
    });

    group('robots.txt', () {
      test('a disallow refuses before the page is asked for', () async {
        final seen = <http.BaseRequest>[];
        final result = await _fetch(
          _site(
            {'/': () => _html(_page)},
            robots: () => http.Response('User-agent: *\nDisallow: /\n', 200),
            seen: seen,
          ),
        );

        expect(_reason(result), MenuFetchFailureReason.disallowedByRobots);
        expect(seen.map((r) => r.url.path), ['/robots.txt']);
      });

      test(
        'an allow lets the page through, and is read once per site',
        () async {
          final seen = <http.BaseRequest>[];
          final fetcher = DirectWebsiteFetcher(
            client: _site(
              {'/': () => _html(_page), '/menu': () => _html(_page)},
              robots: () => http.Response('User-agent: *\nAllow: /\n', 200),
              seen: seen,
            ),
            runsInBrowser: false,
          );

          await fetcher.fetch(_home);
          await fetcher.fetch(Uri.parse('https://cafe.example/menu'));

          expect(seen.map((r) => r.url.path), ['/robots.txt', '/', '/menu']);
        },
      );

      test('a missing robots.txt allows', () async {
        final result = await _fetch(_site({'/': () => _html(_page)}));
        expect(result, isA<WebsitePage>());
      });

      test('a failing robots.txt means the site is not read', () async {
        final result = await _fetch(
          _site({
            '/': () => _html(_page),
          }, robots: () => http.Response('', 503)),
        );
        expect(_reason(result), MenuFetchFailureReason.websiteUnreachable);
      });
    });

    group('refusals and limits', () {
      test('noai and TDM headers refuse', () async {
        for (final headers in [
          {'x-robots-tag': 'noindex, noai'},
          {'tdm-reservation': '1'},
        ]) {
          final result = await _fetch(
            _site({'/': () => _html(_page, headers: headers)}),
          );
          expect(
            _reason(result),
            MenuFetchFailureReason.disallowedByRobots,
            reason: '$headers',
          );
        }
      });

      test('a page over the HTML cap is too large', () async {
        final big = 'x' * (websiteMaxHtmlBytes + 1);
        final result = await _fetch(_site({'/': () => _html(big)}));
        expect(_reason(result), MenuFetchFailureReason.websiteTooLarge);
      });

      test('a PDF over the page cap is too large', () async {
        final big = Uint8List(maxScanPageBytes + 1)..setAll(0, _pdf);
        final result = await _fetch(
          _site({
            '/': () => http.Response.bytes(
              big,
              200,
              headers: {'content-type': 'application/pdf'},
            ),
          }),
        );
        expect(_reason(result), MenuFetchFailureReason.websiteTooLarge);
      });

      test('a stream past every cap is cut off', () async {
        final client = MockClient.streaming((request, _) async {
          if (request.url.path == '/robots.txt') {
            return http.StreamedResponse(const Stream.empty(), 404);
          }
          final chunk = List<int>.filled(1024 * 1024, 0x20);
          return http.StreamedResponse(
            Stream.fromIterable(List.filled(5, chunk)),
            200,
            headers: {'content-type': 'text/html'},
          );
        });
        final result = await _fetch(client);
        expect(_reason(result), MenuFetchFailureReason.websiteTooLarge);
      });

      test('another content type is no menu', () async {
        final result = await _fetch(
          _site({
            '/': () => http.Response.bytes(
              <int>[1, 2, 3],
              200,
              headers: {'content-type': 'image/png'},
            ),
          }),
        );
        expect(_reason(result), MenuFetchFailureReason.menuNotFound);
      });
    });

    group('status and transport', () {
      test('404 and 410 are notFound with the status', () async {
        for (final status in [404, 410]) {
          final result = await _fetch(
            _site({'/': () => http.Response('', status)}),
          );
          expect(result, isA<WebsiteFetchFailed>());
          final failed = result as WebsiteFetchFailed;
          expect(failed.reason, MenuFetchFailureReason.notFound);
          expect(failed.statusCode, status);
        }
      });

      test('another error status is unreachable', () async {
        final result = await _fetch(_site({'/': () => http.Response('', 500)}));
        expect(_reason(result), MenuFetchFailureReason.websiteUnreachable);
        expect((result as WebsiteFetchFailed).statusCode, 500);
      });

      test(
        'a failed request is offline on a phone, blocked in a browser',
        () async {
          final client = MockClient(
            (_) async => throw http.ClientException('x'),
          );
          expect(_reason(await _fetch(client)), MenuFetchFailureReason.offline);
          expect(
            _reason(await _fetch(client, runsInBrowser: true)),
            MenuFetchFailureReason.blockedByBrowser,
          );
        },
      );

      test(
        'a failed page request after robots.txt maps the same way',
        () async {
          final client = MockClient((request) async {
            if (request.url.path == '/robots.txt') {
              return http.Response('', 404);
            }
            throw http.ClientException('x');
          });
          expect(_reason(await _fetch(client)), MenuFetchFailureReason.offline);
        },
      );

      test('a timeout is unreachable', () async {
        final client = MockClient(
          (_) async => throw TimeoutException('Timed out'),
        );
        expect(
          _reason(await _fetch(client)),
          MenuFetchFailureReason.websiteUnreachable,
        );
      });

      test('a page timing out after robots.txt is unreachable', () async {
        final client = MockClient((request) async {
          if (request.url.path == '/robots.txt') return http.Response('', 404);
          throw TimeoutException('Timed out');
        });
        expect(
          _reason(await _fetch(client)),
          MenuFetchFailureReason.websiteUnreachable,
        );
      });
    });

    group('never throws', () {
      for (final (name, fail) in <(String, Never Function())>[
        (
          'an Exception package:http does not wrap',
          () => throw Exception('handshake'),
        ),
        ('an Error', () => throw StateError('plugin')),
      ]) {
        test('$name on robots.txt or the page is unreachable', () async {
          for (final onRobots in [true, false]) {
            // Arrange: a TLS HandshakeException reaches the caller as is.
            final client = MockClient((request) async {
              if (request.url.path == '/robots.txt' && !onRobots) {
                return http.Response('', 404);
              }
              fail();
            });

            // Act
            final result = await _fetch(client);

            // Assert
            expect(
              _reason(result),
              MenuFetchFailureReason.websiteUnreachable,
              reason: 'onRobots: $onRobots',
            );
          }
        });
      }

      test('an Error while reading the body is unreachable', () async {
        final client = MockClient.streaming((request, _) async {
          if (request.url.path == '/robots.txt') {
            return http.StreamedResponse(const Stream.empty(), 404);
          }
          return http.StreamedResponse(
            Stream<List<int>>.error(StateError('stream')),
            200,
            headers: {'content-type': 'text/html'},
          );
        });
        expect(
          _reason(await _fetch(client)),
          MenuFetchFailureReason.websiteUnreachable,
        );
      });

      test('a malformed Location header is unreachable', () async {
        final result = await _fetch(
          _site({
            '/': () =>
                http.Response('', 302, headers: {'location': 'http://[bad'}),
          }),
        );
        expect(_reason(result), MenuFetchFailureReason.websiteUnreachable);
      });
    });

    group("the backend's public-address check", () {
      for (final url in [
        'http://127.0.0.1/',
        'http://10.0.0.8/menu',
        'http://192.168.1.1/',
        'http://172.16.4.2/',
        'http://169.254.169.254/latest/meta-data/',
        'http://100.64.0.1/',
        'http://0.0.0.0/',
        'http://224.0.0.1/',
        'http://2130706433/',
        'http://0x7f.1/',
        'http://127.1/',
        'http://[::1]/',
        'http://[fc00::1]/',
        'http://[fd12:3456::1]/',
        'http://[fe80::1]/',
        'http://[::ffff:127.0.0.1]/',
        'http://localhost/',
        'http://router/',
        'http://printer.local/menu',
        'http://app.localhost/',
        'https://cafe.example:8443/',
        'http://cafe.example:8080/',
        'https://user:pw@cafe.example/',
      ]) {
        test('refuses $url before any request', () async {
          final seen = <http.BaseRequest>[];
          final result = await _fetch(
            _site({'/': () => _html(_page)}, seen: seen),
            url: Uri.parse(url),
          );
          expect(_reason(result), MenuFetchFailureReason.unsupportedSource);
          expect(seen, isEmpty);
        });
      }

      test('a public IP address and the default ports are fetched', () async {
        for (final url in [
          'http://93.184.215.14/',
          'https://cafe.example:443/',
          'http://cafe.example:80/',
        ]) {
          final result = await _fetch(
            _site({'/': () => _html(_page)}),
            url: Uri.parse(url),
          );
          expect(result, isA<WebsitePage>(), reason: url);
        }
      });

      test(
        'a redirect to a private address is refused, not followed',
        () async {
          // Arrange
          final seen = <http.BaseRequest>[];
          final client = _site({
            '/': () => http.Response(
              '',
              302,
              headers: {'location': 'http://192.168.1.1/admin'},
            ),
          }, seen: seen);

          // Act
          final result = await _fetch(client);

          // Assert
          expect(_reason(result), MenuFetchFailureReason.unsupportedSource);
          expect(seen.map((r) => r.url.host), everyElement('cafe.example'));
        },
      );
    });

    group('robots.txt parity with the backend', () {
      test('only the first websiteMaxRobotsBytes are parsed', () async {
        // Arrange: an Allow past the cap would tie with the Disallow and
        // win; cut off, it is never read.
        final robots =
            'User-agent: *\nDisallow: /\n'
            '#${'x' * websiteMaxRobotsBytes}\n'
            'Allow: /\n';

        // Act
        final result = await _fetch(
          _site({
            '/': () => _html(_page),
          }, robots: () => http.Response(robots, 200)),
        );

        // Assert
        expect(_reason(result), MenuFetchFailureReason.disallowedByRobots);
      });

      test('a huge robots.txt is not read to its end', () async {
        // Arrange: 4 MiB, eight times the cap.
        var pulled = 0;
        const chunkBytes = 64 * 1024;
        Iterable<List<int>> huge() sync* {
          yield utf8.encode('User-agent: *\nAllow: /\n');
          for (var i = 0; i < 64; i++) {
            pulled += 1;
            yield List<int>.filled(chunkBytes, 0x23);
          }
        }

        final client = MockClient.streaming((request, _) async {
          if (request.url.path == '/robots.txt') {
            return http.StreamedResponse(Stream.fromIterable(huge()), 200);
          }
          return http.StreamedResponse(
            Stream.value(utf8.encode(_page)),
            200,
            headers: {'content-type': 'text/html'},
          );
        });

        // Act
        final result = await _fetch(client);

        // Assert
        expect(result, isA<WebsitePage>());
        expect(pulled, lessThanOrEqualTo(websiteMaxRobotsBytes ~/ chunkBytes));
      });
    });

    test('decodePage reads the legacy Hebrew code pages', () {
      // "סלט" and a shekel sign in windows-1255, then plain UTF-8.
      final legacy = Uint8List.fromList([0xF1, 0xEC, 0xE8, 0x20, 0xA4]);
      expect(
        DirectWebsiteFetcher.decodePage(
          legacy,
          'text/html; charset=windows-1255',
        ),
        'סלט ₪',
      );
      expect(
        DirectWebsiteFetcher.decodePage(
          Uint8List.fromList(utf8.encode('סלט')),
          'text/html',
        ),
        'סלט',
      );
    });
  });
}

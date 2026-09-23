import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/services/menu/wolt/wolt_adapter.dart';
import 'package:ketoclub/utils/constants.dart';

import '../platform_menu_adapter_contract.dart';

/// The ref used everywhere a working fetch is exercised.
const VenueRef _refItHandles = VenueRef(
  source: MenuSource.wolt,
  platformId: 'vitrina-lilinblum',
);

/// A ref on a different [MenuSource], for the shared contract suite.
const VenueRef _refItRejects = VenueRef(
  source: MenuSource.tenbis,
  platformId: 'some-tenbis-id',
);

/// A minimal, valid, empty Wolt payload.
final String _emptyMenuBody = jsonEncode(<String, Object?>{
  'currency': 'ILS',
  'categories': <Object?>[],
  'items': <Object?>[],
  'options': <Object?>[],
});

/// The expected request URL for [_refItHandles].
final Uri _expectedUri = Uri.https(
  'restaurant-api.wolt.com',
  '/v4/venues/slug/vitrina-lilinblum/menu/data',
);

/// Builds an adapter whose client always answers with a valid, empty
/// menu, regardless of the request — enough for the shared contract
/// suite, which asserts shape and provenance only.
WoltMenuAdapter _buildContractAdapter() => WoltMenuAdapter(
  client: MockClient((request) async => http.Response(_emptyMenuBody, 200)),
);

void main() {
  runPlatformMenuAdapterContract(
    'WoltMenuAdapter',
    _buildContractAdapter,
    refItHandles: _refItHandles,
    refItRejects: _refItRejects,
  );

  group('WoltMenuAdapter', () {
    test('source is wolt', () {
      // Arrange
      final adapter = WoltMenuAdapter(
        client: MockClient((_) async {
          return http.Response(_emptyMenuBody, 200);
        }),
      );

      // Act
      final source = adapter.source;

      // Assert
      expect(source, equals(MenuSource.wolt));
    });

    test('fetch sends the exact venue/data URL', () async {
      // Arrange
      Uri? capturedUri;
      final adapter = WoltMenuAdapter(
        client: MockClient((request) async {
          capturedUri = request.url;
          return http.Response(_emptyMenuBody, 200);
        }),
      );

      // Act
      await adapter.fetch(_refItHandles);

      // Assert
      expect(capturedUri, equals(_expectedUri));
    });

    test('fetch sends the browser User-Agent and Accept headers outside a '
        'browser', () async {
      // Arrange
      Map<String, String>? capturedHeaders;
      final adapter = WoltMenuAdapter(
        client: MockClient((request) async {
          capturedHeaders = request.headers;
          return http.Response(_emptyMenuBody, 200);
        }),
        runsInBrowser: false,
      );

      // Act
      await adapter.fetch(_refItHandles);

      // Assert
      expect(capturedHeaders, isNotNull);
      expect(capturedHeaders!['User-Agent'], equals(browserUserAgent));
      expect(capturedHeaders!['Accept'], equals('application/json'));
    });

    test('fetch returns a menu carrying the requested ref', () async {
      // Arrange
      final adapter = WoltMenuAdapter(
        client: MockClient((request) async {
          return http.Response(_emptyMenuBody, 200);
        }),
      );

      // Act
      final result = await adapter.fetch(_refItHandles);

      // Assert
      expect(result, isA<MenuFetched>());
      expect((result as MenuFetched).menu.venueRef, equals(_refItHandles));
      expect(result.menu.currency, equals('ILS'));
    });

    test('fetch maps a 404 status to notFound with the status code', () async {
      // Arrange
      final adapter = WoltMenuAdapter(
        client: MockClient((request) async {
          return http.Response('not found', 404);
        }),
      );

      // Act
      final result = await adapter.fetch(_refItHandles);

      // Assert
      expect(
        result,
        equals(
          const MenuFetchFailed(
            reason: MenuFetchFailureReason.notFound,
            statusCode: 404,
          ),
        ),
      );
    });

    test('fetch maps a non-404 non-2xx status to platformChanged with the '
        'status code', () async {
      // Arrange
      final adapter = WoltMenuAdapter(
        client: MockClient((request) async {
          return http.Response('server error', 503);
        }),
      );

      // Act
      final result = await adapter.fetch(_refItHandles);

      // Assert
      expect(
        result,
        equals(
          const MenuFetchFailed(
            reason: MenuFetchFailureReason.platformChanged,
            statusCode: 503,
          ),
        ),
      );
    });

    test('fetch maps a 2xx non-JSON body to platformChanged with no status '
        'code', () async {
      // Arrange
      final adapter = WoltMenuAdapter(
        client: MockClient((request) async {
          return http.Response('<html>not json</html>', 200);
        }),
      );

      // Act
      final result = await adapter.fetch(_refItHandles);

      // Assert
      expect(
        result,
        equals(
          const MenuFetchFailed(reason: MenuFetchFailureReason.platformChanged),
        ),
      );
    });

    test(
      'fetch maps a 2xx JSON body of the wrong shape to platformChanged',
      () async {
        // Arrange
        final adapter = WoltMenuAdapter(
          client: MockClient((request) async {
            return http.Response(
              jsonEncode(<String, Object?>{'resultCode': 0}),
              200,
            );
          }),
        );

        // Act
        final result = await adapter.fetch(_refItHandles);

        // Assert
        expect(
          result,
          equals(
            const MenuFetchFailed(
              reason: MenuFetchFailureReason.platformChanged,
            ),
          ),
        );
      },
    );

    test('fetch maps a ClientException to offline outside a browser', () async {
      // Arrange
      final adapter = WoltMenuAdapter(
        client: MockClient((request) async {
          throw http.ClientException('Connection failed', request.url);
        }),
        runsInBrowser: false,
      );

      // Act
      final result = await adapter.fetch(_refItHandles);

      // Assert
      expect(
        result,
        equals(const MenuFetchFailed(reason: MenuFetchFailureReason.offline)),
      );
    });

    test(
      'fetch maps a ClientException to blockedByBrowser in a browser',
      () async {
        // Arrange: a browser reports a CORS block the same way it reports a
        // dead network (architecture.md §13), so the adapter must tell them
        // apart by where it runs, never by the exception.
        final adapter = WoltMenuAdapter(
          client: MockClient((request) async {
            throw http.ClientException('Failed to fetch', request.url);
          }),
          runsInBrowser: true,
        );

        // Act
        final result = await adapter.fetch(_refItHandles);

        // Assert
        expect(
          result,
          equals(
            const MenuFetchFailed(
              reason: MenuFetchFailureReason.blockedByBrowser,
            ),
          ),
        );
      },
    );

    test('fetch omits the User-Agent header in a browser', () async {
      // Arrange: a page may not set User-Agent; a browser drops it with a
      // console warning, so the adapter does not send it there.
      Map<String, String>? capturedHeaders;
      final adapter = WoltMenuAdapter(
        client: MockClient((request) async {
          capturedHeaders = request.headers;
          return http.Response(_emptyMenuBody, 200);
        }),
        runsInBrowser: true,
      );

      // Act
      await adapter.fetch(_refItHandles);

      // Assert
      expect(capturedHeaders, isNotNull);
      expect(capturedHeaders!.containsKey('User-Agent'), isFalse);
      expect(capturedHeaders!['Accept'], equals('application/json'));
    });

    test('fetch maps a TimeoutException to offline', () async {
      // Arrange
      final adapter = WoltMenuAdapter(
        client: MockClient((request) async {
          throw TimeoutException('Timed out');
        }),
      );

      // Act
      final result = await adapter.fetch(_refItHandles);

      // Assert
      expect(
        result,
        equals(const MenuFetchFailed(reason: MenuFetchFailureReason.offline)),
      );
    });
  });

  group('WoltMenuAdapter with a proxy base', () {
    /// The proxied ref used throughout this group.
    const ref = VenueRef(source: MenuSource.wolt, platformId: 'my-venue');

    /// The proxy request URL a base with no trailing slash should produce.
    final expectedProxyUri = Uri.parse(
      'http://localhost:8000/v1/proxy/wolt/v4/venues/slug/my-venue/'
      'menu/data',
    );

    runPlatformMenuAdapterContract(
      'WoltMenuAdapter (proxy)',
      () => WoltMenuAdapter(
        client: MockClient((request) async {
          return http.Response(_emptyMenuBody, 200);
        }),
        proxyBase: Uri.parse('http://localhost:8000'),
      ),
      refItHandles: _refItHandles,
      refItRejects: _refItRejects,
    );

    test('fetch sends the exact proxy URL for a base with no trailing '
        'slash', () async {
      // Arrange
      Uri? capturedUri;
      final adapter = WoltMenuAdapter(
        client: MockClient((request) async {
          capturedUri = request.url;
          return http.Response(_emptyMenuBody, 200);
        }),
        proxyBase: Uri.parse('http://localhost:8000'),
      );

      // Act
      await adapter.fetch(ref);

      // Assert
      expect(capturedUri, equals(expectedProxyUri));
    });

    test('fetch sends the exact proxy URL for a base with a trailing '
        'slash', () async {
      // Arrange
      Uri? capturedUri;
      final adapter = WoltMenuAdapter(
        client: MockClient((request) async {
          capturedUri = request.url;
          return http.Response(_emptyMenuBody, 200);
        }),
        proxyBase: Uri.parse('http://localhost:8000/'),
      );

      // Act
      await adapter.fetch(ref);

      // Assert
      expect(capturedUri, equals(expectedProxyUri));
    });

    test('fetch sends no User-Agent header with a proxy configured', () async {
      // Arrange
      Map<String, String>? capturedHeaders;
      final adapter = WoltMenuAdapter(
        client: MockClient((request) async {
          capturedHeaders = request.headers;
          return http.Response(_emptyMenuBody, 200);
        }),
        proxyBase: Uri.parse('http://localhost:8000'),
        runsInBrowser: false,
      );

      // Act
      await adapter.fetch(ref);

      // Assert: the backend sets its own User-Agent
      // (`backend_plan.md` §3.3).
      expect(capturedHeaders, isNotNull);
      expect(capturedHeaders!.containsKey('User-Agent'), isFalse);
      expect(capturedHeaders!['Accept'], equals('application/json'));
    });

    test(
      'fetch maps a ClientException to backendUnreachable in a browser',
      () async {
        // Arrange
        final adapter = WoltMenuAdapter(
          client: MockClient((request) async {
            throw http.ClientException('Failed to fetch', request.url);
          }),
          proxyBase: Uri.parse('http://localhost:8000'),
          runsInBrowser: true,
        );

        // Act
        final result = await adapter.fetch(ref);

        // Assert: distinct from blockedByBrowser — the browser now talks to
        // KetoClub's own origin, which grants itself CORS.
        expect(
          result,
          equals(
            const MenuFetchFailed(
              reason: MenuFetchFailureReason.backendUnreachable,
            ),
          ),
        );
      },
    );

    test(
      'fetch maps a ClientException to backendUnreachable outside a browser',
      () async {
        // Arrange
        final adapter = WoltMenuAdapter(
          client: MockClient((request) async {
            throw http.ClientException('Connection failed', request.url);
          }),
          proxyBase: Uri.parse('http://localhost:8000'),
          runsInBrowser: false,
        );

        // Act
        final result = await adapter.fetch(ref);

        // Assert
        expect(
          result,
          equals(
            const MenuFetchFailed(
              reason: MenuFetchFailureReason.backendUnreachable,
            ),
          ),
        );
      },
    );

    test('fetch maps a proxy 502 to offline', () async {
      // Arrange: the backend's own "Wolt unreachable" status
      // (`backend_plan.md` §3.3).
      final adapter = WoltMenuAdapter(
        client: MockClient((request) async {
          return http.Response('{"reason":"offline"}', 502);
        }),
        proxyBase: Uri.parse('http://localhost:8000'),
      );

      // Act
      final result = await adapter.fetch(ref);

      // Assert
      expect(
        result,
        equals(const MenuFetchFailed(reason: MenuFetchFailureReason.offline)),
      );
    });

    test('fetch maps a proxy 504 to offline', () async {
      // Arrange: the backend's own "Wolt timed out" status
      // (`backend_plan.md` §3.3).
      final adapter = WoltMenuAdapter(
        client: MockClient((request) async {
          return http.Response('{"reason":"timeout"}', 504);
        }),
        proxyBase: Uri.parse('http://localhost:8000'),
      );

      // Act
      final result = await adapter.fetch(ref);

      // Assert
      expect(
        result,
        equals(const MenuFetchFailed(reason: MenuFetchFailureReason.offline)),
      );
    });

    test(
      'fetch maps a TimeoutException to offline with a proxy configured',
      () async {
        // Arrange
        final adapter = WoltMenuAdapter(
          client: MockClient((request) async {
            throw TimeoutException('Timed out');
          }),
          proxyBase: Uri.parse('http://localhost:8000'),
        );

        // Act
        final result = await adapter.fetch(ref);

        // Assert
        expect(
          result,
          equals(const MenuFetchFailed(reason: MenuFetchFailureReason.offline)),
        );
      },
    );

    test('fetch maps a proxied 404 to notFound with the status code', () async {
      // Arrange: Wolt's own 404 passes through the backend unchanged
      // (`backend_plan.md` §3.3), so the mapping needs no change.
      final adapter = WoltMenuAdapter(
        client: MockClient((request) async {
          return http.Response('not found', 404);
        }),
        proxyBase: Uri.parse('http://localhost:8000'),
      );

      // Act
      final result = await adapter.fetch(ref);

      // Assert
      expect(
        result,
        equals(
          const MenuFetchFailed(
            reason: MenuFetchFailureReason.notFound,
            statusCode: 404,
          ),
        ),
      );
    });

    test(
      'fetch maps a proxied 500 to platformChanged with the status code',
      () async {
        // Arrange
        final adapter = WoltMenuAdapter(
          client: MockClient((request) async {
            return http.Response('server error', 500);
          }),
          proxyBase: Uri.parse('http://localhost:8000'),
        );

        // Act
        final result = await adapter.fetch(ref);

        // Assert
        expect(
          result,
          equals(
            const MenuFetchFailed(
              reason: MenuFetchFailureReason.platformChanged,
              statusCode: 500,
            ),
          ),
        );
      },
    );

    test('fetch returns a menu carrying the requested ref through a '
        'proxy', () async {
      // Arrange
      final adapter = WoltMenuAdapter(
        client: MockClient((request) async {
          return http.Response(_emptyMenuBody, 200);
        }),
        proxyBase: Uri.parse('http://localhost:8000'),
      );

      // Act
      final result = await adapter.fetch(ref);

      // Assert
      expect(result, isA<MenuFetched>());
      expect((result as MenuFetched).menu.venueRef, equals(ref));
    });
  });
}

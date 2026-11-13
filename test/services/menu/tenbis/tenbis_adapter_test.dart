import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/services/menu/tenbis/tenbis_adapter.dart';
import 'package:ketoclub/utils/constants.dart';

import '../../../fakes/fake_clock.dart';
import '../../../fakes/fake_transport_exceptions.dart';
import '../platform_menu_adapter_contract.dart';

/// The clock every adapter here stamps its menus with (issue #284).
final FakeClock _clock = FakeClock(DateTime.utc(2026, 11, 13, 9, 30));

/// The ref used everywhere a working fetch is exercised.
const VenueRef _refItHandles = VenueRef(
  source: MenuSource.tenbis,
  platformId: '654321',
);

/// A ref on a different [MenuSource], for the shared contract suite.
const VenueRef _refItRejects = VenueRef(
  source: MenuSource.wolt,
  platformId: 'some-wolt-slug',
);

/// A minimal, valid, empty 10bis payload, in the live envelope (#468).
final String _emptyMenuBody = jsonEncode(<String, Object?>{
  'Errors': null,
  'Success': true,
  'Data': <String, Object?>{'resId': 654321, 'categoriesList': <Object?>[]},
});

/// The expected direct request URL for [_refItHandles]: the endpoint
/// 10bis's own web app reads, with the query it sends (#468).
final Uri _expectedUri = Uri.parse(
  'https://www.10bis.co.il/NextApi/GetRestaurantMenu'
  '?culture=he-IL&uiCulture=he&restaurantId=654321&deliveryMethod=delivery',
);

/// Builds an adapter whose client always answers with a valid, empty
/// menu, regardless of the request — enough for the shared contract
/// suite, which asserts shape and provenance only.
TenBisAdapter _buildContractAdapter() => TenBisAdapter(
  clock: _clock,
  client: MockClient((request) async => http.Response(_emptyMenuBody, 200)),
);

void main() {
  runPlatformMenuAdapterContract(
    'TenBisAdapter',
    _buildContractAdapter,
    refItHandles: _refItHandles,
    refItRejects: _refItRejects,
  );

  group('TenBisAdapter', () {
    test('fetch sends the exact GetRestaurantMenu URL', () async {
      // Arrange
      Uri? capturedUri;
      final adapter = TenBisAdapter(
        clock: _clock,
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
      final adapter = TenBisAdapter(
        clock: _clock,
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

    test('fetch maps a 404 status to notFound with the status code', () async {
      // Arrange
      final adapter = TenBisAdapter(
        clock: _clock,
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
      final adapter = TenBisAdapter(
        clock: _clock,
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
      final adapter = TenBisAdapter(
        clock: _clock,
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
        final adapter = TenBisAdapter(
          clock: _clock,
          client: MockClient((request) async {
            return http.Response(jsonEncode(<String, Object?>{'x': 1}), 200);
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

    test('fetch maps a 200 body naming no restaurant to notFound', () async {
      // Arrange: 10bis's live answer to an id no restaurant has (#468).
      final adapter = TenBisAdapter(
        clock: _clock,
        client: MockClient((request) async {
          return http.Response(
            jsonEncode(<String, Object?>{
              'Errors': null,
              'Success': true,
              'Data': <String, Object?>{
                'resId': 654321,
                'categoriesList': null,
              },
            }),
            200,
          );
        }),
      );

      // Act
      final result = await adapter.fetch(_refItHandles);

      // Assert
      expect(
        result,
        equals(const MenuFetchFailed(reason: MenuFetchFailureReason.notFound)),
      );
    });

    test('fetch maps a ClientException to offline outside a browser', () async {
      // Arrange
      final adapter = TenBisAdapter(
        clock: _clock,
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
        final adapter = TenBisAdapter(
          clock: _clock,
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

    test('fetch stamps the menu with the injected clock (#284)', () async {
      // Arrange
      final adapter = TenBisAdapter(
        clock: _clock,
        client: MockClient(
          (request) async => http.Response(_emptyMenuBody, 200),
        ),
        runsInBrowser: false,
      );

      // Act
      final result = await adapter.fetch(_refItHandles);

      // Assert
      expect((result as MenuFetched).menu.fetchedAt, _clock.now());
    });

    for (final (label, error) in <(String, Exception)>[
      ('a TLS handshake failure', const FakeHandshakeException()),
      ('a socket closed mid-body', const FakeSocketException()),
    ]) {
      test('fetch maps $label to a failure, never a throw (#278)', () async {
        // Arrange: IOClient lets these through unwrapped.
        TenBisAdapter adapter({Uri? proxyBase}) => TenBisAdapter(
          clock: _clock,
          client: MockClient((request) async => throw error),
          proxyBase: proxyBase,
          runsInBrowser: false,
        );

        // Act
        final direct = await adapter().fetch(_refItHandles);
        final proxied = await adapter(
          proxyBase: Uri.parse('http://localhost:8000'),
        ).fetch(_refItHandles);

        // Assert
        expect(
          direct,
          const MenuFetchFailed(reason: MenuFetchFailureReason.offline),
        );
        expect(
          proxied,
          const MenuFetchFailed(
            reason: MenuFetchFailureReason.backendUnreachable,
          ),
        );
      });
    }

    test('fetch omits the User-Agent header in a browser', () async {
      // Arrange: a page may not set User-Agent; a browser drops it with a
      // console warning, so the adapter does not send it there.
      Map<String, String>? capturedHeaders;
      final adapter = TenBisAdapter(
        clock: _clock,
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
      final adapter = TenBisAdapter(
        clock: _clock,
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

  group('TenBisAdapter with a proxy base', () {
    /// The proxied ref used throughout this group.
    const ref = VenueRef(source: MenuSource.tenbis, platformId: '654321');

    /// The proxy request URL a base with no trailing slash should produce.
    final expectedProxyUri = Uri.parse(
      'http://localhost:8000/v1/proxy/tenbis/restaurants/654321/menu',
    );

    runPlatformMenuAdapterContract(
      'TenBisAdapter (proxy)',
      () => TenBisAdapter(
        clock: _clock,
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
      final adapter = TenBisAdapter(
        clock: _clock,
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
      final adapter = TenBisAdapter(
        clock: _clock,
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
      final adapter = TenBisAdapter(
        clock: _clock,
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
        final adapter = TenBisAdapter(
          clock: _clock,
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
        final adapter = TenBisAdapter(
          clock: _clock,
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
      // Arrange: the backend's own "10bis unreachable" status
      // (`backend_plan.md` §3.3, issue #122).
      final adapter = TenBisAdapter(
        clock: _clock,
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
      // Arrange: the backend's own "10bis timed out" status
      // (`backend_plan.md` §3.3, issue #122).
      final adapter = TenBisAdapter(
        clock: _clock,
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
  });
}

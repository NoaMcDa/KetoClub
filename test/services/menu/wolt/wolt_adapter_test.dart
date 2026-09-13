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
}

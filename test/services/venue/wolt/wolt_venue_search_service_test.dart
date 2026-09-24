import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/venue/venue_search_service.dart';
import 'package:ketoclub/services/venue/wolt/wolt_venue_search_service.dart';
import 'package:ketoclub/utils/constants.dart';

import '../venue_search_service_contract.dart';

/// The position every search here is made from (Rabin Square, Tel Aviv).
const double _lat = 32.0809;

/// See [_lat].
const double _lon = 34.7806;

/// The proxy base used throughout the proxy group.
final Uri _proxy = Uri.parse('http://localhost:8000');

/// The Wolt headers the direct path sends and the proxy path must not.
const List<String> _woltHeaderNames = <String>[
  'platform',
  'client-version',
  'clientversionnumber',
  'app-language',
  'x-wolt-web-clientid',
  'w-wolt-session-id',
  'User-Agent',
];

/// A version-4 UUID in canonical lowercase form.
final RegExp _uuid4 = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

/// The raw text of a fixture from `test/fixtures/`.
String _fixture(String fileName) =>
    File('test/fixtures/$fileName').readAsStringSync();

/// The `pages/restaurants` fixture body.
final String _restaurantsBody = _fixture('wolt_pages_restaurants.json');

/// The `pages/search` fixture body.
final String _searchBody = _fixture('wolt_pages_search.json');

/// A client answering a GET with the restaurants fixture and a POST with
/// the search fixture, recording every request into [requests] when
/// given.
MockClient _fixtureClient([List<http.Request>? requests]) =>
    MockClient((request) async {
      requests?.add(request);
      final body = request.method == 'POST' ? _searchBody : _restaurantsBody;
      return http.Response.bytes(
        utf8.encode(body),
        200,
        headers: <String, String>{
          'content-type': 'application/json; charset=utf-8',
        },
      );
    });

/// A client answering every request with [status] and [body].
MockClient _answering(int status, [String body = '{}']) =>
    MockClient((_) async => http.Response(body, status));

/// A client whose every request throws [error].
MockClient _throwing(Exception error) => MockClient((_) async => throw error);

/// A native, direct service over [client].
WoltVenueSearchService _direct(http.Client client, {Random? random}) =>
    WoltVenueSearchService(
      client: client,
      runsInBrowser: false,
      random: random,
    );

/// A native service over [client] routed through [_proxy].
WoltVenueSearchService _proxied(http.Client client, {bool browser = false}) =>
    WoltVenueSearchService(
      client: client,
      proxyBase: _proxy,
      runsInBrowser: browser,
    );

/// Runs a nearby search from the test position.
Future<VenueSearchResult> _nearby(WoltVenueSearchService service) =>
    service.nearby(latitude: _lat, longitude: _lon, language: 'en');

/// The platform ids in [result], which must be a [VenuesFound].
List<String> _slugs(VenueSearchResult result) {
  expect(result, isA<VenuesFound>());
  return (result as VenuesFound).venues.map((v) => v.ref.platformId).toList();
}

/// Asserts that both entry points of [service] answer [expected].
Future<void> _expectBoth(
  WoltVenueSearchService service,
  VenueSearchFailed expected,
) async {
  expect(await _nearby(service), equals(expected));
  expect(await service.byName('pizza', language: 'en'), equals(expected));
}

void main() {
  runVenueSearchServiceContract(
    'WoltVenueSearchService (direct)',
    () => _direct(_fixtureClient()),
  );
  runVenueSearchServiceContract(
    'WoltVenueSearchService (proxy)',
    () => _proxied(_fixtureClient(), browser: true),
  );
  runVenueSearchServiceContract(
    'WoltVenueSearchService (browser, no proxy)',
    () => WoltVenueSearchService(client: _fixtureClient(), runsInBrowser: true),
  );
  runVenueSearchServiceContract(
    'WoltVenueSearchService (failing client)',
    () => _direct(_throwing(http.ClientException('down'))),
  );

  group('WoltVenueSearchService direct to Wolt', () {
    test('nearby sends a GET to consumer-api pages/restaurants', () async {
      // Arrange
      final requests = <http.Request>[];
      final service = _direct(_fixtureClient(requests));

      // Act
      await _nearby(service);

      // Assert
      expect(requests, hasLength(1));
      expect(requests.single.method, equals('GET'));
      expect(
        requests.single.url,
        equals(
          Uri.https('consumer-api.wolt.com', '/v1/pages/restaurants', {
            'lat': '32.0809',
            'lon': '34.7806',
          }),
        ),
      );
    });

    test('nearby sends the wolt.com web header set', () async {
      // Arrange
      final requests = <http.Request>[];
      final service = _direct(_fixtureClient(requests));

      // Act
      await service.nearby(latitude: _lat, longitude: _lon, language: 'he');

      // Assert
      final headers = requests.single.headers;
      expect(headers['platform'], equals('Web'));
      expect(headers['client-version'], equals(woltClientVersion));
      expect(headers['clientversionnumber'], equals(woltClientVersion));
      expect(headers['app-language'], equals('he'));
      expect(headers['x-wolt-web-clientid'], matches(_uuid4));
      expect(headers['w-wolt-session-id'], equals('no-analytics-consent'));
      expect(headers['Accept'], equals('application/json'));
      expect(headers['User-Agent'], equals(browserUserAgent));
      expect(headers.containsKey('Authorization'), isFalse);
    });

    test('byName sends a POST to restaurant-api pages/search', () async {
      // Arrange
      final requests = <http.Request>[];
      final service = _direct(_fixtureClient(requests));

      // Act
      await service.byName(
        'pizza',
        latitude: _lat,
        longitude: _lon,
        language: 'en',
      );

      // Assert
      final request = requests.single;
      expect(request.method, equals('POST'));
      expect(
        request.url,
        equals(Uri.https('restaurant-api.wolt.com', '/v1/pages/search')),
      );
      expect(
        jsonDecode(request.body),
        equals(<String, Object?>{
          'q': 'pizza',
          'target': 'venues',
          'lat': _lat,
          'lon': _lon,
        }),
      );
      expect(request.headers['Content-Type'], startsWith('application/json'));
      expect(request.headers['platform'], equals('Web'));
      expect(request.headers['app-language'], equals('en'));
      expect(request.headers['User-Agent'], equals(browserUserAgent));
    });

    test('byName without a position sends no coordinates and keeps '
        "Wolt's order", () async {
      // Arrange
      final requests = <http.Request>[];
      final service = _direct(_fixtureClient(requests));

      // Act
      final result = await service.byName('pizza', language: 'en');

      // Assert
      expect(
        jsonDecode(requests.single.body),
        equals(<String, Object?>{'q': 'pizza', 'target': 'venues'}),
      );
      expect(
        _slugs(result),
        orderedEquals(<String>[
          'pizza-romana',
          'pizza-lena',
          'tony-vespa-allenby',
          'pizza-cloud',
        ]),
      );
    });

    test("byName with only one coordinate keeps Wolt's order", () async {
      // Arrange
      final requests = <http.Request>[];
      final service = _direct(_fixtureClient(requests));

      // Act
      final result = await service.byName(
        'pizza',
        latitude: _lat,
        language: 'en',
      );

      // Assert
      expect(
        jsonDecode(requests.single.body),
        equals(<String, Object?>{'q': 'pizza', 'target': 'venues'}),
      );
      expect(_slugs(result).first, equals('pizza-romana'));
    });

    test('byName trims the query and cuts it to the maximum length', () async {
      // Arrange
      final requests = <http.Request>[];
      final service = _direct(_fixtureClient(requests));
      final long = 'פ' * (venueSearchMaxQueryLength + 20);

      // Act
      await service.byName('  sushi  ', language: 'he');
      await service.byName(long, language: 'he');

      // Assert
      final first = jsonDecode(requests[0].body) as Map<String, Object?>;
      final second = jsonDecode(requests[1].body) as Map<String, Object?>;
      expect(first['q'], equals('sushi'));
      expect(
        (second['q']! as String).runes,
        hasLength(venueSearchMaxQueryLength),
      );
    });

    test('byName with a blank query sends nothing', () async {
      // Arrange
      final requests = <http.Request>[];
      final service = _direct(_fixtureClient(requests));

      // Act
      final result = await service.byName('   ', language: 'en');

      // Assert
      expect(result, equals(const VenuesFound(<Venue>[])));
      expect(requests, isEmpty);
    });

    test('keeps one web client id per instance', () async {
      // Arrange
      final requests = <http.Request>[];
      final service = _direct(_fixtureClient(requests));
      final other = _direct(_fixtureClient(requests), random: Random(7));

      // Act
      await _nearby(service);
      await service.byName('pizza', language: 'en');
      await _nearby(other);

      // Assert
      final ids = requests
          .map((request) => request.headers['x-wolt-web-clientid'])
          .toList();
      expect(ids[0], equals(ids[1]));
      expect(ids[2], matches(_uuid4));
      expect(ids[2], isNot(equals(ids[0])));
    });

    test('nearby returns the fixture venues nearest first, unlocated '
        'last', () async {
      // Arrange
      final service = _direct(_fixtureClient());

      // Act
      final result = await _nearby(service);

      // Assert
      expect(
        _slugs(result),
        orderedEquals(<String>[
          'hakosem',
          'shila-sharon-cohen',
          'mashya',
          'port-said',
          'vitrina-lilinblum',
          'ghost-kitchen-tlv',
        ]),
      );
    });

    test('byName with a position returns venues nearest first', () async {
      // Arrange
      final service = _direct(_fixtureClient());

      // Act
      final result = await service.byName(
        'pizza',
        latitude: _lat,
        longitude: _lon,
        language: 'en',
      );

      // Assert
      expect(
        _slugs(result),
        orderedEquals(<String>[
          'pizza-lena',
          'pizza-romana',
          'tony-vespa-allenby',
          'pizza-cloud',
        ]),
      );
    });

    test('maps 429 to rateLimited', () async {
      await _expectBoth(
        _direct(_answering(429)),
        const VenueSearchFailed(VenueSearchFailureReason.rateLimited),
      );
    });

    test('maps 410 and 430 to platformChanged with the status', () async {
      for (final status in <int>[410, 430]) {
        await _expectBoth(
          _direct(_answering(status)),
          VenueSearchFailed(
            VenueSearchFailureReason.platformChanged,
            statusCode: status,
          ),
        );
      }
    });

    test('maps another 4xx to platformChanged with the status', () async {
      await _expectBoth(
        _direct(_answering(404)),
        const VenueSearchFailed(
          VenueSearchFailureReason.platformChanged,
          statusCode: 404,
        ),
      );
    });

    test('maps a 5xx, 502 and 504 included, to platformChanged when no '
        'proxy sent it', () async {
      for (final status in <int>[500, 502, 503, 504]) {
        await _expectBoth(
          _direct(_answering(status)),
          VenueSearchFailed(
            VenueSearchFailureReason.platformChanged,
            statusCode: status,
          ),
        );
      }
    });

    test('maps a ClientException to offline', () async {
      await _expectBoth(
        _direct(_throwing(http.ClientException('Connection failed'))),
        const VenueSearchFailed(VenueSearchFailureReason.offline),
      );
    });

    test('maps a TimeoutException to timeout', () async {
      await _expectBoth(
        _direct(_throwing(TimeoutException('Timed out'))),
        const VenueSearchFailed(VenueSearchFailureReason.timeout),
      );
    });

    test('maps a 2xx body that is not JSON to platformChanged', () async {
      await _expectBoth(
        _direct(_answering(200, '<html>not json</html>')),
        const VenueSearchFailed(VenueSearchFailureReason.platformChanged),
      );
    });

    test(
      'maps a 2xx JSON body of the wrong shape to platformChanged',
      () async {
        for (final body in <String>['[]', '{"error_code":430}', '"x"']) {
          await _expectBoth(
            _direct(_answering(200, body)),
            const VenueSearchFailed(VenueSearchFailureReason.platformChanged),
          );
        }
      },
    );

    test('maps a 2xx page with no venues to an empty list', () async {
      // Arrange
      final service = _direct(_answering(200, '{"sections":[]}'));

      // Act & Assert
      expect(await _nearby(service), equals(const VenuesFound(<Venue>[])));
      expect(
        await service.byName('pizza', language: 'en'),
        equals(const VenuesFound(<Venue>[])),
      );
    });
  });

  group('WoltVenueSearchService in a browser with no proxy', () {
    test('answers blockedByBrowser without sending a request', () async {
      // Arrange
      final requests = <http.Request>[];
      final service = WoltVenueSearchService(
        client: _fixtureClient(requests),
        runsInBrowser: true,
      );

      // Act & Assert
      await _expectBoth(
        service,
        const VenueSearchFailed(VenueSearchFailureReason.blockedByBrowser),
      );
      expect(requests, isEmpty);
    });

    test('still answers a blank query with nothing', () async {
      // Arrange
      final service = WoltVenueSearchService(
        client: _fixtureClient(),
        runsInBrowser: true,
      );

      // Act
      final result = await service.byName('', language: 'en');

      // Assert
      expect(result, equals(const VenuesFound(<Venue>[])));
    });
  });

  group('WoltVenueSearchService through the proxy', () {
    test('nearby sends a GET to the proxy restaurants route', () async {
      // Arrange
      final requests = <http.Request>[];
      final service = _proxied(_fixtureClient(requests));

      // Act
      await service.nearby(latitude: _lat, longitude: _lon, language: 'he');

      // Assert
      expect(requests.single.method, equals('GET'));
      expect(
        requests.single.url.toString(),
        equals(
          'http://localhost:8000/v1/proxy/wolt/pages/restaurants'
          '?lat=32.0809&lon=34.7806&lang=he',
        ),
      );
    });

    test('tolerates a proxy base with a trailing slash', () async {
      // Arrange
      final requests = <http.Request>[];
      final service = WoltVenueSearchService(
        client: _fixtureClient(requests),
        proxyBase: Uri.parse('http://localhost:8000/'),
        runsInBrowser: true,
      );

      // Act
      await _nearby(service);
      await service.byName('pizza', language: 'en');

      // Assert
      expect(requests[0].url.path, equals('/v1/proxy/wolt/pages/restaurants'));
      expect(
        requests[1].url.toString(),
        equals('http://localhost:8000/v1/proxy/wolt/pages/search'),
      );
    });

    test('byName sends a POST with q, position and lang, and no '
        'target', () async {
      // Arrange
      final requests = <http.Request>[];
      final service = _proxied(_fixtureClient(requests));

      // Act
      await service.byName(
        'פיצה',
        latitude: _lat,
        longitude: _lon,
        language: 'he',
      );

      // Assert
      final request = requests.single;
      expect(request.method, equals('POST'));
      expect(
        request.url.toString(),
        equals('http://localhost:8000/v1/proxy/wolt/pages/search'),
      );
      expect(
        jsonDecode(request.body),
        equals(<String, Object?>{
          'q': 'פיצה',
          'lat': _lat,
          'lon': _lon,
          'lang': 'he',
        }),
      );
      expect(request.headers['Content-Type'], startsWith('application/json'));
    });

    test('sends none of the Wolt headers, in a browser or not', () async {
      for (final browser in <bool>[true, false]) {
        // Arrange
        final requests = <http.Request>[];
        final service = _proxied(_fixtureClient(requests), browser: browser);

        // Act
        await _nearby(service);
        await service.byName('pizza', language: 'en');

        // Assert
        for (final request in requests) {
          for (final name in _woltHeaderNames) {
            expect(
              request.headers.containsKey(name),
              isFalse,
              reason: '$name sent through the proxy (browser: $browser)',
            );
          }
          expect(request.headers['Accept'], equals('application/json'));
        }
      }
    });

    test('returns the venues nearest first', () async {
      // Arrange
      final service = _proxied(_fixtureClient(), browser: true);

      // Act
      final result = await _nearby(service);

      // Assert
      expect(_slugs(result).first, equals('hakosem'));
      expect(_slugs(result).last, equals('ghost-kitchen-tlv'));
    });

    test('maps a ClientException to backendUnreachable', () async {
      for (final browser in <bool>[true, false]) {
        await _expectBoth(
          _proxied(
            _throwing(http.ClientException('Failed to fetch')),
            browser: browser,
          ),
          const VenueSearchFailed(VenueSearchFailureReason.backendUnreachable),
        );
      }
    });

    test("maps the backend's 502 to offline", () async {
      await _expectBoth(
        _proxied(_answering(502, '{"reason":"offline"}')),
        const VenueSearchFailed(VenueSearchFailureReason.offline),
      );
    });

    test("maps the backend's 504 to timeout", () async {
      await _expectBoth(
        _proxied(_answering(504, '{"reason":"timeout"}')),
        const VenueSearchFailed(VenueSearchFailureReason.timeout),
      );
    });

    test('maps a TimeoutException to timeout', () async {
      await _expectBoth(
        _proxied(_throwing(TimeoutException('Timed out'))),
        const VenueSearchFailed(VenueSearchFailureReason.timeout),
      );
    });

    test('maps a passed-through 429 to rateLimited', () async {
      await _expectBoth(
        _proxied(_answering(429)),
        const VenueSearchFailed(VenueSearchFailureReason.rateLimited),
      );
    });

    test('maps a passed-through 410 to platformChanged', () async {
      await _expectBoth(
        _proxied(_answering(410)),
        const VenueSearchFailed(
          VenueSearchFailureReason.platformChanged,
          statusCode: 410,
        ),
      );
    });

    test('maps a 2xx body of the wrong shape to platformChanged', () async {
      await _expectBoth(
        _proxied(_answering(200, '{"detail":"nope"}')),
        const VenueSearchFailed(VenueSearchFailureReason.platformChanged),
      );
    });
  });

  test('the constructor sends nothing', () {
    // Arrange
    final requests = <http.Request>[];

    // Act
    WoltVenueSearchService(client: _fixtureClient(requests));

    // Assert
    expect(requests, isEmpty);
  });
}

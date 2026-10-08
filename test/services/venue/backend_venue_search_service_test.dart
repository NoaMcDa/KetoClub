import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/llm/backend_chat_client.dart';
import 'package:ketoclub/services/venue/backend_venue_search_service.dart';
import 'package:ketoclub/services/venue/venue_search_service.dart';
import 'package:ketoclub/utils/constants.dart';

import '../../fakes/fake_install_id_store.dart';
import '../../fakes/fake_venue_search_service.dart';
import 'venue_search_service_contract.dart';

/// The position every search here is made from (Rabin Square, Tel Aviv).
const double _lat = 32.0809;

/// See [_lat].
const double _lon = 34.7806;

final Uri _base = Uri.parse('http://localhost:8000');

/// A Wolt venue with slug [slug], located when [lat] and [lon] are given.
Venue _venue(String slug, {double? lat, double? lon}) => Venue(
  ref: VenueRef(source: MenuSource.wolt, platformId: slug),
  name: slug,
  latitude: lat,
  longitude: lon,
);

/// A 200 body carrying [venues] in the backend's `VenuesResponse` shape.
String _venuesBody(List<Venue> venues) => jsonEncode(<String, Object?>{
  'venues': <Object?>[for (final v in venues) v.toJson()],
});

/// A client answering every request with [status] and [body], recording
/// requests into [requests] when given.
MockClient _answering(
  int status,
  String body, [
  List<http.Request>? requests,
]) => MockClient((request) async {
  requests?.add(request);
  return http.Response(
    body,
    status,
    headers: <String, String>{'content-type': 'application/json'},
  );
});

/// A client whose every request throws [error].
MockClient _throwing(Exception error) => MockClient((_) async => throw error);

BackendVenueSearchService _service(
  http.Client client, {
  Uri? baseUrl,
  FakeInstallIdStore? store,
  Duration timeout = const Duration(seconds: 15),
}) => BackendVenueSearchService(
  client: client,
  baseUrl: baseUrl ?? _base,
  installIdStore: store ?? FakeInstallIdStore(),
  timeout: timeout,
);

Future<VenueSearchResult> _nearby(VenueSearchService service) =>
    service.nearby(latitude: _lat, longitude: _lon, language: 'en');

String _error(String reason, int status) =>
    jsonEncode(<String, Object?>{'reason': reason, 'status_code': status});

List<String> _slugs(VenueSearchResult result) {
  expect(result, isA<VenuesFound>());
  return (result as VenuesFound).venues.map((v) => v.ref.platformId).toList();
}

void main() {
  final contractBody = _venuesBody(<Venue>[
    _venue('far', lat: 32.2, lon: 34.8),
    _venue('near', lat: 32.081, lon: 34.781),
    _venue('nowhere'),
  ]);

  runVenueSearchServiceContract(
    'BackendVenueSearchService',
    () => _service(_answering(200, contractBody)),
  );
  runVenueSearchServiceContract(
    'BackendVenueSearchService (no backend)',
    () => BackendVenueSearchService(
      client: _answering(200, contractBody),
      baseUrl: null,
      installIdStore: FakeInstallIdStore(),
    ),
  );
  runVenueSearchServiceContract(
    'BackendVenueSearchService (failing client)',
    () => _service(_throwing(http.ClientException('down'))),
  );
  runVenueSearchServiceContract(
    'FallbackVenueSearchService',
    () => FallbackVenueSearchService(
      primary: _service(_throwing(http.ClientException('down'))),
      fallback: _service(_answering(200, contractBody)),
    ),
  );

  group('BackendVenueSearchService requests', () {
    test('nearby sends a GET with lat, lon and lang', () async {
      final requests = <http.Request>[];
      final service = _service(_answering(200, '{"venues":[]}', requests));

      await service.nearby(latitude: _lat, longitude: _lon, language: 'he');

      expect(requests, hasLength(1));
      expect(requests.single.method, equals('GET'));
      expect(
        requests.single.url,
        equals(
          Uri.parse(
            'http://localhost:8000/v1/venues/nearby'
            '?lat=32.0809&lon=34.7806&lang=he',
          ),
        ),
      );
    });

    test('a base URL with a trailing slash does not double it', () async {
      final requests = <http.Request>[];
      final service = _service(
        _answering(200, '{"venues":[]}', requests),
        baseUrl: Uri.parse('http://localhost:8000/'),
      );

      await _nearby(service);

      expect(requests.single.url.path, equals('/v1/venues/nearby'));
    });

    test('byName sends a POST with query, lang and both coordinates', () async {
      final requests = <http.Request>[];
      final service = _service(_answering(200, '{"venues":[]}', requests));

      await service.byName(
        '  pizza ',
        language: 'en',
        latitude: _lat,
        longitude: _lon,
      );

      final request = requests.single;
      expect(request.method, equals('POST'));
      expect(request.url.path, equals('/v1/venues/search'));
      expect(
        jsonDecode(request.body),
        equals(<String, Object?>{
          'query': 'pizza',
          'lang': 'en',
          'lat': _lat,
          'lon': _lon,
        }),
      );
    });

    test('byName omits the position unless both halves are given', () async {
      final requests = <http.Request>[];
      final service = _service(_answering(200, '{"venues":[]}', requests));

      await service.byName('a', language: 'en');
      await service.byName('a', language: 'en', latitude: _lat);
      await service.byName('a', language: 'en', longitude: _lon);

      for (final request in requests) {
        expect(
          jsonDecode(request.body),
          equals(<String, Object?>{'query': 'a', 'lang': 'en'}),
        );
      }
      expect(requests, hasLength(3));
    });

    test('byName clips a long query to the backend maximum', () async {
      final requests = <http.Request>[];
      final service = _service(_answering(200, '{"venues":[]}', requests));

      await service.byName('x' * 200, language: 'en');

      final body = jsonDecode(requests.single.body) as Map<String, Object?>;
      expect(
        (body['query']! as String).length,
        equals(venueSearchMaxQueryLength),
      );
    });

    test('a blank query sends nothing', () async {
      final requests = <http.Request>[];
      final store = FakeInstallIdStore();
      final service = _service(
        _answering(200, '{"venues":[]}', requests),
        store: store,
      );

      final result = await service.byName('   ', language: 'en');

      expect(result, equals(const VenuesFound(<Venue>[])));
      expect(requests, isEmpty);
      expect(store.calls, equals(0));
    });

    test('sends the install id, no Authorization header', () async {
      final requests = <http.Request>[];
      final service = _service(
        _answering(200, '{"venues":[]}', requests),
        store: FakeInstallIdStore(installId: 'f' * 32),
      );

      await _nearby(service);
      await service.byName('pizza', language: 'en');

      for (final request in requests) {
        expect(
          request.headers[BackendChatClient.installIdHeader],
          equals('f' * 32),
        );
        expect(request.headers.containsKey('Authorization'), isFalse);
        expect(request.headers['Accept'], equals('application/json'));
      }
      expect(requests.first.headers.containsKey('Content-Type'), isFalse);
      expect(requests.last.headers['Content-Type'], equals('application/json'));
    });

    test('a null base URL does no I/O and reads no install id', () async {
      final requests = <http.Request>[];
      final store = FakeInstallIdStore();
      final service = BackendVenueSearchService(
        client: _answering(200, '{"venues":[]}', requests),
        baseUrl: null,
        installIdStore: store,
      );
      const expected = VenueSearchFailed(
        VenueSearchFailureReason.backendUnreachable,
      );

      expect(await _nearby(service), equals(expected));
      expect(await service.byName('pizza', language: 'en'), equals(expected));
      expect(requests, isEmpty);
      expect(store.calls, equals(0));
    });
  });

  group('BackendVenueSearchService results', () {
    test('nearby sorts nearest first, unlocated last', () async {
      final service = _service(
        _answering(
          200,
          _venuesBody(<Venue>[
            _venue('nowhere'),
            _venue('far', lat: 32.2, lon: 34.8),
            _venue('near', lat: 32.081, lon: 34.781),
          ]),
        ),
      );

      expect(_slugs(await _nearby(service)), <String>[
        'near',
        'far',
        'nowhere',
      ]);
    });

    test('byName keeps the backend order without a position', () async {
      final service = _service(
        _answering(
          200,
          _venuesBody(<Venue>[
            _venue('far', lat: 32.2, lon: 34.8),
            _venue('near', lat: 32.081, lon: 34.781),
          ]),
        ),
      );

      final result = await service.byName('x', language: 'en');

      expect(_slugs(result), <String>['far', 'near']);
    });

    test('byName with a position sorts nearest first', () async {
      final service = _service(
        _answering(
          200,
          _venuesBody(<Venue>[
            _venue('far', lat: 32.2, lon: 34.8),
            _venue('near', lat: 32.081, lon: 34.781),
          ]),
        ),
      );

      final result = await service.byName(
        'x',
        language: 'en',
        latitude: _lat,
        longitude: _lon,
      );

      expect(_slugs(result), <String>['near', 'far']);
    });

    test('skips invalid venues and deduplicates by ref', () async {
      final body = jsonEncode(<String, Object?>{
        'venues': <Object?>[
          _venue('a').toJson(),
          <String, Object?>{'ref': 'broken'},
          _venue('a').toJson(),
          _venue('b').toJson(),
        ],
      });
      final service = _service(_answering(200, body));

      expect(_slugs(await _nearby(service)), <String>['a', 'b']);
    });

    test('an empty list is found, not a failure', () async {
      final service = _service(_answering(200, '{"venues":[]}'));

      expect(await _nearby(service), equals(const VenuesFound(<Venue>[])));
    });

    for (final body in <String>[
      '{}',
      '[]',
      'not json',
      '{"venues":{}}',
      '{"venues":[1]}',
      '{"venues":null}',
    ]) {
      test('a 200 body of $body is platformChanged', () async {
        final service = _service(_answering(200, body));

        expect(
          await _nearby(service),
          equals(
            const VenueSearchFailed(VenueSearchFailureReason.platformChanged),
          ),
        );
      });
    }
  });

  group('BackendVenueSearchService failures', () {
    Future<void> expectBoth(
      BackendVenueSearchService service,
      VenueSearchFailed expected,
    ) async {
      expect(await _nearby(service), equals(expected));
      expect(await service.byName('pizza', language: 'en'), equals(expected));
    }

    test('429 is rateLimited', () async {
      await expectBoth(
        _service(_answering(429, _error('rateLimited', 429))),
        const VenueSearchFailed(VenueSearchFailureReason.rateLimited),
      );
    });

    test('504 is timeout', () async {
      await expectBoth(
        _service(_answering(504, _error('timeout', 504))),
        const VenueSearchFailed(VenueSearchFailureReason.timeout),
      );
    });

    test('502 offline is offline', () async {
      await expectBoth(
        _service(_answering(502, _error('offline', 502))),
        const VenueSearchFailed(VenueSearchFailureReason.offline),
      );
    });

    test('502 platformChanged is platformChanged with its status', () async {
      await expectBoth(
        _service(_answering(502, _error('platformChanged', 502))),
        const VenueSearchFailed(
          VenueSearchFailureReason.platformChanged,
          statusCode: 502,
        ),
      );
    });

    for (final body in <String>['', 'oops', '{"reason":"weird"}', '[]']) {
      test('502 with body "$body" is backendUnreachable', () async {
        await expectBoth(
          _service(_answering(502, body)),
          const VenueSearchFailed(
            VenueSearchFailureReason.backendUnreachable,
            statusCode: 502,
          ),
        );
      });
    }

    for (final status in <int>[400, 404, 422, 500, 503]) {
      test('$status is backendUnreachable with the status', () async {
        await expectBoth(
          _service(_answering(status, _error('badResponse', status))),
          VenueSearchFailed(
            VenueSearchFailureReason.backendUnreachable,
            statusCode: status,
          ),
        );
      });
    }

    test('a ClientException is backendUnreachable', () async {
      await expectBoth(
        _service(_throwing(http.ClientException('down'))),
        const VenueSearchFailed(VenueSearchFailureReason.backendUnreachable),
      );
    });

    test('a TimeoutException is timeout', () async {
      await expectBoth(
        _service(_throwing(TimeoutException('slow'))),
        const VenueSearchFailed(VenueSearchFailureReason.timeout),
      );
    });

    test('a slow answer past the budget is timeout', () async {
      final client = MockClient((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        return http.Response('{"venues":[]}', 200);
      });
      final service = _service(
        client,
        timeout: const Duration(milliseconds: 10),
      );

      expect(
        await _nearby(service),
        equals(const VenueSearchFailed(VenueSearchFailureReason.timeout)),
      );
    });
  });

  group('FallbackVenueSearchService', () {
    final found = <Venue>[_venue('direct')];

    ({
      FallbackVenueSearchService service,
      FakeVenueSearchService primary,
      FakeVenueSearchService fallback,
    })
    build(VenueSearchResult primaryResult, VenueSearchResult fallbackResult) {
      final primary = FakeVenueSearchService()..queueResult(primaryResult);
      final fallback = FakeVenueSearchService()..queueResult(fallbackResult);
      return (
        service: FallbackVenueSearchService(
          primary: primary,
          fallback: fallback,
        ),
        primary: primary,
        fallback: fallback,
      );
    }

    for (final reason in <VenueSearchFailureReason>[
      VenueSearchFailureReason.backendUnreachable,
      VenueSearchFailureReason.timeout,
      VenueSearchFailureReason.rateLimited,
    ]) {
      test('falls through on $reason, both entry points', () async {
        final t = build(VenueSearchFailed(reason), VenuesFound(found));

        expect(await _nearby(t.service), equals(VenuesFound(found)));
        expect(
          await t.service.byName(
            'pizza',
            language: 'en',
            latitude: _lat,
            longitude: _lon,
          ),
          equals(VenuesFound(found)),
        );
        expect(t.fallback.nearbyCalls, hasLength(1));
        expect(t.fallback.byNameCalls.single.query, equals('pizza'));
        expect(t.fallback.byNameCalls.single.latitude, equals(_lat));
        expect(t.fallback.byNameCalls.single.longitude, equals(_lon));
      });
    }

    for (final reason in <VenueSearchFailureReason>[
      VenueSearchFailureReason.offline,
      VenueSearchFailureReason.platformChanged,
      VenueSearchFailureReason.blockedByBrowser,
    ]) {
      test('does not fall through on $reason', () async {
        final failure = VenueSearchFailed(reason);
        final t = build(failure, VenuesFound(found));

        expect(await _nearby(t.service), equals(failure));
        expect(
          await t.service.byName('pizza', language: 'en'),
          equals(failure),
        );
        expect(t.fallback.nearbyCalls, isEmpty);
        expect(t.fallback.byNameCalls, isEmpty);
      });
    }

    test('a primary success never touches the fallback', () async {
      final t = build(
        VenuesFound(<Venue>[_venue('backend')]),
        VenuesFound(found),
      );

      expect(_slugs(await _nearby(t.service)), <String>['backend']);
      expect(t.fallback.nearbyCalls, isEmpty);
    });

    test('returns the primary failure when the fallback fails too', () async {
      const primaryFailure = VenueSearchFailed(
        VenueSearchFailureReason.rateLimited,
      );
      final t = build(
        primaryFailure,
        const VenueSearchFailed(VenueSearchFailureReason.offline),
      );

      expect(await _nearby(t.service), equals(primaryFailure));
      expect(
        await t.service.byName('pizza', language: 'en'),
        equals(primaryFailure),
      );
    });

    test('a blank query is answered by the primary alone', () async {
      final t = build(
        const VenueSearchFailed(VenueSearchFailureReason.timeout),
        VenuesFound(found),
      );

      expect(
        await t.service.byName('  ', language: 'en'),
        equals(const VenuesFound(<Venue>[])),
      );
      expect(t.fallback.byNameCalls, isEmpty);
    });
  });
}

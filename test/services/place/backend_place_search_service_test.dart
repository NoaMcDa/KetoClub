import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ketoclub/models/place.dart';
import 'package:ketoclub/services/llm/backend_chat_client.dart';
import 'package:ketoclub/services/place/backend_place_search_service.dart';
import 'package:ketoclub/services/place/fallback_place_search_service.dart';
import 'package:ketoclub/services/place/place_search_service.dart';

import '../../fakes/fake_install_id_store.dart';
import '../../fakes/fake_place_search_service.dart';

final Uri _base = Uri.parse('http://localhost:8000');

/// A client answering every request with [status] and [body] as UTF-8,
/// with FastAPI's own `content-type` (no charset), recording requests
/// into [requests] when given.
MockClient _answering(
  int status,
  String body, [
  List<http.Request>? requests,
]) => MockClient((request) async {
  requests?.add(request);
  return http.Response.bytes(
    utf8.encode(body),
    status,
    headers: <String, String>{'content-type': 'application/json'},
  );
});

BackendPlaceSearchService _service(
  http.Client client, {
  Uri? baseUrl,
  FakeInstallIdStore? store,
  Duration timeout = const Duration(seconds: 15),
}) => BackendPlaceSearchService(
  client: client,
  baseUrl: baseUrl,
  installIdStore: store ?? FakeInstallIdStore(),
  timeout: timeout,
);

String _error(String reason, int status) =>
    jsonEncode(<String, Object?>{'reason': reason, 'status_code': status});

Map<String, Object?> _place(String label, {String? city}) => <String, Object?>{
  'label': label,
  'city': city,
  'latitude': 32.06,
  'longitude': 34.77,
};

String _places(List<Object?> places) =>
    jsonEncode(<String, Object?>{'places': places});

void main() {
  group('BackendPlaceSearchService (issue #449)', () {
    test('posts the trimmed query and the language to /v1/places/search, '
        'with the install id and no key', () async {
      // Arrange
      final requests = <http.Request>[];
      final store = FakeInstallIdStore();
      final service = _service(
        _answering(200, _places(<Object?>[]), requests),
        baseUrl: Uri.parse('http://localhost:8000/'),
        store: store,
      );

      // Act
      await service.search('  הרצל 10 ', language: 'he');

      // Assert
      final request = requests.single;
      expect(request.method, 'POST');
      expect(request.url.toString(), 'http://localhost:8000/v1/places/search');
      expect(jsonDecode(request.body), <String, Object?>{
        'query': 'הרצל 10',
        'language': 'he',
      });
      expect(
        request.headers[BackendChatClient.installIdHeader],
        await store.id(),
      );
      expect(request.headers['Content-Type'], startsWith('application/json'));
      final names = request.headers.keys.map((k) => k.toLowerCase());
      expect(names, isNot(contains('authorization')));
      expect(names, isNot(contains('x-goog-api-key')));
    });

    test('sends en for any language but Hebrew', () async {
      // Arrange
      final requests = <http.Request>[];
      final service = _service(
        _answering(200, _places(<Object?>[]), requests),
        baseUrl: _base,
      );

      // Act
      await service.search('herzl', language: 'en');
      await service.search('herzl', language: 'fr');

      // Assert
      expect(
        requests.map((r) => (jsonDecode(r.body) as Map)['language']),
        <String>['en', 'en'],
      );
    });

    test('cuts a long query to 120 characters and sends nothing for one '
        'shorter than two', () async {
      // Arrange
      final requests = <http.Request>[];
      final store = FakeInstallIdStore();
      final service = _service(
        _answering(200, _places(<Object?>[]), requests),
        baseUrl: _base,
        store: store,
      );

      // Act
      final short = await service.search(' x ', language: 'en');
      await service.search('a' * 130, language: 'en');

      // Assert
      expect(short, const PlacesFound([]));
      expect(requests, hasLength(1));
      expect((jsonDecode(requests.single.body) as Map)['query'], 'a' * 120);
    });

    test('reads the places, city and all, in order', () async {
      // Arrange
      final service = _service(
        _answering(
          200,
          _places(<Object?>[
            _place('הרצל 10, תל אביב', city: 'תל אביב'),
            _place('Herzl 10'),
          ]),
        ),
        baseUrl: _base,
      );

      // Act
      final result = await service.search('herzl', language: 'he');

      // Assert
      expect(
        result,
        const PlacesFound(<StreetPlace>[
          StreetPlace(
            label: 'הרצל 10, תל אביב',
            city: 'תל אביב',
            latitude: 32.06,
            longitude: 34.77,
          ),
          StreetPlace(label: 'Herzl 10', latitude: 32.06, longitude: 34.77),
        ]),
      );
    });

    test('skips an unusable place, merges a repeated label and keeps at '
        'most six', () async {
      // Arrange
      final service = _service(
        _answering(
          200,
          _places(<Object?>[
            <String, Object?>{'label': 'no coordinates'},
            _place('A'),
            _place('A'),
            for (var i = 0; i < 8; i++) _place('B$i'),
          ]),
        ),
        baseUrl: _base,
      );

      // Act
      final result = await service.search('herzl', language: 'en');

      // Assert
      expect((result as PlacesFound).places.map((p) => p.label), <String>[
        'A',
        'B0',
        'B1',
        'B2',
        'B3',
        'B4',
      ]);
    });

    test('no backend is backend unreachable, with no request and no install '
        'id read', () async {
      // Arrange
      final requests = <http.Request>[];
      final store = FakeInstallIdStore();
      final service = _service(
        _answering(200, _places(<Object?>[]), requests),
        store: store,
      );

      // Act
      final result = await service.search('herzl', language: 'en');

      // Assert
      expect(
        result,
        const PlaceSearchFailed(PlaceSearchFailureReason.backendUnreachable),
      );
      expect(requests, isEmpty);
      expect(store.calls, 0);
    });

    test('a request that never reaches the server is backend '
        'unreachable', () async {
      // Arrange
      final service = _service(
        MockClient((_) async => throw http.ClientException('refused')),
        baseUrl: _base,
      );

      // Act
      final result = await service.search('herzl', language: 'en');

      // Assert
      expect(
        result,
        const PlaceSearchFailed(PlaceSearchFailureReason.backendUnreachable),
      );
    });

    test('no answer within the budget is a timeout', () async {
      // Arrange
      final never = Completer<http.Response>();
      final service = _service(
        MockClient((_) => never.future),
        baseUrl: _base,
        timeout: const Duration(milliseconds: 10),
      );

      // Act
      final result = await service.search('herzl', language: 'en');

      // Assert
      expect(result, const PlaceSearchFailed(PlaceSearchFailureReason.timeout));
    });

    test(
      'maps each of the contract error statuses to its own reason',
      () async {
        final cases = <(int, String, PlaceSearchFailureReason)>[
          (
            429,
            _error('rateLimited', 429),
            PlaceSearchFailureReason.rateLimited,
          ),
          (502, _error('offline', 502), PlaceSearchFailureReason.offline),
          (
            502,
            _error('providerChanged', 502),
            PlaceSearchFailureReason.providerChanged,
          ),
          (504, _error('timeout', 504), PlaceSearchFailureReason.timeout),
          (
            400,
            _error('badResponse', 400),
            PlaceSearchFailureReason.backendUnreachable,
          ),
        ];
        for (final (status, body, reason) in cases) {
          // Arrange
          final service = _service(_answering(status, body), baseUrl: _base);

          // Act
          final result = await service.search('herzl', language: 'en');

          // Assert
          expect(result, isA<PlaceSearchFailed>(), reason: '$status $body');
          final failed = result as PlaceSearchFailed;
          expect(failed.reason, reason, reason: '$status $body');
          expect(failed.statusCode, status, reason: '$status $body');
        }
      },
    );

    test('an unexpected status, or a 502 without a known reason, is a '
        'changed provider', () async {
      for (final (status, body) in <(int, String)>[
        (500, 'Internal Server Error'),
        (502, 'Bad Gateway'),
        (503, '{}'),
        (302, ''),
      ]) {
        // Arrange
        final service = _service(_answering(status, body), baseUrl: _base);

        // Act
        final result = await service.search('herzl', language: 'en');

        // Assert
        expect(
          result,
          PlaceSearchFailed(
            PlaceSearchFailureReason.providerChanged,
            statusCode: status,
          ),
          reason: '$status',
        );
      }
    });

    test('a backend without the route (404) is backend unreachable, so '
        'the fallback can ask Photon', () async {
      // Arrange
      final service = _service(
        _answering(404, '{"detail":"Not Found"}'),
        baseUrl: _base,
      );

      // Act
      final result = await service.search('herzl', language: 'en');

      // Assert
      expect(
        result,
        const PlaceSearchFailed(
          PlaceSearchFailureReason.backendUnreachable,
          statusCode: 404,
        ),
      );
    });

    for (final (status, body) in <(int, String)>[
      (404, '{"detail":"Not Found"}'),
      (400, '{"reason":"badResponse","status_code":400}'),
    ]) {
      test('behind the fallback chain, a $status reaches Photon', () async {
        // Arrange
        final photon = FakePlaceSearchService()
          ..queueFound(const <StreetPlace>[
            StreetPlace(label: 'Herzl 10', latitude: 32.06, longitude: 34.77),
          ]);
        final chain = FallbackPlaceSearchService(
          primary: _service(_answering(status, body), baseUrl: _base),
          fallback: photon,
        );

        // Act
        final result = await chain.search('herzl', language: 'he');

        // Assert
        expect(photon.calls, <PlaceSearchCall>[
          (query: 'herzl', language: 'he'),
        ]);
        expect((result as PlacesFound).places.single.label, 'Herzl 10');
      });
    }

    test('a 2xx body that is not the contract is a changed provider', () async {
      for (final body in <String>[
        'not json',
        '[]',
        '{}',
        '{"places": "none"}',
        '{"places": ["Herzl"]}',
      ]) {
        // Arrange
        final service = _service(_answering(200, body), baseUrl: _base);

        // Act
        final result = await service.search('herzl', language: 'en');

        // Assert
        expect(
          result,
          const PlaceSearchFailed(PlaceSearchFailureReason.providerChanged),
          reason: body,
        );
      }
    });
  });
}

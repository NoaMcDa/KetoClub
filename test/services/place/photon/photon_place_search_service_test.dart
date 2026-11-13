import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ketoclub/services/place/photon/photon_place_search_service.dart';
import 'package:ketoclub/services/place/place_search_service.dart';

import '../../../fakes/fake_transport_exceptions.dart';

/// The recorded Hebrew reply (see `test/fixtures/README.md`), as bytes.
List<int> _herzlReply() =>
    File('test/fixtures/photon/photon_herzl_tel_aviv_default.json')
        .readAsBytesSync();

/// A client answering every request with [status] and [bytes], with
/// Photon's own `content-type` (no charset), recording requests into
/// [requests] when given.
MockClient _answering(
  int status,
  List<int> bytes, [
  List<http.Request>? requests,
]) => MockClient((request) async {
  requests?.add(request);
  return http.Response.bytes(
    bytes,
    status,
    headers: <String, String>{'content-type': 'application/json'},
  );
});

PhotonPlaceSearchService _service(
  http.Client client, {
  Duration timeout = const Duration(seconds: 10),
  bool runsInBrowser = false,
}) => PhotonPlaceSearchService(
  client: client,
  timeout: timeout,
  runsInBrowser: runsInBrowser,
);

void main() {
  group('PhotonPlaceSearchService (issue #449)', () {
    test('asks Photon once with the query, limit, box and both layers, '
        'and nothing else', () async {
      // Arrange
      final requests = <http.Request>[];
      final service = _service(_answering(200, _herzlReply(), requests));

      // Act
      await service.search('  הרצל 10 תל אביב ', language: 'he');

      // Assert
      expect(requests, hasLength(1));
      final request = requests.single;
      expect(request.method, 'GET');
      expect(request.url.scheme, 'https');
      expect(request.url.host, 'photon.komoot.io');
      expect(request.url.path, '/api/');
      expect(request.url.queryParametersAll, <String, List<String>>{
        'q': <String>['הרצל 10 תל אביב'],
        'limit': <String>['15'],
        'lang': <String>['default'],
        'bbox': <String>['34.2,29.4,35.9,33.4'],
        'layer': <String>['house', 'street'],
      });
      expect(
        request.headers.keys.map((k) => k.toLowerCase()),
        isNot(contains('authorization')),
      );
      expect(
        request.headers.keys.map((k) => k.toLowerCase()),
        isNot(contains('x-ketoclub-install-id')),
      );
    });

    test('on a phone names KetoClub in the User-Agent: Photon refuses '
        "Dart's own with a 403", () async {
      // Arrange
      final requests = <http.Request>[];
      final service = _service(_answering(200, _herzlReply(), requests));

      // Act
      await service.search('herzl', language: 'en');

      // Assert
      expect(
        requests.single.headers['User-Agent'],
        'KetoClub/1.0 (+https://github.com/NoaMcDa/KetoClub; place search)',
      );
      expect(
        requests.single.headers['User-Agent'],
        PhotonPlaceSearchService.photonUserAgent,
      );
    });

    test('in a browser sends no User-Agent, which the browser owns', () async {
      // Arrange
      final requests = <http.Request>[];
      final service = _service(
        _answering(200, _herzlReply(), requests),
        runsInBrowser: true,
      );

      // Act
      await service.search('herzl', language: 'en');

      // Assert
      expect(
        requests.single.headers.keys.map((k) => k.toLowerCase()),
        isNot(contains('user-agent')),
      );
      expect(requests.single.headers['Accept'], 'application/json');
    });

    test('a 403, as Photon answers an unnamed client, is a changed '
        'provider', () async {
      // Arrange
      final service = _service(
        _answering(403, utf8.encode('<html>403 Forbidden</html>')),
      );

      // Act
      final result = await service.search('herzl', language: 'en');

      // Assert
      expect(
        result,
        const PlaceSearchFailed(
          PlaceSearchFailureReason.providerChanged,
          statusCode: 403,
        ),
      );
    });

    test('asks for English names under English', () async {
      // Arrange
      final requests = <http.Request>[];
      final service = _service(_answering(200, _herzlReply(), requests));

      // Act
      await service.search('dizengoff', language: 'en');

      // Assert
      expect(requests.single.url.queryParameters['lang'], 'en');
    });

    test('reads the UTF-8 reply into places, though Photon names no '
        'charset', () async {
      // Arrange
      final service = _service(_answering(200, _herzlReply()));

      // Act
      final result = await service.search('הרצל 10', language: 'he');

      // Assert
      expect(result, isA<PlacesFound>());
      final places = (result as PlacesFound).places;
      expect(places, hasLength(6));
      expect(places.first.label, 'הרצל 10, תל אביב');
    });

    test('sends nothing for a query shorter than two characters', () async {
      // Arrange
      final requests = <http.Request>[];
      final service = _service(_answering(200, _herzlReply(), requests));

      // Act
      final blank = await service.search('   ', language: 'en');
      final one = await service.search(' a ', language: 'en');

      // Assert
      expect(blank, const PlacesFound([]));
      expect(one, const PlacesFound([]));
      expect(requests, isEmpty);
    });

    test('cuts a long query to 120 characters', () async {
      // Arrange
      final requests = <http.Request>[];
      final service = _service(_answering(200, _herzlReply(), requests));

      // Act
      await service.search('א' * 200, language: 'he');

      // Assert
      expect(requests.single.url.queryParameters['q'], 'א' * 120);
    });

    test('no connection is offline', () async {
      // Arrange
      final service = _service(
        MockClient((_) async => throw http.ClientException('no route')),
      );

      // Act
      final result = await service.search('herzl', language: 'en');

      // Assert
      expect(result, const PlaceSearchFailed(PlaceSearchFailureReason.offline));
    });

    test('a TLS handshake failure is offline (#278)', () async {
      // Arrange
      final service = _service(
        MockClient((_) async => throw const FakeHandshakeException()),
      );

      // Act
      final result = await service.search('herzl', language: 'en');

      // Assert
      expect(result, const PlaceSearchFailed(PlaceSearchFailureReason.offline));
    });

    test('no answer within the budget is a timeout', () async {
      // Arrange
      final never = Completer<http.Response>();
      final service = _service(
        MockClient((_) => never.future),
        timeout: const Duration(milliseconds: 10),
      );

      // Act
      final result = await service.search('herzl', language: 'en');

      // Assert
      expect(result, const PlaceSearchFailed(PlaceSearchFailureReason.timeout));
    });

    test('429 is rate limited', () async {
      // Arrange
      final service = _service(_answering(429, utf8.encode('slow down')));

      // Act
      final result = await service.search('herzl', language: 'en');

      // Assert
      expect(
        result,
        const PlaceSearchFailed(
          PlaceSearchFailureReason.rateLimited,
          statusCode: 429,
        ),
      );
    });

    test('any other non-2xx status is a changed provider, the status '
        'kept', () async {
      for (final status in <int>[400, 404, 500, 502, 503]) {
        // Arrange
        final service = _service(_answering(status, utf8.encode('{}')));

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

    test('a body that is not JSON, not UTF-8 or not a feature collection is '
        'a changed provider', () async {
      for (final body in <List<int>>[
        utf8.encode('<html>'),
        <int>[0xff, 0xfe, 0x00],
        utf8.encode('[]'),
        utf8.encode('{"features": "none"}'),
      ]) {
        // Arrange
        final service = _service(_answering(200, body));

        // Act
        final result = await service.search('herzl', language: 'en');

        // Assert
        expect(
          result,
          const PlaceSearchFailed(PlaceSearchFailureReason.providerChanged),
          reason: '$body',
        );
      }
    });

    test('an empty feature list is no places, not a failure', () async {
      // Arrange
      final service = _service(
        _answering(
          200,
          utf8.encode('{"type":"FeatureCollection","features":[]}'),
        ),
      );

      // Act
      final result = await service.search('zzzz', language: 'en');

      // Assert
      expect(result, const PlacesFound([]));
    });
  });
}

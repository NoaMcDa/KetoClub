import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/community/menu_store_client.dart';

import '../../fakes/fake_app_logger.dart';
import '../../fakes/fake_install_id_store.dart';

/// The backend base every test uses unless it is exercising the URL
/// composition itself.
final Uri _base = Uri.parse('https://api.ketoclub.test');

/// The install id the fake store answers with in every test.
const String _installId = '0123456789abcdef0123456789abcdef';

/// The venue every upload in this file belongs to.
const VenueRef _ref = VenueRef(source: MenuSource.wolt, platformId: 'hamosad');

/// A menu for [_ref] whose one dish has a [description].
Menu _menu({String description = 'With fries'}) => Menu(
  venueRef: _ref,
  currency: 'ILS',
  fetchedAt: DateTime.utc(2026, 10, 8),
  categories: <MenuCategory>[
    MenuCategory(
      id: 'mains',
      name: 'Mains',
      dishes: <Dish>[
        Dish(
          id: 'd1',
          name: 'Steak',
          description: description,
          price: 9800,
          options: const <DishOption>[],
        ),
      ],
    ),
  ],
);

/// An upload of a small menu, with an analysis carrying diet options.
MenuUpload _upload() => MenuUpload(
  ref: _ref,
  venueName: 'HaMosad',
  city: 'Tel Aviv',
  menu: _menu(),
  analysis: MenuAnalysed(
    dishes: const <AnalysedDish>[
      AnalysedDish(
        dishId: 'd1',
        name: 'Steak',
        verdict: DishVerdict.orderAsIs,
        why: 'Protein.',
      ),
    ],
    unclassified: const <String>[],
    engine: const LlmEngine(model: 'test-model'),
    analysedAt: DateTime.utc(2026, 10, 8),
    options: const AnalysisOptionsSnapshot(netCarbLimitGrams: 20),
  ),
);

/// A backend error body naming [reason].
String _errorBody(String reason) =>
    jsonEncode(<String, Object?>{'reason': reason});

/// Builds a client over [transport], posting to [baseUrl].
BackendMenuStoreClient _build(
  MockClient transport, {
  Uri? baseUrl,
  bool noBase = false,
  FakeInstallIdStore? store,
  FakeAppLogger? logger,
  Duration timeout = const Duration(seconds: 20),
}) => BackendMenuStoreClient(
  client: transport,
  baseUrl: noBase ? null : (baseUrl ?? _base),
  installIdStore: store ?? FakeInstallIdStore(installId: _installId),
  logger: logger ?? FakeAppLogger(),
  timeout: timeout,
);

/// Builds a client whose transport always answers [body] with [status].
BackendMenuStoreClient _answering(
  int status, {
  String body = '{}',
  FakeAppLogger? logger,
}) => _build(
  MockClient((_) async => http.Response(body, status)),
  logger: logger,
);

void main() {
  group('BackendMenuStoreClient with no base URL', () {
    test('is not configured and uploads nothing', () async {
      // Arrange
      var transportCalls = 0;
      final store = FakeInstallIdStore(installId: _installId);
      final client = _build(
        MockClient((_) async {
          transportCalls++;
          return http.Response('{}', 201);
        }),
        noBase: true,
        store: store,
      );

      // Act
      final result = await client.upload(_upload());

      // Assert
      expect(client.isConfigured, isFalse);
      expect(
        result,
        equals(
          const MenuStoreFailed(reason: MenuStoreFailureReason.notConfigured),
        ),
      );
      expect(transportCalls, equals(0));
      expect(store.calls, equals(0));
    });
  });

  group('BackendMenuStoreClient request', () {
    test('is configured with a base URL', () {
      // Assert
      expect(_answering(201).isConfigured, isTrue);
    });

    test('posts the upload as JSON to {base}/v1/menus', () async {
      // Arrange
      http.Request? captured;
      final upload = _upload();
      final client = _build(
        MockClient((request) async {
          captured = request;
          return http.Response('{}', 201);
        }),
      );

      // Act
      await client.upload(upload);

      // Assert
      expect(captured!.method, equals('POST'));
      expect(
        captured!.url,
        equals(Uri.parse('https://api.ketoclub.test/v1/menus')),
      );
      expect(captured!.headers['Content-Type'], startsWith('application/json'));
      expect(
        jsonDecode(captured!.body),
        equals(jsonDecode(jsonEncode(upload.toJson()))),
      );
      expect(captured!.body, isNot(contains('netCarbLimitGrams')));
    });

    test('normalises a base URL with a trailing slash', () async {
      // Arrange
      Uri? capturedUri;
      final client = _build(
        MockClient((request) async {
          capturedUri = request.url;
          return http.Response('{}', 201);
        }),
        baseUrl: Uri.parse('https://api.ketoclub.test/'),
      );

      // Act
      await client.upload(_upload());

      // Assert
      expect(
        capturedUri,
        equals(Uri.parse('https://api.ketoclub.test/v1/menus')),
      );
    });

    test('keeps a base URL path prefix', () async {
      // Arrange
      Uri? capturedUri;
      final client = _build(
        MockClient((request) async {
          capturedUri = request.url;
          return http.Response('{}', 201);
        }),
        baseUrl: Uri.parse('https://api.ketoclub.test/prefix/'),
      );

      // Act
      await client.upload(_upload());

      // Assert
      expect(
        capturedUri,
        equals(Uri.parse('https://api.ketoclub.test/prefix/v1/menus')),
      );
    });

    test('sends the install id, read per call, and no Authorization', () async {
      // Arrange
      final headers = <Map<String, String>>[];
      final store = FakeInstallIdStore(installId: _installId);
      final client = _build(
        MockClient((request) async {
          headers.add(request.headers);
          return http.Response('{}', 201);
        }),
        store: store,
      );

      // Act
      await client.upload(_upload());
      await client.upload(_upload());

      // Assert
      expect(store.calls, equals(2));
      for (final sent in headers) {
        expect(
          sent[BackendMenuStoreClient.installIdHeader],
          equals(_installId),
        );
        expect(
          sent.keys.map((key) => key.toLowerCase()),
          isNot(contains('authorization')),
        );
      }
    });

    test('names the install id header', () {
      // Assert
      expect(
        BackendMenuStoreClient.installIdHeader,
        equals('X-KetoClub-Install-Id'),
      );
    });
  });

  group('BackendMenuStoreClient size cap', () {
    test('an upload over the cap is tooLarge with no request', () async {
      // Arrange
      var transportCalls = 0;
      final store = FakeInstallIdStore(installId: _installId);
      final logger = FakeAppLogger();
      final client = _build(
        MockClient((_) async {
          transportCalls++;
          return http.Response('{}', 201);
        }),
        store: store,
        logger: logger,
      );
      final upload = MenuUpload(
        ref: _ref,
        menu: _menu(description: 'x' * maxMenuUploadBytes),
      );

      // Act
      final result = await client.upload(upload);

      // Assert
      expect(
        result,
        equals(const MenuStoreFailed(reason: MenuStoreFailureReason.tooLarge)),
      );
      expect(transportCalls, equals(0));
      expect(store.calls, equals(0));
      expect(logger.warnings, equals(<String>['Menu upload failed: tooLarge']));
    });

    test('the cap counts UTF-8 bytes, not characters', () async {
      // Arrange
      var transportCalls = 0;
      final client = _build(
        MockClient((_) async {
          transportCalls++;
          return http.Response('{}', 201);
        }),
      );
      // Two bytes per character: half the cap in characters is over it
      // once the rest of the body is added.
      final upload = MenuUpload(
        ref: _ref,
        menu: _menu(description: 'ש' * (maxMenuUploadBytes ~/ 2)),
      );

      // Act
      final result = await client.upload(upload);

      // Assert
      expect(
        result,
        equals(const MenuStoreFailed(reason: MenuStoreFailureReason.tooLarge)),
      );
      expect(transportCalls, equals(0));
    });

    test('is 768 KiB', () {
      // Assert
      expect(maxMenuUploadBytes, equals(786432));
    });
  });

  group('BackendMenuStoreClient response mapping', () {
    test('201 is stored and created', () async {
      // Act
      final result = await _answering(201).upload(_upload());

      // Assert
      expect(result, equals(const MenuStored(created: true)));
    });

    test('200 is stored but not created', () async {
      // Act
      final result = await _answering(200).upload(_upload());

      // Assert
      expect(result, equals(const MenuStored(created: false)));
    });

    final statusCases = <(int, MenuStoreFailureReason)>[
      (429, MenuStoreFailureReason.rateLimited),
      (413, MenuStoreFailureReason.tooLarge),
      (400, MenuStoreFailureReason.rejected),
      (422, MenuStoreFailureReason.rejected),
      (204, MenuStoreFailureReason.badResponse),
      (500, MenuStoreFailureReason.badResponse),
      (503, MenuStoreFailureReason.badResponse),
      (404, MenuStoreFailureReason.badResponse),
    ];
    for (final (status, reason) in statusCases) {
      test('$status is ${reason.name}', () async {
        // Act
        final result = await _answering(status).upload(_upload());

        // Assert
        expect(result, equals(MenuStoreFailed(reason: reason)));
      });
    }

    test('a status mapped on its own ignores the body reason', () async {
      // Act
      final result = await _answering(
        429,
        body: _errorBody('timeout'),
      ).upload(_upload());

      // Assert
      expect(
        result,
        equals(
          const MenuStoreFailed(reason: MenuStoreFailureReason.rateLimited),
        ),
      );
    });

    final bodyCases = <(String, MenuStoreFailureReason)>[
      ('notConfigured', MenuStoreFailureReason.notConfigured),
      ('timeout', MenuStoreFailureReason.timeout),
      ('tooLarge', MenuStoreFailureReason.tooLarge),
      ('rateLimited', MenuStoreFailureReason.rateLimited),
      ('rejected', MenuStoreFailureReason.rejected),
      ('badResponse', MenuStoreFailureReason.badResponse),
      ('backendUnreachable', MenuStoreFailureReason.badResponse),
      ('somethingElse', MenuStoreFailureReason.badResponse),
    ];
    for (final (name, reason) in bodyCases) {
      test('a 503 naming $name is ${reason.name}', () async {
        // Act
        final result = await _answering(
          503,
          body: _errorBody(name),
        ).upload(_upload());

        // Assert
        expect(result, equals(MenuStoreFailed(reason: reason)));
      });
    }

    test('a non-JSON error body is badResponse', () async {
      // Act
      final result = await _answering(
        502,
        body: '<html>Bad gateway</html>',
      ).upload(_upload());

      // Assert
      expect(
        result,
        equals(
          const MenuStoreFailed(reason: MenuStoreFailureReason.badResponse),
        ),
      );
    });

    test('a JSON error body that is not an object is badResponse', () async {
      // Act
      final result = await _answering(
        500,
        body: '["timeout"]',
      ).upload(_upload());

      // Assert
      expect(
        result,
        equals(
          const MenuStoreFailed(reason: MenuStoreFailureReason.badResponse),
        ),
      );
    });

    test('a non-string reason is badResponse', () async {
      // Act
      final result = await _answering(
        500,
        body: '{"reason": 7}',
      ).upload(_upload());

      // Assert
      expect(
        result,
        equals(
          const MenuStoreFailed(reason: MenuStoreFailureReason.badResponse),
        ),
      );
    });
  });

  group('BackendMenuStoreClient transport failures', () {
    test('a ClientException is backendUnreachable', () async {
      // Arrange
      final client = _build(
        MockClient((request) async {
          throw http.ClientException('Connection refused', request.url);
        }),
      );

      // Act
      final result = await client.upload(_upload());

      // Assert
      expect(
        result,
        equals(
          const MenuStoreFailed(
            reason: MenuStoreFailureReason.backendUnreachable,
          ),
        ),
      );
    });

    test('a TimeoutException from the transport is timeout', () async {
      // Arrange
      final client = _build(
        MockClient((_) async {
          throw TimeoutException('slow');
        }),
      );

      // Act
      final result = await client.upload(_upload());

      // Assert
      expect(
        result,
        equals(const MenuStoreFailed(reason: MenuStoreFailureReason.timeout)),
      );
    });

    test('a request outliving the timeout is timeout', () {
      fakeAsync((async) {
        // Arrange
        final client = _build(
          MockClient((_) => Completer<http.Response>().future),
          timeout: const Duration(seconds: 30),
        );
        MenuStoreResult? result;

        // Act
        unawaited(client.upload(_upload()).then((value) => result = value));
        async.elapse(const Duration(seconds: 29));

        // Assert
        expect(result, isNull);

        // Act
        async.elapse(const Duration(seconds: 2));

        // Assert
        expect(
          result,
          equals(const MenuStoreFailed(reason: MenuStoreFailureReason.timeout)),
        );
      });
    });

    test('defaults the timeout to 20 seconds', () {
      // Arrange
      final client = BackendMenuStoreClient(
        client: MockClient((_) async => http.Response('{}', 201)),
        baseUrl: _base,
        installIdStore: FakeInstallIdStore(),
        logger: FakeAppLogger(),
      );

      // Assert
      expect(client.timeout, equals(const Duration(seconds: 20)));
    });
  });

  group('BackendMenuStoreClient logging', () {
    test('a success logs nothing', () async {
      // Arrange
      final logger = FakeAppLogger();

      // Act
      await _answering(201, logger: logger).upload(_upload());

      // Assert
      expect(logger.warnings, isEmpty);
      expect(logger.infos, isEmpty);
    });

    test('a failure logs one line: reason and status only', () async {
      // Arrange
      final logger = FakeAppLogger();
      const secretBody = '{"reason": "rejected", "detail": "secret-detail"}';

      // Act
      await _answering(422, body: secretBody, logger: logger).upload(_upload());

      // Assert
      expect(
        logger.warnings,
        equals(<String>['Menu upload failed: rejected (HTTP 422)']),
      );
      final logged = logger.warnings.single;
      expect(logged, isNot(contains('secret-detail')));
      expect(logged, isNot(contains(_installId)));
      expect(logger.warningErrors.single, isNull);
    });

    test('a transport failure logs the reason with no status', () async {
      // Arrange
      final logger = FakeAppLogger();
      final client = _build(
        MockClient((request) async {
          throw http.ClientException('refused $_installId', request.url);
        }),
        logger: logger,
      );

      // Act
      await client.upload(_upload());

      // Assert
      expect(
        logger.warnings,
        equals(<String>['Menu upload failed: backendUnreachable']),
      );
      expect(logger.warningErrors.single, isNull);
    });

    test('no base URL logs notConfigured once', () async {
      // Arrange
      final logger = FakeAppLogger();
      final client = _build(
        MockClient((_) async => http.Response('{}', 201)),
        noBase: true,
        logger: logger,
      );

      // Act
      await client.upload(_upload());

      // Assert
      expect(
        logger.warnings,
        equals(<String>['Menu upload failed: notConfigured']),
      );
    });
  });
}

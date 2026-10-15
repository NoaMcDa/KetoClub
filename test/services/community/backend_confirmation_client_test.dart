import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/community/confirmation_client.dart';

import '../../fakes/fake_app_logger.dart';
import '../../fakes/fake_install_id_store.dart';

final Uri _base = Uri.parse('https://api.ketoclub.test');

const String _installId = '0123456789abcdef0123456789abcdef';

const VenueRef _ref = VenueRef(source: MenuSource.wolt, platformId: 'hamosad');

const String _fingerprint = 'a1b2c3d4';

String _errorBody(String reason) =>
    jsonEncode(<String, Object?>{'reason': reason});

BackendConfirmationClient _build(
  MockClient transport, {
  bool noBase = false,
  Uri? baseUrl,
  FakeInstallIdStore? store,
  FakeAppLogger? logger,
  Duration timeout = const Duration(seconds: 20),
}) => BackendConfirmationClient(
  client: transport,
  baseUrl: noBase ? null : (baseUrl ?? _base),
  installIdStore: store ?? FakeInstallIdStore(installId: _installId),
  logger: logger ?? FakeAppLogger(),
  timeout: timeout,
);

BackendConfirmationClient _answering(
  int status, {
  String body = '{}',
  FakeAppLogger? logger,
}) => _build(
  MockClient((_) async => http.Response(body, status)),
  logger: logger,
);

Future<ConfirmationResult> _confirm(
  ConfirmationClient client, {
  String dishFingerprint = _fingerprint,
  String restrictionId = 'sesame',
  ConfirmationPolarity polarity = ConfirmationPolarity.present,
}) => client.confirm(
  ref: _ref,
  dishFingerprint: dishFingerprint,
  restrictionId: restrictionId,
  polarity: polarity,
);

void main() {
  group('BackendConfirmationClient with no base URL', () {
    test('is not configured and sends nothing', () async {
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
      final result = await _confirm(client);

      // Assert
      expect(client.isConfigured, isFalse);
      expect(
        result,
        equals(
          const ConfirmationFailed(
            reason: ConfirmationFailureReason.notConfigured,
          ),
        ),
      );
      expect(transportCalls, equals(0));
      expect(store.calls, equals(0));
    });
  });

  group('BackendConfirmationClient request', () {
    test('is configured with a base URL', () {
      // Assert
      expect(_answering(201).isConfigured, isTrue);
    });

    test(
      'posts exactly the contract body to {base}/v1/confirmations',
      () async {
        // Arrange
        http.Request? captured;
        final client = _build(
          MockClient((request) async {
            captured = request;
            return http.Response('{}', 201);
          }),
        );

        // Act
        await _confirm(client, polarity: ConfirmationPolarity.absent);

        // Assert
        expect(captured!.method, equals('POST'));
        expect(
          captured!.url,
          equals(Uri.parse('https://api.ketoclub.test/v1/confirmations')),
        );
        expect(
          captured!.headers['Content-Type'],
          startsWith('application/json'),
        );
        expect(
          jsonDecode(captured!.body),
          equals(<String, Object?>{
            'venue': <String, Object?>{
              'source': 'wolt',
              'platformId': 'hamosad',
            },
            'dishFingerprint': _fingerprint,
            'restrictionId': 'sesame',
            'polarity': 'absent',
          }),
        );
      },
    );

    test('the body never carries an install id or a note', () async {
      // Arrange
      http.Request? captured;
      final client = _build(
        MockClient((request) async {
          captured = request;
          return http.Response('{}', 201);
        }),
      );

      // Act
      await _confirm(client);

      // Assert
      final body = captured!.body.toLowerCase();
      expect(body, isNot(contains(_installId)));
      expect(body, isNot(contains('install')));
      expect(body, isNot(contains('note')));
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
      await _confirm(client);

      // Assert
      expect(
        capturedUri,
        equals(Uri.parse('https://api.ketoclub.test/v1/confirmations')),
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
      await _confirm(client);

      // Assert
      expect(
        capturedUri,
        equals(Uri.parse('https://api.ketoclub.test/prefix/v1/confirmations')),
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
      await _confirm(client);
      await _confirm(client);

      // Assert
      expect(store.calls, equals(2));
      for (final sent in headers) {
        expect(
          sent[BackendConfirmationClient.installIdHeader],
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
        BackendConfirmationClient.installIdHeader,
        equals('X-KetoClub-Install-Id'),
      );
    });
  });

  group('BackendConfirmationClient local validation', () {
    final badFingerprints = <String>[
      '',
      'Eggplant salad, no sesame',
      'סלט חצילים',
      'a' * 65,
      'a/b',
    ];
    for (final fingerprint in badFingerprints) {
      test(
        'a fingerprint of "$fingerprint" is rejected with no request',
        () async {
          // Arrange
          var transportCalls = 0;
          final store = FakeInstallIdStore(installId: _installId);
          final client = _build(
            MockClient((_) async {
              transportCalls++;
              return http.Response('{}', 201);
            }),
            store: store,
          );

          // Act
          final result = await _confirm(client, dishFingerprint: fingerprint);

          // Assert
          expect(
            result,
            equals(
              const ConfirmationFailed(
                reason: ConfirmationFailureReason.rejected,
              ),
            ),
          );
          expect(transportCalls, equals(0));
          expect(store.calls, equals(0));
        },
      );
    }

    test('an empty restriction id is rejected with no request', () async {
      // Arrange
      var transportCalls = 0;
      final client = _build(
        MockClient((_) async {
          transportCalls++;
          return http.Response('{}', 201);
        }),
      );

      // Act
      final result = await _confirm(client, restrictionId: '');

      // Assert
      expect(
        result,
        equals(
          const ConfirmationFailed(reason: ConfirmationFailureReason.rejected),
        ),
      );
      expect(transportCalls, equals(0));
    });

    test('a 64-character token with every allowed symbol is sent', () async {
      // Arrange
      var transportCalls = 0;
      final client = _build(
        MockClient((_) async {
          transportCalls++;
          return http.Response('{}', 201);
        }),
      );
      final fingerprint = 'aZ09._:-' * 8;

      // Act
      final result = await _confirm(client, dishFingerprint: fingerprint);

      // Assert
      expect(fingerprint.length, equals(64));
      expect(result, equals(const ConfirmationRecorded(counted: true)));
      expect(transportCalls, equals(1));
    });
  });

  group('BackendConfirmationClient response mapping', () {
    test('201 is recorded and counted', () async {
      // Act
      final result = await _confirm(_answering(201));

      // Assert
      expect(result, equals(const ConfirmationRecorded(counted: true)));
    });

    test('200 is recorded but not counted again', () async {
      // Act
      final result = await _confirm(_answering(200));

      // Assert
      expect(result, equals(const ConfirmationRecorded(counted: false)));
    });

    final statusCases = <(int, ConfirmationFailureReason)>[
      (429, ConfirmationFailureReason.rateLimited),
      (413, ConfirmationFailureReason.rejected),
      (400, ConfirmationFailureReason.rejected),
      (422, ConfirmationFailureReason.rejected),
      (204, ConfirmationFailureReason.badResponse),
      (500, ConfirmationFailureReason.badResponse),
      (404, ConfirmationFailureReason.badResponse),
    ];
    for (final (status, reason) in statusCases) {
      test('$status is ${reason.name}', () async {
        // Act
        final result = await _confirm(_answering(status));

        // Assert
        expect(result, equals(ConfirmationFailed(reason: reason)));
      });
    }

    test('a status mapped on its own ignores the body reason', () async {
      // Act
      final result = await _confirm(
        _answering(429, body: _errorBody('timeout')),
      );

      // Assert
      expect(
        result,
        equals(
          const ConfirmationFailed(
            reason: ConfirmationFailureReason.rateLimited,
          ),
        ),
      );
    });

    final bodyCases = <(String, ConfirmationFailureReason)>[
      ('notConfigured', ConfirmationFailureReason.notConfigured),
      ('timeout', ConfirmationFailureReason.timeout),
      ('rateLimited', ConfirmationFailureReason.rateLimited),
      ('rejected', ConfirmationFailureReason.rejected),
      ('badResponse', ConfirmationFailureReason.badResponse),
      ('backendUnreachable', ConfirmationFailureReason.badResponse),
      ('somethingElse', ConfirmationFailureReason.badResponse),
    ];
    for (final (name, reason) in bodyCases) {
      test('a 503 naming $name is ${reason.name}', () async {
        // Act
        final result = await _confirm(_answering(503, body: _errorBody(name)));

        // Assert
        expect(result, equals(ConfirmationFailed(reason: reason)));
      });
    }

    final unreadable = <(String, String)>[
      ('a non-JSON body', '<html>Bad gateway</html>'),
      ('a JSON body that is not an object', '["timeout"]'),
      ('a non-string reason', '{"reason": 7}'),
    ];
    for (final (label, body) in unreadable) {
      test('$label is badResponse', () async {
        // Act
        final result = await _confirm(_answering(502, body: body));

        // Assert
        expect(
          result,
          equals(
            const ConfirmationFailed(
              reason: ConfirmationFailureReason.badResponse,
            ),
          ),
        );
      });
    }
  });

  group('BackendConfirmationClient transport failures', () {
    test('a ClientException is backendUnreachable', () async {
      // Arrange
      final client = _build(
        MockClient((request) async {
          throw http.ClientException('Connection refused', request.url);
        }),
      );

      // Act
      final result = await _confirm(client);

      // Assert
      expect(
        result,
        equals(
          const ConfirmationFailed(
            reason: ConfirmationFailureReason.backendUnreachable,
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
      final result = await _confirm(client);

      // Assert
      expect(
        result,
        equals(
          const ConfirmationFailed(reason: ConfirmationFailureReason.timeout),
        ),
      );
    });

    test('a request outliving the timeout is timeout', () {
      fakeAsync((async) {
        // Arrange
        final client = _build(
          MockClient((_) => Completer<http.Response>().future),
          timeout: const Duration(seconds: 30),
        );
        ConfirmationResult? result;

        // Act
        unawaited(_confirm(client).then((value) => result = value));
        async.elapse(const Duration(seconds: 29));

        // Assert
        expect(result, isNull);

        // Act
        async.elapse(const Duration(seconds: 2));

        // Assert
        expect(
          result,
          equals(
            const ConfirmationFailed(reason: ConfirmationFailureReason.timeout),
          ),
        );
      });
    });

    test('defaults the timeout to 20 seconds', () {
      // Arrange
      final client = BackendConfirmationClient(
        client: MockClient((_) async => http.Response('{}', 201)),
        baseUrl: _base,
        installIdStore: FakeInstallIdStore(),
        logger: FakeAppLogger(),
      );

      // Assert
      expect(client.timeout, equals(const Duration(seconds: 20)));
    });
  });

  group('BackendConfirmationClient logging', () {
    test('a success logs nothing', () async {
      // Arrange
      final logger = FakeAppLogger();

      // Act
      await _confirm(_answering(201, logger: logger));

      // Assert
      expect(logger.warnings, isEmpty);
      expect(logger.infos, isEmpty);
    });

    test('a failure logs one line: reason and status only', () async {
      // Arrange
      final logger = FakeAppLogger();
      const secretBody = '{"reason": "rejected", "detail": "secret-detail"}';

      // Act
      await _confirm(_answering(422, body: secretBody, logger: logger));

      // Assert
      expect(
        logger.warnings,
        equals(<String>['Confirmation failed: rejected (HTTP 422)']),
      );
      final logged = logger.warnings.single;
      expect(logged, isNot(contains('secret-detail')));
      expect(logged, isNot(contains(_installId)));
      expect(logged, isNot(contains(_fingerprint)));
      expect(logged, isNot(contains('sesame')));
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
      await _confirm(client);

      // Assert
      expect(
        logger.warnings,
        equals(<String>['Confirmation failed: backendUnreachable']),
      );
      expect(logger.warningErrors.single, isNull);
    });
  });

  group('NoConfirmationClient', () {
    test('is not configured and answers notConfigured', () async {
      // Arrange
      const client = NoConfirmationClient();

      // Act
      final result = await _confirm(client);

      // Assert
      expect(client.isConfigured, isFalse);
      expect(
        result,
        equals(
          const ConfirmationFailed(
            reason: ConfirmationFailureReason.notConfigured,
          ),
        ),
      );
    });
  });

  group('results', () {
    test('compare by value and print their fields', () {
      // Assert
      expect(
        const ConfirmationRecorded(counted: true),
        equals(const ConfirmationRecorded(counted: true)),
      );
      expect(
        const ConfirmationRecorded(counted: true).hashCode,
        equals(const ConfirmationRecorded(counted: true).hashCode),
      );
      expect(
        const ConfirmationRecorded(counted: true),
        isNot(equals(const ConfirmationRecorded(counted: false))),
      );
      expect(
        const ConfirmationRecorded(counted: false).toString(),
        equals('ConfirmationRecorded(counted: false)'),
      );
      const failed = ConfirmationFailed(
        reason: ConfirmationFailureReason.timeout,
      );
      expect(
        failed,
        equals(
          const ConfirmationFailed(reason: ConfirmationFailureReason.timeout),
        ),
      );
      expect(
        failed.hashCode,
        equals(
          const ConfirmationFailed(reason: ConfirmationFailureReason.timeout)
              .hashCode,
        ),
      );
      expect(failed.toString(), equals('ConfirmationFailed(reason: timeout)'));
    });
  });
}

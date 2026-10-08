import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/classifier/backend_menu_classifier.dart';
import 'package:ketoclub/services/classifier/menu_classifier.dart';
import 'package:ketoclub/services/classifier/menu_response_parser.dart';
import 'package:ketoclub/utils/constants.dart';

import '../../fakes/fake_install_id_store.dart';
import 'menu_classifier_contract.dart';

/// The backend base every test uses unless it is exercising the URL
/// composition itself.
final Uri _base = Uri.parse('https://api.ketoclub.test');

/// The install id the fake store answers with in every test.
const String _installId = '0123456789abcdef0123456789abcdef';

/// When the fake server says it analysed a menu.
final DateTime _analysedAt = DateTime.utc(2026, 10, 8, 12);

/// A two-dish menu, the one most tests send.
final Menu _menu = Menu(
  venueRef: const VenueRef(source: MenuSource.wolt, platformId: 'hamosad'),
  currency: 'ILS',
  fetchedAt: DateTime.utc(2026, 10, 8),
  categories: const <MenuCategory>[
    MenuCategory(
      id: 'mains',
      name: 'Mains',
      dishes: <Dish>[
        Dish(
          id: 'd1',
          name: 'Grilled Salmon',
          description: 'With lemon butter.',
          price: 68,
          options: <DishOption>[],
        ),
        Dish(
          id: 'd2',
          name: 'Steak and fries',
          description: 'With fries.',
          price: 92,
          options: <DishOption>[],
        ),
      ],
    ),
  ],
);

/// Options that differ from the defaults in every verdict-shaping field.
const ClassificationOptions _steered = ClassificationOptions(
  estimationConsentGiven: true,
  netCarbLimitGrams: 9,
  dietaryConstraints: <String>[dairyFreePromptFragment],
);

/// An analysis of [menu]'s dishes, every one green, made by [engine]
/// under [options].
MenuAnalysed _analysisOf(
  Menu menu, {
  AnalysisOptionsSnapshot? options,
  AnalysisEngine engine = const LlmEngine(model: 'gemini-test'),
}) => MenuAnalysed(
  dishes: <AnalysedDish>[
    for (final dish in menu.allDishes)
      AnalysedDish(
        dishId: dish.id,
        name: dish.name,
        verdict: DishVerdict.orderAsIs,
        why: 'The server placed it.',
      ),
  ],
  unclassified: const <String>[],
  engine: engine,
  analysedAt: _analysedAt,
  options: options,
  schemaVersion: MenuResponseParser.schemaVersion,
);

/// A fake server's handler that analyses whatever menu it is sent, under
/// the options it is sent, as `POST /v1/classify` does.
Future<http.Response> _echo(http.Request request) async {
  final body = jsonDecode(request.body) as Map<String, Object?>;
  final menu = Menu.tryFrom(body['menu']! as Map<String, Object?>)!;
  final options = AnalysisOptionsSnapshot.tryFrom(
    body['options']! as Map<String, Object?>,
  );
  return http.Response(
    jsonEncode(<String, Object?>{
      'analysis': _analysisOf(menu, options: options).toJson(),
    }),
    200,
  );
}

/// A fake server answering through [_echo].
MockClient _echoServer() => MockClient(_echo);

/// A backend error body naming [reason] with [statusCode].
String _errorBody(String reason, int statusCode) =>
    jsonEncode(<String, Object?>{'reason': reason, 'status_code': statusCode});

/// Builds a classifier over [transport].
BackendMenuClassifier _build(
  http.Client transport, {
  Uri? baseUrl,
  bool noBase = false,
  FakeInstallIdStore? store,
  Duration timeout = const Duration(seconds: 120),
}) => BackendMenuClassifier(
  client: transport,
  baseUrl: noBase ? null : (baseUrl ?? _base),
  installIdStore: store ?? FakeInstallIdStore(installId: _installId),
  timeout: timeout,
);

/// Builds a classifier whose server always answers [body] with [status].
BackendMenuClassifier _answering(String body, int status) =>
    _build(MockClient((_) async => http.Response(body, status)));

/// A classifier whose transport records every request into [requests]
/// and answers through [_echoServer].
BackendMenuClassifier _recording(List<http.Request> requests, {Uri? baseUrl}) {
  return _build(
    MockClient((request) async {
      requests.add(request);
      return await _echo(request);
    }),
    baseUrl: baseUrl,
  );
}

void main() {
  runMenuClassifierContract(
    'BackendMenuClassifier',
    () => _build(_echoServer()),
  );
  runMenuClassifierContract(
    'BackendMenuClassifier (not configured)',
    () => _build(_echoServer(), noBase: true),
  );

  group('BackendMenuClassifier with no backend', () {
    test('answers notConfigured without any I/O or announcement', () async {
      // Arrange
      var requests = 0;
      final store = FakeInstallIdStore();
      final heard = <ClassifyingEngine>[];
      final classifier = _build(
        MockClient((_) async {
          requests++;
          return http.Response('{}', 200);
        }),
        noBase: true,
        store: store,
      );

      // Act
      final result = await classifier.classify(
        _menu,
        options: ClassificationOptions(onEngineStarted: heard.add),
      );

      // Assert
      expect(
        result,
        equals(
          const MenuAnalysisFailed(
            reason: MenuAnalysisFailureReason.notConfigured,
          ),
        ),
      );
      expect(requests, equals(0));
      expect(store.calls, equals(0));
      expect(heard, isEmpty);
    });
  });

  group('BackendMenuClassifier request', () {
    test('posts once to {base}/v1/classify', () async {
      // Arrange
      final requests = <http.Request>[];
      final classifier = _recording(requests);

      // Act
      await classifier.classify(_menu, options: _steered);

      // Assert
      expect(requests, hasLength(1));
      expect(requests.single.method, equals('POST'));
      expect(
        requests.single.url,
        equals(Uri.parse('https://api.ketoclub.test/v1/classify')),
      );
    });

    test('keeps a base path and drops a trailing slash', () async {
      // Arrange
      final requests = <http.Request>[];
      final classifier = _recording(
        requests,
        baseUrl: Uri.parse('https://api.ketoclub.test/prefix/'),
      );

      // Act
      await classifier.classify(_menu);

      // Assert
      expect(
        requests.single.url,
        equals(Uri.parse('https://api.ketoclub.test/prefix/v1/classify')),
      );
    });

    test('the body is exactly {menu, options}, menu as Menu.toJson', () async {
      // Arrange
      final requests = <http.Request>[];
      final classifier = _recording(requests);

      // Act
      await classifier.classify(_menu, options: _steered);

      // Assert
      final body = jsonDecode(requests.single.body) as Map<String, Object?>;
      expect(body.keys, unorderedEquals(<String>['menu', 'options']));
      expect(body['menu'], equals(jsonDecode(jsonEncode(_menu.toJson()))));
      expect(
        body['options'],
        equals(<String, Object?>{
          'netCarbLimitGrams': 9,
          'dietaryConstraints': <Object?>[dairyFreePromptFragment],
        }),
      );
    });

    test('the default options are sent as the 6 g limit and no '
        'constraints', () async {
      // Arrange
      final requests = <http.Request>[];
      final classifier = _recording(requests);

      // Act
      await classifier.classify(_menu);

      // Assert
      final body = jsonDecode(requests.single.body) as Map<String, Object?>;
      expect(
        body['options'],
        equals(<String, Object?>{
          'netCarbLimitGrams': defaultNetCarbLimitGrams,
          'dietaryConstraints': <Object?>[],
        }),
      );
    });

    test('sends the install id and JSON content type, never '
        'Authorization', () async {
      // Arrange
      final requests = <http.Request>[];
      final classifier = _recording(requests);

      // Act
      await classifier.classify(_menu);

      // Assert
      final headers = requests.single.headers;
      expect(headers['X-KetoClub-Install-Id'], equals(_installId));
      expect(headers['Content-Type'], startsWith('application/json'));
      expect(
        headers.keys.map((key) => key.toLowerCase()),
        isNot(contains('authorization')),
      );
      expect(backendInstallIdHeader, equals('X-KetoClub-Install-Id'));
    });

    test('announces the llm engine once, before the request '
        'resolves', () async {
      // Arrange
      final heard = <ClassifyingEngine>[];
      final gate = Completer<http.Response>();
      final classifier = _build(MockClient((_) => gate.future));

      // Act
      final pending = classifier.classify(
        _menu,
        options: ClassificationOptions(onEngineStarted: heard.add),
      );

      // Assert
      expect(heard, equals(<ClassifyingEngine>[ClassifyingEngine.llm]));
      gate.complete(http.Response('{}', 200));
      await pending;
      expect(heard, equals(<ClassifyingEngine>[ClassifyingEngine.llm]));
    });
  });

  group('BackendMenuClassifier success', () {
    test("returns the server's llm analysis", () async {
      // Arrange
      final served = _analysisOf(_menu, options: _steered.snapshot);
      final classifier = _answering(
        jsonEncode(<String, Object?>{'analysis': served.toJson()}),
        200,
      );

      // Act
      final result = await classifier.classify(_menu, options: _steered);

      // Assert
      expect(result, equals(served));
    });

    test('returns a rules-stamped analysis as it came, not as a '
        'failure', () async {
      // Arrange: the server's Gemini call failed, so it ran its own rules.
      final served = _analysisOf(
        _menu,
        options: _steered.snapshot,
        engine: const RulesEngine(reason: MenuAnalysisFailureReason.offline),
      );
      final classifier = _answering(
        jsonEncode(<String, Object?>{'analysis': served.toJson()}),
        200,
      );

      // Act
      final result = await classifier.classify(_menu, options: _steered);

      // Assert
      expect(result, equals(served));
      expect(
        (result as MenuAnalysed).engine,
        equals(const RulesEngine(reason: MenuAnalysisFailureReason.offline)),
      );
    });

    final unreadable = <String, String>{
      'a non-JSON body': 'not json',
      'a JSON array': '[]',
      'no analysis key': '{}',
      'a null analysis': '{"analysis": null}',
      'an analysis that is not an object': '{"analysis": "green"}',
      'a malformed analysis': '{"analysis": {"dishes": 3}}',
      'an analysis naming a dish the menu lacks': jsonEncode(<String, Object?>{
        'analysis': MenuAnalysed(
          dishes: const <AnalysedDish>[
            AnalysedDish(
              dishId: 'invented',
              name: 'Invented',
              verdict: DishVerdict.orderAsIs,
              why: 'Made up.',
            ),
          ],
          unclassified: const <String>[],
          engine: const LlmEngine(model: 'm'),
          analysedAt: _analysedAt,
        ).toJson(),
      }),
    };
    for (final MapEntry(key: label, value: body) in unreadable.entries) {
      test('a 200 with $label is badResponse', () async {
        // Arrange
        final classifier = _answering(body, 200);

        // Act
        final result = await classifier.classify(_menu);

        // Assert
        expect(
          result,
          equals(
            const MenuAnalysisFailed(
              reason: MenuAnalysisFailureReason.badResponse,
            ),
          ),
        );
      });
    }
  });

  group('BackendMenuClassifier error bodies', () {
    const named = <(String, int, MenuAnalysisFailureReason)>[
      ('notConfigured', 503, MenuAnalysisFailureReason.notConfigured),
      ('offline', 502, MenuAnalysisFailureReason.offline),
      ('timeout', 504, MenuAnalysisFailureReason.timeout),
      ('rateLimited', 429, MenuAnalysisFailureReason.rateLimited),
      ('badResponse', 502, MenuAnalysisFailureReason.badResponse),
      ('badResponse', 400, MenuAnalysisFailureReason.badResponse),
      ('noDishesFound', 422, MenuAnalysisFailureReason.noDishesFound),
    ];
    for (final (name, status, reason) in named) {
      test('$status $name maps to $reason', () async {
        // Arrange
        final classifier = _answering(_errorBody(name, status), status);

        // Act
        final result = await classifier.classify(_menu);

        // Assert
        expect(result, equals(MenuAnalysisFailed(reason: reason)));
      });
    }

    final untrusted = <String, (String, int)>{
      'payloadTooLarge': (_errorBody('payloadTooLarge', 413), 413),
      'an unknown name': (_errorBody('somethingNew', 500), 500),
      'client-only backendUnreachable': (
        _errorBody('backendUnreachable', 502),
        502,
      ),
      'client-only consentWithheld': (_errorBody('consentWithheld', 400), 400),
      'client-only apiKeyMissing': (_errorBody('apiKeyMissing', 400), 400),
      'client-only apiKeyRejected': (_errorBody('apiKeyRejected', 400), 400),
      "FastAPI's 422 detail": (
        jsonEncode(<String, Object?>{
          'detail': <Object?>[
            <String, Object?>{'type': 'missing', 'loc': <Object?>[]},
          ],
        }),
        422,
      ),
      'a non-string reason': ('{"reason": 7, "status_code": 500}', 500),
      'a non-JSON body': ('<html>Bad gateway</html>', 502),
    };
    for (final MapEntry(key: label, value: (body, status))
        in untrusted.entries) {
      test('$label is badResponse', () async {
        // Arrange
        final classifier = _answering(body, status);

        // Act
        final result = await classifier.classify(_menu);

        // Assert
        expect(
          result,
          equals(
            const MenuAnalysisFailed(
              reason: MenuAnalysisFailureReason.badResponse,
            ),
          ),
        );
      });
    }

    test('a failure carries no text from the error body', () async {
      // Arrange
      const secret = 'upstream-said-something-private';
      final classifier = _answering(
        jsonEncode(<String, Object?>{
          'reason': 'rateLimited',
          'status_code': 429,
          'extra': secret,
        }),
        429,
      );

      // Act
      final result = await classifier.classify(_menu);

      // Assert
      expect(result, isA<MenuAnalysisFailed>());
      expect((result as MenuAnalysisFailed).detail, isNull);
      expect(result.toString(), isNot(contains(secret)));
    });
  });

  group('BackendMenuClassifier transport failures', () {
    test('a ClientException is backendUnreachable, never offline', () async {
      // Arrange
      final classifier = _build(
        MockClient((request) async {
          throw http.ClientException('Connection refused', request.url);
        }),
      );

      // Act
      final result = await classifier.classify(_menu);

      // Assert
      expect(
        result,
        equals(
          const MenuAnalysisFailed(
            reason: MenuAnalysisFailureReason.backendUnreachable,
          ),
        ),
      );
    });

    test('a TimeoutException from the transport is timeout', () async {
      // Arrange
      final classifier = _build(
        MockClient((_) async {
          throw TimeoutException('slow');
        }),
      );

      // Act
      final result = await classifier.classify(_menu);

      // Assert
      expect(
        result,
        equals(
          const MenuAnalysisFailed(reason: MenuAnalysisFailureReason.timeout),
        ),
      );
    });

    test('a request exceeding the timeout is timeout', () {
      fakeAsync((async) {
        // Arrange
        final classifier = _build(
          MockClient((_) => Completer<http.Response>().future),
          timeout: const Duration(seconds: 30),
        );
        MenuAnalysis? result;

        // Act
        unawaited(classifier.classify(_menu).then((value) => result = value));
        async.elapse(const Duration(seconds: 29));

        // Assert
        expect(result, isNull);
        async.elapse(const Duration(seconds: 1));
        expect(
          result,
          equals(
            const MenuAnalysisFailed(reason: MenuAnalysisFailureReason.timeout),
          ),
        );
      });
    });

    test('the default timeout is the LLM request budget', () {
      // Arrange & Act
      final classifier = BackendMenuClassifier(
        client: _echoServer(),
        baseUrl: _base,
        installIdStore: FakeInstallIdStore(),
      );

      // Assert
      expect(classifier.timeout, equals(llmRequestTimeout));
      expect(classifier.baseUrl, equals(_base));
    });
  });

  group('the shared wire helpers', () {
    test('backendRouteUri joins with or without a trailing slash', () {
      expect(
        backendRouteUri(Uri.parse('http://localhost:8000'), '/v1/x'),
        equals(Uri.parse('http://localhost:8000/v1/x')),
      );
      expect(
        backendRouteUri(Uri.parse('http://localhost:8000/'), '/v1/x'),
        equals(Uri.parse('http://localhost:8000/v1/x')),
      );
    });

    test('backendFailureReasonFrom trusts only the wire reasons', () {
      for (final reason in MenuAnalysisFailureReason.values) {
        final mapped = backendFailureReasonFrom(<String, Object?>{
          'reason': reason.name,
        });
        final wire = <MenuAnalysisFailureReason>{
          MenuAnalysisFailureReason.notConfigured,
          MenuAnalysisFailureReason.offline,
          MenuAnalysisFailureReason.timeout,
          MenuAnalysisFailureReason.rateLimited,
          MenuAnalysisFailureReason.badResponse,
          MenuAnalysisFailureReason.noDishesFound,
        };
        expect(
          mapped,
          equals(
            wire.contains(reason)
                ? reason
                : MenuAnalysisFailureReason.badResponse,
          ),
          reason: reason.name,
        );
      }
      expect(
        backendFailureReasonFrom(null),
        equals(MenuAnalysisFailureReason.badResponse),
      );
    });

    test('decodeBackendBody reads JSON and answers null for anything '
        'else', () {
      expect(
        decodeBackendBody(http.Response('{"a": 1}', 200)),
        equals(<String, Object?>{'a': 1}),
      );
      expect(decodeBackendBody(http.Response('nope', 200)), isNull);
      expect(
        decodeBackendBody(
          http.Response.bytes(
            <int>[0xff, 0xfe],
            200,
            headers: <String, String>{
              'content-type': 'application/json; charset=utf-8',
            },
          ),
        ),
        isNull,
      );
    });
  });
}

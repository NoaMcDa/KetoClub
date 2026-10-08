import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/scanned_menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/classifier/backend_scanned_menu_classifier.dart';
import 'package:ketoclub/services/classifier/menu_classifier.dart';
import 'package:ketoclub/services/classifier/scanned_menu_classifier.dart';
import 'package:ketoclub/utils/constants.dart';

import '../../fakes/fake_install_id_store.dart';
import 'scanned_menu_classifier_contract.dart';

/// The backend base every test uses unless it is exercising the URL
/// composition itself.
final Uri _base = Uri.parse('https://api.ketoclub.test');

/// The install id the fake store answers with in every test.
const String _installId = '0123456789abcdef0123456789abcdef';

/// When the fake server says it read a scan.
final DateTime _readAt = DateTime.utc(2026, 10, 8, 12);

/// A JPEG photograph and a PDF, in that order.
final ScannedMenu _twoPages = ScannedMenu(
  pages: <ScannedPage>[
    ScannedPage(
      mimeType: ScannedPage.jpeg,
      bytes: Uint8List.fromList(<int>[0xFF, 0xD8, 0xFF, 0xE0, 0x00]),
    ),
    ScannedPage(
      mimeType: ScannedPage.pdf,
      bytes: Uint8List.fromList(utf8.encode('%PDF-1.4 menu')),
    ),
  ],
);

/// Options that differ from the defaults in every verdict-shaping field.
const ClassificationOptions _steered = ClassificationOptions(
  estimationConsentGiven: true,
  netCarbLimitGrams: 9,
  dietaryConstraints: <String>[dairyFreePromptFragment],
);

/// The menu a server reads from [pageCount] pages: one dish per page,
/// addressed to [source].
Menu _menuOf(int pageCount, {MenuSource source = MenuSource.scan}) => Menu(
  venueRef: VenueRef(source: source, platformId: 'a1b2c3d4'),
  currency: 'ILS',
  fetchedAt: _readAt,
  categories: <MenuCategory>[
    MenuCategory(
      id: 'scanned',
      name: 'Scanned',
      dishes: <Dish>[
        for (var i = 1; i <= pageCount; i++)
          Dish(
            id: 's$i',
            name: 'Dish on page $i',
            description: '',
            price: 0,
            options: const <DishOption>[],
            page: i,
          ),
      ],
    ),
  ],
);

/// An analysis of [menu]'s dishes, every one green, under [options].
MenuAnalysed _analysisOf(Menu menu, {AnalysisOptionsSnapshot? options}) =>
    MenuAnalysed(
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
      engine: const LlmEngine(model: 'gemini-test'),
      analysedAt: _readAt,
      options: options,
      schemaVersion: 1,
    );

/// The success body `POST /v1/scan` answers for [menu] and [analysis].
String _readBody(Menu menu, MenuAnalysed analysis) => jsonEncode(
  <String, Object?>{'menu': menu.toJson(), 'analysis': analysis.toJson()},
);

/// A fake server's handler that reads one dish per page it is sent, under
/// the options it is sent, as `POST /v1/scan` does.
Future<http.Response> _echo(http.Request request) async {
  final body = jsonDecode(request.body) as Map<String, Object?>;
  final pages = body['pages']! as List<Object?>;
  final options = AnalysisOptionsSnapshot.tryFrom(
    body['options']! as Map<String, Object?>,
  );
  final menu = _menuOf(pages.length);
  return http.Response(
    _readBody(menu, _analysisOf(menu, options: options)),
    200,
  );
}

/// A backend error body naming [reason] with [statusCode].
String _errorBody(String reason, int statusCode) =>
    jsonEncode(<String, Object?>{'reason': reason, 'status_code': statusCode});

/// Builds a classifier over [transport].
BackendScannedMenuClassifier _build(
  http.Client transport, {
  Uri? baseUrl,
  bool noBase = false,
  FakeInstallIdStore? store,
  Duration timeout = const Duration(seconds: 120),
}) => BackendScannedMenuClassifier(
  client: transport,
  baseUrl: noBase ? null : (baseUrl ?? _base),
  installIdStore: store ?? FakeInstallIdStore(installId: _installId),
  timeout: timeout,
);

/// Builds a classifier whose server always answers [body] with [status].
BackendScannedMenuClassifier _answering(String body, int status) =>
    _build(MockClient((_) async => http.Response(body, status)));

/// A classifier whose transport records every request into [requests]
/// and answers through [_echo].
BackendScannedMenuClassifier _recording(
  List<http.Request> requests, {
  Uri? baseUrl,
}) => _build(
  MockClient((request) async {
    requests.add(request);
    return await _echo(request);
  }),
  baseUrl: baseUrl,
);

/// Classifies [_twoPages] with the default options.
Future<ScannedMenuResult> _classify(BackendScannedMenuClassifier classifier) =>
    classifier.classify(_twoPages, options: const ClassificationOptions());

void main() {
  runScannedMenuClassifierContract(
    'BackendScannedMenuClassifier',
    () => _build(MockClient(_echo)),
  );
  runScannedMenuClassifierContract(
    'BackendScannedMenuClassifier (not configured)',
    () => _build(MockClient(_echo), noBase: true),
  );

  group('BackendScannedMenuClassifier without a request', () {
    test('no backend: notConfigured, no I/O, no announcement', () async {
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
        _twoPages,
        options: ClassificationOptions(onEngineStarted: heard.add),
      );

      // Assert
      expect(
        result,
        equals(
          const ScannedMenuFailed(
            reason: MenuAnalysisFailureReason.notConfigured,
          ),
        ),
      );
      expect(requests, equals(0));
      expect(store.calls, equals(0));
      expect(heard, isEmpty);
    });

    test('an empty scan: noDishesFound, no I/O, no announcement', () async {
      // Arrange
      var requests = 0;
      final store = FakeInstallIdStore();
      final heard = <ClassifyingEngine>[];
      final classifier = _build(
        MockClient((_) async {
          requests++;
          return http.Response('{}', 200);
        }),
        store: store,
      );

      // Act
      final result = await classifier.classify(
        ScannedMenu(pages: const <ScannedPage>[]),
        options: ClassificationOptions(onEngineStarted: heard.add),
      );

      // Assert
      expect(
        result,
        equals(
          const ScannedMenuFailed(
            reason: MenuAnalysisFailureReason.noDishesFound,
          ),
        ),
      );
      expect(requests, equals(0));
      expect(store.calls, equals(0));
      expect(heard, isEmpty);
    });
  });

  group('BackendScannedMenuClassifier request', () {
    test('posts all pages once to {base}/v1/scan', () async {
      // Arrange
      final requests = <http.Request>[];
      final classifier = _recording(
        requests,
        baseUrl: Uri.parse('https://api.ketoclub.test/'),
      );

      // Act
      await _classify(classifier);

      // Assert
      expect(requests, hasLength(1));
      expect(requests.single.method, equals('POST'));
      expect(
        requests.single.url,
        equals(Uri.parse('https://api.ketoclub.test/v1/scan')),
      );
    });

    test('the body is exactly {pages, options}, each page {mimeType, '
        'data} in base64, in order', () async {
      // Arrange
      final requests = <http.Request>[];
      final classifier = _recording(requests);

      // Act
      await classifier.classify(_twoPages, options: _steered);

      // Assert
      final body = jsonDecode(requests.single.body) as Map<String, Object?>;
      expect(body.keys, unorderedEquals(<String>['pages', 'options']));
      expect(
        body['pages'],
        equals(<Object?>[
          <String, Object?>{
            'mimeType': 'image/jpeg',
            'data': base64Encode(_twoPages.pages[0].bytes),
          },
          <String, Object?>{
            'mimeType': 'application/pdf',
            'data': base64Encode(_twoPages.pages[1].bytes),
          },
        ]),
      );
      expect(
        body['options'],
        equals(<String, Object?>{
          'netCarbLimitGrams': 9,
          'dietaryConstraints': <Object?>[dairyFreePromptFragment],
        }),
      );
    });

    test('sends the install id and JSON content type, never '
        'Authorization', () async {
      // Arrange
      final requests = <http.Request>[];
      final classifier = _recording(requests);

      // Act
      await _classify(classifier);

      // Assert
      final headers = requests.single.headers;
      expect(headers['X-KetoClub-Install-Id'], equals(_installId));
      expect(headers['Content-Type'], startsWith('application/json'));
      expect(
        headers.keys.map((key) => key.toLowerCase()),
        isNot(contains('authorization')),
      );
    });

    test('announces the llm engine once, before the request '
        'resolves', () async {
      // Arrange
      final heard = <ClassifyingEngine>[];
      final gate = Completer<http.Response>();
      final classifier = _build(MockClient((_) => gate.future));

      // Act
      final pending = classifier.classify(
        _twoPages,
        options: ClassificationOptions(onEngineStarted: heard.add),
      );

      // Assert
      expect(heard, equals(<ClassifyingEngine>[ClassifyingEngine.llm]));
      gate.complete(http.Response('{}', 200));
      await pending;
      expect(heard, equals(<ClassifyingEngine>[ClassifyingEngine.llm]));
    });
  });

  group('BackendScannedMenuClassifier success', () {
    test("returns the server's menu and analysis as one read", () async {
      // Arrange
      final menu = _menuOf(2);
      final analysis = _analysisOf(menu, options: _steered.snapshot);
      final classifier = _answering(_readBody(menu, analysis), 200);

      // Act
      final result = await classifier.classify(_twoPages, options: _steered);

      // Assert
      expect(result, isA<ScannedMenuRead>());
      final read = result as ScannedMenuRead;
      expect(read.analysis, equals(analysis));
      expect(read.menu.toJson(), equals(menu.toJson()));
      expect(read.menu.allDishes.map((dish) => dish.page), equals(<int>[1, 2]));
    });

    final menu = _menuOf(2);
    final analysis = _analysisOf(menu);
    final unreadable = <String, String>{
      'a non-JSON body': 'not json',
      'a JSON array': '[]',
      'no menu': jsonEncode(<String, Object?>{'analysis': analysis.toJson()}),
      'no analysis': jsonEncode(<String, Object?>{'menu': menu.toJson()}),
      'a malformed menu': jsonEncode(<String, Object?>{
        'menu': <String, Object?>{'venueRef': 3},
        'analysis': analysis.toJson(),
      }),
      'a malformed analysis': jsonEncode(<String, Object?>{
        'menu': menu.toJson(),
        'analysis': <String, Object?>{'dishes': 'none'},
      }),
      'a menu not addressed to a scan': _readBody(
        _menuOf(2, source: MenuSource.wolt),
        analysis,
      ),
      'an analysis naming a dish the menu lacks': _readBody(
        _menuOf(1),
        analysis,
      ),
    };
    for (final MapEntry(key: label, value: body) in unreadable.entries) {
      test('a 200 with $label is badResponse', () async {
        // Arrange
        final classifier = _answering(body, 200);

        // Act
        final result = await _classify(classifier);

        // Assert
        expect(
          result,
          equals(
            const ScannedMenuFailed(
              reason: MenuAnalysisFailureReason.badResponse,
            ),
          ),
        );
      });
    }
  });

  group('BackendScannedMenuClassifier error bodies', () {
    const named = <(String, int, MenuAnalysisFailureReason)>[
      ('notConfigured', 503, MenuAnalysisFailureReason.notConfigured),
      ('offline', 502, MenuAnalysisFailureReason.offline),
      ('timeout', 504, MenuAnalysisFailureReason.timeout),
      ('rateLimited', 429, MenuAnalysisFailureReason.rateLimited),
      ('badResponse', 502, MenuAnalysisFailureReason.badResponse),
      ('noDishesFound', 422, MenuAnalysisFailureReason.noDishesFound),
    ];
    for (final (name, status, reason) in named) {
      test('$status $name maps to $reason', () async {
        // Arrange
        final classifier = _answering(_errorBody(name, status), status);

        // Act
        final result = await _classify(classifier);

        // Assert
        expect(result, equals(ScannedMenuFailed(reason: reason)));
      });
    }

    final untrusted = <String, (String, int)>{
      'payloadTooLarge': (_errorBody('payloadTooLarge', 413), 413),
      'client-only backendUnreachable': (
        _errorBody('backendUnreachable', 502),
        502,
      ),
      "FastAPI's 422 detail": ('{"detail": []}', 422),
      'a non-JSON body': ('<html>Bad gateway</html>', 502),
    };
    for (final MapEntry(key: label, value: (body, status))
        in untrusted.entries) {
      test('$label is badResponse', () async {
        // Arrange
        final classifier = _answering(body, status);

        // Act
        final result = await _classify(classifier);

        // Assert
        expect(
          result,
          equals(
            const ScannedMenuFailed(
              reason: MenuAnalysisFailureReason.badResponse,
            ),
          ),
        );
      });
    }
  });

  group('BackendScannedMenuClassifier transport failures', () {
    test('a ClientException is backendUnreachable, never offline', () async {
      // Arrange
      final classifier = _build(
        MockClient((request) async {
          throw http.ClientException('Connection refused', request.url);
        }),
      );

      // Act
      final result = await _classify(classifier);

      // Assert
      expect(
        result,
        equals(
          const ScannedMenuFailed(
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
      final result = await _classify(classifier);

      // Assert
      expect(
        result,
        equals(
          const ScannedMenuFailed(reason: MenuAnalysisFailureReason.timeout),
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
        ScannedMenuResult? result;

        // Act
        unawaited(_classify(classifier).then((value) => result = value));
        async.elapse(const Duration(seconds: 29));

        // Assert
        expect(result, isNull);
        async.elapse(const Duration(seconds: 1));
        expect(
          result,
          equals(
            const ScannedMenuFailed(reason: MenuAnalysisFailureReason.timeout),
          ),
        );
      });
    });

    test('the default timeout is the LLM request budget', () {
      // Arrange & Act
      final classifier = BackendScannedMenuClassifier(
        client: MockClient(_echo),
        baseUrl: _base,
        installIdStore: FakeInstallIdStore(),
      );

      // Assert
      expect(classifier.timeout, equals(llmRequestTimeout));
      expect(classifier.baseUrl, equals(_base));
    });
  });
}

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/scanned_menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/classifier/backend_menu_classifier.dart';
import 'package:ketoclub/services/classifier/backend_scanned_menu_classifier.dart';
import 'package:ketoclub/services/classifier/fallback_classifiers.dart';
import 'package:ketoclub/services/classifier/menu_classifier.dart';
import 'package:ketoclub/services/classifier/scanned_menu_classifier.dart';

import '../../fakes/fake_install_id_store.dart';
import '../../fakes/fake_menu_classifier.dart';
import '../../fakes/fake_scanned_menu_classifier.dart';
import 'menu_classifier_contract.dart';
import 'scanned_menu_classifier_contract.dart';

/// The reasons the chain hands to the fallback, and only these.
const Set<MenuAnalysisFailureReason> _fallThrough = <MenuAnalysisFailureReason>{
  MenuAnalysisFailureReason.notConfigured,
  MenuAnalysisFailureReason.backendUnreachable,
  MenuAnalysisFailureReason.timeout,
  MenuAnalysisFailureReason.rateLimited,
};

/// Every reason the chain does not hand on.
final List<MenuAnalysisFailureReason> _standing = <MenuAnalysisFailureReason>[
  for (final reason in MenuAnalysisFailureReason.values)
    if (!_fallThrough.contains(reason)) reason,
];

/// A one-dish menu.
final Menu _menu = Menu(
  venueRef: const VenueRef(source: MenuSource.wolt, platformId: 'v'),
  currency: 'ILS',
  fetchedAt: DateTime.utc(2026),
  categories: const <MenuCategory>[
    MenuCategory(
      id: 'c',
      name: 'Mains',
      dishes: <Dish>[
        Dish(
          id: 'd1',
          name: 'Ribeye',
          description: '',
          price: 120,
          options: <DishOption>[],
        ),
      ],
    ),
  ],
);

/// A one-page scan.
final ScannedMenu _scan = ScannedMenu(
  pages: <ScannedPage>[
    ScannedPage(
      mimeType: ScannedPage.jpeg,
      bytes: Uint8List.fromList(<int>[0xFF, 0xD8, 0x01, 0xFF, 0xD9]),
    ),
  ],
);

/// Options a test can tell apart from the defaults.
const ClassificationOptions _options = ClassificationOptions(
  estimationConsentGiven: true,
  netCarbLimitGrams: 11,
);

/// A distinct analysis stamped with [engine].
MenuAnalysed _analysis(AnalysisEngine engine) => MenuAnalysed(
  dishes: const <AnalysedDish>[],
  unclassified: const <String>['Ribeye'],
  engine: engine,
  analysedAt: DateTime.utc(2026, 10, 8),
);

/// A distinct scan read whose analysis is stamped with [model].
ScannedMenuRead _read(String model) => ScannedMenuRead(
  menu: Menu(
    venueRef: const VenueRef(source: MenuSource.scan, platformId: 'feed'),
    currency: 'ILS',
    fetchedAt: DateTime.utc(2026),
    categories: const <MenuCategory>[],
  ),
  analysis: _analysis(LlmEngine(model: model)),
);

/// A fake primary that fails for [reason].
FakeMenuClassifier _failing(MenuAnalysisFailureReason reason) =>
    FakeMenuClassifier()..respondWith(MenuAnalysisFailed(reason: reason));

/// A fake scanned primary that fails for [reason].
FakeScannedMenuClassifier _scanFailing(MenuAnalysisFailureReason reason) =>
    FakeScannedMenuClassifier()..respondWith(ScannedMenuFailed(reason: reason));

/// A backend menu classifier whose server analyses what it is sent.
BackendMenuClassifier _backendMenu({bool configured = true}) =>
    BackendMenuClassifier(
      client: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, Object?>;
        final menu = Menu.tryFrom(body['menu']! as Map<String, Object?>)!;
        final options = AnalysisOptionsSnapshot.tryFrom(
          body['options']! as Map<String, Object?>,
        );
        final analysis = MenuAnalysed(
          dishes: <AnalysedDish>[
            for (final dish in menu.allDishes)
              AnalysedDish(
                dishId: dish.id,
                name: dish.name,
                verdict: DishVerdict.orderAsIs,
                why: 'Server verdict.',
              ),
          ],
          unclassified: const <String>[],
          engine: const LlmEngine(model: 'gemini-test'),
          analysedAt: DateTime.utc(2026),
          options: options,
        );
        return http.Response(
          jsonEncode(<String, Object?>{'analysis': analysis.toJson()}),
          200,
        );
      }),
      baseUrl: configured ? Uri.parse('https://api.ketoclub.test') : null,
      installIdStore: FakeInstallIdStore(),
    );

/// A backend scanned classifier whose server is down.
BackendScannedMenuClassifier _unreachableScan() => BackendScannedMenuClassifier(
  client: MockClient((request) async {
    throw http.ClientException('Connection refused', request.url);
  }),
  baseUrl: Uri.parse('https://api.ketoclub.test'),
  installIdStore: FakeInstallIdStore(),
);

void main() {
  runMenuClassifierContract(
    'FallbackMenuClassifier (fake primary)',
    () => FallbackMenuClassifier(
      primary: FakeMenuClassifier(),
      fallback: FakeMenuClassifier(),
    ),
  );
  runMenuClassifierContract(
    'FallbackMenuClassifier (backend primary)',
    () => FallbackMenuClassifier(
      primary: _backendMenu(),
      fallback: FakeMenuClassifier(),
    ),
  );
  runMenuClassifierContract(
    'FallbackMenuClassifier (no backend, so the fallback answers)',
    () => FallbackMenuClassifier(
      primary: _backendMenu(configured: false),
      fallback: FakeMenuClassifier(),
    ),
  );
  runScannedMenuClassifierContract(
    'FallbackScannedMenuClassifier (fake primary)',
    () => FallbackScannedMenuClassifier(
      primary: FakeScannedMenuClassifier(),
      fallback: FakeScannedMenuClassifier(),
    ),
  );
  runScannedMenuClassifierContract(
    'FallbackScannedMenuClassifier (unreachable backend, so the fallback '
    'answers)',
    () => FallbackScannedMenuClassifier(
      primary: _unreachableScan(),
      fallback: FakeScannedMenuClassifier(),
    ),
  );

  group('shouldFallBack', () {
    for (final reason in MenuAnalysisFailureReason.values) {
      final expected = _fallThrough.contains(reason);
      test('${reason.name} ${expected ? 'falls' : 'does not fall'} '
          'back', () {
        expect(FallbackMenuClassifier.shouldFallBack(reason), equals(expected));
        expect(
          FallbackScannedMenuClassifier.shouldFallBack(reason),
          equals(expected),
        );
      });
    }
  });

  group('FallbackMenuClassifier', () {
    test("returns the primary's analysis without asking the "
        'fallback', () async {
      // Arrange
      final served = _analysis(const LlmEngine(model: 'primary'));
      final primary = FakeMenuClassifier()..respondWith(served);
      final fallback = FakeMenuClassifier();
      final chain = FallbackMenuClassifier(
        primary: primary,
        fallback: fallback,
      );

      // Act
      final result = await chain.classify(_menu, options: _options);

      // Assert
      expect(result, same(served));
      expect(primary.calls, hasLength(1));
      expect(fallback.calls, isEmpty);
    });

    test("returns the server's rules-stamped analysis without asking the "
        'fallback', () async {
      // Arrange
      final served = _analysis(
        const RulesEngine(reason: MenuAnalysisFailureReason.timeout),
      );
      final fallback = FakeMenuClassifier();
      final chain = FallbackMenuClassifier(
        primary: FakeMenuClassifier()..respondWith(served),
        fallback: fallback,
      );

      // Act
      final result = await chain.classify(_menu, options: _options);

      // Assert
      expect(result, same(served));
      expect(fallback.calls, isEmpty);
    });

    for (final reason in _fallThrough) {
      test('a primary ${reason.name} hands the same menu and options to '
          'the fallback, whose analysis is returned', () async {
        // Arrange
        final rescued = _analysis(const LlmEngine(model: 'fallback'));
        final fallback = FakeMenuClassifier()..respondWith(rescued);
        final chain = FallbackMenuClassifier(
          primary: _failing(reason),
          fallback: fallback,
        );

        // Act
        final result = await chain.classify(_menu, options: _options);

        // Assert
        expect(result, same(rescued));
        expect(fallback.calls, hasLength(1));
        expect(fallback.calls.single.$1, same(_menu));
        expect(fallback.calls.single.$2, same(_options));
      });
    }

    for (final reason in _standing) {
      test('a primary ${reason.name} stands and the fallback is never '
          'asked', () async {
        // Arrange
        final failure = MenuAnalysisFailed(reason: reason, detail: 'kept');
        final fallback = FakeMenuClassifier();
        final chain = FallbackMenuClassifier(
          primary: FakeMenuClassifier()..respondWith(failure),
          fallback: fallback,
        );

        // Act
        final result = await chain.classify(_menu, options: _options);

        // Assert
        expect(result, same(failure));
        expect(fallback.calls, isEmpty);
      });
    }

    for (final reason in _fallThrough.difference(<MenuAnalysisFailureReason>{
      MenuAnalysisFailureReason.notConfigured,
    })) {
      test('when both fail, the primary ${reason.name} is reported', () async {
        // Arrange
        final failure = MenuAnalysisFailed(reason: reason, detail: 'first');
        final chain = FallbackMenuClassifier(
          primary: FakeMenuClassifier()..respondWith(failure),
          fallback: _failing(MenuAnalysisFailureReason.apiKeyMissing),
        );

        // Act
        final result = await chain.classify(_menu, options: _options);

        // Assert
        expect(result, same(failure));
      });
    }

    test("when both fail after a primary notConfigured, the fallback's "
        'failure is reported', () async {
      // Arrange
      const second = MenuAnalysisFailed(
        reason: MenuAnalysisFailureReason.offline,
        detail: 'second',
      );
      final chain = FallbackMenuClassifier(
        primary: _failing(MenuAnalysisFailureReason.notConfigured),
        fallback: FakeMenuClassifier()..respondWith(second),
      );

      // Act
      final result = await chain.classify(_menu, options: _options);

      // Assert
      expect(result, same(second));
    });

    test('each engine announces itself, primary first', () async {
      // Arrange
      final heard = <ClassifyingEngine>[];
      final chain = FallbackMenuClassifier(
        primary: _failing(MenuAnalysisFailureReason.backendUnreachable)
          ..announces = const <ClassifyingEngine>[ClassifyingEngine.llm],
        fallback: FakeMenuClassifier()
          ..announces = const <ClassifyingEngine>[ClassifyingEngine.rules],
      );

      // Act
      await chain.classify(
        _menu,
        options: ClassificationOptions(onEngineStarted: heard.add),
      );

      // Assert
      expect(
        heard,
        equals(<ClassifyingEngine>[
          ClassifyingEngine.llm,
          ClassifyingEngine.rules,
        ]),
      );
    });

    test('an unconfigured backend falls to the fallback with no '
        'request', () async {
      // Arrange
      final fallback = FakeMenuClassifier();
      final chain = FallbackMenuClassifier(
        primary: _backendMenu(configured: false),
        fallback: fallback,
      );

      // Act
      final result = await chain.classify(_menu, options: _options);

      // Assert
      expect(result, isA<MenuAnalysed>());
      expect(fallback.calls, hasLength(1));
    });
  });

  group('FallbackScannedMenuClassifier', () {
    test("returns the primary's read without asking the fallback", () async {
      // Arrange
      final served = _read('primary');
      final fallback = FakeScannedMenuClassifier();
      final chain = FallbackScannedMenuClassifier(
        primary: FakeScannedMenuClassifier()..respondWith(served),
        fallback: fallback,
      );

      // Act
      final result = await chain.classify(_scan, options: _options);

      // Assert
      expect(result, same(served));
      expect(fallback.calls, isEmpty);
    });

    for (final reason in _fallThrough) {
      test('a primary ${reason.name} hands the same scan and options to '
          'the fallback, whose read is returned', () async {
        // Arrange
        final rescued = _read('fallback');
        final fallback = FakeScannedMenuClassifier()..respondWith(rescued);
        final chain = FallbackScannedMenuClassifier(
          primary: _scanFailing(reason),
          fallback: fallback,
        );

        // Act
        final result = await chain.classify(_scan, options: _options);

        // Assert
        expect(result, same(rescued));
        expect(fallback.calls, hasLength(1));
        expect(fallback.calls.single.$1, same(_scan));
        expect(fallback.calls.single.$2, same(_options));
      });
    }

    for (final reason in _standing) {
      test('a primary ${reason.name} stands and the fallback is never '
          'asked', () async {
        // Arrange
        final failure = ScannedMenuFailed(reason: reason);
        final fallback = FakeScannedMenuClassifier();
        final chain = FallbackScannedMenuClassifier(
          primary: FakeScannedMenuClassifier()..respondWith(failure),
          fallback: fallback,
        );

        // Act
        final result = await chain.classify(_scan, options: _options);

        // Assert
        expect(result, same(failure));
        expect(fallback.calls, isEmpty);
      });
    }

    test('when both fail, the primary rateLimited is reported', () async {
      // Arrange
      final chain = FallbackScannedMenuClassifier(
        primary: _scanFailing(MenuAnalysisFailureReason.rateLimited),
        fallback: _scanFailing(MenuAnalysisFailureReason.apiKeyMissing),
      );

      // Act
      final result = await chain.classify(_scan, options: _options);

      // Assert
      expect(
        result,
        equals(
          const ScannedMenuFailed(
            reason: MenuAnalysisFailureReason.rateLimited,
          ),
        ),
      );
    });

    test("when both fail after a primary notConfigured, the fallback's "
        'failure is reported', () async {
      // Arrange
      final chain = FallbackScannedMenuClassifier(
        primary: _scanFailing(MenuAnalysisFailureReason.notConfigured),
        fallback: _scanFailing(MenuAnalysisFailureReason.apiKeyRejected),
      );

      // Act
      final result = await chain.classify(_scan, options: _options);

      // Assert
      expect(
        result,
        equals(
          const ScannedMenuFailed(
            reason: MenuAnalysisFailureReason.apiKeyRejected,
          ),
        ),
      );
    });

    test('an unreachable backend falls to the fallback', () async {
      // Arrange
      final fallback = FakeScannedMenuClassifier();
      final chain = FallbackScannedMenuClassifier(
        primary: _unreachableScan(),
        fallback: fallback,
      );

      // Act
      final result = await chain.classify(_scan, options: _options);

      // Assert
      expect(result, isA<ScannedMenuRead>());
      expect(fallback.calls, hasLength(1));
    });
  });
}

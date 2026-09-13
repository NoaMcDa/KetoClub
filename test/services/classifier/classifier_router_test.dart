import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/classifier/classifier_router.dart';
import 'package:ketoclub/services/classifier/menu_classifier.dart';

import '../../fakes/fake_key_store.dart';
import '../../fakes/fake_menu_classifier.dart';
import 'menu_classifier_contract.dart';

/// The venue every menu built by this file is addressed to.
const VenueRef _venueRef = VenueRef(
  source: MenuSource.wolt,
  platformId: 'router-test-venue',
);

/// A dish carrying [name] and nothing else, for tests that only care
/// about one piece of text.
Dish _dishNamed(String id, String name) =>
    Dish(id: id, name: name, description: '', price: 10, options: const []);

/// A menu addressed to [_venueRef] containing [dishes] in one category.
Menu _menuOf(List<Dish> dishes) => Menu(
  venueRef: _venueRef,
  currency: 'ILS',
  fetchedAt: DateTime.utc(2026),
  categories: [MenuCategory(id: 'cat-1', name: 'Mains', dishes: dishes)],
);

/// A trivially-valid completed analysis over [dishes], stamped
/// [LlmEngine] with [model].
MenuAnalysed _llmAnalysis(List<Dish> dishes, {String model = 'llm-model'}) =>
    MenuAnalysed(
      dishes: [
        for (final dish in dishes)
          AnalysedDish(
            dishId: dish.id,
            name: dish.name,
            verdict: DishVerdict.orderAsIs,
            why: 'LLM verdict for a router test.',
          ),
      ],
      unclassified: const <String>[],
      engine: LlmEngine(model: model),
      analysedAt: DateTime.utc(2026),
    );

/// A trivially-valid completed analysis over [dishes], stamped
/// [RulesEngine] with [reason] — what `HeuristicMenuClassifier` would
/// return before the router re-stamps it.
MenuAnalysed _heuristicAnalysis(
  List<Dish> dishes, {
  MenuAnalysisFailureReason reason = MenuAnalysisFailureReason.notConfigured,
}) => MenuAnalysed(
  dishes: [
    for (final dish in dishes)
      AnalysedDish(
        dishId: dish.id,
        name: dish.name,
        verdict: DishVerdict.orderAsIs,
        why: 'Rules verdict for a router test.',
      ),
  ],
  unclassified: const <String>[],
  engine: RulesEngine(reason: reason),
  analysedAt: DateTime.utc(2026),
);

/// The reasons the router falls back to the heuristic for and re-stamps
/// with the exact same reason it received from the LLM (architecture.md
/// §6.2, §10).
const List<MenuAnalysisFailureReason> _fallbackReasons =
    <MenuAnalysisFailureReason>[
      MenuAnalysisFailureReason.offline,
      MenuAnalysisFailureReason.timeout,
      MenuAnalysisFailureReason.rateLimited,
      MenuAnalysisFailureReason.badResponse,
    ];

void main() {
  runMenuClassifierContract(
    'RoutingMenuClassifier',
    () => RoutingMenuClassifier(
      FakeMenuClassifier(),
      FakeMenuClassifier(),
      FakeKeyStore(seed: 'contract-key'),
    ),
  );

  group('RoutingMenuClassifier', () {
    test('classify given no key stored returns the heuristic result stamped '
        'notConfigured, and the LLM was never called', () async {
      // Arrange
      final llm = FakeMenuClassifier();
      final heuristic = FakeMenuClassifier();
      final keyStore = FakeKeyStore();
      final router = RoutingMenuClassifier(llm, heuristic, keyStore);
      final menu = _menuOf([_dishNamed('dish-1', 'Salmon')]);
      const options = ClassificationOptions(estimationConsentGiven: true);

      // Act
      final result = await router.classify(menu, options: options);

      // Assert
      expect(llm.calls, isEmpty);
      expect(heuristic.calls, hasLength(1));
      final analysed = result as MenuAnalysed;
      expect(
        analysed.engine,
        equals(
          const RulesEngine(reason: MenuAnalysisFailureReason.notConfigured),
        ),
      );
    });

    test('classify given a key but withheld consent returns the heuristic '
        'result stamped notConfigured, and the LLM was never called', () async {
      // Arrange
      final llm = FakeMenuClassifier();
      final heuristic = FakeMenuClassifier();
      final keyStore = FakeKeyStore(seed: 'stored-key');
      final router = RoutingMenuClassifier(llm, heuristic, keyStore);
      final menu = _menuOf([_dishNamed('dish-1', 'Salmon')]);

      // Act
      final result = await router.classify(menu);

      // Assert
      expect(llm.calls, isEmpty);
      expect(heuristic.calls, hasLength(1));
      final analysed = result as MenuAnalysed;
      expect(
        analysed.engine,
        equals(
          const RulesEngine(reason: MenuAnalysisFailureReason.notConfigured),
        ),
      );
    });

    test('classify given a key and consent, with the LLM succeeding, returns '
        "the LLM's result stamped LlmEngine", () async {
      // Arrange
      final dishes = [_dishNamed('dish-1', 'Salmon')];
      final llmResult = _llmAnalysis(dishes, model: 'served-model');
      final llm = FakeMenuClassifier()..respondWith(llmResult);
      final heuristic = FakeMenuClassifier();
      final keyStore = FakeKeyStore(seed: 'stored-key');
      final router = RoutingMenuClassifier(llm, heuristic, keyStore);
      final menu = _menuOf(dishes);
      const options = ClassificationOptions(estimationConsentGiven: true);

      // Act
      final result = await router.classify(menu, options: options);

      // Assert
      expect(heuristic.calls, isEmpty);
      expect(llm.calls, hasLength(1));
      expect(result, equals(llmResult));
      final analysed = result as MenuAnalysed;
      expect(analysed.engine, equals(const LlmEngine(model: 'served-model')));
    });

    group('classify given the LLM fails, falls back to the heuristic stamped '
        'with the same reason', () {
      for (final reason in _fallbackReasons) {
        test('for MenuAnalysisFailureReason.${reason.name}', () async {
          // Arrange
          final dishes = [_dishNamed('dish-1', 'Salmon')];
          final llm = FakeMenuClassifier()
            ..respondWith(MenuAnalysisFailed(reason: reason));
          final heuristicResult = _heuristicAnalysis(dishes);
          final heuristic = FakeMenuClassifier()..respondWith(heuristicResult);
          final keyStore = FakeKeyStore(seed: 'stored-key');
          final router = RoutingMenuClassifier(llm, heuristic, keyStore);
          final menu = _menuOf(dishes);
          const options = ClassificationOptions(estimationConsentGiven: true);

          // Act
          final result = await router.classify(menu, options: options);

          // Assert
          expect(heuristic.calls, hasLength(1));
          final analysed = result as MenuAnalysed;
          expect(analysed.dishes, equals(heuristicResult.dishes));
          expect(analysed.engine, equals(RulesEngine(reason: reason)));
        });
      }
    });

    test('classify given the LLM fails with unauthorised returns '
        'MenuAnalysisFailed(unauthorised), and the heuristic was never '
        'called', () async {
      // Arrange
      final llm = FakeMenuClassifier()
        ..respondWith(
          const MenuAnalysisFailed(
            reason: MenuAnalysisFailureReason.unauthorised,
          ),
        );
      final heuristic = FakeMenuClassifier();
      final keyStore = FakeKeyStore(seed: 'stored-key');
      final router = RoutingMenuClassifier(llm, heuristic, keyStore);
      final menu = _menuOf([_dishNamed('dish-1', 'Salmon')]);
      const options = ClassificationOptions(estimationConsentGiven: true);

      // Act
      final result = await router.classify(menu, options: options);

      // Assert
      expect(heuristic.calls, isEmpty);
      expect(
        result,
        equals(
          const MenuAnalysisFailed(
            reason: MenuAnalysisFailureReason.unauthorised,
          ),
        ),
      );
    });

    test('classify given the LLM fails with noDishesFound returns the '
        'failure unchanged, and the heuristic was never called', () async {
      // Arrange
      final llm = FakeMenuClassifier()
        ..respondWith(
          const MenuAnalysisFailed(
            reason: MenuAnalysisFailureReason.noDishesFound,
          ),
        );
      final heuristic = FakeMenuClassifier();
      final keyStore = FakeKeyStore(seed: 'stored-key');
      final router = RoutingMenuClassifier(llm, heuristic, keyStore);
      final menu = _menuOf([_dishNamed('dish-1', 'Salmon')]);
      const options = ClassificationOptions(estimationConsentGiven: true);

      // Act
      final result = await router.classify(menu, options: options);

      // Assert
      expect(heuristic.calls, isEmpty);
      expect(
        result,
        equals(
          const MenuAnalysisFailed(
            reason: MenuAnalysisFailureReason.noDishesFound,
          ),
        ),
      );
    });

    test(
      'classify given the LLM fails with notConfigured (unreachable in '
      'practice) falls back to the heuristic stamped notConfigured',
      () async {
        // Arrange: defensive coverage of a reason `LlmMenuClassifier`
        // never actually produces (see classifier_router.dart).
        final dishes = [_dishNamed('dish-1', 'Salmon')];
        final llm = FakeMenuClassifier()
          ..respondWith(
            const MenuAnalysisFailed(
              reason: MenuAnalysisFailureReason.notConfigured,
            ),
          );
        final heuristicResult = _heuristicAnalysis(dishes);
        final heuristic = FakeMenuClassifier()..respondWith(heuristicResult);
        final keyStore = FakeKeyStore(seed: 'stored-key');
        final router = RoutingMenuClassifier(llm, heuristic, keyStore);
        final menu = _menuOf(dishes);
        const options = ClassificationOptions(estimationConsentGiven: true);

        // Act
        final result = await router.classify(menu, options: options);

        // Assert
        expect(heuristic.calls, hasLength(1));
        final analysed = result as MenuAnalysed;
        expect(analysed.dishes, equals(heuristicResult.dishes));
        expect(
          analysed.engine,
          equals(
            const RulesEngine(reason: MenuAnalysisFailureReason.notConfigured),
          ),
        );
      },
    );

    test('re-stamping keeps the heuristic result a copy, not a rebuild: '
        'unclassified names survive too', () async {
      // Arrange
      final dishes = [_dishNamed('dish-1', 'Salmon')];
      final llm = FakeMenuClassifier()
        ..respondWith(
          const MenuAnalysisFailed(reason: MenuAnalysisFailureReason.offline),
        );
      final heuristicResult = MenuAnalysed(
        dishes: const <AnalysedDish>[],
        unclassified: const ['Salmon'],
        engine: const RulesEngine(
          reason: MenuAnalysisFailureReason.notConfigured,
        ),
        analysedAt: DateTime.utc(2026),
      );
      final heuristic = FakeMenuClassifier()..respondWith(heuristicResult);
      final keyStore = FakeKeyStore(seed: 'stored-key');
      final router = RoutingMenuClassifier(llm, heuristic, keyStore);
      final menu = _menuOf(dishes);
      const options = ClassificationOptions(estimationConsentGiven: true);

      // Act
      final result = await router.classify(menu, options: options);

      // Assert
      final analysed = result as MenuAnalysed;
      expect(analysed.unclassified, equals(const ['Salmon']));
      expect(analysed.analysedAt, heuristicResult.analysedAt);
      expect(
        analysed.engine,
        equals(const RulesEngine(reason: MenuAnalysisFailureReason.offline)),
      );
    });

    test(
      'classify given the heuristic itself fails (defensive: it never '
      'does in the real implementation) returns that failure unre-stamped',
      () async {
        // Arrange: `HeuristicMenuClassifier` never returns
        // `MenuAnalysisFailed`, but the router degrades rather than
        // crashing on a bad cast if a `MenuClassifier` ever did.
        final llm = FakeMenuClassifier();
        const heuristicFailure = MenuAnalysisFailed(
          reason: MenuAnalysisFailureReason.noDishesFound,
        );
        final heuristic = FakeMenuClassifier()..respondWith(heuristicFailure);
        final keyStore = FakeKeyStore();
        final router = RoutingMenuClassifier(llm, heuristic, keyStore);
        final menu = _menuOf([_dishNamed('dish-1', 'Salmon')]);

        // Act
        final result = await router.classify(menu);

        // Assert
        expect(result, equals(heuristicFailure));
      },
    );
  });
}

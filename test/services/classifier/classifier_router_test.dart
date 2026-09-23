import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/classifier/classifier_router.dart';
import 'package:ketoclub/services/classifier/heuristic_menu_classifier.dart';
import 'package:ketoclub/services/classifier/llm_menu_classifier.dart';
import 'package:ketoclub/services/classifier/menu_classifier.dart';
import 'package:ketoclub/services/llm/llm_chat_client.dart';

import '../../fakes/fake_clock.dart';
import '../../fakes/fake_connectivity.dart';
import '../../fakes/fake_llm_chat_client.dart';
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
      MenuAnalysisFailureReason.backendUnreachable,
      MenuAnalysisFailureReason.notConfigured,
    ];

void main() {
  runMenuClassifierContract(
    'RoutingMenuClassifier',
    () => RoutingMenuClassifier(
      FakeMenuClassifier(),
      FakeMenuClassifier(),
      FakeConnectivity(),
    ),
  );

  group('RoutingMenuClassifier', () {
    test('classify given withheld consent returns the heuristic result '
        'stamped consentWithheld, and the LLM was never called', () async {
      // Arrange
      final llm = FakeMenuClassifier();
      final heuristic = FakeMenuClassifier();
      final router = RoutingMenuClassifier(llm, heuristic, FakeConnectivity());
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
          const RulesEngine(reason: MenuAnalysisFailureReason.consentWithheld),
        ),
      );
    });

    test('classify given consent, with the LLM succeeding, returns '
        "the LLM's result stamped LlmEngine", () async {
      // Arrange
      final dishes = [_dishNamed('dish-1', 'Salmon')];
      final llmResult = _llmAnalysis(dishes, model: 'served-model');
      final llm = FakeMenuClassifier()..respondWith(llmResult);
      final heuristic = FakeMenuClassifier();
      final router = RoutingMenuClassifier(llm, heuristic, FakeConnectivity());
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
          final router = RoutingMenuClassifier(
            llm,
            heuristic,
            FakeConnectivity(),
          );
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
      final router = RoutingMenuClassifier(llm, heuristic, FakeConnectivity());
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
      final router = RoutingMenuClassifier(llm, heuristic, FakeConnectivity());
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
        final router = RoutingMenuClassifier(
          llm,
          heuristic,
          FakeConnectivity(),
        );
        final menu = _menuOf([_dishNamed('dish-1', 'Salmon')]);

        // Act
        final result = await router.classify(menu);

        // Assert
        expect(result, equals(heuristicFailure));
      },
    );

    test('classify given the device reports offline returns the heuristic '
        'result stamped offline, and the LLM was never called', () async {
      // Arrange
      final dishes = [_dishNamed('dish-1', 'Salmon')];
      final llm = FakeMenuClassifier();
      final heuristicResult = _heuristicAnalysis(dishes);
      final heuristic = FakeMenuClassifier()..respondWith(heuristicResult);
      final connectivity = FakeConnectivity(online: false);
      final router = RoutingMenuClassifier(llm, heuristic, connectivity);
      final menu = _menuOf(dishes);
      const options = ClassificationOptions(estimationConsentGiven: true);

      // Act
      final result = await router.classify(menu, options: options);

      // Assert
      expect(llm.calls, isEmpty);
      expect(heuristic.calls, hasLength(1));
      final analysed = result as MenuAnalysed;
      expect(analysed.dishes, equals(heuristicResult.dishes));
      expect(
        analysed.engine,
        equals(const RulesEngine(reason: MenuAnalysisFailureReason.offline)),
      );
    });

    test(
      'classify given withheld consent stamps consentWithheld even when the '
      'device is also offline: rule 1 is decided before rule 2 is reached',
      () async {
        // Arrange: connectivity reports offline too, so a stamp of
        // `offline` rather than `consentWithheld` would mean rule 2 ran
        // first — that is the only way to tell the two rules apart from
        // the outside.
        final llm = FakeMenuClassifier();
        final heuristic = FakeMenuClassifier();
        final connectivity = FakeConnectivity(online: false);
        final router = RoutingMenuClassifier(llm, heuristic, connectivity);
        final menu = _menuOf([_dishNamed('dish-1', 'Salmon')]);

        // Act
        final result = await router.classify(menu);

        // Assert
        final analysed = result as MenuAnalysed;
        expect(
          analysed.engine,
          equals(
            const RulesEngine(
              reason: MenuAnalysisFailureReason.consentWithheld,
            ),
          ),
        );
      },
    );

    test('classify given the device reports online but the LLM call then '
        'fails offline anyway still returns the heuristic result stamped '
        'offline: the pre-check is a hint, never a verdict', () async {
      // Arrange
      final dishes = [_dishNamed('dish-1', 'Salmon')];
      final llm = FakeMenuClassifier()
        ..respondWith(
          const MenuAnalysisFailed(reason: MenuAnalysisFailureReason.offline),
        );
      final heuristicResult = _heuristicAnalysis(dishes);
      final heuristic = FakeMenuClassifier()..respondWith(heuristicResult);
      final connectivity = FakeConnectivity();
      final router = RoutingMenuClassifier(llm, heuristic, connectivity);
      final menu = _menuOf(dishes);
      const options = ClassificationOptions(estimationConsentGiven: true);

      // Act
      final result = await router.classify(menu, options: options);

      // Assert: the LLM was tried (the pre-check said online), it failed,
      // and the result is indistinguishable from the pre-check path above.
      expect(llm.calls, hasLength(1));
      expect(heuristic.calls, hasLength(1));
      final analysed = result as MenuAnalysed;
      expect(
        analysed.engine,
        equals(const RulesEngine(reason: MenuAnalysisFailureReason.offline)),
      );
    });

    test('every reason is either a fallback reason above, noDishesFound, or '
        "the router's own consentWithheld", () {
      // Arrange
      final covered = <MenuAnalysisFailureReason>{
        ..._fallbackReasons,
        MenuAnalysisFailureReason.noDishesFound,
        MenuAnalysisFailureReason.consentWithheld,
      };

      // Act & Assert
      expect(covered, equals(MenuAnalysisFailureReason.values.toSet()));
    });
  });

  group('RoutingMenuClassifier engine announcements (issue #65)', () {
    late FakeLlmChatClient client;
    late FakeConnectivity connectivity;
    late RoutingMenuClassifier router;
    late List<ClassifyingEngine> heard;
    late Menu menu;

    setUp(() {
      // The real engines, not fakes: each announces itself, and these
      // tests pin that the router's choice reaches a listener that way.
      client = FakeLlmChatClient();
      connectivity = FakeConnectivity();
      final clock = FakeClock(DateTime.utc(2026));
      router = RoutingMenuClassifier(
        LlmMenuClassifier(client, clock),
        HeuristicMenuClassifier(clock: clock),
        connectivity,
      );
      heard = <ClassifyingEngine>[];
      menu = _menuOf([_dishNamed('dish-1', 'Salmon')]);
    });

    test('classify with consent withheld announces only the rules', () async {
      // Arrange
      final options = ClassificationOptions(onEngineStarted: heard.add);

      // Act
      await router.classify(menu, options: options);

      // Assert
      expect(heard, equals([ClassifyingEngine.rules]));
      expect(client.requests, isEmpty);
    });

    test('classify with consent while offline announces only the rules — '
        'the pre-check skips the AI before it starts', () async {
      // Arrange
      connectivity.online = false;
      final options = ClassificationOptions(
        estimationConsentGiven: true,
        onEngineStarted: heard.add,
      );

      // Act
      await router.classify(menu, options: options);

      // Assert
      expect(heard, equals([ClassifyingEngine.rules]));
      expect(client.requests, isEmpty);
    });

    test('classify with consent and a successful AI call announces only '
        'the AI', () async {
      // Arrange: an empty dishes array is a reply the parser accepts.
      client.fallback = const ChatCompleted(
        content: '{"dishes": []}',
        model: 'served-model',
      );
      final options = ClassificationOptions(
        estimationConsentGiven: true,
        onEngineStarted: heard.add,
      );

      // Act
      await router.classify(menu, options: options);

      // Assert
      expect(heard, equals([ClassifyingEngine.llm]));
    });

    test('classify with consent and a failed AI call announces the AI and '
        'then the rules it fell back to', () async {
      // Arrange
      client.fallback = const ChatFailed(reason: ChatFailureReason.timeout);
      final options = ClassificationOptions(
        estimationConsentGiven: true,
        onEngineStarted: heard.add,
      );

      // Act
      final result = await router.classify(menu, options: options);

      // Assert
      expect(heard, equals([ClassifyingEngine.llm, ClassifyingEngine.rules]));
      expect(
        (result as MenuAnalysed).engine,
        equals(const RulesEngine(reason: MenuAnalysisFailureReason.timeout)),
      );
    });
  });
}

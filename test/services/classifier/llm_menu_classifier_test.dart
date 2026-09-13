import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/classifier/llm_menu_classifier.dart';
import 'package:ketoclub/services/classifier/menu_analysis_prompt.dart';
import 'package:ketoclub/services/classifier/menu_classifier.dart';
import 'package:ketoclub/services/llm/llm_chat_client.dart';

import '../../fakes/fake_clock.dart';
import '../../fakes/fake_llm_chat_client.dart';
import 'menu_classifier_contract.dart';

/// The venue every menu built by this file is addressed to.
const VenueRef _venueRef = VenueRef(
  source: MenuSource.wolt,
  platformId: 'llm-classifier-test-venue',
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

/// A gateway reply body naming one dish, valid against
/// [MenuAnalysisPrompt.responseSchema].
String _validReplyBody({
  required String dishId,
  required String dishName,
  String verdict = 'orderAsIs',
  String why = 'Lean protein with no carb sides.',
  String? modification,
}) => jsonEncode(<String, Object?>{
  'dishes': <Object?>[
    <String, Object?>{
      'id': dishId,
      'name': dishName,
      'verdict': verdict,
      'why': why,
      'modification': modification,
      'net_carbs_estimate': null,
    },
  ],
});

/// Builds an [LlmMenuClassifier] over a fresh [FakeLlmChatClient] that
/// always answers with an empty `dishes` array — a reply the parser
/// accepts for any menu (every source dish lands in `unclassified`,
/// never invented), which is all `menu_classifier_contract.dart` needs:
/// it only checks shape and provenance, never which verdict comes back.
LlmMenuClassifier _buildContractClassifier() => LlmMenuClassifier(
  FakeLlmChatClient()
    ..fallback = const ChatCompleted(
      content: '{"dishes":[]}',
      model: 'contract-model',
    ),
  FakeClock(DateTime.utc(2026)),
);

void main() {
  runMenuClassifierContract('LlmMenuClassifier', _buildContractClassifier);

  group('LlmMenuClassifier', () {
    test(
      'classify given a successful reply returns the parsed dishes',
      () async {
        // Arrange
        final client = FakeLlmChatClient()
          ..fallback = ChatCompleted(
            content: _validReplyBody(
              dishId: 'dish-1',
              dishName: 'Grilled Salmon',
              why: 'Lean protein, no carb sides.',
            ),
            model: 'served-model-x',
          );
        final classifier = LlmMenuClassifier(
          client,
          FakeClock(DateTime.utc(2026, 3)),
        );
        final menu = _menuOf([_dishNamed('dish-1', 'Grilled Salmon')]);

        // Act
        final result = await classifier.classify(menu);

        // Assert
        expect(result, isA<MenuAnalysed>());
        final analysed = result as MenuAnalysed;
        expect(analysed.dishes, hasLength(1));
        expect(analysed.dishes.single.dishId, 'dish-1');
        expect(analysed.dishes.single.verdict, DishVerdict.orderAsIs);
        expect(analysed.analysedAt, DateTime.utc(2026, 3));
      },
    );

    test('classify stamps the engine with the model the response carries, '
        'not the one requested', () async {
      // Arrange
      final client = FakeLlmChatClient()
        ..fallback = ChatCompleted(
          content: _validReplyBody(
            dishId: 'dish-1',
            dishName: 'Grilled Salmon',
          ),
          model: 'served-model-x',
        );
      final classifier = LlmMenuClassifier(
        client,
        FakeClock(DateTime.utc(2026)),
      );
      final menu = _menuOf([_dishNamed('dish-1', 'Grilled Salmon')]);

      // Act
      final result = await classifier.classify(menu);

      // Assert
      final analysed = result as MenuAnalysed;
      expect(analysed.engine, equals(const LlmEngine(model: 'served-model-x')));
    });

    test('classify sends the system prompt, the user prompt, the schema, and '
        'the schema name', () async {
      // Arrange
      final client = FakeLlmChatClient()
        ..fallback = ChatCompleted(
          content: _validReplyBody(dishId: 'dish-1', dishName: 'Salmon'),
          model: 'm',
        );
      final classifier = LlmMenuClassifier(
        client,
        FakeClock(DateTime.utc(2026)),
      );
      final menu = _menuOf([_dishNamed('dish-1', 'Salmon')]);
      const options = ClassificationOptions(
        estimationConsentGiven: true,
        dietaryConstraints: ['dairy-free'],
      );

      // Act
      await classifier.classify(menu, options: options);

      // Assert
      final recorded = client.requests.single;
      expect(
        recorded.systemPrompt,
        MenuAnalysisPrompt.systemPrompt(options: options),
      );
      expect(recorded.userPrompt, MenuAnalysisPrompt.userPrompt(menu));
      expect(
        recorded.responseSchema,
        equals(MenuAnalysisPrompt.responseSchema()),
      );
      expect(recorded.schemaName, MenuAnalysisPrompt.schemaName);
    });

    test(
      'classify sends exactly one request whatever the dish count',
      () async {
        // Arrange
        final client = FakeLlmChatClient()
          ..fallback = const ChatCompleted(
            content: '{"dishes":[]}',
            model: 'm',
          );
        final classifier = LlmMenuClassifier(
          client,
          FakeClock(DateTime.utc(2026)),
        );
        final menu = _menuOf([
          for (var i = 0; i < 12; i++) _dishNamed('dish-$i', 'Dish $i'),
        ]);

        // Act
        await classifier.classify(menu);

        // Assert
        expect(client.requests, hasLength(1));
      },
    );

    group('classify maps each ChatFailureReason to its own '
        'MenuAnalysisFailureReason', () {
      for (final chatReason in ChatFailureReason.values) {
        test('for ChatFailureReason.${chatReason.name}', () async {
          // Arrange
          final client = FakeLlmChatClient()
            ..enqueue(ChatFailed(reason: chatReason));
          final classifier = LlmMenuClassifier(
            client,
            FakeClock(DateTime.utc(2026)),
          );
          final menu = _menuOf([_dishNamed('dish-1', 'Salmon')]);

          // Act
          final result = await classifier.classify(menu);

          // Assert
          final expectedReason = switch (chatReason) {
            ChatFailureReason.offline => MenuAnalysisFailureReason.offline,
            ChatFailureReason.timeout => MenuAnalysisFailureReason.timeout,
            ChatFailureReason.rateLimited =>
              MenuAnalysisFailureReason.rateLimited,
            ChatFailureReason.unauthorised =>
              MenuAnalysisFailureReason.unauthorised,
            ChatFailureReason.badResponse =>
              MenuAnalysisFailureReason.badResponse,
          };
          expect(result, equals(MenuAnalysisFailed(reason: expectedReason)));
        });
      }
    });

    test('classify given a reply the parser rejects returns '
        'MenuAnalysisFailed(badResponse)', () async {
      // Arrange
      final client = FakeLlmChatClient()
        ..fallback = const ChatCompleted(
          content: 'this is not json',
          model: 'm',
        );
      final classifier = LlmMenuClassifier(
        client,
        FakeClock(DateTime.utc(2026)),
      );
      final menu = _menuOf([_dishNamed('dish-1', 'Salmon')]);

      // Act
      final result = await classifier.classify(menu);

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
  });
}

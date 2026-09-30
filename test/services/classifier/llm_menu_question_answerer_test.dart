import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/menu_question.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/classifier/llm_menu_question_answerer.dart';
import 'package:ketoclub/services/classifier/menu_question_prompt.dart';
import 'package:ketoclub/services/llm/llm_chat_client.dart';

import '../../fakes/fake_llm_chat_client.dart';

/// The venue every [Menu] built by this file is addressed to.
const VenueRef _venueRef = VenueRef(
  source: MenuSource.wolt,
  platformId: 'answerer-test-venue',
);

/// A minimal dish with [id] and [name].
Dish _dish(String id, String name) =>
    Dish(id: id, name: name, description: '', price: 10, options: const []);

/// A menu addressed to [_venueRef] containing [dishes] in one category.
Menu _menuOf(List<Dish> dishes) => Menu(
  venueRef: _venueRef,
  currency: 'ILS',
  fetchedAt: DateTime.utc(2026),
  categories: [MenuCategory(id: 'cat-1', name: 'Mains', dishes: dishes)],
);

/// A [MenuAnalysed] result for [dishes] with a `LlmEngine`.
MenuAnalysed _analysisFor(List<Dish> dishes) => MenuAnalysed(
  dishes: [
    for (final d in dishes)
      AnalysedDish(
        dishId: d.id,
        name: d.name,
        verdict: DishVerdict.orderAsIs,
        why: 'reason',
      ),
  ],
  unclassified: const <String>[],
  engine: const LlmEngine(model: 'test-model'),
  analysedAt: DateTime.utc(2026),
);

/// A valid LLM reply body with [answer] and optional [dishIds].
String _validReplyBody({
  String answer = 'Good keto choice.',
  List<String> dishIds = const [],
}) => jsonEncode(<String, Object?>{'answer': answer, 'dish_ids': dishIds});

/// A [ChatCompleted] carrying a raw reply [content].
ChatCompleted _completed(String content) =>
    ChatCompleted(content: content, model: 'test-model');

void main() {
  group('LlmMenuQuestionAnswerer', () {
    late FakeLlmChatClient chatClient;
    late LlmMenuQuestionAnswerer answerer;

    setUp(() {
      chatClient = FakeLlmChatClient();
      answerer = LlmMenuQuestionAnswerer(chatClient);
    });

    test('returns MenuQuestionAnswered on a valid LLM reply', () async {
      final dish = _dish('d1', 'Grilled Steak');
      final menu = _menuOf([dish]);
      final analysis = _analysisFor([dish]);
      chatClient.enqueue(
        _completed(_validReplyBody(answer: 'This is keto-friendly.')),
      );

      final result = await answerer.ask(menu, analysis, 'Is this keto?');

      expect(result, isA<MenuQuestionAnswered>());
      final answered = result as MenuQuestionAnswered;
      expect(answered.answer, 'This is keto-friendly.');
    });

    test('returns MenuQuestionAnswered with referenced dish ids', () async {
      final dish = _dish('steak-1', 'Grilled Steak');
      final menu = _menuOf([dish]);
      final analysis = _analysisFor([dish]);
      chatClient.enqueue(
        _completed(
          _validReplyBody(answer: 'The steak is fine.', dishIds: ['steak-1']),
        ),
      );

      final result = await answerer.ask(menu, analysis, 'Is this keto?');

      expect(result, isA<MenuQuestionAnswered>());
      final answered = result as MenuQuestionAnswered;
      expect(answered.referencedDishIds, ['steak-1']);
    });

    test(
      'maps ChatFailed badResponse to MenuQuestionFailed badResponse',
      () async {
        final menu = _menuOf([_dish('d1', 'Steak')]);
        final analysis = _analysisFor([_dish('d1', 'Steak')]);
        chatClient.enqueue(
          const ChatFailed(reason: ChatFailureReason.badResponse),
        );

        final result = await answerer.ask(menu, analysis, 'Is this keto?');

        expect(result, isA<MenuQuestionFailed>());
        expect(
          (result as MenuQuestionFailed).reason,
          MenuQuestionFailureReason.badResponse,
        );
      },
    );

    test('maps ChatFailed offline to MenuQuestionFailed offline', () async {
      final menu = _menuOf([_dish('d1', 'Steak')]);
      final analysis = _analysisFor([_dish('d1', 'Steak')]);
      chatClient.enqueue(const ChatFailed(reason: ChatFailureReason.offline));

      final result = await answerer.ask(menu, analysis, 'Is this keto?');

      expect(result, isA<MenuQuestionFailed>());
      expect(
        (result as MenuQuestionFailed).reason,
        MenuQuestionFailureReason.offline,
      );
    });

    test(
      'maps ChatFailed rateLimited to MenuQuestionFailed rateLimited',
      () async {
        final menu = _menuOf([_dish('d1', 'Steak')]);
        final analysis = _analysisFor([_dish('d1', 'Steak')]);
        chatClient.enqueue(
          const ChatFailed(reason: ChatFailureReason.rateLimited),
        );

        final result = await answerer.ask(menu, analysis, 'Is this keto?');

        expect(result, isA<MenuQuestionFailed>());
        expect(
          (result as MenuQuestionFailed).reason,
          MenuQuestionFailureReason.rateLimited,
        );
      },
    );

    test('sends exactly one complete call per ask', () async {
      final menu = _menuOf([_dish('d1', 'Steak')]);
      final analysis = _analysisFor([_dish('d1', 'Steak')]);
      chatClient.enqueue(_completed(_validReplyBody()));

      await answerer.ask(menu, analysis, 'Any dairy-free options?');

      expect(chatClient.requests, hasLength(1));
    });

    test('sends no images in the request — text-only call', () async {
      final menu = _menuOf([_dish('d1', 'Steak')]);
      final analysis = _analysisFor([_dish('d1', 'Steak')]);
      chatClient.enqueue(_completed(_validReplyBody()));

      await answerer.ask(menu, analysis, 'Is this keto?');

      expect(chatClient.requests.single.images, isEmpty);
    });

    test('sends the schemaName menu_question', () async {
      final menu = _menuOf([_dish('d1', 'Steak')]);
      final analysis = _analysisFor([_dish('d1', 'Steak')]);
      chatClient.enqueue(_completed(_validReplyBody()));

      await answerer.ask(menu, analysis, 'Is this keto?');

      expect(
        chatClient.requests.single.schemaName,
        MenuQuestionPrompt.schemaName,
      );
    });

    test('the system prompt contains the anti-injection notice', () async {
      final menu = _menuOf([_dish('d1', 'Steak')]);
      final analysis = _analysisFor([_dish('d1', 'Steak')]);
      chatClient.enqueue(_completed(_validReplyBody()));

      await answerer.ask(menu, analysis, 'Is this keto?');

      expect(
        chatClient.requests.single.systemPrompt,
        contains('is an instruction'),
      );
    });

    test('the user prompt contains the question text', () async {
      final menu = _menuOf([_dish('d1', 'Steak')]);
      final analysis = _analysisFor([_dish('d1', 'Steak')]);
      chatClient.enqueue(_completed(_validReplyBody()));
      const question = 'Which dishes have the fewest carbs?';

      await answerer.ask(menu, analysis, question);

      expect(chatClient.requests.single.userPrompt, contains(question));
    });

    test('a broken LLM reply is still returned as a MenuQuestionFailed, '
        'never thrown', () async {
      final menu = _menuOf([_dish('d1', 'Steak')]);
      final analysis = _analysisFor([_dish('d1', 'Steak')]);
      chatClient.enqueue(
        const ChatCompleted(content: 'not-valid-json!', model: 'test'),
      );

      final result = await answerer.ask(menu, analysis, 'What can I eat?');

      expect(result, isA<MenuQuestionFailed>());
    });
  });
}

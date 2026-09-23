import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/classifier/llm_menu_classifier.dart';
import 'package:ketoclub/services/classifier/menu_analysis_prompt.dart';
import 'package:ketoclub/services/classifier/menu_classifier.dart';
import 'package:ketoclub/services/llm/backend_chat_client.dart';
import 'package:ketoclub/services/llm/llm_chat_client.dart';

import '../../fakes/fake_clock.dart';
import '../../fakes/fake_install_id_store.dart';
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
  double? netCarbsEstimate,
}) => jsonEncode(<String, Object?>{
  'dishes': <Object?>[
    <String, Object?>{
      'id': dishId,
      'name': dishName,
      'verdict': verdict,
      'why': why,
      'modification': modification,
      'net_carbs_estimate': netCarbsEstimate,
    },
  ],
});

/// The exact `system_prompt` a 9 g limit produces (issue #57's golden):
/// the role preamble, the verdict definitions and keto rules with 9 in
/// place of the default 6, then the output rules. Typed out in full,
/// never rebuilt from the constants it tests, so a change to any of that
/// text has to be made here too, on purpose.
const String _goldenSystemPromptAt9g = '''
You are the keto-diet menu analyst for KetoClub. Classify every dish in the user message into exactly one of three verdicts.

orderAsIs — net carbohydrates 9g or less, a healthy fat-and-protein base, and no starchy side, sugary sauce, or flour coating: order it exactly as printed.
modifiable — the core protein, fish, egg, or salad is keto-compliant, but the dish arrives with a starchy side (fries, mash, rice, bread), a root vegetable (carrot, beet, corn), or a sugary sauce or glaze (teriyaki, honey, barbecue): order it with the stated substitution or removal.
nonKeto — the dish is built on a high-carbohydrate foundation no substitution can fix, such as pasta, pizza crust, a rice bowl, noodles, a breaded or battered protein, or a pastry or dessert base: skip it.

Net carbs of 9g or less per dish make it green (orderAsIs).
Starchy sides, root vegetables, sugary sauces and glazes, breading, and bread that only carries the dish (a bun, pita, toast) make an otherwise-compliant dish yellow (modifiable): name the exact component to remove and the exact substitute to ask for.
Pasta, pizza, rice bowls, noodles, breaded or battered proteins, and pastry make a dish red (nonKeto), even with modifications, and get no modification text.
Write "why" and "modification" in the language the menu is written in, each under 300 characters. Return only dishes present in the input, using their given id and exact printed name.

Every "modifiable" dish must carry a non-empty "modification" naming the exact component to remove and the exact substitute to ask for. A dish with no compliant path is "nonKeto" and must not carry a "modification".
Respond with JSON matching the supplied schema and nothing else: no markdown fence, no heading, no commentary before or after the JSON object.''';

/// The dietary-constraints section the "Strict seed-oil free" toggle
/// alone appends after the default prompt (issue #56's golden): a blank
/// line, the section preamble, then the toggle's fragment as one `- `
/// line. Typed out in full for the same reason as
/// [_goldenSystemPromptAt9g].
const String _goldenSeedOilFreeSection = '''


The user has these additional dietary constraints. A dish that violates one is not orderAsIs even if it otherwise would be — mark it modifiable or nonKeto, whichever fits:
- Strict seed-oil free: the user avoids industrial seed oils (canola, rapeseed, soybean, sunflower, corn, cottonseed and generic vegetable oil). A dish that is fried, deep-fried or cooked in one of them is modifiable, with a modification asking for it to be cooked in olive oil, butter or tallow instead, unless it is already nonKeto.''';

/// The section the "Dairy-free keto" toggle alone appends (issue #56).
const String _goldenDairyFreeSection = '''


The user has these additional dietary constraints. A dish that violates one is not orderAsIs even if it otherwise would be — mark it modifiable or nonKeto, whichever fits:
- Dairy-free keto: the user eats no dairy. A dish containing cheese, cream, butter, milk or yogurt is modifiable, with a modification asking for it without the dairy component, unless it is already nonKeto.''';

/// The section the "Carnivore only" toggle alone appends (issue #56).
const String _goldenCarnivoreOnlySection = '''


The user has these additional dietary constraints. A dish that violates one is not orderAsIs even if it otherwise would be — mark it modifiable or nonKeto, whichever fits:
- Carnivore only: the user eats only animal foods (meat, fish, seafood, eggs and animal fats). A dish that includes any vegetable, salad, fruit, legume, herb garnish or other plant is modifiable, with a modification asking for only the meat, fish or eggs, with no plants, unless it is already nonKeto.''';

/// The section all three toggles together append (issue #56): one line
/// each, always seed-oil, dairy, carnivore.
const String _goldenAllTogglesSection = '''


The user has these additional dietary constraints. A dish that violates one is not orderAsIs even if it otherwise would be — mark it modifiable or nonKeto, whichever fits:
- Strict seed-oil free: the user avoids industrial seed oils (canola, rapeseed, soybean, sunflower, corn, cottonseed and generic vegetable oil). A dish that is fried, deep-fried or cooked in one of them is modifiable, with a modification asking for it to be cooked in olive oil, butter or tallow instead, unless it is already nonKeto.
- Dairy-free keto: the user eats no dairy. A dish containing cheese, cream, butter, milk or yogurt is modifiable, with a modification asking for it without the dairy component, unless it is already nonKeto.
- Carnivore only: the user eats only animal foods (meat, fish, seafood, eggs and animal fats). A dish that includes any vegetable, salad, fruit, legume, herb garnish or other plant is modifiable, with a modification asking for only the meat, fish or eggs, with no plants, unless it is already nonKeto.''';

/// [_goldenSystemPromptAt9g] at the default 6 g limit: only its two limit
/// figures changed back, exactly as issue #57's default-limit test does.
final String _goldenSystemPromptAt6g = _goldenSystemPromptAt9g
    .replaceAll('net carbohydrates 9g', 'net carbohydrates 6g')
    .replaceAll('Net carbs of 9g', 'Net carbs of 6g');

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
            ChatFailureReason.notConfigured =>
              MenuAnalysisFailureReason.notConfigured,
            ChatFailureReason.offline => MenuAnalysisFailureReason.offline,
            ChatFailureReason.timeout => MenuAnalysisFailureReason.timeout,
            ChatFailureReason.rateLimited =>
              MenuAnalysisFailureReason.rateLimited,
            ChatFailureReason.badResponse =>
              MenuAnalysisFailureReason.badResponse,
            ChatFailureReason.backendUnreachable =>
              MenuAnalysisFailureReason.backendUnreachable,
          };
          expect(result, equals(MenuAnalysisFailed(reason: expectedReason)));
        });
      }
    });

    test('classify records the options it was given on a placed '
        'result', () async {
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
      const options = ClassificationOptions(
        estimationConsentGiven: true,
        netCarbLimitGrams: 14,
        dietaryConstraints: ['dairy-free'],
      );

      // Act
      final result = await classifier.classify(
        _menuOf([_dishNamed('dish-1', 'Salmon')]),
        options: options,
      );

      // Assert
      expect(
        (result as MenuAnalysed).options,
        equals(
          const AnalysisOptionsSnapshot(
            netCarbLimitGrams: 14,
            dietaryConstraints: ['dairy-free'],
          ),
        ),
      );
    });

    test('classify holds a green to the limit it was given: 8 g is over '
        'the default 6 g but within a 10 g limit', () async {
      // Arrange: the same green reply, estimated at 8 g, with a usable
      // instruction, classified under the default limit and under 10 g.
      ChatResult reply() => ChatCompleted(
        content: _validReplyBody(
          dishId: 'dish-1',
          dishName: 'Salmon',
          modification: 'Ask for the glaze on the side.',
          netCarbsEstimate: 8,
        ),
        model: 'm',
      );
      final client = FakeLlmChatClient()
        ..enqueue(reply())
        ..enqueue(reply());
      final classifier = LlmMenuClassifier(
        client,
        FakeClock(DateTime.utc(2026)),
      );
      final menu = _menuOf([_dishNamed('dish-1', 'Salmon')]);

      // Act
      final atDefault = await classifier.classify(menu);
      final atTen = await classifier.classify(
        menu,
        options: const ClassificationOptions(netCarbLimitGrams: 10),
      );

      // Assert
      final defaultDish = (atDefault as MenuAnalysed).dishes.single;
      expect(defaultDish.verdict, DishVerdict.modifiable);
      expect(defaultDish.modification, 'Ask for the glaze on the side.');
      final tenDish = (atTen as MenuAnalysed).dishes.single;
      expect(tenDish.verdict, DishVerdict.orderAsIs);
      expect(tenDish.modification, isNull);
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

  group('LlmMenuClassifier over BackendChatClient (issue #57 golden)', () {
    test(
      'a non-default limit posts exactly the golden system_prompt',
      () async {
        // Arrange: the real transport client over a mock HTTP client, so
        // the assertion is on the JSON body that actually leaves the app.
        Map<String, Object?>? posted;
        final chat = BackendChatClient(
          client: MockClient((request) async {
            posted = jsonDecode(request.body) as Map<String, Object?>;
            return http.Response(
              jsonEncode(<String, Object?>{
                'content': '{"dishes":[]}',
                'model': 'served-model',
              }),
              200,
            );
          }),
          baseUrl: Uri.parse('https://api.ketoclub.test'),
          installIdStore: FakeInstallIdStore(),
        );
        final classifier = LlmMenuClassifier(
          chat,
          FakeClock(DateTime.utc(2026)),
        );

        // Act
        await classifier.classify(
          _menuOf([_dishNamed('dish-1', 'Salmon')]),
          options: const ClassificationOptions(
            estimationConsentGiven: true,
            netCarbLimitGrams: 9,
          ),
        );

        // Assert
        expect(posted, isNotNull);
        expect(posted!['system_prompt'], equals(_goldenSystemPromptAt9g));
      },
    );

    test('the default limit posts the same prompt with 6g, byte for byte, '
        'as before the limit became a setting', () async {
      // Arrange
      Map<String, Object?>? posted;
      final chat = BackendChatClient(
        client: MockClient((request) async {
          posted = jsonDecode(request.body) as Map<String, Object?>;
          return http.Response(
            jsonEncode(<String, Object?>{
              'content': '{"dishes":[]}',
              'model': 'served-model',
            }),
            200,
          );
        }),
        baseUrl: Uri.parse('https://api.ketoclub.test'),
        installIdStore: FakeInstallIdStore(),
      );
      final classifier = LlmMenuClassifier(chat, FakeClock(DateTime.utc(2026)));

      // Act
      await classifier.classify(_menuOf([_dishNamed('dish-1', 'Salmon')]));

      // Assert: the golden with only its two limit figures changed back.
      expect(
        posted!['system_prompt'],
        equals(
          _goldenSystemPromptAt9g
              .replaceAll('net carbohydrates 9g', 'net carbohydrates 6g')
              .replaceAll('Net carbs of 9g', 'Net carbs of 6g'),
        ),
      );
    });
  });

  group('LlmMenuClassifier over BackendChatClient (issue #56 goldens)', () {
    /// Classifies a one-dish menu under [options] through the real
    /// transport client over a mock HTTP client, and returns the
    /// `system_prompt` it posted.
    Future<Object?> postedSystemPrompt(ClassificationOptions options) async {
      Map<String, Object?>? posted;
      final chat = BackendChatClient(
        client: MockClient((request) async {
          posted = jsonDecode(request.body) as Map<String, Object?>;
          return http.Response(
            jsonEncode(<String, Object?>{
              'content': '{"dishes":[]}',
              'model': 'served-model',
            }),
            200,
          );
        }),
        baseUrl: Uri.parse('https://api.ketoclub.test'),
        installIdStore: FakeInstallIdStore(),
      );
      final classifier = LlmMenuClassifier(chat, FakeClock(DateTime.utc(2026)));
      await classifier.classify(
        _menuOf([_dishNamed('dish-1', 'Salmon')]),
        options: options,
      );
      expect(posted, isNotNull);
      return posted!['system_prompt'];
    }

    /// The options MenuController builds for these toggles, with consent
    /// given.
    ClassificationOptions toggles({
      bool seedOilFree = false,
      bool dairyFree = false,
      bool carnivoreOnly = false,
    }) => ClassificationOptions(
      estimationConsentGiven: true,
      dietaryConstraints: ClassificationOptions.dietaryConstraintsFor(
        seedOilFree: seedOilFree,
        dairyFree: dairyFree,
        carnivoreOnly: carnivoreOnly,
      ),
    );

    test('every toggle off posts the default prompt byte for byte', () async {
      // Act
      final prompt = await postedSystemPrompt(toggles());

      // Assert
      expect(prompt, equals(_goldenSystemPromptAt6g));
    });

    test('seed-oil free posts exactly the golden system_prompt', () async {
      // Act
      final prompt = await postedSystemPrompt(toggles(seedOilFree: true));

      // Assert
      expect(
        prompt,
        equals(_goldenSystemPromptAt6g + _goldenSeedOilFreeSection),
      );
    });

    test('dairy-free posts exactly the golden system_prompt', () async {
      // Act
      final prompt = await postedSystemPrompt(toggles(dairyFree: true));

      // Assert
      expect(prompt, equals(_goldenSystemPromptAt6g + _goldenDairyFreeSection));
    });

    test('carnivore only posts exactly the golden system_prompt', () async {
      // Act
      final prompt = await postedSystemPrompt(toggles(carnivoreOnly: true));

      // Assert
      expect(
        prompt,
        equals(_goldenSystemPromptAt6g + _goldenCarnivoreOnlySection),
      );
    });

    test('all three toggles post exactly the golden system_prompt, in the '
        'fixed order', () async {
      // Act
      final prompt = await postedSystemPrompt(
        toggles(seedOilFree: true, dairyFree: true, carnivoreOnly: true),
      );

      // Assert
      expect(
        prompt,
        equals(_goldenSystemPromptAt6g + _goldenAllTogglesSection),
      );
    });
  });
}

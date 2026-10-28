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
import 'package:ketoclub/services/classifier/menu_response_parser.dart';
import 'package:ketoclub/services/llm/backend_chat_client.dart';
import 'package:ketoclub/services/llm/llm_chat_client.dart';
import 'package:ketoclub/utils/constants.dart';

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
Drinks: cola, sprite, juice, lemonade, beer, sweet wine, and liqueur are red; iced coffee, latte, cappuccino, and tonic are yellow (ask for black coffee, unsweetened almond milk, or soda water instead); zero-sugar or diet versions of soda or beer, plain water, black coffee, espresso, tea, dry wine, and spirits are green.
Write "why" and "modification" in the language the menu is written in, each under 300 characters. Return only dishes present in the input, using their given id and exact printed name.
Hidden carbs: breading crumbs, sweet marinades, house dressings, thickeners and glazes often contain sugar, honey, flour or cornstarch even when the dish name reads clean. For each dish, list any such suspected or confirmed hidden carb under "hidden_carbs" as {source, certainty ("suspected" or "likely"), waiter_question} — the question to ask the waiter, in the menu's language, under 300 characters. Use an empty array when none apply.

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

/// [count] dishes `d0..d{count-1}` named `Dish number i`, 30 a category.
Menu _largeMenu(int count) => Menu(
  venueRef: _venueRef,
  currency: 'ILS',
  fetchedAt: DateTime.utc(2026),
  categories: [
    for (var start = 0; start < count; start += 30)
      MenuCategory(
        id: 'cat-$start',
        name: 'Aisle $start',
        dishes: [
          for (var i = start; i < count && i < start + 30; i++)
            _dishNamed('d$i', 'Dish number $i'),
        ],
      ),
  ],
);

/// An [LlmChatClient] that places every dish its user prompt names as
/// order-as-is, unless [failures] scripts the n-th call (from 1), and
/// records every user prompt it was sent (issue #188). It answers after a
/// turn of the event loop and counts how many calls were out at once.
final class _PromptAnsweringChatClient implements LlmChatClient {
  /// Creates a client answering the calls [failures] names with them.
  new([this.failures = const <int, ChatResult>{}]);

  /// The answer to the n-th call, by n, instead of the placed reply.
  final Map<int, ChatResult> failures;

  /// Every user prompt received, in call order.
  final List<String> userPrompts = <String>[];

  /// Every response schema received, in call order.
  final List<Map<String, Object?>?> schemas = <Map<String, Object?>?>[];

  /// The most calls awaiting an answer at one time.
  int maxInFlight = 0;

  int _inFlight = 0;

  @override
  Future<ChatResult> complete({
    required String systemPrompt,
    required String userPrompt,
    Map<String, Object?>? responseSchema,
    String? schemaName,
    List<ChatImagePart> images = const <ChatImagePart>[],
  }) async {
    userPrompts.add(userPrompt);
    schemas.add(responseSchema);
    final call = userPrompts.length;
    _inFlight++;
    if (_inFlight > maxInFlight) maxInFlight = _inFlight;
    await Future<void>.delayed(Duration.zero);
    _inFlight--;
    final scripted = failures[call];
    if (scripted != null) return scripted;
    final dishes = <Object?>[
      for (final line in userPrompt.split('\n'))
        <String, Object?>{
          'id': line.split(' | ')[0],
          'name': line.split(' | ')[2],
          'verdict': 'orderAsIs',
          'why': 'Plain protein.',
          'modification': null,
          'net_carbs_estimate': 1,
          'hidden_carbs': <Object?>[],
        },
    ];
    return ChatCompleted(
      content: jsonEncode(<String, Object?>{'dishes': dishes}),
      model: 'batch-model-$call',
    );
  }
}

/// The names of [menu]'s dishes, in order.
List<String> _namesOf(Menu menu) => [
  for (final dish in menu.allDishes) dish.name,
];

/// A classifier over [client] on a fixed clock.
LlmMenuClassifier _over(LlmChatClient client) =>
    LlmMenuClassifier(client, FakeClock(DateTime.utc(2026)));

void main() {
  runMenuClassifierContract('LlmMenuClassifier', _buildContractClassifier);

  group('LlmMenuClassifier', () {
    test('with restrictionsRequested, asks for and reads ingredients '
        '(ALG-03)', () async {
      // Arrange
      final reply = jsonEncode(<String, Object?>{
        'dishes': <Object?>[
          <String, Object?>{
            'id': 'dish-1',
            'name': 'Salmon',
            'verdict': 'orderAsIs',
            'why': 'Fish.',
            'modification': null,
            'net_carbs_estimate': null,
            'hidden_carbs': <Object?>[],
            'ingredients': <Object?>[
              <String, Object?>{
                'name': 'salmon',
                'certainty': 'stated',
                'role': 'protein',
              },
            ],
          },
        ],
      });
      final client = FakeLlmChatClient()
        ..fallback = ChatCompleted(content: reply, model: 'm');
      final classifier = LlmMenuClassifier(
        client,
        FakeClock(DateTime.utc(2026)),
      );
      final menu = _menuOf([_dishNamed('dish-1', 'Salmon')]);
      const options = ClassificationOptions(restrictionsRequested: true);

      // Act
      final result = await classifier.classify(menu, options: options);

      // Assert
      final recorded = client.requests.single;
      expect(
        recorded.systemPrompt,
        MenuAnalysisPrompt.systemPrompt(options: options),
      );
      expect(
        recorded.responseSchema,
        MenuAnalysisPrompt.responseSchema(extract: true),
      );
      final analysed = result as MenuAnalysed;
      expect(analysed.dishes.single.ingredients.single.name, 'salmon');
      expect(analysed.options!.restrictionsRequested, isTrue);
    });

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
      'classify sends exactly one request for a menu within one batch',
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
            ChatFailureReason.apiKeyMissing =>
              MenuAnalysisFailureReason.apiKeyMissing,
            ChatFailureReason.apiKeyRejected =>
              MenuAnalysisFailureReason.apiKeyRejected,
          };
          expect(result, equals(MenuAnalysisFailed(reason: expectedReason)));
        });
      }
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

  group('LlmMenuClassifier on a menu larger than one batch (issue #188)', () {
    final menu = _largeMenu(200);
    final batches = MenuAnalysisPrompt.batches(
      menu,
      maxDishes: llmBatchMaxDishes,
    );

    test('sends one request per batch, one at a time, in order, and merges '
        'them', () async {
      // Arrange
      final client = _PromptAnsweringChatClient();
      const options = ClassificationOptions(netCarbLimitGrams: 9);

      // Act
      final result = await _over(client).classify(menu, options: options);

      // Assert: three requests, each its batch's prompt, never two at once.
      expect(batches, hasLength(3));
      expect(client.userPrompts, [
        for (final batch in batches) MenuAnalysisPrompt.userPrompt(batch),
      ]);
      expect(client.maxInFlight, 1);
      final analysed = result as MenuAnalysed;
      expect(
        [for (final dish in analysed.dishes) dish.dishId],
        [for (final dish in menu.allDishes) dish.id],
      );
      expect(analysed.unclassified, isEmpty);
      // The first answering batch names the model.
      expect(analysed.engine, const LlmEngine(model: 'batch-model-1'));
      expect(analysed.options, options.snapshot);
      expect(analysed.schemaVersion, MenuResponseParser.schemaVersion);
      expect(analysed.analysedAt, DateTime.utc(2026));
    });

    final ownFailures = <String, ChatResult>{
      'a badResponse': const ChatFailed(reason: ChatFailureReason.badResponse),
      'a timeout': const ChatFailed(reason: ChatFailureReason.timeout),
      'a reply the parser rejects': const ChatCompleted(
        content: 'not json',
        model: 'm',
      ),
    };
    for (final MapEntry(key: label, value: failure) in ownFailures.entries) {
      test('one failed batch of three ($label) puts only its dishes under '
          'unclassified, and the third is still sent', () async {
        // Arrange
        final client = _PromptAnsweringChatClient({2: failure});

        // Act
        final result = await _over(client).classify(menu);

        // Assert
        expect(client.userPrompts, hasLength(3));
        final analysed = result as MenuAnalysed;
        expect(
          [for (final dish in analysed.dishes) dish.dishId],
          [
            for (final dish in batches[0].allDishes) dish.id,
            for (final dish in batches[2].allDishes) dish.id,
          ],
        );
        expect(analysed.unclassified, _namesOf(batches[1]));
        expect(analysed.engine, const LlmEngine(model: 'batch-model-1'));
      });
    }

    test(
      'a first batch failing on its own lets the next name the model',
      () async {
        // Arrange
        final client = _PromptAnsweringChatClient({
          1: const ChatFailed(reason: ChatFailureReason.timeout),
        });

        // Act
        final result = await _over(client).classify(menu);

        // Assert
        final analysed = result as MenuAnalysed;
        expect(analysed.engine, const LlmEngine(model: 'batch-model-2'));
        expect(analysed.unclassified, _namesOf(batches[0]));
      },
    );

    test(
      'every batch failing is the menu failing, with the first reason',
      () async {
        // Arrange
        final client = _PromptAnsweringChatClient({
          1: const ChatFailed(reason: ChatFailureReason.timeout),
          2: const ChatFailed(reason: ChatFailureReason.badResponse),
          3: const ChatCompleted(content: 'not json', model: 'm'),
        });

        // Act
        final result = await _over(client).classify(menu);

        // Assert
        expect(
          result,
          const MenuAnalysisFailed(reason: MenuAnalysisFailureReason.timeout),
        );
      },
    );

    const menuWide = <ChatFailureReason>[
      ChatFailureReason.rateLimited,
      ChatFailureReason.offline,
      ChatFailureReason.backendUnreachable,
      ChatFailureReason.notConfigured,
      ChatFailureReason.apiKeyMissing,
      ChatFailureReason.apiKeyRejected,
    ];
    for (final reason in menuWide) {
      test(
        '${reason.name} mid-menu stops the menu and is its failure',
        () async {
          // Arrange
          final client = _PromptAnsweringChatClient({
            2: ChatFailed(reason: reason),
          });

          // Act
          final result = await _over(client).classify(menu);

          // Assert: the third batch is never sent, and the router will
          // answer with the rules stamped with this reason.
          expect(client.userPrompts, hasLength(2));
          expect(
            result,
            MenuAnalysisFailed(reason: menuFailureReasonFor(reason)),
          );
        },
      );
    }

    test('with restrictionsRequested, batches are the smaller extraction '
        'size and ask for ingredients', () async {
      // Arrange
      final client = _PromptAnsweringChatClient();
      const options = ClassificationOptions(restrictionsRequested: true);

      // Act
      final result = await _over(client).classify(menu, options: options);

      // Assert: 200 dishes under a ceiling of 35 are 6 batches.
      expect(client.userPrompts, hasLength(6));
      for (final prompt in client.userPrompts) {
        expect(
          prompt.split('\n').length,
          lessThanOrEqualTo(llmBatchMaxDishesWithExtraction),
        );
      }
      expect(
        client.schemas,
        everyElement(MenuAnalysisPrompt.responseSchema(extract: true)),
      );
      expect((result as MenuAnalysed).dishes, hasLength(200));
    });

    test(
      'a menu of exactly the ceiling is one request of the whole prompt',
      () async {
        // Arrange
        final fits = _largeMenu(llmBatchMaxDishes);
        final client = _PromptAnsweringChatClient();

        // Act
        await _over(client).classify(fits);

        // Assert
        expect(client.userPrompts, [MenuAnalysisPrompt.userPrompt(fits)]);
      },
    );

    test('each batch numbers its dishes from 1, and the merge maps every '
        'reply id back to its own dish, even when every name is one', () async {
      // Arrange: 200 dishes of one name, so no name can place a dish.
      final menu = Menu(
        venueRef: _venueRef,
        currency: 'ILS',
        fetchedAt: DateTime.utc(2026),
        categories: [
          MenuCategory(
            id: 'cat',
            name: 'Burgers',
            dishes: [
              for (var i = 0; i < 200; i++) _dishNamed('wolt-$i', 'Burger'),
            ],
          ),
        ],
      );
      final client = _PromptAnsweringChatClient();

      // Act
      final result = await _over(client).classify(menu);

      // Assert
      expect(client.userPrompts, hasLength(3));
      for (final prompt in client.userPrompts) {
        expect(prompt.split('\n').first, startsWith('1 | Burgers | Burger'));
        expect(prompt, isNot(contains('wolt-')));
      }
      final analysed = result as MenuAnalysed;
      expect(
        [for (final dish in analysed.dishes) dish.dishId],
        [for (final dish in menu.allDishes) dish.id],
      );
      expect(analysed.unclassified, isEmpty);
    });
  });

  group('LlmMenuClassifier reads reply ids through the prompt ids', () {
    const burgerA = Dish(
      id: '65b0c1f2a3d4e5f60718293a',
      name: 'סמאשבורגר',
      description: '',
      price: 52,
      options: [],
    );
    const burgerB = Dish(
      id: '65b0c1f2a3d4e5f60718293b',
      name: 'סמאשבורגר',
      description: 'כפול',
      price: 64,
      options: [],
    );
    final menu = _menuOf([burgerA, burgerB]);

    Map<String, Object?> element(String id, String name, String verdict) =>
        <String, Object?>{
          'id': id,
          'name': name,
          'verdict': verdict,
          'why': 'סיבה.',
          'modification': verdict == 'modifiable' ? 'בלי לחמנייה.' : null,
          'net_carbs_estimate': null,
          'hidden_carbs': <Object?>[],
        };

    Future<MenuAnalysed> classifyReplying(List<Object?> elements) async {
      final client = FakeLlmChatClient()
        ..enqueue(
          ChatCompleted(
            content: jsonEncode(<String, Object?>{'dishes': elements}),
            model: 'm',
          ),
        );
      final result = await _over(client).classify(menu);
      expect(
        client.requests.single.userPrompt,
        '1 | Mains | סמאשבורגר |  | \n2 | Mains | סמאשבורגר | כפול | ',
      );
      return result as MenuAnalysed;
    }

    test('two dishes of one name each get their own verdict, even under a '
        'name the model reworded', () async {
      // Act
      final analysed = await classifyReplying([
        element('1', 'ספיישל סמאשבורגר 🌟', 'modifiable'),
        element('2', 'סמאשבורגר', 'nonKeto'),
      ]);

      // Assert
      expect(
        [for (final d in analysed.dishes) (d.dishId, d.verdict)],
        [
          (burgerA.id, DishVerdict.modifiable),
          (burgerB.id, DishVerdict.nonKeto),
        ],
      );
      expect(analysed.dishes.first.name, 'סמאשבורגר');
      expect(analysed.unclassified, isEmpty);
    });

    test('a reply echoing the full platform ids still places both', () async {
      // Act
      final analysed = await classifyReplying([
        element(burgerB.id, 'סמאשבורגר', 'nonKeto'),
        element(burgerA.id, 'סמאשבורגר', 'orderAsIs'),
      ]);

      // Assert
      expect(
        [for (final d in analysed.dishes) (d.dishId, d.verdict)],
        [
          (burgerB.id, DishVerdict.nonKeto),
          (burgerA.id, DishVerdict.orderAsIs),
        ],
      );
      expect(analysed.unclassified, isEmpty);
    });

    test('16-character prefixes, as the recorded reply sent, fall to the '
        'names: the first namesake is placed and the second lost, as '
        'before', () async {
      // Act
      final analysed = await classifyReplying([
        element('65b0c1f2a3d4e5f6', 'סמאשבורגר', 'modifiable'),
        element('65b0c1f2a3d4e5f6', 'סמאשבורגר', 'nonKeto'),
      ]);

      // Assert
      expect(
        [for (final d in analysed.dishes) (d.dishId, d.verdict)],
        [(burgerA.id, DishVerdict.modifiable)],
      );
      expect(analysed.unclassified, ['סמאשבורגר']);
    });
  });
}

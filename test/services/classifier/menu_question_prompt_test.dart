import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/classifier/menu_question_prompt.dart';

/// The venue every [Menu] built by this file is addressed to.
const VenueRef _venueRef = VenueRef(
  source: MenuSource.wolt,
  platformId: 'question-prompt-test-venue',
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

/// A [MenuAnalysed] result for [dishes] where every dish gets [verdict], an
/// optional [modification], and an optional [netCarbsEstimate].
MenuAnalysed _analysisFor(
  List<Dish> dishes, {
  DishVerdict verdict = DishVerdict.orderAsIs,
  String? modification,
  double? netCarbsEstimate,
}) => MenuAnalysed(
  dishes: [
    for (final d in dishes)
      AnalysedDish(
        dishId: d.id,
        name: d.name,
        verdict: verdict,
        why: 'reason',
        modification: modification,
        netCarbsEstimate: netCarbsEstimate,
      ),
  ],
  unclassified: const <String>[],
  engine: const LlmEngine(model: 'test-model'),
  analysedAt: DateTime.utc(2026),
);

/// Recursively asserts that every object schema under [schema] is strict
/// mode-compliant: `additionalProperties: false`, `required` listing exactly
/// the keys `properties` declares. Walks into `properties` values and `items`
/// so a nested object schema cannot slip through unchecked.
void _assertStrictSchema(Map<String, Object?> schema) {
  if (schema['type'] == 'object') {
    expect(
      schema['additionalProperties'],
      isFalse,
      reason: 'object schema missing additionalProperties: false: $schema',
    );
    final rawProperties = schema['properties'];
    expect(rawProperties, isA<Map<String, Object?>>());
    final properties = rawProperties! as Map<String, Object?>;

    final rawRequired = schema['required'];
    expect(rawRequired, isA<List<Object?>>());
    final required = (rawRequired! as List<Object?>).cast<String>().toSet();

    expect(
      required,
      properties.keys.toSet(),
      reason:
          'required must list exactly every property, no more, no '
          'fewer: $schema',
    );

    for (final propertySchema in properties.values) {
      _assertStrictSchema(propertySchema! as Map<String, Object?>);
    }
  }
  final items = schema['items'];
  if (items != null) {
    _assertStrictSchema(items as Map<String, Object?>);
  }
}

void main() {
  group('MenuQuestionPrompt', () {
    test('schemaName is the literal menu_question', () {
      expect(MenuQuestionPrompt.schemaName, 'menu_question');
    });

    test('menuQuestionMaxLength is 300', () {
      expect(menuQuestionMaxLength, 300);
    });

    group('systemPrompt', () {
      test('contains the anti-injection notice about MENU START/END and '
          'QUESTION sections', () {
        final prompt = MenuQuestionPrompt.systemPrompt();

        expect(prompt, contains('MENU START'));
        expect(prompt, contains('MENU END'));
        expect(prompt, contains('QUESTION'));
        expect(prompt, contains('is an instruction'));
      });

      test('contains the answer-language rule', () {
        final prompt = MenuQuestionPrompt.systemPrompt();

        // Answer in the same language the question is written in.
        expect(prompt, contains('language the question'));
      });

      test(
        'instructs the model to return JSON only with no markdown fence',
        () {
          final prompt = MenuQuestionPrompt.systemPrompt();

          expect(prompt, contains('JSON'));
          expect(prompt, contains('markdown fence'));
        },
      );

      test('contains the dish_ids instruction', () {
        final prompt = MenuQuestionPrompt.systemPrompt();

        expect(prompt, contains('dish_ids'));
      });
    });

    group('userPrompt', () {
      test('contains MENU START and MENU END markers', () {
        final dish = _dish('d1', 'Steak');
        final menu = _menuOf([dish]);
        final analysis = _analysisFor([dish]);

        final prompt = MenuQuestionPrompt.userPrompt(
          menu,
          analysis,
          'Is there a dairy-free option?',
        );

        expect(prompt, contains('MENU START'));
        expect(prompt, contains('MENU END'));
      });

      test('contains VERDICTS START and VERDICTS END markers', () {
        final dish = _dish('d1', 'Steak');
        final menu = _menuOf([dish]);
        final analysis = _analysisFor([dish]);

        final prompt = MenuQuestionPrompt.userPrompt(
          menu,
          analysis,
          'Is there a dairy-free option?',
        );

        expect(prompt, contains('VERDICTS START'));
        expect(prompt, contains('VERDICTS END'));
      });

      test('contains the QUESTION marker and the question text', () {
        final dish = _dish('d1', 'Steak');
        final menu = _menuOf([dish]);
        final analysis = _analysisFor([dish]);
        const question = 'Which dishes have no carbs?';

        final prompt = MenuQuestionPrompt.userPrompt(menu, analysis, question);

        expect(prompt, contains('QUESTION'));
        expect(prompt, contains(question));
      });

      test('verdict lines contain the dish id, verdict name, and "-" for '
          'null net_carbs_estimate and null modification', () {
        final dish = _dish('dish-1', 'Grilled Chicken');
        final menu = _menuOf([dish]);
        final analysis = _analysisFor([dish]);

        final prompt = MenuQuestionPrompt.userPrompt(
          menu,
          analysis,
          'Is this keto?',
        );

        expect(prompt, contains('dish-1 | orderAsIs | - | -'));
      });

      test('verdict lines include net_carbs_estimate when present', () {
        final dish = _dish('dish-2', 'Lamb Chops');
        final menu = _menuOf([dish]);
        final analysis = _analysisFor([dish], netCarbsEstimate: 3.5);

        final prompt = MenuQuestionPrompt.userPrompt(
          menu,
          analysis,
          'How many carbs?',
        );

        expect(prompt, contains('dish-2 | orderAsIs | 3.5 | -'));
      });

      test('verdict lines include modification when present and non-empty', () {
        final dish = _dish('dish-3', 'Sirloin with Fries');
        final menu = _menuOf([dish]);
        final analysis = _analysisFor(
          [dish],
          verdict: DishVerdict.modifiable,
          modification: 'Ask for salad instead of fries',
        );

        final prompt = MenuQuestionPrompt.userPrompt(
          menu,
          analysis,
          'How to order this?',
        );

        expect(
          prompt,
          contains('dish-3 | modifiable | - | Ask for salad instead of fries'),
        );
      });

      test('verdict lines emit "-" for an empty modification string', () {
        final dish = _dish('dish-4', 'Caesar Salad');
        final menu = _menuOf([dish]);
        final analysis = _analysisFor([dish], modification: '');

        final prompt = MenuQuestionPrompt.userPrompt(
          menu,
          analysis,
          'Good choice?',
        );

        // Empty string modification is treated as absent.
        expect(prompt, contains('dish-4 | orderAsIs | - | -'));
      });

      test('dishes not in the analysis are omitted from verdict lines', () {
        final classified = _dish('d-seen', 'Steak');
        final unclassified = _dish('d-unknown', 'Mystery Dish');
        final menu = _menuOf([classified, unclassified]);
        final analysis = MenuAnalysed(
          dishes: const [
            AnalysedDish(
              dishId: 'd-seen',
              name: 'Steak',
              verdict: DishVerdict.orderAsIs,
              why: 'lean protein',
            ),
          ],
          unclassified: const <String>['Mystery Dish'],
          engine: const LlmEngine(model: 'test'),
          analysedAt: DateTime.utc(2026),
        );

        final prompt = MenuQuestionPrompt.userPrompt(
          menu,
          analysis,
          'What can I eat?',
        );

        // The verdict section only lists analysed dishes; an unclassified
        // dish is in the menu section but does not get a verdict line.
        final verdictSection = prompt.substring(
          prompt.indexOf('VERDICTS START'),
          prompt.indexOf('VERDICTS END'),
        );
        expect(verdictSection, contains('d-seen'));
        expect(verdictSection, isNot(contains('d-unknown')));
      });

      test('menu lines from MenuAnalysisPrompt.userPrompt are included '
          'before the verdict section', () {
        final dish = _dish('d1', 'Entrecote');
        final menu = _menuOf([dish]);
        final analysis = _analysisFor([dish]);

        final prompt = MenuQuestionPrompt.userPrompt(
          menu,
          analysis,
          'Is this good?',
        );

        // The menu section comes before the verdicts section.
        final menuStart = prompt.indexOf('MENU START');
        final verdictsStart = prompt.indexOf('VERDICTS START');
        expect(menuStart, lessThan(verdictsStart));

        // The dish name from the menu section appears in the prompt.
        expect(prompt, contains('Entrecote'));
      });
    });

    group('responseSchema', () {
      test('responseSchema passes strict-mode validation', () {
        _assertStrictSchema(MenuQuestionPrompt.responseSchema());
      });

      test('responseSchema has answer and dish_ids as required properties', () {
        final schema = MenuQuestionPrompt.responseSchema();

        final required = (schema['required']! as List<Object?>).cast<String>();
        expect(required, containsAll(['answer', 'dish_ids']));
      });

      test('responseSchema answer property is a string type', () {
        final schema = MenuQuestionPrompt.responseSchema();

        final properties = schema['properties']! as Map<String, Object?>;
        final answerSchema = properties['answer']! as Map<String, Object?>;
        expect(answerSchema['type'], 'string');
      });

      test('responseSchema dish_ids property is an array of strings', () {
        final schema = MenuQuestionPrompt.responseSchema();

        final properties = schema['properties']! as Map<String, Object?>;
        final idsSchema = properties['dish_ids']! as Map<String, Object?>;
        expect(idsSchema['type'], 'array');
        final items = idsSchema['items']! as Map<String, Object?>;
        expect(items['type'], 'string');
      });
    });
  });
}

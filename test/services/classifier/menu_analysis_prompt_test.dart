import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/classifier/menu_analysis_prompt.dart';
import 'package:ketoclub/services/classifier/menu_classifier.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/services/menu/wolt/wolt_menu_mapper.dart';
import 'package:ketoclub/utils/constants.dart';

/// The venue every [Menu] built by this file is addressed to.
const VenueRef _venueRef = VenueRef(
  source: MenuSource.wolt,
  platformId: 'analysis-prompt-test-venue',
);

/// A menu with [categories], each a `(name, dishes)` pair, in order.
Menu _menuOf(List<(String, List<Dish>)> categories) => Menu(
  venueRef: _venueRef,
  currency: 'ILS',
  fetchedAt: DateTime.utc(2026),
  categories: [
    for (final (name, dishes) in categories)
      MenuCategory(id: 'cat-$name', name: name, dishes: dishes),
  ],
);

/// Recursively asserts that every object schema under [schema] is strict
/// mode-compliant (architecture.md §9.2, `m16_structured_output_fix.md`):
/// `additionalProperties: false`, and `required` listing exactly the keys
/// `properties` declares — no more, no fewer. Walks into `properties`
/// values and `items` so a nested object schema cannot slip through
/// unchecked.
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

/// The real 56-dish Wolt fixture (issue #22), mapped as the app maps it.
Menu _woltFixtureMenu() {
  final raw = jsonDecode(
    File('test/fixtures/wolt_hamosad_menu.json').readAsStringSync(),
  ) as Map<String, Object?>;
  final result = WoltMenuMapper.toMenu(
    raw,
    ref: _venueRef,
    fetchedAt: DateTime.utc(2026),
  );
  return (result as MenuFetched).menu;
}

/// [count] dishes `d0..d{count-1}`, spread over categories of [perCategory].
Menu _largeMenu(int count, {int perCategory = 30}) => _menuOf([
  for (var start = 0; start < count; start += perCategory)
    (
      'Aisle ${start ~/ perCategory}',
      [
        for (var i = start; i < count && i < start + perCategory; i++)
          Dish(
            id: 'd$i',
            name: 'Dish number $i',
            description: '',
            price: 10,
            options: const [],
          ),
      ],
    ),
]);

/// Every batch's dish ids, in order.
List<List<String>> _ids(List<Menu> batches) => [
  for (final batch in batches) [for (final dish in batch.allDishes) dish.id],
];

void main() {
  group('MenuAnalysisPrompt', () {
    group('systemPrompt', () {
      test('systemPrompt never leaves the limit placeholder unfilled', () {
        // Act
        final prompt = MenuAnalysisPrompt.systemPrompt(
          options: const ClassificationOptions(netCarbLimitGrams: 11),
        );

        // Assert
        expect(prompt, isNot(contains(netCarbLimitPlaceholder)));
      });

      for (final limit in <int>[3, 20]) {
        test('systemPrompt given a ${limit}g limit states it in both the '
            'green definition and the keto rules', () {
          // Act
          final prompt = MenuAnalysisPrompt.systemPrompt(
            options: ClassificationOptions(netCarbLimitGrams: limit),
          );

          // Assert
          expect(prompt, contains('net carbohydrates ${limit}g or less'));
          expect(prompt, contains('Net carbs of ${limit}g or less per dish'));
          expect(prompt, isNot(contains('6g')));
        });
      }

      test('systemPrompt states the reply must be JSON and nothing else', () {
        // Act
        final prompt = MenuAnalysisPrompt.systemPrompt();

        // Assert
        expect(prompt.toLowerCase(), contains('json'));
        expect(prompt.toLowerCase(), contains('nothing else'));
      });

      test('systemPrompt given dietaryConstraints appends every one of '
          'them', () {
        // Arrange
        const options = ClassificationOptions(
          dietaryConstraints: ['dairy-free', 'seed-oil free', 'carnivore'],
        );

        // Act
        final prompt = MenuAnalysisPrompt.systemPrompt(options: options);

        // Assert
        expect(prompt.toLowerCase(), contains('dietary constraint'));
        expect(prompt, contains('dairy-free'));
        expect(prompt, contains('seed-oil free'));
        expect(prompt, contains('carnivore'));
      });
    });

    group('userPrompt — golden fixture menu (#17 audit)', () {
      // A realistic multi-category, multi-dish menu, exercising a plain
      // dish, a dish with one option group, and a dish with two option
      // groups together, so the golden string below is a genuine
      // end-to-end check of `userPrompt` rather than a single-dish
      // structural assertion (the groups above already cover those).
      test('userPrompt renders the exact expected text for an English '
          'fixture menu', () {
        // Arrange
        final menu = _menuOf([
          (
            'Starters',
            [
              const Dish(
                id: 'starter-1',
                name: 'Greek Salad',
                description: 'Feta, olives and cucumber',
                price: 38,
                options: [],
              ),
              const Dish(
                id: 'starter-2',
                name: 'Buffalo Wings',
                description: 'Crispy wings with hot sauce',
                price: 44,
                options: [
                  DishOption(name: 'Sauce', values: ['Buffalo', 'BBQ']),
                ],
              ),
            ],
          ),
          (
            'Mains',
            [
              const Dish(
                id: 'main-1',
                name: 'Grilled Salmon',
                description: 'Served with lemon butter',
                price: 96,
                options: [
                  DishOption(
                    name: 'Side',
                    values: ['French Fries', 'Green Salad'],
                  ),
                ],
              ),
              const Dish(
                id: 'main-2',
                name: 'Margherita Pizza',
                description: 'Tomato, mozzarella, basil',
                price: 58,
                options: [],
              ),
              const Dish(
                id: 'main-3',
                name: 'Beef Burger',
                description: 'Served on a brioche bun with fries',
                price: 64,
                options: [
                  DishOption(
                    name: 'Bun',
                    values: ['Brioche bun', 'Lettuce wrap'],
                  ),
                  DishOption(name: 'Side', values: ['Fries', 'Salad']),
                ],
              ),
            ],
          ),
          (
            'Desserts',
            [
              const Dish(
                id: 'dessert-1',
                name: 'Chocolate Cake',
                description: 'Rich dark chocolate',
                price: 32,
                options: [],
              ),
            ],
          ),
        ]);

        // Act
        final prompt = MenuAnalysisPrompt.userPrompt(menu);

        // Assert
        expect(
          prompt,
          '1 | Starters | Greek Salad | Feta, olives and cucumber | '
          '\n'
          '2 | Starters | Buffalo Wings | Crispy wings with hot '
          'sauce | Sauce: Buffalo, BBQ\n'
          '3 | Mains | Grilled Salmon | Served with lemon butter | '
          'Side: French Fries, Green Salad\n'
          '4 | Mains | Margherita Pizza | Tomato, mozzarella, '
          'basil | \n'
          '5 | Mains | Beef Burger | Served on a brioche bun with '
          'fries | Bun: Brioche bun, Lettuce wrap; Side: Fries, Salad\n'
          '6 | Desserts | Chocolate Cake | Rich dark chocolate '
          '| ',
        );
      });

      test('userPrompt renders the exact expected text for a Hebrew '
          'fixture menu', () {
        // Arrange
        final menu = _menuOf([
          (
            'מנות ראשונות',
            [
              const Dish(
                id: 'starter-1',
                name: 'סלט יווני',
                description: 'פטה, זיתים ומלפפון',
                price: 38,
                options: [],
              ),
              const Dish(
                id: 'starter-2',
                name: 'כנפי עוף',
                description: "צ'יפס וכנפיים פריכות עם רוטב חריף",
                price: 44,
                options: [
                  DishOption(name: 'רוטב', values: ['חריף', 'ברביקיו']),
                ],
              ),
            ],
          ),
          (
            'עיקריות',
            [
              const Dish(
                id: 'main-1',
                name: 'סלמון בגריל',
                description: 'מוגש עם חמאת לימון ופירה תפוחי אדמה',
                price: 96,
                options: [
                  DishOption(name: 'תוספת', values: ["צ'יפס", 'סלט ירוק']),
                ],
              ),
              const Dish(
                id: 'main-2',
                name: 'המבורגר בקר',
                description: 'מוגש בלחמנייה עם צ׳יפס',
                price: 64,
                options: [],
              ),
            ],
          ),
        ]);

        // Act
        final prompt = MenuAnalysisPrompt.userPrompt(menu);

        // Assert
        expect(
          prompt,
          '1 | מנות ראשונות | סלט יווני | פטה, זיתים ומלפפון | \n'
          "2 | מנות ראשונות | כנפי עוף | צ'יפס וכנפיים פריכות "
          'עם רוטב חריף | רוטב: חריף, ברביקיו\n'
          '3 | עיקריות | סלמון בגריל | מוגש עם חמאת לימון ופירה '
          "תפוחי אדמה | תוספת: צ'יפס, סלט ירוק\n"
          '4 | עיקריות | המבורגר בקר | מוגש בלחמנייה עם צ׳יפס | ',
        );
      });
    });

    group('userPrompt', () {
      test('userPrompt contains no price, in any format', () {
        // Arrange
        const dish = Dish(
          id: 'dish-1',
          name: 'Prime Ribeye',
          description: 'Dry-aged',
          price: 189.9,
          options: [],
        );
        final menu = _menuOf([
          ('Mains', [dish]),
        ]);

        // Act
        final prompt = MenuAnalysisPrompt.userPrompt(menu);

        // Assert
        expect(prompt, isNot(contains('189.9')));
        expect(prompt, isNot(contains('189')));
      });

      test('userPrompt flattens a single option group to label and '
          'comma-joined values', () {
        // Arrange
        const dish = Dish(
          id: 'dish-1',
          name: 'Grilled Chicken',
          description: '',
          price: 45,
          options: [
            DishOption(
              name: 'Choice of side',
              values: ['French Fries', 'Green Salad'],
            ),
          ],
        );
        final menu = _menuOf([
          ('Mains', [dish]),
        ]);

        // Act
        final prompt = MenuAnalysisPrompt.userPrompt(menu);

        // Assert
        expect(
          prompt,
          '1 | Mains | Grilled Chicken |  | '
          'Choice of side: French Fries, Green Salad',
        );
      });

      test('userPrompt given a menu with no dishes returns an empty '
          'string', () {
        // Arrange
        final menu = _menuOf(const []);

        // Act
        final prompt = MenuAnalysisPrompt.userPrompt(menu);

        // Assert
        expect(prompt, isEmpty);
        expect(MenuAnalysisPrompt.promptIds(menu), isEmpty);
      });

      test('userPrompt sends short positional ids, never the platform id, '
          'and promptIds maps each back to its dish', () {
        // Arrange: Wolt-shaped ids, two dishes of one name, and one item
        // listed under two categories.
        const burgerA = Dish(
          id: '65b0c1f2a3d4e5f60718293a',
          name: 'Smashburger',
          description: '',
          price: 52,
          options: [],
        );
        const burgerB = Dish(
          id: '65b0c1f2a3d4e5f60718293b',
          name: 'Smashburger',
          description: 'Double',
          price: 64,
          options: [],
        );
        final menu = _menuOf([
          ('Burgers', [burgerA, burgerB]),
          ('Specials', [burgerA]),
        ]);

        // Act
        final prompt = MenuAnalysisPrompt.userPrompt(menu);
        final ids = MenuAnalysisPrompt.promptIds(menu);

        // Assert
        expect(
          prompt,
          '1 | Burgers | Smashburger |  | \n'
          '2 | Burgers | Smashburger | Double | \n'
          '3 | Specials | Smashburger |  | ',
        );
        expect(prompt, isNot(contains('65b0c1f2')));
        expect(ids, <String, String>{
          '1': burgerA.id,
          '2': burgerB.id,
          '3': burgerA.id,
        });
      });

      test('platformIdLines is userPrompt under the platform ids, for the '
          'menu question path', () {
        // Arrange
        const dish = Dish(
          id: 'dish-1',
          name: 'Grilled Chicken',
          description: 'Lemon',
          price: 45,
          options: [
            DishOption(name: 'Side', values: ['Fries']),
          ],
        );
        final menu = _menuOf([
          ('Mains', [dish]),
        ]);

        // Act + Assert
        expect(
          MenuAnalysisPrompt.platformIdLines(menu),
          'dish-1 | Mains | Grilled Chicken | Lemon | Side: Fries',
        );
        expect(
          MenuAnalysisPrompt.userPrompt(menu),
          '1 | Mains | Grilled Chicken | Lemon | Side: Fries',
        );
      });
    });

    group('responseSchema', () {
      test('responseSchema requires exactly dishes at the root and '
          'forbids additional properties', () {
        // Act
        final schema = MenuAnalysisPrompt.responseSchema();

        // Assert
        expect(schema['type'], 'object');
        expect(schema['additionalProperties'], isFalse);
        expect(schema['required'], ['dishes']);
      });

      test('responseSchema lists every dish property in required and '
          'forbids additional ones, walked structurally', () {
        // Act
        final schema = MenuAnalysisPrompt.responseSchema();

        // Assert
        _assertStrictSchema(schema);
      });

      test('responseSchema declares exactly the seven documented dish '
          'properties (issue #213 adds hidden_carbs)', () {
        // Act
        final schema = MenuAnalysisPrompt.responseSchema();
        final dishesSchema =
            (schema['properties']! as Map<String, Object?>)['dishes']!
                as Map<String, Object?>;
        final itemSchema = dishesSchema['items']! as Map<String, Object?>;
        final properties = itemSchema['properties']! as Map<String, Object?>;

        // Assert
        expect(properties.keys.toSet(), {
          'id',
          'name',
          'verdict',
          'why',
          'modification',
          'net_carbs_estimate',
          'hidden_carbs',
        });
      });

      test('responseSchema hidden_carbs nested object is strict with three '
          'required properties', () {
        // Act
        final schema = MenuAnalysisPrompt.responseSchema();
        final dishProperties =
            ((schema['properties']! as Map<String, Object?>)['dishes']!
                    as Map<String, Object?>)['items']!
                as Map<String, Object?>;
        final hiddenCarbs =
            (dishProperties['properties']!
                    as Map<String, Object?>)['hidden_carbs']!
                as Map<String, Object?>;
        final itemSchema = hiddenCarbs['items']! as Map<String, Object?>;

        // Assert
        expect(itemSchema['additionalProperties'], isFalse);
        expect((itemSchema['required']! as List<Object?>).toSet(), {
          'source',
          'certainty',
          'waiter_question',
        });
        final itemProps = itemSchema['properties']! as Map<String, Object?>;
        final certainty = itemProps['certainty']! as Map<String, Object?>;
        expect(certainty['enum'], containsAll(['suspected', 'likely']));
      });

      test('responseSchema types modification and net_carbs_estimate as '
          'nullable rather than omitting them', () {
        // Act
        final schema = MenuAnalysisPrompt.responseSchema();
        final dishesSchema =
            (schema['properties']! as Map<String, Object?>)['dishes']!
                as Map<String, Object?>;
        final itemSchema = dishesSchema['items']! as Map<String, Object?>;
        final properties = itemSchema['properties']! as Map<String, Object?>;
        final modification =
            properties['modification']! as Map<String, Object?>;
        final netCarbs =
            properties['net_carbs_estimate']! as Map<String, Object?>;

        // Assert
        expect(modification['type'], ['string', 'null']);
        expect(netCarbs['type'], ['number', 'null']);
      });

      test('responseSchema enumerates the verdict property from '
          'DishVerdict, not a retyped literal', () {
        // Act
        final schema = MenuAnalysisPrompt.responseSchema();
        final dishesSchema =
            (schema['properties']! as Map<String, Object?>)['dishes']!
                as Map<String, Object?>;
        final itemSchema = dishesSchema['items']! as Map<String, Object?>;
        final properties = itemSchema['properties']! as Map<String, Object?>;
        final verdict = properties['verdict']! as Map<String, Object?>;

        // Assert
        expect(verdict['enum'], DishVerdict.values.map((v) => v.name).toList());
      });
    });
  });

  group('MenuAnalysisPrompt.systemPrompt dietary toggles (issue #56)', () {
    /// The options MenuController builds for these three toggles.
    ClassificationOptions togglesOn({
      bool seedOilFree = false,
      bool dairyFree = false,
      bool carnivoreOnly = false,
    }) => ClassificationOptions(
      dietaryConstraints: ClassificationOptions.dietaryConstraintsFor(
        seedOilFree: seedOilFree,
        dairyFree: dairyFree,
        carnivoreOnly: carnivoreOnly,
      ),
    );

    test('with every toggle off the prompt is byte-for-byte the default '
        'one, so the server keeps its default cache key', () {
      // Act
      final prompt = MenuAnalysisPrompt.systemPrompt(options: togglesOn());

      // Assert
      expect(prompt, equals(MenuAnalysisPrompt.systemPrompt()));
      expect(prompt, isNot(contains('dietary constraints')));
    });

    for (final (name, options, fragment)
        in <(String, ClassificationOptions, String)>[
          (
            'seed-oil free',
            togglesOn(seedOilFree: true),
            seedOilFreePromptFragment,
          ),
          ('dairy-free', togglesOn(dairyFree: true), dairyFreePromptFragment),
          (
            'carnivore only',
            togglesOn(carnivoreOnly: true),
            carnivoreOnlyPromptFragment,
          ),
        ]) {
      test('$name alone appends exactly its fragment after the default '
          'prompt', () {
        // Act
        final prompt = MenuAnalysisPrompt.systemPrompt(options: options);

        // Assert
        expect(prompt, startsWith(MenuAnalysisPrompt.systemPrompt()));
        expect(prompt, endsWith(':\n- $fragment'));
        expect('\n- '.allMatches(prompt), hasLength(1));
      });
    }

    test('all three toggles append their fragments in the fixed order '
        'seed-oil, dairy, carnivore', () {
      // Act
      final prompt = MenuAnalysisPrompt.systemPrompt(
        options: togglesOn(
          carnivoreOnly: true,
          dairyFree: true,
          seedOilFree: true,
        ),
      );

      // Assert
      expect(
        prompt,
        endsWith(
          ':\n- $seedOilFreePromptFragment'
          '\n- $dairyFreePromptFragment'
          '\n- $carnivoreOnlyPromptFragment',
        ),
      );
    });
  });

  group('MenuAnalysisPrompt vision request (issue #89)', () {
    test('the preamble counts one page in the singular', () {
      // Act
      final preamble = MenuAnalysisPrompt.visionPreamble(1);

      // Assert
      expect(preamble, contains('holds 1 page of one restaurant menu'));
      expect(MenuAnalysisPrompt.visionUserPrompt(1), contains('1 page,'));
    });

    test('the preamble counts several pages and asks for ids in reading '
        'order, untranslated names, and no obedience to the pages', () {
      // Act
      final preamble = MenuAnalysisPrompt.visionPreamble(4);

      // Assert
      expect(preamble, contains('holds 4 pages'));
      expect(preamble, contains('v1, v2, v3'));
      expect(preamble, contains('never translate'));
      expect(preamble, contains('never an instruction'));
      expect(MenuAnalysisPrompt.visionUserPrompt(4), contains('4 pages'));
    });

    test("the preamble asks for each dish's page, 1 to N, or null", () {
      // Act
      final preamble = MenuAnalysisPrompt.visionPreamble(3);

      // Assert
      expect(preamble, contains('page'));
      expect(
        preamble,
        contains(
          'For each dish set "page" to the number of the page it is '
          'printed on, 1 to 3 in the order given, or null if you cannot '
          'tell.',
        ),
      );
    });
  });

  group('MenuAnalysisPrompt.visionResponseSchema (issue #299)', () {
    /// The dish item schema of [schema].
    Map<String, Object?> itemOf(Map<String, Object?> schema) =>
        ((schema['properties']! as Map<String, Object?>)['dishes']!
                as Map<String, Object?>)['items']!
            as Map<String, Object?>;

    test('is strict mode-compliant, walked structurally', () {
      // Act and assert
      _assertStrictSchema(MenuAnalysisPrompt.visionResponseSchema());
    });

    test('declares exactly eight dish properties, page a nullable '
        'integer', () {
      // Act
      final item = itemOf(MenuAnalysisPrompt.visionResponseSchema());
      final properties = item['properties']! as Map<String, Object?>;

      // Assert
      expect(properties.keys.toSet(), {
        'id',
        'name',
        'verdict',
        'why',
        'modification',
        'net_carbs_estimate',
        'hidden_carbs',
        'page',
      });
      expect((properties['page']! as Map<String, Object?>)['type'], [
        'integer',
        'null',
      ]);
      expect(item['required'], contains('page'));
    });

    test('leaves responseSchema at exactly seven dish properties', () {
      // Act
      MenuAnalysisPrompt.visionResponseSchema();
      final item = itemOf(MenuAnalysisPrompt.responseSchema());

      // Assert
      expect((item['properties']! as Map<String, Object?>).keys, hasLength(7));
      expect(item['required'], hasLength(7));
      expect(item['required'], isNot(contains('page')));
    });

    test('is responseSchema plus page, nothing else changed', () {
      // Arrange
      final text = MenuAnalysisPrompt.responseSchema();
      final vision = MenuAnalysisPrompt.visionResponseSchema();
      final textItem = itemOf(text);
      final visionItem = itemOf(vision);

      // Assert
      expect(vision['required'], text['required']);
      expect(visionItem['additionalProperties'], isFalse);
      final visionProperties = <String, Object?>{
        ...visionItem['properties']! as Map<String, Object?>,
      }..remove('page');
      expect(visionProperties, textItem['properties']);
    });
  });

  group('MenuAnalysisPrompt ingredient extraction (ALG-03)', () {
    const extracting = ClassificationOptions(restrictionsRequested: true);

    /// The dish item schema of [schema].
    Map<String, Object?> itemOf(Map<String, Object?> schema) =>
        ((schema['properties']! as Map<String, Object?>)['dishes']!
                as Map<String, Object?>)['items']!
            as Map<String, Object?>;

    test('the keto prompt names no ingredient extraction', () {
      // Act
      final prompt = MenuAnalysisPrompt.systemPrompt();

      // Assert
      expect(prompt, isNot(contains('"ingredients"')));
    });

    test('appends the extraction section last, after a blank line, and '
        'leaves the keto prompt before it byte for byte', () {
      // Act
      final ketoPrompt = MenuAnalysisPrompt.systemPrompt();
      final prompt = MenuAnalysisPrompt.systemPrompt(options: extracting);

      // Assert
      expect(prompt.startsWith('$ketoPrompt\n\n'), isTrue);
      final section = prompt.substring(ketoPrompt.length + 2);
      expect(section, contains('"ingredients"'));
      expect(section, contains('tahini in sabich'));
      expect(section, contains('"stated"'));
      expect(section, contains('"likely"'));
      expect(section, contains('"suspected"'));
      expect(section, isNot(contains('\n')));
      expect(prompt.endsWith('\n'), isFalse);
    });

    test('follows the dietary constraints section when both are present', () {
      // Arrange
      final constraints = ClassificationOptions.dietaryConstraintsFor(
        seedOilFree: true,
        dairyFree: false,
        carnivoreOnly: false,
      );
      final ketoOptions = ClassificationOptions(
        dietaryConstraints: constraints,
      );
      final both = ClassificationOptions(
        dietaryConstraints: constraints,
        restrictionsRequested: true,
      );

      // Act
      final ketoPrompt = MenuAnalysisPrompt.systemPrompt(options: ketoOptions);
      final prompt = MenuAnalysisPrompt.systemPrompt(options: both);

      // Assert
      expect(prompt.startsWith('$ketoPrompt\n\n'), isTrue);
      expect(ketoPrompt, endsWith('- $seedOilFreePromptFragment'));
    });

    test('names no restriction, so one extraction serves every '
        'profile (C1)', () {
      // Act
      final section = MenuAnalysisPrompt.systemPrompt(options: extracting)
          .substring(MenuAnalysisPrompt.systemPrompt().length);

      // Assert
      for (final word in <String>['allerg', 'profile', 'gluten', 'vegan']) {
        expect(section.toLowerCase(), isNot(contains(word)));
      }
    });

    test('the vision prompt adds the description paragraph last', () {
      // Act
      final ketoVision = MenuAnalysisPrompt.visionSystemPrompt(pageCount: 2);
      final vision = MenuAnalysisPrompt.visionSystemPrompt(
        pageCount: 2,
        options: extracting,
      );

      // Assert
      final textPrompt = MenuAnalysisPrompt.systemPrompt(options: extracting);
      final prefix =
          '${MenuAnalysisPrompt.visionPreamble(2)}\n\n'
          '$textPrompt\n\n';
      expect(vision.startsWith(prefix), isTrue);
      expect(vision.substring(prefix.length), contains('"description"'));
      expect(ketoVision, isNot(contains('"description"')));
      expect(ketoVision, isNot(contains('"ingredients"')));
    });

    test('the extracting schema is strict and adds ingredients last', () {
      // Act
      final schema = MenuAnalysisPrompt.responseSchema(extract: true);
      final item = itemOf(schema);
      final properties = item['properties']! as Map<String, Object?>;
      final ingredients = properties['ingredients']! as Map<String, Object?>;
      final entry = ingredients['items']! as Map<String, Object?>;
      final entryProperties = entry['properties']! as Map<String, Object?>;

      // Assert
      _assertStrictSchema(schema);
      expect((item['required']! as List<Object?>).last, 'ingredients');
      expect(item['required'], hasLength(8));
      expect(entry['required'], <String>['name', 'certainty', 'role']);
      expect(
        (entryProperties['certainty']! as Map<String, Object?>)['enum'],
        <String>['stated', 'likely', 'suspected'],
      );
      expect(
        (entryProperties['role']! as Map<String, Object?>)['enum'],
        <String>[
          'base',
          'protein',
          'side',
          'sauce',
          'garnish',
          'option',
          'unknown',
        ],
      );
      expect(properties, isNot(contains('concerns')));
    });

    test('the extracting schema is the keto one plus ingredients', () {
      // Act
      final keto = itemOf(MenuAnalysisPrompt.responseSchema());
      final extracting = itemOf(
        MenuAnalysisPrompt.responseSchema(extract: true),
      );

      // Assert
      expect(
        <String, Object?>{...extracting['properties']! as Map<String, Object?>}
          ..remove('ingredients'),
        keto['properties'],
      );
    });

    test('the extracting vision schema adds ingredients, page and a '
        'nullable description', () {
      // Act
      final schema = MenuAnalysisPrompt.visionResponseSchema(extract: true);
      final item = itemOf(schema);
      final properties = item['properties']! as Map<String, Object?>;

      // Assert
      _assertStrictSchema(schema);
      expect((item['required']! as List<Object?>).sublist(7), <String>[
        'ingredients',
        'page',
        'description',
      ]);
      expect((properties['description']! as Map<String, Object?>)['type'], [
        'string',
        'null',
      ]);
      expect(
        itemOf(MenuAnalysisPrompt.visionResponseSchema())['properties'],
        isNot(contains('description')),
      );
    });
  });

  group('MenuAnalysisPrompt.batches (issue #188)', () {
    test('the 56-dish Wolt fixture fits one keto request whole', () {
      // Arrange
      final menu = _woltFixtureMenu();

      // Act
      final batches = MenuAnalysisPrompt.batches(
        menu,
        maxDishes: MenuAnalysisPrompt.batchMaxDishes(extract: false),
      );

      // Assert: the prompt the issue measured (24,237 characters under the
      // platform ids; 56 short ids save 1,241), far under the budget, and
      // the menu itself, so the request is one request of the whole menu.
      expect(menu.allDishes, hasLength(56));
      expect(MenuAnalysisPrompt.userPrompt(menu).length, 22996);
      expect(batches, hasLength(1));
      expect(identical(batches.single, menu), isTrue);
    });

    test('the 56-dish Wolt fixture is two extraction requests of 28', () {
      // Act
      final batches = MenuAnalysisPrompt.batches(
        _woltFixtureMenu(),
        maxDishes: MenuAnalysisPrompt.batchMaxDishes(extract: true),
      );

      // Assert
      expect([for (final b in batches) b.allDishes.length], [28, 28]);
    });

    test('batchMaxDishes is the keto ceiling, or the smaller extraction '
        'one', () {
      expect(
        MenuAnalysisPrompt.batchMaxDishes(extract: false),
        llmBatchMaxDishes,
      );
      expect(
        MenuAnalysisPrompt.batchMaxDishes(extract: true),
        llmBatchMaxDishesWithExtraction,
      );
      expect(llmBatchMaxDishesWithExtraction, lessThan(llmBatchMaxDishes));
    });

    test('200 dishes under a ceiling of 80 are balanced as 67, 67 and 66, '
        'in menu order', () {
      // Arrange
      final menu = _largeMenu(200);

      // Act
      final batches = MenuAnalysisPrompt.batches(menu, maxDishes: 80);

      // Assert
      expect([for (final b in batches) b.allDishes.length], [67, 67, 66]);
      expect(_ids(batches).expand((ids) => ids).toList(), [
        for (final dish in menu.allDishes) dish.id,
      ]);
    });

    test('a batch keeps the venue fields and cuts a category in two under '
        'its own id and name', () {
      // Arrange: 30 dishes a category, so batch one ends inside the third.
      final menu = _largeMenu(200);

      // Act
      final first = MenuAnalysisPrompt.batches(menu, maxDishes: 80).first;

      // Assert
      expect(first.venueRef, menu.venueRef);
      expect(first.currency, menu.currency);
      expect(first.fetchedAt, menu.fetchedAt);
      expect(first.venueName, menu.venueName);
      expect(
        [for (final c in first.categories) c.id],
        ['cat-Aisle 0', 'cat-Aisle 1', 'cat-Aisle 2'],
      );
      expect(first.categories.last.dishes, hasLength(7));
      expect(
        MenuAnalysisPrompt.userPrompt(first).split('\n').first,
        '1 | Aisle 0 | Dish number 0 |  | ',
      );
    });

    test("the batches' prompts are the whole prompt's lines, partitioned, "
        'each numbered from 1', () {
      // Arrange
      final menu = _largeMenu(200);
      List<String> withoutIds(String prompt) => [
        for (final line in prompt.split('\n'))
          line.substring(line.indexOf(' | ')),
      ];

      // Act
      final batches = MenuAnalysisPrompt.batches(menu, maxDishes: 80);

      // Assert
      expect(
        batches.map(MenuAnalysisPrompt.userPrompt).expand(withoutIds).toList(),
        withoutIds(MenuAnalysisPrompt.userPrompt(menu)),
      );
      for (final batch in batches) {
        final ids = [
          for (final line in MenuAnalysisPrompt.userPrompt(batch).split('\n'))
            line.substring(0, line.indexOf(' | ')),
        ];
        expect(ids, [for (var i = 1; i <= ids.length; i++) '$i']);
        expect(MenuAnalysisPrompt.promptIds(batch).keys, ids);
        expect(MenuAnalysisPrompt.promptIds(batch).values, [
          for (final dish in batch.allDishes) dish.id,
        ]);
      }
    });

    test('the character budget measures each line with the id it carries '
        'in its batch', () {
      // Arrange: twelve dishes, so the last three carry two-digit ids.
      final menu = _largeMenu(12);
      final whole = MenuAnalysisPrompt.userPrompt(menu).length;

      // Act
      final exact = MenuAnalysisPrompt.batches(
        menu,
        maxDishes: 100,
        maxChars: whole,
      );
      final short = MenuAnalysisPrompt.batches(
        menu,
        maxDishes: 100,
        maxChars: whole - 1,
      );

      // Assert: the whole prompt, two-digit ids and all, fits exactly its
      // own length; one character less splits it, and every batch's real
      // prompt, renumbered from 1, is within the budget.
      expect(identical(exact.single, menu), isTrue);
      expect(short, hasLength(2));
      for (final batch in short) {
        expect(
          MenuAnalysisPrompt.userPrompt(batch).length,
          lessThanOrEqualTo(whole - 1),
        );
      }
    });

    test('the character budget closes a batch before the dish ceiling', () {
      // Arrange: each line is 34-36 characters.
      final menu = _largeMenu(10);

      // Act
      final batches = MenuAnalysisPrompt.batches(
        menu,
        maxDishes: 100,
        maxChars: 100,
      );

      // Assert: no batch's prompt is over the budget.
      expect(batches.length, greaterThan(1));
      for (final batch in batches) {
        expect(
          MenuAnalysisPrompt.userPrompt(batch).length,
          lessThanOrEqualTo(100),
        );
      }
      expect(_ids(batches).expand((ids) => ids), hasLength(10));
    });

    test('a line longer than the budget is a batch of its own', () {
      // Act
      final batches = MenuAnalysisPrompt.batches(
        _largeMenu(3),
        maxDishes: 100,
        maxChars: 5,
      );

      // Assert
      expect(_ids(batches), [
        ['d0'],
        ['d1'],
        ['d2'],
      ]);
    });

    test('the same menu always splits the same way', () {
      // Arrange
      final menu = _largeMenu(173);

      // Act
      final once = MenuAnalysisPrompt.batches(menu, maxDishes: 35);
      final twice = MenuAnalysisPrompt.batches(menu, maxDishes: 35);

      // Assert
      expect(
        once.map(MenuAnalysisPrompt.userPrompt).toList(),
        twice.map(MenuAnalysisPrompt.userPrompt).toList(),
      );
    });

    test('a menu at exactly the ceiling, and the empty menu, are returned '
        'themselves', () {
      // Arrange
      final full = _largeMenu(80);
      final empty = _menuOf(const []);

      // Act + Assert
      expect(
        identical(MenuAnalysisPrompt.batches(full, maxDishes: 80).single, full),
        isTrue,
      );
      expect(
        identical(
          MenuAnalysisPrompt.batches(empty, maxDishes: 80).single,
          empty,
        ),
        isTrue,
      );
      expect(
        MenuAnalysisPrompt.batches(_largeMenu(81), maxDishes: 80),
        hasLength(2),
      );
    });
  });
}

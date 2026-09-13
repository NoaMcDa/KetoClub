import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/classifier/menu_analysis_prompt.dart';
import 'package:ketoclub/services/classifier/menu_classifier.dart';
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

void main() {
  group('MenuAnalysisPrompt', () {
    test('schemaName is the literal menu_analysis', () {
      // Assert
      expect(MenuAnalysisPrompt.schemaName, 'menu_analysis');
    });

    group('systemPrompt', () {
      test('systemPrompt contains promptVerdictDefinitions verbatim', () {
        // Act
        final prompt = MenuAnalysisPrompt.systemPrompt();

        // Assert
        expect(prompt, contains(promptVerdictDefinitions));
      });

      test('systemPrompt contains promptKetoRules verbatim', () {
        // Act
        final prompt = MenuAnalysisPrompt.systemPrompt();

        // Assert
        expect(prompt, contains(promptKetoRules));
      });

      test('systemPrompt states every modifiable dish must carry a '
          'modification', () {
        // Act
        final prompt = MenuAnalysisPrompt.systemPrompt();

        // Assert
        expect(prompt, contains('modification'));
        expect(prompt, contains('nonKeto'));
      });

      test('systemPrompt states the reply must be JSON and nothing else', () {
        // Act
        final prompt = MenuAnalysisPrompt.systemPrompt();

        // Assert
        expect(prompt.toLowerCase(), contains('json'));
        expect(prompt.toLowerCase(), contains('nothing else'));
      });

      test('systemPrompt given default options omits any dietary '
          'constraint section', () {
        // Act
        final prompt = MenuAnalysisPrompt.systemPrompt();

        // Assert
        expect(prompt.toLowerCase(), isNot(contains('dietary constraint')));
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

      test('systemPrompt given dietaryConstraints still contains the '
          'verdict definitions and keto rules', () {
        // Arrange
        const options = ClassificationOptions(
          dietaryConstraints: ['dairy-free'],
        );

        // Act
        final prompt = MenuAnalysisPrompt.systemPrompt(options: options);

        // Assert
        expect(prompt, contains(promptVerdictDefinitions));
        expect(prompt, contains(promptKetoRules));
      });
    });

    group('userPrompt', () {
      test('userPrompt emits one line per dish, in menu order', () {
        // Arrange
        final menu = _menuOf([
          (
            'Mains',
            [
              const Dish(
                id: 'dish-1',
                name: 'Grilled Steak',
                description: 'With herb butter',
                price: 68,
                options: [],
              ),
              const Dish(
                id: 'dish-2',
                name: 'Margherita Pizza',
                description: 'Tomato and mozzarella',
                price: 52,
                options: [],
              ),
            ],
          ),
          (
            'Salads',
            [
              const Dish(
                id: 'dish-3',
                name: 'Greek Salad',
                description: 'Feta and olives',
                price: 38,
                options: [],
              ),
            ],
          ),
        ]);

        // Act
        final prompt = MenuAnalysisPrompt.userPrompt(menu);

        // Assert
        final lines = prompt.split('\n');
        expect(lines, [
          'dish-1 | Mains | Grilled Steak | With herb butter | ',
          'dish-2 | Mains | Margherita Pizza | Tomato and mozzarella | ',
          'dish-3 | Salads | Greek Salad | Feta and olives | ',
        ]);
      });

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
          'dish-1 | Mains | Grilled Chicken |  | '
          'Choice of side: French Fries, Green Salad',
        );
      });

      test('userPrompt joins more than one option group with a '
          'semicolon', () {
        // Arrange
        const dish = Dish(
          id: 'dish-1',
          name: 'Build-Your-Bowl',
          description: '',
          price: 45,
          options: [
            DishOption(name: 'Base', values: ['Rice', 'Cauliflower rice']),
            DishOption(name: 'Protein', values: ['Chicken', 'Tofu']),
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
          contains('Base: Rice, Cauliflower rice; Protein: Chicken, Tofu'),
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

      test('responseSchema declares exactly the six documented dish '
          'properties', () {
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
        });
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

      test('responseSchema has no description property on a dish', () {
        // Act
        final schema = MenuAnalysisPrompt.responseSchema();
        final dishesSchema =
            (schema['properties']! as Map<String, Object?>)['dishes']!
                as Map<String, Object?>;
        final itemSchema = dishesSchema['items']! as Map<String, Object?>;
        final properties = itemSchema['properties']! as Map<String, Object?>;

        // Assert
        expect(properties.containsKey('description'), isFalse);
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
}

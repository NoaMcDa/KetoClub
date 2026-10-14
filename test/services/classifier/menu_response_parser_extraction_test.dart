import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/concern.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/classifier/menu_response_parser.dart';
import 'package:ketoclub/services/classifier/scanned_menu_classifier.dart';

/// The engine every parse in this file is stamped with.
const AnalysisEngine _engine = LlmEngine(model: 'test-model');

/// The timestamp every parse in this file is stamped with.
final DateTime _analysedAt = DateTime.utc(2026, 3, 4, 5, 6);

/// A sabich with a description and an option group holding a removal.
const Dish _sabich = Dish(
  id: 'dish-sabich',
  name: 'Sabich',
  description: 'Fried eggplant, egg and amba in pita',
  price: 10,
  options: <DishOption>[
    DishOption(name: 'Extras', values: <String>['Tahini', 'No sesame']),
  ],
);

/// A Hebrew schnitzel whose description carries a particle ("הטחינה").
const Dish _schnitzel = Dish(
  id: 'dish-schnitzel',
  name: 'שניצל',
  description: 'עוף בציפוי פירורי לחם עם הטחינה',
  price: 10,
  options: <DishOption>[],
);

/// A dish with no description at all.
const Dish _water = Dish(
  id: 'dish-water',
  name: 'Water',
  description: '',
  price: 10,
  options: <DishOption>[],
);

/// The source menu every text parse in this file is read against.
final Menu _menu = Menu(
  venueRef: const VenueRef(source: MenuSource.wolt, platformId: 'v'),
  currency: 'ILS',
  fetchedAt: DateTime.utc(2026),
  categories: const <MenuCategory>[
    MenuCategory(
      id: 'cat-1',
      name: 'Mains',
      dishes: <Dish>[_sabich, _schnitzel, _water],
    ),
  ],
);

/// One `ingredients` entry.
Map<String, Object?> _ingredient(
  Object? name, {
  Object? certainty = 'stated',
  Object? role = 'base',
}) => <String, Object?>{'name': name, 'certainty': certainty, 'role': role};

/// One reply element for [dish] with [ingredients] (omitted when absent).
Map<String, Object?> _element(
  Dish dish, {
  String verdict = 'orderAsIs',
  Object? ingredients = const <Object?>[],
  bool withIngredients = true,
  Map<String, Object?> extra = const <String, Object?>{},
}) => <String, Object?>{
  'id': dish.id,
  'name': dish.name,
  'verdict': verdict,
  'why': 'A reason.',
  'modification': null,
  'net_carbs_estimate': null,
  'hidden_carbs': const <Object?>[],
  if (withIngredients) 'ingredients': ingredients,
  ...extra,
};

/// The analysis of a reply holding [elements], parsed against [_menu].
MenuAnalysed _parse(List<Object?> elements, {bool extract = true}) {
  final result = MenuResponseParser.parse(
    jsonEncode(<String, Object?>{'dishes': elements}),
    source: _menu,
    analysedAt: _analysedAt,
    engine: _engine,
    extract: extract,
  );
  return result as MenuAnalysed;
}

/// The ingredients the parser kept for [dish] from [ingredients].
List<ExtractedIngredient> _ingredientsOf(Dish dish, List<Object?> ingredients) {
  final analysis = _parse(<Object?>[_element(dish, ingredients: ingredients)]);
  return analysis.dishes.single.ingredients;
}

void main() {
  group('parse with extraction (ALG-03)', () {
    test('without extract, ingredients are never read', () {
      // Act
      final analysis = _parse(<Object?>[
        _element(_sabich, ingredients: <Object?>[_ingredient('egg')]),
      ], extract: false);

      // Assert
      expect(analysis.dishes.single.ingredients, isEmpty);
      expect(analysis.dishes.single.toJson(), isNot(contains('ingredients')));
    });

    test('keeps every verdict, a red one too, with its ingredients', () {
      // Act
      final analysis = _parse(<Object?>[
        _element(
          _sabich,
          verdict: 'nonKeto',
          ingredients: <Object?>[_ingredient('pita')],
        ),
      ]);

      // Assert
      final dish = analysis.dishes.single;
      expect(dish.verdict, DishVerdict.nonKeto);
      expect(dish.ingredients, const <ExtractedIngredient>[
        ExtractedIngredient(
          name: 'pita',
          certainty: Certainty.stated,
          role: ComponentRole.base,
        ),
      ]);
    });

    // (name sent, certainty sent, certainty kept, why)
    const supportTable = <(String, String, Certainty, String)>[
      ('egg', 'stated', Certainty.stated, 'in the description'),
      ('  Eggplant  ', 'likely', Certainty.likely, 'trimmed, case folded'),
      ('Tahini', 'stated', Certainty.stated, 'in a non-removal option'),
      ('sesame', 'stated', Certainty.suspected, 'only in a removal option'),
      ('flour', 'likely', Certainty.suspected, 'not in the text'),
      ('pita', 'suspected', Certainty.suspected, 'already suspected'),
      ('🌶', 'stated', Certainty.suspected, 'normalises to nothing'),
    ];
    for (final (name, sent, kept, why) in supportTable) {
      test('caps "$name" ($sent) at ${kept.name}: $why', () {
        // Act
        final kept0 = _ingredientsOf(_sabich, <Object?>[
          _ingredient(name, certainty: sent),
        ]);

        // Assert
        expect(kept0.single.certainty, kept);
        expect(kept0.single.name, name.trim());
      });
    }

    test('a Hebrew name is supported through a particle', () {
      // Act
      final kept = _ingredientsOf(_schnitzel, <Object?>[
        _ingredient('טחינה', role: 'sauce'),
        _ingredient('קמח'),
      ]);

      // Assert
      expect(kept.map((i) => i.certainty), <Certainty>[
        Certainty.stated,
        Certainty.suspected,
      ]);
      expect(kept.first.role, ComponentRole.sauce);
    });

    // (entry, why it is dropped)
    final droppedTable = <(Object?, String)>[
      ('not a map', 'not an object'),
      (_ingredient(null), 'a null name'),
      (_ingredient(3), 'a non-string name'),
      (_ingredient('   '), 'a blank name'),
      (_ingredient('x' * (maxIngredientNameLength + 1)), 'an over-long name'),
      (_ingredient('egg', certainty: 'Stated'), 'an unknown certainty'),
      (_ingredient('egg', certainty: null), 'a null certainty'),
      (<String, Object?>{'name': 'egg'}, 'no certainty'),
    ];
    for (final (entry, why) in droppedTable) {
      test('drops an entry with $why', () {
        // Act
        final kept = _ingredientsOf(_sabich, <Object?>[entry]);

        // Assert
        expect(kept, isEmpty);
      });
    }

    test('keeps a name of exactly the length cap', () {
      // Act
      final kept = _ingredientsOf(_sabich, <Object?>[
        _ingredient('y' * maxIngredientNameLength),
      ]);

      // Assert
      expect(kept, hasLength(1));
    });

    test('reads an unknown or missing role as unknown', () {
      // Act
      final kept = _ingredientsOf(_sabich, <Object?>[
        _ingredient('egg', role: 'topping'),
        <String, Object?>{'name': 'amba', 'certainty': 'stated'},
      ]);

      // Assert
      expect(kept.map((i) => i.role), <ComponentRole>[
        ComponentRole.unknown,
        ComponentRole.unknown,
      ]);
    });

    test('keeps the first of names that normalise alike', () {
      // Act
      final kept = _ingredientsOf(_sabich, <Object?>[
        _ingredient('egg', role: 'protein'),
        _ingredient('EGG!', certainty: 'likely'),
      ]);

      // Assert
      expect(kept.single.role, ComponentRole.protein);
    });

    test('keeps at most maxIngredientsPerDish', () {
      // Act
      final kept = _ingredientsOf(_sabich, <Object?>[
        for (var i = 0; i < maxIngredientsPerDish + 5; i++)
          _ingredient('item $i'),
      ]);

      // Assert
      expect(kept, hasLength(maxIngredientsPerDish));
      expect(kept.last.name, 'item ${maxIngredientsPerDish - 1}');
    });

    test('reads a non-list ingredients as none', () {
      // Act
      final kept = _ingredientsOf(_sabich, const <Object?>[]);
      final analysis = _parse(<Object?>[_element(_sabich, ingredients: 'egg')]);

      // Assert
      expect(kept, isEmpty);
      expect(analysis.dishes.single.ingredients, isEmpty);
    });

    test('never reads a model-sent concerns (C1)', () {
      // Act
      final analysis = _parse(<Object?>[
        _element(
          _sabich,
          extra: <String, Object?>{
            'concerns': <Object?>[
              <String, Object?>{
                'restrictionId': 'sesame',
                'source': 'model',
                'certainty': 'stated',
                'tier': 'stated',
              },
            ],
          },
        ),
      ]);

      // Assert
      expect(analysis.dishes.single.concerns, isEmpty);
    });
  });

  group('MenuResponseParser.extractionMissing (ALG-03)', () {
    MenuAnalysed parsed() => _parse(<Object?>[
      _element(_sabich, withIngredients: false),
      _element(_schnitzel, ingredients: <Object?>[_ingredient('עוף')]),
      _element(_water),
    ]);

    test('keeps the keto verdict of a described dish with no ingredient', () {
      // Act
      final analysis = parsed();

      // Assert
      expect(analysis.dishes, hasLength(3));
      expect(analysis.unclassified, isEmpty);
    });

    // (dish, extract, missing)
    const table = <(Dish, bool, bool)>[
      (_sabich, true, true),
      (_schnitzel, true, false),
      (_water, true, false),
      (_sabich, false, false),
    ];
    for (final (dish, extract, missing) in table) {
      test('is $missing for ${dish.id} with extract $extract', () {
        // Arrange
        final verdict = parsed().dishes.firstWhere((d) => d.dishId == dish.id);

        // Act
        final result = MenuResponseParser.extractionMissing(
          dish,
          verdict,
          extract: extract,
        );

        // Assert
        expect(result, missing);
      });
    }
  });

  group('parseScanned with extraction (ALG-03)', () {
    ScannedMenuRead read(List<Object?> elements, {bool extract = true}) =>
        MenuResponseParser.parseScanned(
          jsonEncode(<String, Object?>{'dishes': elements}),
          analysedAt: _analysedAt,
          engine: _engine,
          pageCount: 1,
          extract: extract,
        ) as ScannedMenuRead;

    Map<String, Object?> scanned(
      String name,
      Object? description, [
      List<Object?> ingredients = const <Object?>[],
    ]) => <String, Object?>{
      'name': name,
      'verdict': 'orderAsIs',
      'why': 'A reason.',
      'modification': null,
      'net_carbs_estimate': null,
      'hidden_carbs': const <Object?>[],
      'page': 1,
      'description': description,
      'ingredients': ingredients,
    };

    test('transcribes a trimmed description and judges against it', () {
      // Act
      final result = read(<Object?>[
        scanned('Sabich', '  Fried eggplant and tahini  ', <Object?>[
          _ingredient('tahini'),
          _ingredient('sesame'),
        ]),
      ]);

      // Assert
      final dish = result.menu.allDishes.single;
      expect(dish.description, 'Fried eggplant and tahini');
      expect(
        result.analysis.dishes.single.ingredients.map((i) => i.certainty),
        [Certainty.stated, Certainty.suspected],
      );
    });

    // (description sent, description kept)
    final descriptionTable = <(Object?, String)>[
      (null, ''),
      (42, ''),
      (
        'd' * (maxTranscribedDescriptionLength + 1),
        'd' * maxTranscribedDescriptionLength,
      ),
    ];
    for (final (sent, kept) in descriptionTable) {
      test('reads a description of ${sent.runtimeType} as '
          '${kept.length} characters', () {
        // Act
        final result = read(<Object?>[scanned('Soup', sent)]);

        // Assert
        expect(result.menu.allDishes.single.description, kept);
      });
    }

    test('without extract, the description and ingredients are not read', () {
      // Act
      final result = read(<Object?>[
        scanned('Sabich', 'Fried eggplant', <Object?>[_ingredient('egg')]),
      ], extract: false);

      // Assert
      expect(result.menu.allDishes.single.description, isEmpty);
      expect(result.analysis.dishes.single.ingredients, isEmpty);
    });

    test('a described scanned dish with no ingredient is missing', () {
      // Act
      final result = read(<Object?>[scanned('Cod', 'Battered')]);

      // Assert
      expect(
        MenuResponseParser.extractionMissing(
          result.menu.allDishes.single,
          result.analysis.dishes.single,
          extract: true,
        ),
        isTrue,
      );
    });
  });
}

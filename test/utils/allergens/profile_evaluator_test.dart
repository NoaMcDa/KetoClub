// ProfileEvaluator (Banto; ALG-04b, related to #346): concerns + a
// profile → one of four states per dish, on the device.
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/concern.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/utils/allergens/profile_evaluator.dart';
import 'package:ketoclub/utils/allergens/taxonomy.dart';

/// A dish with [name], [description] and [options].
Dish _dish(
  String name, {
  String description = '',
  List<DishOption> options = const <DishOption>[],
}) => Dish(
  id: 'd',
  name: name,
  description: description,
  price: 10,
  options: options,
);

/// A green analysis of [dishName] with [ingredients] and [concerns].
AnalysedDish _green(
  String dishName, {
  List<ExtractedIngredient> ingredients = const <ExtractedIngredient>[],
  List<Concern> concerns = const <Concern>[],
}) => AnalysedDish(
  dishId: 'd',
  name: dishName,
  verdict: DishVerdict.orderAsIs,
  why: 'Fits',
  ingredients: ingredients,
  concerns: concerns,
);

/// A yellow analysis of [dishName] whose keto script is [script].
AnalysedDish _yellow(String dishName, {String script = 'No fries'}) =>
    AnalysedDish(
      dishId: 'd',
      name: dishName,
      verdict: DishVerdict.modifiable,
      why: 'Swap',
      modification: script,
    );

/// A red analysis of [dishName].
AnalysedDish _red(String dishName) => AnalysedDish(
  dishId: 'd',
  name: dishName,
  verdict: DishVerdict.nonKeto,
  why: 'Pasta',
);

/// A profile holding [ids], in order, with no exceptions.
DietaryProfile _profile(List<RestrictionId> ids) {
  var profile = DietaryProfile.empty;
  for (final id in ids) {
    profile = profile.withEntry(id);
  }
  return profile;
}

/// A dish whose only text is a neutral name, so the rule engine finds
/// nothing and only the model's ingredients speak.
final Dish _plain = _dish('Plate');

/// The words the app never says about a dish (file 09 §6).
const List<String> _banned = <String>['safe', 'Safe', 'SAFE', 'בטוח'];

void main() {
  group('ProfileEvaluator — the empty profile is the identity', () {
    final cases = <(AnalysedDish, DishState)>[
      (_green('Steak'), DishState.fits),
      (_yellow('Steak with fries'), DishState.fitsWithChange),
      (_red('Pasta'), DishState.avoid),
    ];
    for (final (analysed, state) in cases) {
      test('${analysed.verdict.name} → ${state.name}', () {
        // Act
        final result = ProfileEvaluator.evaluate(
          analysed,
          _dish(analysed.name, description: 'with peanuts and tahini'),
          DietaryProfile.empty,
        );

        // Assert
        expect(result.dish, same(analysed));
        expect(result.state, state);
        expect(result.modification, analysed.modification);
        expect(result.concerns, isEmpty);
      });
    }
  });

  group('ProfileEvaluator — a model ingredient, by role and certainty', () {
    const strict = RestrictionId.peanuts;
    const flexible = RestrictionId.lactose;
    const removable = <ComponentRole>[
      ComponentRole.side,
      ComponentRole.sauce,
      ComponentRole.garnish,
      ComponentRole.option,
    ];
    const fixed = <ComponentRole>[
      ComponentRole.base,
      ComponentRole.protein,
      ComponentRole.unknown,
    ];
    final ingredientFor = <RestrictionId, String>{
      strict: 'peanuts',
      flexible: 'milk',
    };

    test('the two restrictions differ in strictness', () {
      // Assert
      expect(restrictionFor(strict).isStrict, isTrue);
      expect(restrictionFor(flexible).isStrict, isFalse);
    });

    for (final id in <RestrictionId>[strict, flexible]) {
      final isStrict = id == strict;
      for (final role in <ComponentRole>[...removable, ...fixed]) {
        for (final certainty in Certainty.values) {
          final firm = certainty != Certainty.suspected;
          final DishState expected;
          if (firm) {
            expected = removable.contains(role)
                ? DishState.fitsWithChange
                : DishState.avoid;
          } else {
            expected = isStrict ? DishState.ask : DishState.fits;
          }
          test('${id.name} (${isStrict ? 'strict' : 'flexible'}), '
              '${role.name}, ${certainty.name} → ${expected.name}', () {
            // Arrange
            final item = ingredientFor[id]!;
            final analysed = _green(
              'Plate',
              ingredients: <ExtractedIngredient>[
                ExtractedIngredient(
                  name: item,
                  certainty: certainty,
                  role: role,
                ),
              ],
            );

            // Act
            final result = ProfileEvaluator.evaluate(
              analysed,
              _plain,
              _profile(<RestrictionId>[id]),
              hebrew: false,
            );

            // Assert
            expect(result.state, expected);
            expect(result.concerns, hasLength(1));
            final concern = result.concerns.single;
            expect(concern.restrictionId, id);
            expect(concern.source, ConcernSource.model);
            expect(concern.certainty, certainty);
            expect(concern.matchedText, item);
            expect(
              result.modification,
              expected == DishState.fitsWithChange
                  ? 'Ask for it without $item'
                  : null,
            );
            expect(result.dish.verdict, DishVerdict.orderAsIs);
          });
        }
      }
    }
  });

  group('ProfileEvaluator — the rule engine is always consulted', () {
    test('a stated term in the name the model missed → avoid', () {
      // Arrange: the model says green and lists no sesame (ALG-04's
      // "missed" dish); the name says tahini.
      final analysed = _green(
        'סלט עם טחינה',
        ingredients: const <ExtractedIngredient>[
          ExtractedIngredient(name: 'חסה', certainty: Certainty.stated),
        ],
      );

      // Act
      final result = ProfileEvaluator.evaluate(
        analysed,
        _dish('סלט עם טחינה'),
        _profile(<RestrictionId>[RestrictionId.sesame]),
      );

      // Assert
      expect(result.state, DishState.avoid);
      expect(result.concerns.single.restrictionId, RestrictionId.sesame);
      expect(result.concerns.single.source, ConcernSource.name);
      expect(result.modification, isNull);
      expect(result.dish.verdict, DishVerdict.orderAsIs);
    });

    test('a stated term in an option → fitsWithChange, in the menu '
        'language (Hebrew)', () {
      // Arrange
      final dish = _dish(
        'טוסט',
        options: const <DishOption>[
          DishOption(name: 'תוספות', values: <String>['ביצה', 'זיתים']),
        ],
      );

      // Act
      final result = ProfileEvaluator.evaluate(
        _green('טוסט'),
        dish,
        _profile(<RestrictionId>[RestrictionId.eggs]),
      );

      // Assert
      expect(result.state, DishState.fitsWithChange);
      expect(result.modification, 'לבקש את המנה בלי ביצה');
    });

    test('a stated term in an option → fitsWithChange, in English', () {
      // Arrange
      final dish = _dish(
        'Toast',
        options: const <DishOption>[
          DishOption(name: 'Extras', values: <String>['Egg', 'Olives']),
        ],
      );

      // Act
      final result = ProfileEvaluator.evaluate(
        _green('Toast'),
        dish,
        _profile(<RestrictionId>[RestrictionId.eggs]),
      );

      // Assert
      expect(result.state, DishState.fitsWithChange);
      expect(result.modification, 'Ask for it without Egg');
    });

    test('an explicit language wins over the dish text', () {
      // Arrange
      final dish = _dish(
        'Toast',
        options: const <DishOption>[
          DishOption(name: 'Extras', values: <String>['Egg']),
        ],
      );

      // Act
      final result = ProfileEvaluator.evaluate(
        _green('Toast'),
        dish,
        _profile(<RestrictionId>[RestrictionId.eggs]),
        hebrew: true,
      );

      // Assert
      expect(result.modification, 'לבקש את המנה בלי Egg');
    });

    test('a guarded term on a strict entry → ask', () {
      // Act
      final result = ProfileEvaluator.evaluate(
        _green('Peanut-free cookie'),
        _dish('Peanut-free cookie'),
        _profile(<RestrictionId>[RestrictionId.peanuts]),
      );

      // Assert
      expect(result.state, DishState.ask);
      expect(result.concerns.single.certainty, Certainty.suspected);
    });

    test('a hidden likely source in the name → avoid', () {
      // Act
      final result = ProfileEvaluator.evaluate(
        _green('Chicken satay'),
        _dish('Chicken satay'),
        _profile(<RestrictionId>[RestrictionId.peanuts]),
      );

      // Assert
      expect(result.state, DishState.avoid);
      expect(result.concerns.single.source, ConcernSource.hidden);
    });

    test(
      'a weaker finding is never hidden behind a stronger removable one',
      () {
        // Arrange: a hidden, likely sesame in the name (hummus) and a stated
        // one in an option (tahini).
        final dish = _dish(
          'Hummus plate',
          options: const <DishOption>[
            DishOption(name: 'Extras', values: <String>['Tahini']),
          ],
        );

        // Act
        final result = ProfileEvaluator.evaluate(
          _green('Hummus plate'),
          dish,
          _profile(<RestrictionId>[RestrictionId.sesame]),
        );

        // Assert: the name decides; the listed concern is the stated one.
        expect(result.state, DishState.avoid);
        expect(result.concerns.single.certainty, Certainty.stated);
      },
    );

    test('a concern the analysis carried is used too', () {
      // Arrange: a server-sent concern the dish text does not support.
      final analysed = _green(
        'Plate',
        concerns: const <Concern>[
          Concern(
            restrictionId: RestrictionId.sesame,
            source: ConcernSource.option,
            certainty: Certainty.stated,
            tier: EvidenceTier.stated,
            matchedText: 'tahini',
          ),
        ],
      );

      // Act
      final result = ProfileEvaluator.evaluate(
        analysed,
        _plain,
        _profile(<RestrictionId>[RestrictionId.sesame]),
        hebrew: false,
      );

      // Assert
      expect(result.state, DishState.fitsWithChange);
      expect(result.modification, 'Ask for it without tahini');
    });

    test('the union keeps the surer of a rules and a model finding', () {
      // Arrange: the model guesses sesame on a garnish; the name states it.
      final analysed = _green(
        'Tahini bowl',
        ingredients: const <ExtractedIngredient>[
          ExtractedIngredient(
            name: 'sesame seeds',
            certainty: Certainty.suspected,
            role: ComponentRole.garnish,
          ),
        ],
      );

      // Act
      final result = ProfileEvaluator.evaluate(
        analysed,
        _dish('Tahini bowl'),
        _profile(<RestrictionId>[RestrictionId.sesame]),
      );

      // Assert
      expect(result.state, DishState.avoid);
      expect(result.concerns.single.source, ConcernSource.name);
      expect(result.concerns.single.certainty, Certainty.stated);
    });

    test('the model certainty is the weaker of ingredient and trigger', () {
      // Arrange: a stated ingredient whose trigger is a likely hidden one.
      final analysed = _green(
        'Plate',
        ingredients: const <ExtractedIngredient>[
          ExtractedIngredient(
            name: 'satay sauce',
            certainty: Certainty.stated,
            role: ComponentRole.sauce,
          ),
        ],
      );

      // Act
      final result = ProfileEvaluator.evaluate(
        analysed,
        _plain,
        _profile(<RestrictionId>[RestrictionId.peanuts]),
        hebrew: false,
      );

      // Assert
      expect(result.concerns.single.certainty, Certainty.likely);
      expect(result.concerns.single.tier, EvidenceTier.inferred);
      expect(result.state, DishState.fitsWithChange);
      expect(result.modification, 'Ask for it without satay sauce');
    });
  });

  group('ProfileEvaluator — the profile chooses', () {
    test('a restriction not in the profile is ignored', () {
      // Act
      final result = ProfileEvaluator.evaluate(
        _green('Tahini bowl'),
        _dish('Tahini bowl'),
        _profile(<RestrictionId>[RestrictionId.peanuts]),
      );

      // Assert
      expect(result.state, DishState.fits);
      expect(result.concerns, isEmpty);
    });

    test('a keto entry is never a concern; keto stays the verdict', () {
      // Arrange
      final analysed = _green(
        'Plate',
        concerns: const <Concern>[
          Concern(
            restrictionId: RestrictionId.keto,
            source: ConcernSource.name,
            certainty: Certainty.stated,
            tier: EvidenceTier.stated,
          ),
        ],
      );

      // Act
      final result = ProfileEvaluator.evaluate(
        analysed,
        _plain,
        _profile(<RestrictionId>[RestrictionId.keto]),
      );

      // Assert
      expect(result.concerns, isEmpty);
      expect(result.state, DishState.fits);
    });

    test('without keto in the profile, a keto verdict moves nothing', () {
      // Arrange
      final profile = _profile(<RestrictionId>[RestrictionId.peanuts]);

      // Act
      final red = ProfileEvaluator.evaluate(_red('Pasta'), _plain, profile);
      final yellow = ProfileEvaluator.evaluate(
        _yellow('Steak'),
        _plain,
        profile,
      );

      // Assert
      expect(red.state, DishState.fits);
      expect(yellow.state, DishState.fits);
      expect(yellow.modification, isNull);
      expect(red.dish.verdict, DishVerdict.nonKeto);
    });

    test('with keto in the profile, the keto verdict counts', () {
      // Arrange
      final profile = _profile(<RestrictionId>[
        RestrictionId.keto,
        RestrictionId.eggs,
      ]);
      const options = <DishOption>[
        DishOption(name: 'Extras', values: <String>['Egg']),
      ];

      // Act
      final red = ProfileEvaluator.evaluate(_red('Pasta'), _plain, profile);
      final yellow = ProfileEvaluator.evaluate(
        _yellow('Steak'),
        _dish('Steak', options: options),
        profile,
      );

      // Assert: keto's script first, then the removal.
      expect(red.state, DishState.avoid);
      expect(yellow.state, DishState.fitsWithChange);
      expect(yellow.modification, 'No fries\nAsk for it without Egg');
    });

    test('a strict suspected concern outranks a change and keeps it', () {
      // Arrange
      final dish = _dish(
        'Peanut-free toast',
        options: const <DishOption>[
          DishOption(name: 'Extras', values: <String>['Egg']),
        ],
      );

      // Act
      final result = ProfileEvaluator.evaluate(
        _green('Peanut-free toast'),
        dish,
        _profile(<RestrictionId>[RestrictionId.peanuts, RestrictionId.eggs]),
      );

      // Assert
      expect(result.state, DishState.ask);
      expect(result.modification, 'Ask for it without Egg');
      expect(result.concerns.map((c) => c.restrictionId), <RestrictionId>[
        RestrictionId.peanuts,
        RestrictionId.eggs,
      ]);
    });

    test('a flexible suspected concern is listed but moves nothing', () {
      // Arrange
      final analysed = _green(
        'Plate',
        ingredients: const <ExtractedIngredient>[
          ExtractedIngredient(name: 'cream', certainty: Certainty.suspected),
        ],
      );

      // Act
      final result = ProfileEvaluator.evaluate(
        analysed,
        _plain,
        _profile(<RestrictionId>[RestrictionId.lactose]),
      );

      // Assert
      expect(result.state, DishState.fits);
      expect(result.concerns.single.restrictionId, RestrictionId.lactose);
    });
  });

  group('ProfileEvaluator — exceptions', () {
    test('an exception the matched text holds drops the concern', () {
      // Arrange
      final profile = DietaryProfile.empty.withEntry(
        RestrictionId.lactose,
        exceptions: <String>['Cream'],
      );

      // Act
      final result = ProfileEvaluator.evaluate(
        _green('Berries with cream'),
        _dish('Berries with cream'),
        profile,
      );

      // Assert
      expect(result.concerns, isEmpty);
      expect(result.state, DishState.fits);
    });

    test('a narrower exception does not cover a broader term', () {
      // Arrange: "baked milk" is tolerated; plain milk is not.
      final profile = DietaryProfile.empty.withEntry(
        RestrictionId.lactose,
        exceptions: <String>['baked milk'],
      );

      // Act
      final result = ProfileEvaluator.evaluate(
        _green('Coffee with milk'),
        _dish('Coffee with milk'),
        profile,
      );

      // Assert
      expect(result.state, DishState.avoid);
    });

    test('a Hebrew exception matches a prefixed term', () {
      // Arrange
      final profile = DietaryProfile.empty.withEntry(
        RestrictionId.sesame,
        exceptions: <String>['טחינה'],
      );

      // Act
      final result = ProfileEvaluator.evaluate(
        _green('סלט בטחינה'),
        _dish('סלט בטחינה'),
        profile,
      );

      // Assert
      expect(result.concerns, isEmpty);
    });

    test("an exception covers only its own entry's concerns", () {
      // Arrange
      final profile = DietaryProfile.empty
          .withEntry(RestrictionId.milk, exceptions: <String>['milk'])
          .withEntry(RestrictionId.lactose);

      // Act
      final result = ProfileEvaluator.evaluate(
        _green('Coffee with milk'),
        _dish('Coffee with milk'),
        profile,
      );

      // Assert
      expect(result.concerns.map((c) => c.restrictionId), <RestrictionId>[
        RestrictionId.lactose,
      ]);
    });
  });

  group('ProfileEvaluator — wording', () {
    test('no template says a dish is safe, in either language', () {
      // Assert
      for (final word in _banned) {
        expect(removeItemModificationEn, isNot(contains(word)));
        expect(removeItemModificationHe, isNot(contains(word)));
      }
    });

    test('no state is named safe', () {
      // Assert
      for (final state in DishState.values) {
        expect(state.name.toLowerCase(), isNot(contains('safe')));
      }
    });

    test('no produced script says safe, over every state', () {
      // Arrange
      final profile = _profile(<RestrictionId>[
        RestrictionId.keto,
        RestrictionId.peanuts,
        RestrictionId.eggs,
      ]);
      final dishes = <(AnalysedDish, Dish)>[
        (_green('Toast'), _dish('Toast')),
        (
          _yellow('Toast'),
          _dish(
            'Toast',
            options: const <DishOption>[
              DishOption(name: 'x', values: <String>['Egg', 'ביצה']),
            ],
          ),
        ),
        (_green('Peanut-free toast'), _dish('Peanut-free toast')),
        (_red('Pasta'), _dish('Pasta with peanuts')),
      ];

      // Act
      final results = <EvaluatedDish>[
        for (final (analysed, dish) in dishes)
          ProfileEvaluator.evaluate(analysed, dish, profile),
      ];

      // Assert
      expect(results.map((r) => r.state).toSet(), DishState.values.toSet());
      for (final result in results) {
        for (final word in _banned) {
          expect(result.modification ?? '', isNot(contains(word)));
        }
      }
    });
  });

  group('EvaluatedDish', () {
    test('is a value type', () {
      // Arrange
      final a = EvaluatedDish(
        dish: _green('Toast'),
        concerns: const <Concern>[],
        state: DishState.fits,
      );
      final b = EvaluatedDish(
        dish: _green('Toast'),
        concerns: const <Concern>[],
        state: DishState.fits,
      );

      // Assert
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a.toString(), 'EvaluatedDish(d: fits, 0 concerns)');
      expect(
        a,
        isNot(
          EvaluatedDish(
            dish: _green('Toast'),
            concerns: const <Concern>[],
            state: DishState.ask,
          ),
        ),
      );
    });
  });
}

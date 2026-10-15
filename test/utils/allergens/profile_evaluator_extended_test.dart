// ProfileEvaluator and the ALG-17 restrictions (Banto, issue #359):
// alpha-gal is strict (avoid, ask), FODMAP, histamine and small portions are
// heads-ups that never move a dish, and the user's own words are matched on
// the device, strictly, one concern per word.
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/concern.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/named_profile.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/utils/allergens/group_evaluator.dart';
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

/// A green analysis of [name] with [ingredients].
AnalysedDish _green(
  String name, {
  List<ExtractedIngredient> ingredients = const <ExtractedIngredient>[],
}) => AnalysedDish(
  dishId: 'd',
  name: name,
  verdict: DishVerdict.orderAsIs,
  why: 'Fits',
  ingredients: ingredients,
);

/// A profile holding [ids], in order.
DietaryProfile _profile(List<RestrictionId> ids) {
  var profile = DietaryProfile.empty;
  for (final id in ids) {
    profile = profile.withEntry(id);
  }
  return profile;
}

/// A profile holding only the user's own [words].
DietaryProfile _own(List<String> words) {
  var profile = DietaryProfile.empty;
  for (final word in words) {
    profile = profile.withCustomTerm(word);
  }
  return profile;
}

/// [dish] evaluated as green for [profile].
EvaluatedDish _evaluate(Dish dish, DietaryProfile profile) =>
    ProfileEvaluator.evaluate(_green(dish.name), dish, profile);

void main() {
  group('alpha-gal is strict', () {
    final profile = _profile(<RestrictionId>[RestrictionId.alphaGal]);

    test('a named mammal meat in the dish is avoid', () {
      for (final dish in <Dish>[
        _dish('Beef with broccoli'),
        _dish('שישליק בקר'),
        _dish('Burger', description: 'Lamb patty, pickles'),
      ]) {
        final result = _evaluate(dish, profile);
        expect(result.state, DishState.avoid, reason: dish.name);
        expect(
          result.concerns.single.restrictionId,
          RestrictionId.alphaGal,
          reason: dish.name,
        );
      }
    });

    test('a casing or a stock is a suspicion, so ask', () {
      for (final dish in <Dish>[
        _dish('Chicken sausage roll'),
        _dish('Risotto', description: 'Cooked in stock'),
        _dish('שווארמה הודו בפיתה'),
      ]) {
        expect(
          _evaluate(dish, profile).state,
          DishState.ask,
          reason: dish.name,
        );
      }
    });

    test('a guard lowers to ask, never to fits', () {
      expect(_evaluate(_dish('Chicken burger'), profile).state, DishState.ask);
      expect(_evaluate(_dish('קבב עוף'), profile).state, DishState.ask);
    });

    test('meat only in a removable option is a change', () {
      // Arrange
      final dish = _dish(
        'Caesar salad',
        options: const <DishOption>[
          DishOption(name: 'Add', values: <String>['Beef strips']),
        ],
      );

      // Act
      final result = _evaluate(dish, profile);

      // Assert
      expect(result.state, DishState.fitsWithChange);
      expect(result.modification, "Ask for it without 'Beef'");
    });

    test("dairy is the milk entry's, not alpha-gal's", () {
      final result = _evaluate(_dish('Cheese omelette'), profile);
      expect(result.state, DishState.fits);
      expect(result.concerns, isEmpty);
    });

    test('a waiter question names the class of foods', () {
      final question = _evaluate(
        _dish('Beef with broccoli'),
        profile,
      ).concerns.single.waiterQuestion;
      expect(question, contains('mammal meat'));
    });
  });

  group('FODMAP, histamine and small portions are heads-ups', () {
    final cases = <(RestrictionId, Dish)>[
      (RestrictionId.fodmap, _dish('Onion soup', description: 'With garlic')),
      (RestrictionId.fodmap, _dish('מרק עדשים עם בצל')),
      (RestrictionId.histamine, _dish('Tuna salad', description: 'Parmesan')),
      (RestrictionId.histamine, _dish('פסטה עם פרמזן ועגבניות')),
      (RestrictionId.glp1, _dish('Double fried chicken bucket')),
      (RestrictionId.glp1, _dish('שניצל מטוגן עם צ׳יפס')),
    ];
    for (final (id, dish) in cases) {
      test(
        '${id.name}: "${dish.name}" is listed, suspected, and still fits',
        () {
          // Act
          final result = _evaluate(dish, _profile(<RestrictionId>[id]));

          // Assert
          expect(result.state, DishState.fits);
          expect(result.modification, isNull);
          expect(result.concerns, hasLength(1));
          final concern = result.concerns.single;
          expect(concern.restrictionId, id);
          expect(concern.certainty, Certainty.suspected);
          expect(concern.waiterQuestion, isNotNull);
          expect(concern.waiterQuestion, endsWith('?'));
        },
      );
    }

    test('never avoid, even beside a strict entry that finds nothing', () {
      // Arrange
      final profile = _profile(<RestrictionId>[
        RestrictionId.sesame,
        RestrictionId.fodmap,
      ]);

      // Act
      final result = _evaluate(_dish('Garlic and onion stew'), profile);

      // Assert
      expect(result.state, DishState.fits);
      expect(
        result.concerns.map((concern) => concern.restrictionId),
        <RestrictionId>[RestrictionId.fodmap],
      );
    });

    test('a model ingredient is a heads-up too', () {
      // Arrange
      final analysed = _green(
        'Plate',
        ingredients: const <ExtractedIngredient>[
          ExtractedIngredient(
            name: 'garlic',
            certainty: Certainty.stated,
            role: ComponentRole.base,
          ),
        ],
      );

      // Act
      final result = ProfileEvaluator.evaluate(
        analysed,
        _dish('Plate'),
        _profile(<RestrictionId>[RestrictionId.fodmap]),
      );

      // Assert
      expect(result.state, DishState.fits);
      expect(result.concerns.single.certainty, Certainty.suspected);
      expect(result.concerns.single.source, ConcernSource.model);
    });
  });

  group("the user's own words", () {
    test('a word in the name is avoid, quoted as the menu wrote it', () {
      // Act
      final result = _evaluate(_dish('Kiwi sorbet'), _own(<String>['kiwi']));

      // Assert
      expect(result.state, DishState.avoid);
      final concern = result.concerns.single;
      expect(concern.restrictionId, RestrictionId.custom);
      expect(concern.matchedText, 'Kiwi');
      expect(concern.waiterQuestion, 'Can this be made without kiwi?');
    });

    test('Hebrew, with a prefix letter, in Hebrew', () {
      // Act
      final result = _evaluate(
        _dish('סלט ירוק', description: 'עגבניות, מלפפון ובכוסברה'),
        _own(<String>['כוסברה']),
      );

      // Assert
      expect(result.state, DishState.avoid);
      expect(result.concerns.single.matchedText, 'ובכוסברה');
      expect(
        result.concerns.single.waiterQuestion,
        'אפשר להכין את המנה בלי כוסברה?',
      );
    });

    test('a word only in an option is a change', () {
      // Arrange
      final dish = _dish(
        'Yogurt bowl',
        options: const <DishOption>[
          DishOption(name: 'Fruit', values: <String>['Kiwi', 'Banana']),
        ],
      );

      // Act
      final result = _evaluate(dish, _own(<String>['kiwi']));

      // Assert
      expect(result.state, DishState.fitsWithChange);
      expect(result.modification, "Ask for it without 'Kiwi'");
    });

    test('"no kiwi" is a strict suspicion: ask', () {
      final result = _evaluate(
        _dish('Fruit salad', description: 'No kiwi'),
        _own(<String>['kiwi']),
      );
      expect(result.state, DishState.ask);
    });

    test('two words are two concerns, in the order found', () {
      // Act
      final result = _evaluate(
        _dish('Kiwi and coriander salsa'),
        _own(<String>['coriander', 'kiwi']),
      );

      // Assert
      expect(result.concerns.map((concern) => concern.matchedText), <String>[
        'Kiwi',
        'coriander',
      ]);
      expect(
        result.concerns.map((concern) => concern.waiterQuestion).toSet(),
        hasLength(2),
      );
    });

    test('a model ingredient that names the word is found too', () {
      // Arrange
      final analysed = _green(
        'Green salad',
        ingredients: const <ExtractedIngredient>[
          ExtractedIngredient(
            name: 'pine nuts',
            certainty: Certainty.likely,
            role: ComponentRole.garnish,
          ),
        ],
      );

      // Act
      final result = ProfileEvaluator.evaluate(
        analysed,
        _dish('Green salad'),
        _own(<String>['pine nut']),
      );

      // Assert
      expect(result.state, DishState.fitsWithChange);
      expect(result.concerns.single.source, ConcernSource.model);
      expect(result.modification, "Ask for it without 'pine nuts'");
    });

    test('a dish with none of the words fits, and the profile is strict', () {
      final result = _evaluate(_dish('Green salad'), _own(<String>['kiwi']));
      expect(result.state, DishState.fits);
      expect(result.concerns, isEmpty);
      expect(restrictionFor(RestrictionId.custom).isStrict, isTrue);
    });

    test("another person's words are not this profile's", () {
      final result = _evaluate(
        _dish('Kiwi sorbet'),
        _profile(<RestrictionId>[RestrictionId.sesame]),
      );
      expect(result.concerns, isEmpty);
    });
  });

  group('groups', () {
    NamedProfile person(String id, DietaryProfile profile) =>
        NamedProfile(id: id, name: id, profile: profile);

    test("the union holds every person's words, once each, uncapped", () {
      // Arrange
      final a = _own(<String>[
        for (var i = 0; i < ProfileEntry.maxTerms; i++) 'a$i',
      ]);
      final b = _own(<String>['kiwi', 'A0']);

      // Act
      final union = GroupEvaluator.union(<DietaryProfile>[a, b]);

      // Assert
      expect(union.customTerms, <String>[...a.customTerms, 'kiwi']);
    });

    test("two people's words stay two concerns", () {
      // Act
      final result = GroupEvaluator.evaluate(
        _green('Kiwi and coriander salsa'),
        _dish('Kiwi and coriander salsa'),
        <NamedProfile>[
          person('me', _own(<String>['kiwi'])),
          person('p1', _own(<String>['coriander'])),
        ],
      );

      // Assert
      expect(result.state, DishState.avoid);
      expect(
        result.combined.concerns.map((concern) => concern.matchedText),
        <String>['Kiwi', 'coriander'],
      );
    });
  });

  group('ProfileEvaluator.concernKey', () {
    test('is the restriction, and for the own entry also its words', () {
      const sesame = Concern(
        restrictionId: RestrictionId.sesame,
        source: ConcernSource.name,
        certainty: Certainty.stated,
        tier: EvidenceTier.stated,
        matchedText: 'Tahini',
      );
      const kiwi = Concern(
        restrictionId: RestrictionId.custom,
        source: ConcernSource.name,
        certainty: Certainty.stated,
        tier: EvidenceTier.stated,
        matchedText: 'KIWI',
      );
      expect(ProfileEvaluator.concernKey(sesame), 'sesame');
      expect(ProfileEvaluator.concernKey(kiwi), 'custom:kiwi');
    });
  });
}

// GroupEvaluator (Banto; ALG-12, #354): one menu read for several
// profiles — the strictest state shown, each person's kept.
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/concern.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/named_profile.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/utils/allergens/group_evaluator.dart';
import 'package:ketoclub/utils/allergens/profile_evaluator.dart';

/// A dish named [name].
Dish _dish(String name) => Dish(
  id: 'd',
  name: name,
  description: '',
  price: 10,
  options: const <DishOption>[],
);

/// An analysis of [name] with [verdict], and [modification] for a yellow.
AnalysedDish _analysed(
  String name, {
  DishVerdict verdict = DishVerdict.orderAsIs,
  String? modification,
}) => AnalysedDish(
  dishId: 'd',
  name: name,
  verdict: verdict,
  why: 'Because',
  modification: modification,
);

/// A profile holding [ids], in order.
DietaryProfile _profile(List<RestrictionId> ids) {
  var profile = DietaryProfile.empty;
  for (final id in ids) {
    profile = profile.withEntry(id);
  }
  return profile;
}

/// The person [id] holding [ids].
NamedProfile _person(String id, List<RestrictionId> ids) =>
    NamedProfile(id: id, name: id, profile: _profile(ids));

/// An evaluation in [state] with [concerns] and [modification].
EvaluatedDish _evaluated(
  DishState state, {
  List<Concern> concerns = const <Concern>[],
  String? modification,
}) => EvaluatedDish(
  dish: _analysed('Plate'),
  concerns: concerns,
  state: state,
  modification: modification,
);

/// A concern on [id] at [certainty].
Concern _concern(RestrictionId id, Certainty certainty) => Concern(
  restrictionId: id,
  source: ConcernSource.name,
  certainty: certainty,
  tier: EvidenceTier.inferred,
);

void main() {
  group('GroupEvaluator.strictest', () {
    // The whole 4 × 4 table: the later state in avoid > ask >
    // fitsWithChange > fits always wins, whatever the order.
    for (final a in DishState.values) {
      for (final b in DishState.values) {
        final expected = a.index >= b.index ? a : b;
        test('${a.name} with ${b.name} is ${expected.name}', () {
          // Act
          final result = GroupEvaluator.strictest(<DishState>[a, b]);

          // Assert
          expect(result, expected);
        });
      }
    }

    test('no state at all reads as fits', () {
      // Act
      final result = GroupEvaluator.strictest(const <DishState>[]);

      // Assert
      expect(result, DishState.fits);
    });

    test('three people: one ask among fits reads ask', () {
      // Act
      final result = GroupEvaluator.strictest(const <DishState>[
        DishState.fits,
        DishState.ask,
        DishState.fitsWithChange,
      ]);

      // Assert
      expect(result, DishState.ask);
    });
  });

  group('GroupEvaluator.combine', () {
    test('one evaluation is returned unchanged', () {
      // Arrange
      final only = _evaluated(DishState.ask);

      // Act
      final result = GroupEvaluator.combine(<EvaluatedDish>[only]);

      // Assert
      expect(identical(result, only), isTrue);
    });

    test('keeps every restriction once, the surest, in taxonomy order', () {
      // Arrange
      final first = _evaluated(
        DishState.ask,
        concerns: <Concern>[
          _concern(RestrictionId.sesame, Certainty.suspected),
        ],
      );
      final second = _evaluated(
        DishState.avoid,
        concerns: <Concern>[
          _concern(RestrictionId.sesame, Certainty.stated),
          _concern(RestrictionId.peanuts, Certainty.likely),
        ],
      );

      // Act
      final result = GroupEvaluator.combine(<EvaluatedDish>[first, second]);

      // Assert
      expect(result.state, DishState.avoid);
      expect(
        result.concerns.map((concern) => concern.restrictionId).toList(),
        <RestrictionId>[RestrictionId.peanuts, RestrictionId.sesame]
          ..sort((a, b) => a.index.compareTo(b.index)),
      );
      expect(
        result.concerns
            .firstWhere((c) => c.restrictionId == RestrictionId.sesame)
            .certainty,
        Certainty.stated,
      );
    });

    test('merges waiter lines once each, and drops them for avoid', () {
      // Arrange
      final a = _evaluated(
        DishState.fitsWithChange,
        modification: 'No fries\nNo bun',
      );
      final b = _evaluated(DishState.fitsWithChange, modification: 'No bun');
      final c = _evaluated(DishState.avoid);

      // Act
      final change = GroupEvaluator.combine(<EvaluatedDish>[a, b]);
      final avoid = GroupEvaluator.combine(<EvaluatedDish>[a, c]);

      // Assert
      expect(change.modification, 'No fries\nNo bun');
      expect(avoid.state, DishState.avoid);
      expect(avoid.modification, isNull);
    });
  });

  group('GroupEvaluator.union', () {
    test('one profile is itself; none is empty', () {
      // Arrange
      final one = _profile(<RestrictionId>[RestrictionId.milk]);

      // Act + Assert
      expect(GroupEvaluator.union(<DietaryProfile>[one]), one);
      expect(
        GroupEvaluator.union(const <DietaryProfile>[]),
        DietaryProfile.empty,
      );
    });

    test('an empty profile keeps keto in a union with an allergen', () {
      // Act
      final union = GroupEvaluator.union(<DietaryProfile>[
        _profile(<RestrictionId>[RestrictionId.milk]),
        DietaryProfile.empty,
      ]);

      // Assert
      expect(
        union.entries.map((entry) => entry.restrictionId).toList(),
        <RestrictionId>[RestrictionId.milk, RestrictionId.keto],
      );
    });

    test('two keto-only profiles stay the keto-only empty profile', () {
      // Act
      final union = GroupEvaluator.union(const <DietaryProfile>[
        DietaryProfile.empty,
        DietaryProfile.empty,
      ]);

      // Assert
      expect(union, DietaryProfile.empty);
    });

    test('keeps only the exceptions every holder shares', () {
      // Arrange
      final a = DietaryProfile.empty.withEntry(
        RestrictionId.lactose,
        exceptions: <String>['butter', 'ghee'],
      );
      final b = DietaryProfile.empty
          .withEntry(RestrictionId.lactose, exceptions: <String>['butter'])
          .withEntry(RestrictionId.vegan);

      // Act
      final union = GroupEvaluator.union(<DietaryProfile>[a, b]);

      // Assert
      expect(union.entryFor(RestrictionId.lactose)!.exceptions, <String>[
        'butter',
      ]);
      expect(union.contains(RestrictionId.vegan), isTrue);
      expect(union.contains(RestrictionId.keto), isFalse);
    });
  });

  group('GroupEvaluator.evaluate', () {
    final omelette = _dish('Cheese omelette');
    final analysed = _analysed('Cheese omelette');
    final milk = _person('a', <RestrictionId>[RestrictionId.milk]);
    final keto = _person('b', const <RestrictionId>[]);

    test('cheese omelette: avoid for milk, fits for keto, avoid shown', () {
      // Act
      final result = GroupEvaluator.evaluate(analysed, omelette, <NamedProfile>[
        milk,
        keto,
      ]);

      // Assert
      expect(result.state, DishState.avoid);
      expect(
        result.people.map((person) => (person.person.id, person.state)),
        <(String, DishState)>[('a', DishState.avoid), ('b', DishState.fits)],
      );
    });

    test('each person is evaluated exactly as alone', () {
      // Act
      final result = GroupEvaluator.evaluate(analysed, omelette, <NamedProfile>[
        milk,
        keto,
      ]);

      // Assert
      expect(
        result.people.first.evaluated,
        ProfileEvaluator.evaluate(analysed, omelette, milk.profile),
      );
      expect(
        result.people.last.evaluated,
        ProfileEvaluator.evaluate(analysed, omelette, keto.profile),
      );
    });

    test('one person: the combined result is their own', () {
      // Act
      final result = GroupEvaluator.evaluate(analysed, omelette, <NamedProfile>[
        milk,
      ]);

      // Assert
      expect(
        result.combined,
        ProfileEvaluator.evaluate(analysed, omelette, milk.profile),
      );
    });

    test('a keto change for one person is the group change', () {
      // Arrange
      final burger = _analysed(
        'Burger with fries',
        verdict: DishVerdict.modifiable,
        modification: 'Replace the fries with a salad',
      );
      final vegan = _person('c', <RestrictionId>[RestrictionId.vegetarian]);

      // Act
      final result = GroupEvaluator.evaluate(
        burger,
        _dish('Burger with fries'),
        <NamedProfile>[keto, vegan],
      );

      // Assert
      expect(result.people.first.state, DishState.fitsWithChange);
      expect(result.combined.modification, contains('salad'));
    });
  });
}

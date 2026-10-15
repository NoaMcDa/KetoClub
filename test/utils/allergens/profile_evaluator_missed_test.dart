// The rules catch what the model missed, for every restriction (Banto;
// ALG-04, issue #346): a dish named by a direct trigger of the vocabulary,
// whose model analysis is green and lists only an unrelated ingredient,
// still carries the rules concern. A strict entry is never left at "fits"
// or "fits with a change" by it; a flexible entry lists the concern. The
// evaluation is device-only (D26 C1), so these tables have no Python twin.
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/concern.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/utils/allergens/profile_evaluator.dart';
import 'package:ketoclub/utils/allergens/taxonomy.dart';
import 'package:ketoclub/utils/allergens/vocabulary.dart';

/// A dish named [name] and nothing else.
Dish _dish(String name) => Dish(
  id: 'd',
  name: name,
  description: '',
  price: 10,
  options: const <DishOption>[],
);

/// The model's green analysis of [name], listing only water: it "missed"
/// whatever the name says.
AnalysedDish _missed(String name) => AnalysedDish(
  dishId: 'd',
  name: name,
  verdict: DishVerdict.orderAsIs,
  why: 'Fits',
  ingredients: const <ExtractedIngredient>[
    ExtractedIngredient(
      name: 'water',
      certainty: Certainty.stated,
      role: ComponentRole.base,
    ),
  ],
);

void main() {
  final ids = <RestrictionId>[
    for (final id in RestrictionId.values)
      if (id != RestrictionId.keto &&
          id != RestrictionId.custom &&
          (allergenVocabulary[id]?.directEn.isNotEmpty ?? false))
        id,
  ];

  test('the table covers every vocabulary restriction', () {
    expect(ids, contains(RestrictionId.sesame));
    expect(ids, contains(RestrictionId.gluten));
    expect(ids, contains(RestrictionId.lactose));
    expect(ids.length, greaterThanOrEqualTo(15));
  });

  for (final id in ids) {
    final term = allergenVocabulary[id]!.directEn.first;
    final strict = restrictionFor(id).isStrict;

    test('${id.name}: "$term" in the name the model missed is caught', () {
      // Act
      final result = ProfileEvaluator.evaluate(
        _missed(term),
        _dish(term),
        DietaryProfile.empty.withEntry(id),
      );

      // Assert: the rules concern is there, whatever the model said.
      expect(
        result.concerns.map((concern) => concern.restrictionId),
        contains(id),
      );
      if (strict) {
        expect(
          result.state,
          isIn(<DishState>[DishState.avoid, DishState.ask]),
          reason: 'a strict entry is never left at fits by the model',
        );
      }
      // The wire verdict is never rewritten.
      expect(result.dish.verdict, DishVerdict.orderAsIs);
    });
  }

  test('a rules concern never removes a model concern', () {
    // Arrange: the model carried a milk concern; the name says tahini.
    const milk = Concern(
      restrictionId: RestrictionId.milk,
      source: ConcernSource.model,
      certainty: Certainty.likely,
      tier: EvidenceTier.inferred,
      matchedText: 'yogurt',
    );
    final analysed = AnalysedDish(
      dishId: 'd',
      name: 'Tahini salad',
      verdict: DishVerdict.orderAsIs,
      why: 'Fits',
      concerns: const <Concern>[milk],
    );

    // Act
    final result = ProfileEvaluator.evaluate(
      analysed,
      _dish('Tahini salad'),
      DietaryProfile.empty
          .withEntry(RestrictionId.sesame)
          .withEntry(RestrictionId.milk),
    );

    // Assert
    expect(
      result.concerns.map((concern) => concern.restrictionId).toSet(),
      <RestrictionId>{RestrictionId.sesame, RestrictionId.milk},
    );
  });
}

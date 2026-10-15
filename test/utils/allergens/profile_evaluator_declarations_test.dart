// ProfileEvaluator and declarations (Banto; ALG-09, issue #351): a declared
// absence lowers a concern by one step, never below suspected for a strict
// entry and never removing it; a flexible entry's suspected concern may be
// cleared.
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/concern.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/utils/allergens/declarations.dart';
import 'package:ketoclub/utils/allergens/profile_evaluator.dart';

/// A dish whose own text holds no allergen trigger, named [name], with
/// [tags]; the concerns come from the analysis alone.
Dish _dish(String name, {List<String> tags = const <String>[]}) => Dish(
  id: 'd',
  name: name,
  description: '',
  price: 10,
  options: const <DishOption>[],
  declaredTags: tags,
);

/// A concern about [id] found in the description at [certainty].
Concern _concern(
  RestrictionId id,
  Certainty certainty, {
  ConcernSource source = ConcernSource.description,
}) => Concern(
  restrictionId: id,
  source: source,
  certainty: certainty,
  tier: EvidenceTier.stated,
  matchedText: 'x',
);

/// A green analysis of `Bowl` carrying [concerns].
AnalysedDish _analysed(List<Concern> concerns) => AnalysedDish(
  dishId: 'd',
  name: 'Bowl',
  verdict: DishVerdict.orderAsIs,
  why: 'Fits',
  concerns: concerns,
);

/// A profile holding [ids], in order.
DietaryProfile _profile(List<RestrictionId> ids) {
  var profile = DietaryProfile.empty;
  for (final id in ids) {
    profile = profile.withEntry(id);
  }
  return profile;
}

void main() {
  group('ProfileEvaluator — a declared absence on a strict entry', () {
    final cases = <(Certainty, Certainty, DishState)>[
      (Certainty.stated, Certainty.likely, DishState.avoid),
      (Certainty.likely, Certainty.suspected, DishState.ask),
      (Certainty.suspected, Certainty.suspected, DishState.ask),
    ];
    for (final (before, after, state) in cases) {
      test('gluten ${before.name} → ${after.name}, ${state.name}', () {
        // Act: the heading declares "ללא גלוטן".
        final result = ProfileEvaluator.evaluate(
          _analysed(<Concern>[_concern(RestrictionId.gluten, before)]),
          _dish('Bowl'),
          _profile(<RestrictionId>[RestrictionId.gluten]),
          heading: 'סושי ללא גלוטן',
        );

        // Assert: never below suspected, never removed.
        expect(result.concerns, hasLength(1));
        expect(result.concerns.single.certainty, after);
        expect(result.concerns.single.tier, EvidenceTier.declared);
        expect(result.state, state);
        expect(result.declarations.single.rule, 'glutenFree');
        expect(result.declarations.single.source, DeclarationSource.heading);
      });
    }
  });

  group('ProfileEvaluator — a declared absence on a flexible entry', () {
    final cases = <(Certainty, Certainty?, DishState)>[
      (Certainty.stated, Certainty.likely, DishState.avoid),
      (Certainty.likely, Certainty.suspected, DishState.fits),
      (Certainty.suspected, null, DishState.fits),
    ];
    for (final (before, after, state) in cases) {
      test('lactose ${before.name} → ${after?.name ?? 'cleared'}', () {
        // Act
        final result = ProfileEvaluator.evaluate(
          _analysed(<Concern>[_concern(RestrictionId.lactose, before)]),
          _dish('Bowl, dairy-free'),
          _profile(<RestrictionId>[RestrictionId.lactose]),
        );

        // Assert
        if (after == null) {
          expect(result.concerns, isEmpty);
        } else {
          expect(result.concerns.single.certainty, after);
          expect(result.concerns.single.tier, EvidenceTier.declared);
        }
        expect(result.state, state);
        expect(result.declarations.single.rule, 'dairyFree');
      });
    }
  });

  test('a declaration with no concern adds nothing', () {
    // Act
    final result = ProfileEvaluator.evaluate(
      _analysed(const <Concern>[]),
      _dish('Vegan bowl 🌱'),
      _profile(<RestrictionId>[RestrictionId.milk, RestrictionId.vegan]),
    );

    // Assert
    expect(result.concerns, isEmpty);
    expect(result.declarations, isEmpty);
    expect(result.state, DishState.fits);
  });

  test('a concern the declaration does not speak for is untouched', () {
    // Act: gluten-free says nothing about sesame.
    final result = ProfileEvaluator.evaluate(
      _analysed(<Concern>[_concern(RestrictionId.sesame, Certainty.likely)]),
      _dish('Gluten-free bowl'),
      _profile(<RestrictionId>[RestrictionId.sesame]),
    );

    // Assert
    expect(result.concerns.single.certainty, Certainty.likely);
    expect(result.concerns.single.tier, EvidenceTier.stated);
    expect(result.declarations, isEmpty);
    expect(result.state, DishState.avoid);
  });

  test('a restriction declared twice is lowered once', () {
    // Act: the name, the heading and a platform tag all say gluten-free.
    final result = ProfileEvaluator.evaluate(
      _analysed(<Concern>[_concern(RestrictionId.gluten, Certainty.stated)]),
      _dish('Gluten-free bowl', tags: <String>['GLUTEN_FREE']),
      _profile(<RestrictionId>[RestrictionId.gluten]),
      heading: 'ללא גלוטן',
    );

    // Assert
    expect(result.concerns.single.certainty, Certainty.likely);
    expect(
      <DeclarationSource>[
        for (final declaration in result.declarations) declaration.source,
      ],
      <DeclarationSource>[
        DeclarationSource.platformTag,
        DeclarationSource.dishText,
        DeclarationSource.heading,
      ],
    );
  });

  test('vegan lowers milk (strict) and clears a suspected vegan concern', () {
    // Act
    final result = ProfileEvaluator.evaluate(
      _analysed(<Concern>[
        _concern(RestrictionId.milk, Certainty.likely),
        _concern(RestrictionId.vegan, Certainty.suspected),
      ]),
      _dish('קערה טבעונית 🌱'),
      _profile(<RestrictionId>[RestrictionId.milk, RestrictionId.vegan]),
    );

    // Assert
    expect(result.concerns.single.restrictionId, RestrictionId.milk);
    expect(result.concerns.single.certainty, Certainty.suspected);
    expect(result.state, DishState.ask);
  });

  test('a removable concern keeps its "without" sentence', () {
    // Act: a stated milk option under a dairy-free heading.
    final result = ProfileEvaluator.evaluate(
      _analysed(<Concern>[
        _concern(
          RestrictionId.milk,
          Certainty.stated,
          source: ConcernSource.option,
        ),
      ]),
      _dish('Bowl'),
      _profile(<RestrictionId>[RestrictionId.milk]),
      heading: 'Dairy free',
    );

    // Assert
    expect(result.concerns.single.certainty, Certainty.likely);
    expect(result.state, DishState.fitsWithChange);
    expect(result.modification, isNotNull);
  });

  test('a guarded offer lowers nothing', () {
    // Act
    final result = ProfileEvaluator.evaluate(
      _analysed(<Concern>[_concern(RestrictionId.gluten, Certainty.likely)]),
      _dish('Bowl'),
      _profile(<RestrictionId>[RestrictionId.gluten]),
      heading: 'ניתן לקבל ללא גלוטן',
    );

    // Assert
    expect(result.concerns.single.certainty, Certainty.likely);
    expect(result.declarations, isEmpty);
    expect(result.state, DishState.avoid);
  });

  test('the empty profile is still the identity of the verdict', () {
    // Act
    final result = ProfileEvaluator.evaluate(
      _analysed(<Concern>[_concern(RestrictionId.gluten, Certainty.stated)]),
      _dish('Gluten-free bowl 🌱', tags: <String>['VEGAN']),
      DietaryProfile.empty,
      heading: 'ללא גלוטן',
    );

    // Assert
    expect(result.concerns, isEmpty);
    expect(result.declarations, isEmpty);
    expect(result.state, DishState.fits);
  });
}

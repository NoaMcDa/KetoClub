// ProfileEvaluator and the restaurant's allergen matrix (Banto; ALG-16,
// related to #358): a `contains` cell is a declared stated concern on the
// dish itself (avoid), `may_contain` a declared suspected one (ask for a
// strict entry, listed for a flexible one), and a `free` cell lowers a
// concern as ALG-09's declarations do: one step, never below suspected for
// a strict entry.
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/allergen_matrix.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/concern.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/named_profile.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/utils/allergens/allergen_matrix.dart';
import 'package:ketoclub/utils/allergens/declarations.dart';
import 'package:ketoclub/utils/allergens/group_evaluator.dart';
import 'package:ketoclub/utils/allergens/profile_evaluator.dart';

/// A dish whose own text holds no allergen trigger.
const Dish _dish = Dish(
  id: 'd',
  name: 'Bowl',
  description: '',
  price: 10,
  options: <DishOption>[],
);

/// A concern about [id] found in the description at [certainty].
Concern _concern(RestrictionId id, Certainty certainty) => Concern(
  restrictionId: id,
  source: ConcernSource.description,
  certainty: certainty,
  tier: EvidenceTier.stated,
  matchedText: 'x',
);

/// A green analysis of the dish carrying [concerns].
AnalysedDish _analysed([List<Concern> concerns = const <Concern>[]]) =>
    AnalysedDish(
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

/// The evidence of a row named `Bowl` with [cells].
MatrixEvidence _matrix(Map<RestrictionId, MatrixCell> cells) =>
    AllergenMatrixMatcher.evidenceOf(
      AllergenMatrixRow(name: 'Bowl', cells: cells),
    );

void main() {
  group('a contains or may_contain cell', () {
    // (restriction, cell, state, certainty)
    final cases = <(RestrictionId, MatrixCell, DishState, Certainty)>[
      // Strict: an allergen and celiac disease.
      (
        RestrictionId.sesame,
        MatrixCell.contains,
        DishState.avoid,
        Certainty.stated,
      ),
      (
        RestrictionId.sesame,
        MatrixCell.mayContain,
        DishState.ask,
        Certainty.suspected,
      ),
      (
        RestrictionId.gluten,
        MatrixCell.mayContain,
        DishState.ask,
        Certainty.suspected,
      ),
      (
        RestrictionId.milk,
        MatrixCell.contains,
        DishState.avoid,
        Certainty.stated,
      ),
    ];
    for (final (id, cell, state, certainty) in cases) {
      test('${id.name} ${cell.wire} → ${state.name}', () {
        // Act
        final result = ProfileEvaluator.evaluate(
          _analysed(),
          _dish,
          _profile(<RestrictionId>[id]),
          matrix: _matrix(<RestrictionId, MatrixCell>{id: cell}),
        );

        // Assert
        final concern = result.concerns.single;
        expect(concern.restrictionId, id);
        expect(concern.source, ConcernSource.matrix);
        expect(concern.tier, EvidenceTier.declared);
        expect(concern.certainty, certainty);
        expect(concern.waiterQuestion, isNotEmpty);
        expect(result.state, state);
        if (state == DishState.avoid) expect(result.modification, isNull);
      });
    }

    test('a cell for a restriction the profile lacks changes nothing', () {
      // Act
      final result = ProfileEvaluator.evaluate(
        _analysed(),
        _dish,
        _profile(<RestrictionId>[RestrictionId.peanuts]),
        matrix: _matrix(const <RestrictionId, MatrixCell>{
          RestrictionId.sesame: MatrixCell.contains,
        }),
      );

      // Assert
      expect(result.concerns, isEmpty);
      expect(result.state, DishState.fits);
    });

    test('the matrix outranks nothing the menu states more surely', () {
      // Arrange: the menu states sesame; the matrix says may contain.
      final result = ProfileEvaluator.evaluate(
        _analysed(<Concern>[_concern(RestrictionId.sesame, Certainty.stated)]),
        _dish,
        _profile(<RestrictionId>[RestrictionId.sesame]),
        matrix: _matrix(const <RestrictionId, MatrixCell>{
          RestrictionId.sesame: MatrixCell.mayContain,
        }),
      );

      // Assert: one concern per restriction, the surest.
      expect(result.concerns.single.certainty, Certainty.stated);
      expect(result.state, DishState.avoid);
    });
  });

  group('a free cell on a strict entry: never below suspected', () {
    final cases = <(Certainty, Certainty, DishState)>[
      (Certainty.stated, Certainty.likely, DishState.avoid),
      (Certainty.likely, Certainty.suspected, DishState.ask),
      (Certainty.suspected, Certainty.suspected, DishState.ask),
    ];
    for (final (before, after, state) in cases) {
      test('gluten ${before.name} → ${after.name}, ${state.name}', () {
        // Act
        final result = ProfileEvaluator.evaluate(
          _analysed(<Concern>[_concern(RestrictionId.gluten, before)]),
          _dish,
          _profile(<RestrictionId>[RestrictionId.gluten]),
          matrix: _matrix(const <RestrictionId, MatrixCell>{
            RestrictionId.gluten: MatrixCell.free,
          }),
        );

        // Assert: lowered once, kept, and attributed to the matrix row.
        expect(result.concerns, hasLength(1));
        expect(result.concerns.single.certainty, after);
        expect(result.concerns.single.tier, EvidenceTier.declared);
        expect(result.state, state);
        final declared = result.declarations.single;
        expect(declared.source, DeclarationSource.allergenMatrix);
        expect(declared.rule, allergenMatrixRule);
        expect(declared.matchedText, 'Bowl');
      });
    }

    test('a free cell with no concern adds nothing', () {
      // Act
      final result = ProfileEvaluator.evaluate(
        _analysed(),
        _dish,
        _profile(<RestrictionId>[RestrictionId.sesame]),
        matrix: _matrix(const <RestrictionId, MatrixCell>{
          RestrictionId.sesame: MatrixCell.free,
        }),
      );

      // Assert: fits, never "safe", and no declaration is reported.
      expect(result.concerns, isEmpty);
      expect(result.declarations, isEmpty);
      expect(result.state, DishState.fits);
    });

    test('the matrix and a dish-text declaration lower only once', () {
      // Arrange: "gluten free" in the name and in the matrix.
      const glutenFreeDish = Dish(
        id: 'd',
        name: 'Bowl, gluten free',
        description: '',
        price: 10,
        options: <DishOption>[],
      );

      // Act
      final result = ProfileEvaluator.evaluate(
        _analysed(<Concern>[_concern(RestrictionId.gluten, Certainty.stated)]),
        glutenFreeDish,
        _profile(<RestrictionId>[RestrictionId.gluten]),
        matrix: _matrix(const <RestrictionId, MatrixCell>{
          RestrictionId.gluten: MatrixCell.free,
        }),
      );

      // Assert: stated → likely, once per restriction (ALG-09's rule).
      expect(result.concerns.single.certainty, Certainty.likely);
      expect(result.state, DishState.avoid);
      expect(result.declarations.map((declaration) => declaration.source), [
        DeclarationSource.dishText,
        DeclarationSource.allergenMatrix,
      ]);
    });
  });

  test('every column is strict, and a column speaks for its id only', () {
    // Arrange: lactose (an intolerance) has no column; milk's cell is
    // milk's alone (one id per column, nothing derived).
    final result = ProfileEvaluator.evaluate(
      _analysed(<Concern>[_concern(RestrictionId.lactose, Certainty.likely)]),
      _dish,
      _profile(<RestrictionId>[RestrictionId.lactose]),
      matrix: _matrix(const <RestrictionId, MatrixCell>{
        RestrictionId.milk: MatrixCell.free,
      }),
    );

    // Assert
    expect(result.concerns.single.certainty, Certainty.likely);
    expect(result.concerns.single.tier, EvidenceTier.stated);
    expect(result.declarations, isEmpty);
    expect(result.state, DishState.avoid);
  });

  test('no matrix is exactly the evaluation without one', () {
    // Arrange
    final analysed = _analysed(<Concern>[
      _concern(RestrictionId.sesame, Certainty.likely),
    ]);
    final profile = _profile(<RestrictionId>[RestrictionId.sesame]);

    // Act
    final without = ProfileEvaluator.evaluate(analysed, _dish, profile);
    final none = ProfileEvaluator.evaluate(
      analysed,
      _dish,
      profile,
      matrix: _matrix(const <RestrictionId, MatrixCell>{}),
    );

    // Assert
    expect(none, without);
  });

  test('a group carries the matrix to every person', () {
    // Arrange
    final people = <NamedProfile>[
      NamedProfile(
        id: 'a',
        name: 'Dana',
        profile: _profile(<RestrictionId>[RestrictionId.sesame]),
      ),
      NamedProfile(
        id: 'b',
        name: 'Omer',
        profile: _profile(<RestrictionId>[RestrictionId.eggs]),
      ),
    ];

    // Act
    final group = GroupEvaluator.evaluate(
      _analysed(),
      _dish,
      people,
      matrix: _matrix(const <RestrictionId, MatrixCell>{
        RestrictionId.eggs: MatrixCell.contains,
      }),
    );

    // Assert
    expect(group.people.first.evaluated.state, DishState.fits);
    expect(group.people.last.evaluated.state, DishState.avoid);
    expect(group.combined.state, DishState.avoid);
  });
}

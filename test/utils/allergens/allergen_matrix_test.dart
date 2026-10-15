// Matching a restaurant's allergen matrix to a menu, and the evidence a row
// gives (Banto; ALG-16, related to #358): a row speaks for a dish only when
// one of its names normalises exactly to the dish's name; a row naming no
// dish, or only a dish another row names, is listed and never guessed.
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/allergen_matrix.dart';
import 'package:ketoclub/models/concern.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/utils/allergens/allergen_matrix.dart';
import 'package:ketoclub/utils/allergens/declarations.dart';

Dish _dish(String id, String name) => Dish(
  id: id,
  name: name,
  description: '',
  price: 10,
  options: const <DishOption>[],
);

Menu _menu(List<Dish> dishes, {List<Dish> more = const <Dish>[]}) => Menu(
  venueRef: const VenueRef(source: MenuSource.wolt, platformId: 'v'),
  currency: 'ILS',
  fetchedAt: DateTime.utc(2026, 10, 15),
  categories: <MenuCategory>[
    MenuCategory(id: 'c1', name: 'Main', dishes: dishes),
    if (more.isNotEmpty) MenuCategory(id: 'c2', name: 'Popular', dishes: more),
  ],
);

AllergenMatrixRow _row(
  String name, {
  List<String> aliases = const <String>[],
  Map<RestrictionId, MatrixCell> cells = const <RestrictionId, MatrixCell>{
    RestrictionId.eggs: MatrixCell.contains,
  },
}) => AllergenMatrixRow(name: name, aliases: aliases, cells: cells);

AllergenMatrix _matrix(List<AllergenMatrixRow> rows) => AllergenMatrix(
  source: MatrixSource.restaurant,
  validFrom: DateTime.utc(2026, 10),
  rows: rows,
);

void main() {
  group('AllergenMatrixMatcher.match — one row, one dish', () {
    // (row name, dish name, matches?)
    final cases = <(String, String, bool)>[
      // English: case, punctuation, diacritics and spacing.
      ('Shakshuka', 'shakshuka', true),
      ('Caesar Salad', 'Caesar salad!', true),
      ('Purée of the day', 'Puree of the day', true),
      ('Fish & chips', 'Fish chips', true),
      ('Fish-and-chips', 'Fish and chips', true),
      ('Crème brûlée', 'Creme brulee', true),
      // Hebrew: geresh, gershayim, maqaf, final letters, niqqud.
      ("צ'יפס", 'ציפס', true),
      ('תפו"א בתנור', 'תפוא בתנור', true),
      // The normaliser deletes a maqaf with the points (U+0591-U+05C7),
      // joining its words, as it does for every other name it keys.
      ('סלט־חלומי', 'סלטחלומי', true),
      ('סלט-חלומי', 'סלט חלומי', true),
      ('שָׁקְשׁוּקָה', 'שקשוקה', true),
      ('בורקס!', 'בורקס', true),
      // Nothing looser: a shared word, a prefix or a plural is not a name.
      ('Chicken salad', 'Chicken schnitzel', false),
      ('Salad', 'Greek salad', false),
      ('שקשוקה', 'השקשוקה', false),
      ('Burger', 'Burgers', false),
      ('חומוס', 'חומוס פטריות', false),
      ('Shakshuka', 'שקשוקה', false),
    ];
    for (final (rowName, dishName, matches) in cases) {
      test('"$rowName" ${matches ? 'is' : 'is not'} "$dishName"', () {
        // Arrange
        final row = _row(rowName);

        // Act
        final match = AllergenMatrixMatcher.match(
          _matrix(<AllergenMatrixRow>[row]),
          _menu(<Dish>[_dish('d', dishName)]),
        );

        // Assert
        if (matches) {
          expect(match.rowsByDishId, {'d': row});
          expect(match.unmatched, isEmpty);
        } else {
          expect(match.rowsByDishId, isEmpty);
          expect(match.unmatched.single.reason, UnmatchedReason.noDish);
        }
      });
    }
  });

  group('AllergenMatrixMatcher.match — aliases and sharing', () {
    test('an alias names the dish on a menu printed in English', () {
      // Arrange: the matrix is in Hebrew, the menu in English.
      final row = _row('שקשוקה', aliases: <String>['Shakshuka']);

      // Act
      final match = AllergenMatrixMatcher.match(
        _matrix(<AllergenMatrixRow>[row]),
        _menu(<Dish>[_dish('d', 'SHAKSHUKA')]),
      );

      // Assert
      expect(match.rowsByDishId, {'d': row});
    });

    test('a printed name two dishes share speaks for both', () {
      // Arrange: the same dish under "Main" and "Popular".
      final row = _row('Shakshuka');

      // Act
      final match = AllergenMatrixMatcher.match(
        _matrix(<AllergenMatrixRow>[row]),
        _menu(
          <Dish>[_dish('a', 'Shakshuka')],
          more: <Dish>[_dish('b', 'Shakshuka')],
        ),
      );

      // Assert
      expect(match.rowsByDishId, {'a': row, 'b': row});
    });

    test('two rows naming one dish speak for neither, listed', () {
      // Arrange
      final first = _row('Shakshuka');
      final second = _row('Eggs in tomato', aliases: <String>['shakshuka!']);

      // Act
      final match = AllergenMatrixMatcher.match(
        _matrix(<AllergenMatrixRow>[first, second]),
        _menu(<Dish>[_dish('d', 'Shakshuka')]),
      );

      // Assert: whose cells hold would be a guess.
      expect(match.rowsByDishId, isEmpty);
      expect(match.unmatched.map((entry) => (entry.row, entry.reason)), [
        (first, UnmatchedReason.sharedDish),
        (second, UnmatchedReason.sharedDish),
      ]);
      expect(match.evidenceFor('d'), MatrixEvidence.none);
    });

    test('a row keeps the dishes no other row names', () {
      // Arrange: row A names X and Y; row B names Y too.
      final a = _row('X', aliases: <String>['Y']);
      final b = _row('Y');

      // Act
      final match = AllergenMatrixMatcher.match(
        _matrix(<AllergenMatrixRow>[a, b]),
        _menu(<Dish>[_dish('x', 'X'), _dish('y', 'Y')]),
      );

      // Assert
      expect(match.rowsByDishId, {'x': a});
      expect(match.unmatched.single.row, b);
      expect(match.unmatched.single.reason, UnmatchedReason.sharedDish);
    });

    test('unmatched rows are listed in the matrix order', () {
      // Arrange
      final rows = <AllergenMatrixRow>[
        _row('Pizza'),
        _row('Shakshuka'),
        _row('!!'),
        _row('פסטה'),
      ];

      // Act
      final match = AllergenMatrixMatcher.match(
        _matrix(rows),
        _menu(<Dish>[_dish('d', 'Shakshuka'), _dish('e', '***')]),
      );

      // Assert: a name with no letter or digit identifies nothing.
      expect(match.unmatched.map((entry) => entry.row.name), [
        'Pizza',
        '!!',
        'פסטה',
      ]);
      expect(AllergenMatrixMatcher.nameKey('!!'), isNull);
      expect(AllergenMatrixMatcher.nameKey("צ'יפס"), 'ציפס');
    });
  });

  group('AllergenMatrixMatcher.evidenceOf', () {
    test('contains is stated, may_contain suspected, free one declaration', () {
      // Arrange: cells in no particular order.
      final row = _row(
        'Shakshuka',
        cells: const <RestrictionId, MatrixCell>{
          RestrictionId.sesame: MatrixCell.free,
          RestrictionId.eggs: MatrixCell.contains,
          RestrictionId.gluten: MatrixCell.mayContain,
          RestrictionId.milk: MatrixCell.free,
        },
      );

      // Act
      final evidence = AllergenMatrixMatcher.evidenceOf(row);

      // Assert: the EU 14 order, every concern declared, no matched text.
      expect(evidence.concerns, const <Concern>[
        Concern(
          restrictionId: RestrictionId.gluten,
          source: ConcernSource.matrix,
          certainty: Certainty.suspected,
          tier: EvidenceTier.declared,
        ),
        Concern(
          restrictionId: RestrictionId.eggs,
          source: ConcernSource.matrix,
          certainty: Certainty.stated,
          tier: EvidenceTier.declared,
        ),
      ]);
      expect(evidence.absences, const <Declaration>[
        Declaration(
          rule: allergenMatrixRule,
          restrictionIds: <RestrictionId>[
            RestrictionId.milk,
            RestrictionId.sesame,
          ],
          polarity: DeclarationPolarity.absent,
          source: DeclarationSource.allergenMatrix,
          matchedText: 'Shakshuka',
        ),
      ]);
      expect(evidence.isEmpty, isFalse);
    });

    test('a row of blank cells says nothing', () {
      final evidence = AllergenMatrixMatcher.evidenceOf(
        _row('Bread', cells: const <RestrictionId, MatrixCell>{}),
      );

      expect(evidence, MatrixEvidence.none);
      expect(evidence.isEmpty, isTrue);
      expect(evidence.hashCode, MatrixEvidence.none.hashCode);
    });

    test('evidenceFor reads the matched row', () {
      // Arrange
      final match = AllergenMatrixMatcher.match(
        _matrix(<AllergenMatrixRow>[_row('Shakshuka')]),
        _menu(<Dish>[_dish('d', 'Shakshuka'), _dish('e', 'Toast')]),
      );

      // Assert
      expect(
        match.evidenceFor('d').concerns.single.restrictionId,
        RestrictionId.eggs,
      );
      expect(match.evidenceFor('e'), MatrixEvidence.none);
    });
  });
}

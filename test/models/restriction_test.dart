import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/restriction.dart';

void main() {
  group('RestrictionId', () {
    test('has exactly the 54 ids, in order; a rename needs a migration', () {
      // Arrange
      const expectedNames = <String>[
        'peanuts',
        'treeNuts',
        'milk',
        'lactose',
        'eggs',
        'soy',
        'wheat',
        'gluten',
        'fish',
        'crustaceans',
        'molluscs',
        'sesame',
        'celery',
        'mustard',
        'lupin',
        'sulphites',
        'legumes',
        'alphaGal',
        'fodmap',
        'histamine',
        'vegan',
        'vegetarian',
        'glp1',
        'buckwheat',
        'kiwi',
        'peach',
        'apple',
        'banana',
        'orange',
        'beef',
        'pork',
        'chicken',
        'gelatin',
        'yam',
        'corn',
        'sunflower',
        'flax',
        'chickpea',
        'lentil',
        'pea',
        'fenugreek',
        'fava',
        'nightshades',
        'msg',
        'caffeine',
        'salicylates',
        'oralAllergy',
        'pescatarian',
        'paleo',
        'whole30',
        'aip',
        'jain',
        'keto',
        'custom',
      ];

      // Act
      final names = RestrictionId.values.map((id) => id.name).toList();

      // Assert
      expect(names, expectedNames);
    });

    test('tryParse reads every id by name', () {
      for (final id in RestrictionId.values) {
        expect(RestrictionId.tryParse(id.name), id);
      }
    });

    test('tryParse answers null for an unknown, ordinal or cased name', () {
      expect(RestrictionId.tryParse('shellfish'), isNull);
      expect(RestrictionId.tryParse('0'), isNull);
      expect(RestrictionId.tryParse('Sesame'), isNull);
      expect(RestrictionId.tryParse(''), isNull);
    });
  });

  group('RestrictionKind', () {
    test('only an allergen, an autoimmune or a medical condition is '
        'strict', () {
      // Arrange
      const expected = <RestrictionKind, bool>{
        RestrictionKind.allergen: true,
        RestrictionKind.intolerance: false,
        RestrictionKind.autoimmune: true,
        RestrictionKind.lifestyle: false,
        RestrictionKind.religiousComponent: false,
        RestrictionKind.keto: false,
        RestrictionKind.medical: true,
      };

      // Act
      final actual = <RestrictionKind, bool>{
        for (final kind in RestrictionKind.values) kind: kind.isStrict,
      };

      // Assert
      expect(actual, expected);
    });

    test('tryParse reads every kind by name and rejects others', () {
      for (final kind in RestrictionKind.values) {
        expect(RestrictionKind.tryParse(kind.name), kind);
      }
      expect(RestrictionKind.tryParse('severe'), isNull);
    });
  });

  group('Jurisdiction', () {
    test('has exactly the seven jurisdictions of file 02', () {
      expect(Jurisdiction.values.map((j) => j.name).toList(), <String>[
        'us',
        'eu',
        'uk',
        'ca',
        'anz',
        'jp',
        'il',
      ]);
    });

    test('tryParse reads every jurisdiction by name and rejects others', () {
      for (final jurisdiction in Jurisdiction.values) {
        expect(Jurisdiction.tryParse(jurisdiction.name), jurisdiction);
      }
      expect(Jurisdiction.tryParse('fr'), isNull);
    });
  });

  group('Restriction', () {
    const sesame = Restriction(
      id: RestrictionId.sesame,
      kind: RestrictionKind.allergen,
      jurisdictions: <Jurisdiction>{Jurisdiction.us, Jurisdiction.eu},
      nameEn: 'Sesame',
      nameHe: 'שומשום',
      source: '11 §11',
    );

    test('isStrict follows the kind', () {
      // Arrange
      const lactose = Restriction(
        id: RestrictionId.lactose,
        kind: RestrictionKind.intolerance,
        jurisdictions: <Jurisdiction>{},
        nameEn: 'Lactose',
        nameHe: 'לקטוז',
        source: '11 §4',
      );

      // Assert
      expect(sesame.isStrict, isTrue);
      expect(lactose.isStrict, isFalse);
    });

    test('equal entries are equal and hash alike, whatever the set order', () {
      // Arrange
      const reordered = Restriction(
        id: RestrictionId.sesame,
        kind: RestrictionKind.allergen,
        jurisdictions: <Jurisdiction>{Jurisdiction.eu, Jurisdiction.us},
        nameEn: 'Sesame',
        nameHe: 'שומשום',
        source: '11 §11',
      );

      // Assert
      expect(reordered, sesame);
      expect(reordered.hashCode, sesame.hashCode);
    });

    test('differs when any field differs', () {
      // Arrange
      const other = Restriction(
        id: RestrictionId.sesame,
        kind: RestrictionKind.allergen,
        jurisdictions: <Jurisdiction>{Jurisdiction.us},
        nameEn: 'Sesame',
        nameHe: 'שומשום',
        source: '11 §11',
      );

      // Assert
      expect(other, isNot(sesame));
    });

    test('toString names the id and the kind', () {
      expect(sesame.toString(), 'Restriction(sesame, allergen)');
    });
  });
}

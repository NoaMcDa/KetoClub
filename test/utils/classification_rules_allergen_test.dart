// ClassificationRules.allergenFindings and allergenConcerns (Banto;
// ALG-04b, related to #346). The Python twin replays the same functions
// through the golden `allergen_concerns.json`.
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/concern.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/utils/classification_rules.dart';

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

/// One option group, "Extras", holding [values].
List<DishOption> _extras(List<String> values) => <DishOption>[
  DishOption(name: 'Extras', values: values),
];

/// The concern for [id] in [concerns], or null.
Concern? _for(List<Concern> concerns, RestrictionId id) {
  for (final concern in concerns) {
    if (concern.restrictionId == id) return concern;
  }
  return null;
}

void main() {
  group('ClassificationRules.allergenConcerns — source, certainty, tier', () {
    final cases =
        <
          ({
            String label,
            Dish dish,
            RestrictionId id,
            ConcernSource source,
            Certainty certainty,
            EvidenceTier tier,
            String matched,
          })
        >[
          (
            label: 'a direct term in the name is stated',
            dish: _dish('Tahini bowl'),
            id: RestrictionId.sesame,
            source: ConcernSource.name,
            certainty: Certainty.stated,
            tier: EvidenceTier.stated,
            matched: 'Tahini',
          ),
          (
            label: 'a direct term in the description is stated',
            dish: _dish('Salad', description: 'with roasted peanuts'),
            id: RestrictionId.peanuts,
            source: ConcernSource.description,
            certainty: Certainty.stated,
            tier: EvidenceTier.stated,
            matched: 'peanuts',
          ),
          (
            label: 'a direct term in an option value is an option',
            dish: _dish('Toast', options: _extras(<String>['Egg'])),
            id: RestrictionId.eggs,
            source: ConcernSource.option,
            certainty: Certainty.stated,
            tier: EvidenceTier.stated,
            matched: 'Egg',
          ),
          (
            label: 'a hidden term is hidden, its own certainty, inferred',
            dish: _dish('Chicken satay'),
            id: RestrictionId.peanuts,
            source: ConcernSource.hidden,
            certainty: Certainty.likely,
            tier: EvidenceTier.inferred,
            matched: 'satay',
          ),
          (
            label: 'a hidden term in an option is still hidden',
            dish: _dish('Plate', options: _extras(<String>['Hummus'])),
            id: RestrictionId.sesame,
            source: ConcernSource.hidden,
            certainty: Certainty.likely,
            tier: EvidenceTier.inferred,
            matched: 'Hummus',
          ),
          (
            label: 'a guarded term is lowered and inferred, never dropped',
            dish: _dish('Peanut-free cookie'),
            id: RestrictionId.peanuts,
            source: ConcernSource.name,
            certainty: Certainty.suspected,
            tier: EvidenceTier.inferred,
            matched: 'Peanut',
          ),
          (
            label: 'a Hebrew term keeps its points and its prefix letter',
            dish: _dish('סָלָט בַּטְּחִינָה'),
            id: RestrictionId.sesame,
            source: ConcernSource.name,
            certainty: Certainty.stated,
            tier: EvidenceTier.stated,
            matched: 'בַּטְּחִינָה',
          ),
          (
            label: 'a maqaf joins two words, and each is read',
            dish: _dish('טוסט', description: 'עם חמאת־בוטנים'),
            id: RestrictionId.peanuts,
            source: ConcernSource.description,
            certainty: Certainty.stated,
            tier: EvidenceTier.stated,
            matched: 'בוטנים',
          ),
          (
            label: 'a character outside the BMP before the term is skipped',
            dish: _dish('🥜 Peanut skewers'),
            id: RestrictionId.peanuts,
            source: ConcernSource.name,
            certainty: Certainty.stated,
            tier: EvidenceTier.stated,
            matched: 'Peanut',
          ),
        ];
    for (final entry in cases) {
      test(entry.label, () {
        // Act
        final concern = _for(
          ClassificationRules.allergenConcerns(entry.dish),
          entry.id,
        );

        // Assert
        expect(concern, isNotNull);
        expect(concern!.source, entry.source);
        expect(concern.certainty, entry.certainty);
        expect(concern.tier, entry.tier);
        expect(concern.matchedText, entry.matched);
        expect(concern.waiterQuestion, isNull);
      });
    }
  });

  group('ClassificationRules.allergenConcerns — what is read', () {
    test('a removal option value is skipped, with or without a maqaf', () {
      // Arrange
      final dish = _dish(
        'Plate',
        options: <DishOption>[
          const DishOption(
            name: 'Changes',
            values: <String>['No sesame', 'ללא־שומשום', 'בלי ביצה'],
          ),
        ],
      );

      // Act
      final concerns = ClassificationRules.allergenConcerns(dish);

      // Assert
      expect(concerns, isEmpty);
    });

    test('an option group name is not read', () {
      // Arrange
      final dish = _dish(
        'Plate',
        options: <DishOption>[
          const DishOption(name: 'Peanut sauce', values: <String>['Small']),
        ],
      );

      // Act / Assert
      expect(ClassificationRules.allergenConcerns(dish), isEmpty);
    });

    test('a dish with no trigger has no concern', () {
      // Act / Assert
      expect(ClassificationRules.allergenConcerns(_dish('Water')), isEmpty);
    });

    test('every restriction found is reported, whatever any profile', () {
      // Arrange
      final dish = _dish('Peanut and tahini bowl', description: 'with egg');

      // Act
      final ids = <RestrictionId>[
        for (final concern in ClassificationRules.allergenConcerns(dish))
          concern.restrictionId,
      ];

      // Assert: taxonomy order, one each. A peanut is also a legume, and
      // the peanut and egg make the dish not vegan.
      expect(ids, <RestrictionId>[
        RestrictionId.peanuts,
        RestrictionId.eggs,
        RestrictionId.sesame,
        RestrictionId.legumes,
        RestrictionId.vegan,
      ]);
    });
  });

  group('ClassificationRules.allergenConcerns — one per restriction', () {
    test('the surest finding wins over an earlier, weaker one', () {
      // Arrange: a guarded (suspected) peanut in the name, a stated one
      // in an option.
      final dish = _dish(
        'Peanut-free cookie',
        options: _extras(<String>['Peanuts']),
      );

      // Act
      final findings = ClassificationRules.allergenFindings(dish);
      final concern = _for(
        ClassificationRules.allergenConcerns(dish),
        RestrictionId.peanuts,
      );

      // Assert
      expect(
        findings.where((f) => f.restrictionId == RestrictionId.peanuts),
        hasLength(2),
      );
      expect(concern!.source, ConcernSource.option);
      expect(concern.certainty, Certainty.stated);
    });

    test('at a tie the earliest finding wins: name before option', () {
      // Arrange
      final dish = _dish('Egg salad', options: _extras(<String>['Egg']));

      // Act
      final concern = _for(
        ClassificationRules.allergenConcerns(dish),
        RestrictionId.eggs,
      );

      // Assert
      expect(concern!.source, ConcernSource.name);
    });

    test('the findings keep every hit in name, description, option order', () {
      // Arrange
      final dish = _dish(
        'Hummus with tahini',
        description: 'and pita',
        options: _extras(<String>['Egg']),
      );

      // Act
      final sources = <(RestrictionId, ConcernSource)>[
        for (final finding in ClassificationRules.allergenFindings(dish))
          (finding.restrictionId, finding.source),
      ];

      // Assert
      expect(sources.first, (RestrictionId.sesame, ConcernSource.hidden));
      expect(sources, contains((RestrictionId.sesame, ConcernSource.name)));
      // The option's egg comes last; it also reads as not vegan.
      expect(sources, contains((RestrictionId.eggs, ConcernSource.option)));
      expect(sources.last.$2, ConcernSource.option);
      expect(
        sources.indexOf((RestrictionId.eggs, ConcernSource.option)),
        greaterThan(
          sources.indexOf((RestrictionId.sesame, ConcernSource.name)),
        ),
      );
    });

    test('the result is unmodifiable', () {
      // Arrange
      final concerns = ClassificationRules.allergenConcerns(_dish('Egg'));

      // Act / Assert
      expect(() => concerns.add(concerns.first), throwsUnsupportedError);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/utils/allergens/taxonomy.dart';

/// A citation of the allergen documentation: file 11 or 12 and a section,
/// file 02, or (for keto alone, which no research file covers) the epic's
/// own ALG-01 section in file 10.
final RegExp _citation = RegExp(r'^(1[12] §\d+(\.\d+)?|02 §|10 §ALG-\d+)');

void main() {
  group('restrictionTaxonomy', () {
    test('has one entry per id, in RestrictionId order', () {
      expect(
        restrictionTaxonomy.map((entry) => entry.id).toList(),
        RestrictionId.values,
      );
    });

    test('restrictionFor answers each id with its own entry', () {
      for (final id in RestrictionId.values) {
        expect(restrictionFor(id).id, id);
      }
    });

    test('strictness: allergens and celiac are strict, the rest are not', () {
      // Arrange
      const flexible = <RestrictionId>{
        RestrictionId.lactose,
        RestrictionId.fodmap,
        RestrictionId.histamine,
        RestrictionId.vegan,
        RestrictionId.vegetarian,
        RestrictionId.glp1,
        RestrictionId.keto,
      };

      // Assert
      for (final entry in restrictionTaxonomy) {
        expect(
          entry.isStrict,
          !flexible.contains(entry.id),
          reason: entry.id.name,
        );
      }
    });

    test('gluten is celiac (autoimmune, strict), distinct from wheat', () {
      // Act
      final gluten = restrictionFor(RestrictionId.gluten);
      final wheat = restrictionFor(RestrictionId.wheat);

      // Assert
      expect(gluten.kind, RestrictionKind.autoimmune);
      expect(gluten.isStrict, isTrue);
      expect(wheat.kind, RestrictionKind.allergen);
    });

    test('lactose is an intolerance and not strict; milk is the allergy', () {
      expect(
        restrictionFor(RestrictionId.lactose).kind,
        RestrictionKind.intolerance,
      );
      expect(restrictionFor(RestrictionId.lactose).isStrict, isFalse);
      expect(restrictionFor(RestrictionId.milk).isStrict, isTrue);
    });

    test('vegan and vegetarian are lifestyle; keto is keto', () {
      expect(
        restrictionFor(RestrictionId.vegan).kind,
        RestrictionKind.lifestyle,
      );
      expect(
        restrictionFor(RestrictionId.vegetarian).kind,
        RestrictionKind.lifestyle,
      );
      expect(restrictionFor(RestrictionId.keto).kind, RestrictionKind.keto);
    });

    test('the US list is the Codex eight plus sesame (file 02)', () {
      // Arrange
      const us9 = <RestrictionId>{
        RestrictionId.peanuts,
        RestrictionId.treeNuts,
        RestrictionId.milk,
        RestrictionId.eggs,
        RestrictionId.soy,
        RestrictionId.wheat,
        RestrictionId.fish,
        RestrictionId.crustaceans,
        RestrictionId.sesame,
      };

      // Act
      final regulated = <RestrictionId>{
        for (final entry in restrictionTaxonomy)
          if (entry.jurisdictions.contains(Jurisdiction.us)) entry.id,
      };

      // Assert
      expect(regulated, us9);
    });

    test('the EU, UK and Israel lists are the same 14 (gluten cereals as '
        'wheat and gluten)', () {
      // Arrange
      const eu14 = <RestrictionId>{
        RestrictionId.peanuts,
        RestrictionId.treeNuts,
        RestrictionId.milk,
        RestrictionId.eggs,
        RestrictionId.soy,
        RestrictionId.wheat,
        RestrictionId.gluten,
        RestrictionId.fish,
        RestrictionId.crustaceans,
        RestrictionId.molluscs,
        RestrictionId.sesame,
        RestrictionId.celery,
        RestrictionId.mustard,
        RestrictionId.lupin,
        RestrictionId.sulphites,
      };

      // Assert
      for (final jurisdiction in <Jurisdiction>[
        Jurisdiction.eu,
        Jurisdiction.uk,
        Jurisdiction.il,
      ]) {
        expect(
          <RestrictionId>{
            for (final entry in restrictionTaxonomy)
              if (entry.jurisdictions.contains(jurisdiction)) entry.id,
          },
          eu14,
          reason: jurisdiction.name,
        );
      }
    });

    test('Japan lists only its mandatory items: milk, eggs, wheat, '
        'peanuts, shrimp and crab, walnut and cashew (checked 2026-10-19; '
        'buckwheat has no id)', () {
      // Arrange
      const japan = <RestrictionId>{
        RestrictionId.peanuts,
        RestrictionId.treeNuts,
        RestrictionId.milk,
        RestrictionId.eggs,
        RestrictionId.wheat,
        RestrictionId.crustaceans,
      };

      // Act
      final regulated = <RestrictionId>{
        for (final entry in restrictionTaxonomy)
          if (entry.jurisdictions.contains(Jurisdiction.jp)) entry.id,
      };

      // Assert: soy, sesame, fish and molluscs are only recommended there.
      expect(regulated, japan);
    });

    test('Canada and Australia / New Zealand: the Codex eight, sesame and '
        'their own additions, gluten in both (checked 2026-10-19)', () {
      // Arrange
      const codexAndSesame = <RestrictionId>{
        RestrictionId.peanuts,
        RestrictionId.treeNuts,
        RestrictionId.milk,
        RestrictionId.eggs,
        RestrictionId.soy,
        RestrictionId.wheat,
        RestrictionId.fish,
        RestrictionId.crustaceans,
        RestrictionId.sesame,
        RestrictionId.gluten,
        RestrictionId.molluscs,
        RestrictionId.sulphites,
      };
      Set<RestrictionId> listedIn(Jurisdiction jurisdiction) => <RestrictionId>{
        for (final entry in restrictionTaxonomy)
          if (entry.jurisdictions.contains(jurisdiction)) entry.id,
      };

      // Assert
      expect(listedIn(Jurisdiction.ca), <RestrictionId>{
        ...codexAndSesame,
        RestrictionId.mustard,
      });
      expect(listedIn(Jurisdiction.anz), <RestrictionId>{
        ...codexAndSesame,
        RestrictionId.lupin,
      });
    });

    test('sesame is regulated in the US and the EU', () {
      final sesame = restrictionFor(RestrictionId.sesame);
      expect(sesame.jurisdictions, contains(Jurisdiction.us));
      expect(sesame.jurisdictions, contains(Jurisdiction.eu));
    });

    test('legumes, lactose, the diets and the ALG-17 restrictions are '
        'regulated nowhere', () {
      for (final id in <RestrictionId>[
        RestrictionId.legumes,
        RestrictionId.alphaGal,
        RestrictionId.fodmap,
        RestrictionId.histamine,
        RestrictionId.glp1,
        RestrictionId.custom,
        RestrictionId.lactose,
        RestrictionId.vegan,
        RestrictionId.vegetarian,
        RestrictionId.keto,
      ]) {
        expect(restrictionFor(id).jurisdictions, isEmpty, reason: id.name);
      }
    });

    test('every entry has both names, Hebrew written in Hebrew', () {
      final hebrewLetter = RegExp('[א-ת]');
      for (final entry in restrictionTaxonomy) {
        expect(entry.nameEn.trim(), isNotEmpty, reason: entry.id.name);
        expect(hebrewLetter.hasMatch(entry.nameHe), isTrue);
      }
    });

    test('every source cites the allergen documentation', () {
      for (final entry in restrictionTaxonomy) {
        expect(entry.source, matches(_citation), reason: entry.id.name);
      }
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/utils/allergens/taxonomy.dart';

/// A citation of the allergen documentation: file 11 or 12 and a section,
/// file 02 or 03 and a heading, or (for keto alone, which no research file
/// covers) the epic's own ALG-01 section in file 10.
final RegExp _citation = RegExp(r'^(1[12] §\d+(\.\d+)?|0[23] §\S|10 §ALG-\d+)');

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

    test('strictness: allergens, celiac and fava are strict, the rest are '
        'not', () {
      // Arrange
      const flexible = <RestrictionId>{
        RestrictionId.lactose,
        RestrictionId.fodmap,
        RestrictionId.histamine,
        RestrictionId.vegan,
        RestrictionId.vegetarian,
        RestrictionId.glp1,
        RestrictionId.kosher,
        RestrictionId.halal,
        RestrictionId.nightshades,
        RestrictionId.msg,
        RestrictionId.caffeine,
        RestrictionId.salicylates,
        RestrictionId.oralAllergy,
        RestrictionId.pescatarian,
        RestrictionId.paleo,
        RestrictionId.whole30,
        RestrictionId.aip,
        RestrictionId.jain,
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
        'peanuts, shrimp and crab, buckwheat, walnut and cashew (checked '
        '2026-10-19)', () {
      // Arrange
      const japan = <RestrictionId>{
        RestrictionId.peanuts,
        RestrictionId.treeNuts,
        RestrictionId.milk,
        RestrictionId.eggs,
        RestrictionId.wheat,
        RestrictionId.crustaceans,
        RestrictionId.buckwheat,
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

    test('legumes, lactose, the diets, the ALG-17 restrictions and the '
        'research restrictions but buckwheat are regulated nowhere', () {
      for (final id in <RestrictionId>[
        for (final id in RestrictionId.values)
          if (id.index > RestrictionId.buckwheat.index &&
              id.index < RestrictionId.keto.index)
            id,
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

    test('the heads-up restrictions are FODMAP, histamine, small portions '
        'and the five research sensitivities, none of them strict', () {
      expect(headsUpRestrictions, <RestrictionId>{
        RestrictionId.fodmap,
        RestrictionId.histamine,
        RestrictionId.glp1,
        RestrictionId.nightshades,
        RestrictionId.msg,
        RestrictionId.caffeine,
        RestrictionId.salicylates,
        RestrictionId.oralAllergy,
      });
      for (final id in headsUpRestrictions) {
        expect(restrictionFor(id).isStrict, isFalse, reason: id.name);
      }
    });

    test('fava is a medical condition (G6PD), strict, and not an allergen; '
        "Israel's fava marking is no allergen list", () {
      final fava = restrictionFor(RestrictionId.fava);
      expect(fava.kind, RestrictionKind.medical);
      expect(fava.isStrict, isTrue);
      expect(fava.jurisdictions, isEmpty);
      expect(restrictionParent, isNot(contains(RestrictionId.fava)));
    });

    test('each single legume is an allergen under legumes', () {
      expect(restrictionParent, <RestrictionId, RestrictionId>{
        RestrictionId.chickpea: RestrictionId.legumes,
        RestrictionId.lentil: RestrictionId.legumes,
        RestrictionId.pea: RestrictionId.legumes,
        RestrictionId.fenugreek: RestrictionId.legumes,
      });
      for (final MapEntry(key: child, value: parent)
          in restrictionParent.entries) {
        expect(
          restrictionFor(child).kind,
          restrictionFor(parent).kind,
          reason: child.name,
        );
      }
    });

    test("Japan's recommended-only foods carry no jurisdiction (jp is the "
        'mandatory list) and are allergens', () {
      expect(japanRecommendedOnly, hasLength(10));
      for (final id in japanRecommendedOnly) {
        final restriction = restrictionFor(id);
        expect(restriction.jurisdictions, isEmpty, reason: id.name);
        expect(restriction.kind, RestrictionKind.allergen, reason: id.name);
      }
    });

    test('the research diets: four lifestyles and Jain, a religious '
        'component', () {
      for (final id in <RestrictionId>[
        RestrictionId.pescatarian,
        RestrictionId.paleo,
        RestrictionId.whole30,
        RestrictionId.aip,
      ]) {
        expect(restrictionFor(id).kind, RestrictionKind.lifestyle);
      }
      expect(
        restrictionFor(RestrictionId.jain).kind,
        RestrictionKind.religiousComponent,
      );
    });

    test('every source cites the allergen documentation', () {
      for (final entry in restrictionTaxonomy) {
        expect(entry.source, matches(_citation), reason: entry.id.name);
      }
    });
  });
}

// The small-portions tag (Banto; ALG-17's GLP-1 follow-up, issue #359):
// "protein-forward" from the model's extraction roles, or from the dish's
// name where no model listed them, and "small portion" from the menu's
// words. A tag only: the evaluator, the state and the wire never see it.
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/concern.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/utils/allergens/glp1_tag.dart';

/// A dish named [name], described as [description].
Dish _dish(String name, {String description = ''}) => Dish(
  id: 'd',
  name: name,
  description: description,
  price: 10,
  options: const <DishOption>[],
);

/// A model analysis of [dish] listing [ingredients].
AnalysedDish _analysed(Dish dish, List<ExtractedIngredient> ingredients) =>
    AnalysedDish(
      dishId: dish.id,
      name: dish.name,
      verdict: DishVerdict.orderAsIs,
      why: 'why',
      ingredients: ingredients,
    );

/// One ingredient.
ExtractedIngredient _ingredient(
  String name,
  ComponentRole role, {
  Certainty certainty = Certainty.stated,
}) => ExtractedIngredient(name: name, certainty: certainty, role: role);

void main() {
  group('protein-forward from the extraction roles', () {
    final dish = _dish('House plate');

    for (final (label, ingredients, expected)
        in <(String, List<ExtractedIngredient>, bool)>[
          (
            'a protein and a salad base',
            [
              _ingredient('grilled chicken', ComponentRole.protein),
              _ingredient('lettuce', ComponentRole.base),
              _ingredient('fries', ComponentRole.side),
            ],
            true,
          ),
          (
            'a protein on a pasta base',
            [
              _ingredient('chicken', ComponentRole.protein),
              _ingredient('pasta', ComponentRole.base),
            ],
            false,
          ),
          (
            'a protein in a pita base',
            [
              _ingredient('שווארמה', ComponentRole.protein),
              _ingredient('פיתה', ComponentRole.base),
            ],
            false,
          ),
          (
            'only a suspected protein',
            [
              _ingredient(
                'egg',
                ComponentRole.protein,
                certainty: Certainty.suspected,
              ),
            ],
            false,
          ),
          (
            'a suspected carb base does not withhold it',
            [
              _ingredient('salmon', ComponentRole.protein),
              _ingredient(
                'rice',
                ComponentRole.base,
                certainty: Certainty.suspected,
              ),
            ],
            true,
          ),
          (
            'no protein at all',
            [_ingredient('tomato', ComponentRole.base)],
            false,
          ),
        ]) {
      test(label, () {
        expect(
          Glp1Tags.of(dish, _analysed(dish, ingredients)).proteinForward,
          expected,
        );
      });
    }

    test('the roles win over the name when the model listed them', () {
      final named = _dish('Chicken pasta');

      final tag = Glp1Tags.of(
        named,
        _analysed(named, [_ingredient('pasta', ComponentRole.base)]),
      );

      expect(tag.proteinForward, isFalse);
    });
  });

  group('protein-forward by the rules, where no model listed ingredients', () {
    for (final (name, expected) in <(String, bool)>[
      ('Grilled salmon', true),
      ('Entrecote steak with fries', true),
      ('שיפודי עוף', true),
      ('החביתה של הבית', true),
      ('Chicken pasta', false),
      ('Pizza margherita', false),
      ('Tomato salad', false),
      ('Falafel plate', false),
    ]) {
      test('"$name" is ${expected ? '' : 'not '}protein-forward', () {
        expect(Glp1Tags.of(_dish(name), null).proteinForward, expected);
      });
    }

    test('an analysis with an empty extraction reads as the rules', () {
      final dish = _dish('Grilled salmon');

      expect(
        Glp1Tags.of(dish, _analysed(dish, const [])).proteinForward,
        isTrue,
      );
    });
  });

  group('small portion from the menu words', () {
    test('the name, the description or the heading can say it', () {
      expect(Glp1Tags.of(_dish('Mini sliders'), null).smallPortion, isTrue);
      expect(
        Glp1Tags.of(
          _dish('Soup', description: 'A half portion'),
          null,
        ).smallPortion,
        isTrue,
      );
      expect(
        Glp1Tags.of(_dish('Soup'), null, heading: 'Starters').smallPortion,
        isTrue,
      );
      expect(
        Glp1Tags.of(_dish('מרק'), null, heading: 'ראשונות').smallPortion,
        isTrue,
      );
      expect(Glp1Tags.of(_dish('סלט קטן'), null).smallPortion, isTrue);
    });

    test('a large word in the dish withholds it', () {
      expect(
        Glp1Tags.of(
          _dish('Sharing platter'),
          null,
          heading: 'Starters',
        ).smallPortion,
        isFalse,
      );
      expect(Glp1Tags.of(_dish('סלט קטן כפול'), null).smallPortion, isFalse);
    });

    test('nothing said is nothing tagged', () {
      final tag = Glp1Tags.of(_dish('Soup'), null, heading: 'Mains');

      expect(tag.smallPortion, isFalse);
      expect(tag, Glp1Tag.none);
      expect(tag.isEmpty, isTrue);
    });

    test('a bare "מיני" (kinds of) is not small', () {
      expect(Glp1Tags.of(_dish('מיני מאפים'), null).smallPortion, isFalse);
    });
  });

  group('Glp1Tag', () {
    test('value semantics', () {
      const both = Glp1Tag(proteinForward: true, smallPortion: true);

      expect(both, const Glp1Tag(proteinForward: true, smallPortion: true));
      expect(
        both.hashCode,
        const Glp1Tag(proteinForward: true, smallPortion: true).hashCode,
      );
      expect(both, isNot(Glp1Tag.none));
      expect(both.isEmpty, isFalse);
      expect(both.toString(), contains('smallPortion: true'));
    });
  });
}

/// The rule engine on dishes found mis-classified on real Wolt menus
/// (issues #469, #470, #473, #276): desserts and sweets, sushi rolls, a
/// pasta listed by its sauce, and a starch named alone.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/utils/classification_rules.dart';
import 'package:ketoclub/utils/constants.dart';

/// Asserts [result] is green: no base and no waiter sentence.
void _expectGreen(RuleMatch result) {
  expect(result.isNonKeto, isFalse, reason: '$result');
  expect(result.instructions, isEmpty, reason: '$result');
}

/// Asserts [result] is red, labelled [label] when one is given.
void _expectRed(RuleMatch result, {String? label}) {
  expect(result.isNonKeto, isTrue, reason: '$result');
  if (label != null) expect(result.baseLabel, label);
}

/// Asserts [result] is yellow with exactly [sentences].
void _expectYellow(RuleMatch result, List<String?> sentences) {
  expect(result.isNonKeto, isFalse, reason: '$result');
  expect(result.instructions, sentences);
}

/// A dish with [name], an optional [description] and [options].
Dish _dish(
  String name, {
  String description = '',
  List<DishOption> options = const [],
}) => Dish(
  id: 'd',
  name: name,
  description: description,
  price: 10,
  options: options,
);

void main() {
  group('desserts and sweets (issue #469)', () {
    test('every dessert word is red, named alone', () {
      for (final name in [
        'טבלת שוקולד חלב וקרמל מלוח',
        'בר שוקולד דובאי',
        'ממרח שוקולד VEGO',
        'קרם שוקולד',
        'וולקנו שוקולד חם',
        'כדורי שוקולד של פעם',
        "פאדג' שוקולד | קוטר 26 ס״מ",
        'מארז סוכריות גומי',
        'מארז טראפלס',
        'ספיישל פחזניות טופי מיסו',
        'בוואריה שנות ה80׳',
        'קדאיף חלבי',
        'מארז שערות קדאיף',
        'תוספת גביע',
        "מארז גביעים - 5 יח'",
        'ביסקיט תרד עלומות',
        'זיווה גבינות',
        'מלוואח במילוי שוקולד',
        'חלת בצל',
        "בן אנד ג'ריס פיינט (500 מל') - וניל",
        'סופגניות ריבה',
        'פרלינים',
        'מוס שוקולד',
        'פוקאצ׳ה',
        'Chocolate fudge',
        'Panna cotta',
        'Profiteroles',
        'Gummy candy',
        'Chocolate truffles',
        'Chocolate mousse',
        'Pralines',
      ]) {
        _expectRed(ClassificationRules.matchDish(_dish(name)));
      }
    });

    test('a mousse in the description is red', () {
      _expectRed(
        ClassificationRules.matchDish(
          _dish('שביל האבנים הצהובות', description: 'פנקוטה וניל, מוס מנגו'),
        ),
      );
    });

    test('sugar-free, keto or dark chocolate is not candy', () {
      _expectGreen(ClassificationRules.match('שוקולד מריר 85%'));
      _expectGreen(ClassificationRules.match('שוקולד ללא סוכר'));
      _expectGreen(ClassificationRules.match('Sugar-free chocolate'));
      _expectGreen(ClassificationRules.match('Dark chocolate, 85%'));
    });

    test('a chocolate sauce on a protein is a yellow, not a red', () {
      _expectYellow(ClassificationRules.match('Steak with chocolate sauce'), [
        carbModifiersEn['chocolate sauce'],
      ]);
      _expectYellow(ClassificationRules.match('סטייק ברוטב שוקולד'), [
        carbModifiersHe['רוטב שוקולד'],
      ]);
    });

    test('a savoury mousse is not a dessert', () {
      _expectGreen(ClassificationRules.match('Chicken liver mousse'));
      _expectGreen(ClassificationRules.match('מוס כבד עוף'));
    });

    test('a truffle on its own is a mushroom', () {
      _expectGreen(ClassificationRules.match('Steak with truffle butter'));
    });
  });

  group('sushi rolls (issue #470)', () {
    test('maki, temaki, inside-out, nigiri and named rolls are red for '
        'their rice', () {
      for (final name in [
        'ניגירי סלמון ללא גלוטן',
        'מאקי טונה אדומה ובצל ירוק ללא גלוטן',
        'טמאקי סלמון אבוקדו ללא גלוטן',
        'גרין רול ללא גלוטן',
        'מאקי אבוקדו 🌱',
        'אוממי רול',
        'אינסייד אווט טונה אבוקדו',
        'אינסייד אאוט סלמון',
        'קליפורניה רול',
      ]) {
        _expectRed(
          ClassificationRules.matchDish(_dish(name)),
          label: 'אורז סושי',
        );
      }
      for (final name in [
        'Salmon maki',
        'Salmon temaki',
        'Spicy tuna sushi roll',
        'California roll',
        'Uramaki',
      ]) {
        _expectRed(
          ClassificationRules.matchDish(_dish(name)),
          label: 'sushi rice',
        );
      }
    });

    test('a roll is red whatever its options say', () {
      _expectRed(
        ClassificationRules.matchDish(
          _dish(
            'מאקי אבוקדו',
            options: const [
              DishOption(name: 'תוספות', values: ['גזר', 'בטטה']),
            ],
          ),
        ),
        label: 'אורז סושי',
      );
    });

    test('sashimi and riceless rolls are not reddened', () {
      _expectGreen(ClassificationRules.match('סשימי סלמון'));
      _expectGreen(ClassificationRules.match('Salmon sashimi'));
      _expectGreen(ClassificationRules.match('נארוטו רול סלמון'));
      _expectGreen(ClassificationRules.match('רול סלמון ללא אורז'));
      _expectGreen(ClassificationRules.match('Naruto sushi roll'));
    });

    test('a spring roll or a cinnamon roll is red for itself', () {
      _expectRed(
        ClassificationRules.match('ספרינג רול ירקות'),
        label: 'ספרינג רול',
      );
      _expectRed(ClassificationRules.match('רול קינמון'), label: 'רול קינמון');
      _expectRed(
        ClassificationRules.match('Vegetable spring rolls'),
        label: 'spring roll',
      );
    });

    test('a bread roll is not sushi', () {
      _expectGreen(ClassificationRules.match('Lobster roll'));
    });
  });

  group('a pasta listed by its sauce (issue #473)', () {
    test('a choice of pasta is what the dish is made of', () {
      _expectRed(
        ClassificationRules.matchDish(
          _dish(
            'רוזה',
            description: 'עגבניות ושמנת',
            options: const [
              DishOption(name: 'בחרו סוג פסטה', values: ['פנה']),
            ],
          ),
        ),
        label: 'פסטה',
      );
      _expectRed(
        ClassificationRules.matchDish(
          _dish(
            'בולונז',
            description: 'בקר טחון שבושל ביין אדום וירקות שורש, רוטב עגבניות',
            options: const [
              DishOption(
                name: 'בחר סוג פסטה',
                values: ['רדיאטורי', 'בומבטי', 'בומבטי סלק'],
              ),
            ],
          ),
        ),
        label: 'פסטה',
      );
      _expectRed(
        ClassificationRules.matchDish(
          _dish(
            'Bolognese',
            options: const [
              DishOption(name: 'Choose your pasta', values: ['Penne']),
            ],
          ),
        ),
        label: 'pasta',
      );
    });

    test('a choice that offers a keto pasta is a yellow', () {
      _expectYellow(
        ClassificationRules.matchDish(
          _dish(
            'רוזה',
            options: const [
              DishOption(name: 'בחרו סוג פסטה', values: ['פנה', 'קישואים']),
            ],
          ),
        ),
        [optionBaseModificationHe.replaceAll('{base}', 'פסטה')],
      );
      _expectYellow(
        ClassificationRules.matchDish(
          _dish(
            'Bolognese',
            options: const [
              DishOption(
                name: 'Choose your noodles',
                values: ['Egg noodles', 'Zucchini noodles'],
              ),
            ],
          ),
        ),
        [optionBaseModificationEn.replaceAll('{base}', 'noodles')],
      );
    });

    test('a side choice that lists pasta stays the #192 yellow', () {
      _expectYellow(
        ClassificationRules.matchDish(
          _dish(
            'עוף צלוי',
            options: const [
              DishOption(name: 'תוספת לבחירה', values: ['פסטה', 'סלט']),
            ],
          ),
        ),
        [optionBaseModificationHe.replaceAll('{base}', 'פסטה')],
      );
      expect(
        ClassificationRules.doughChoiceBase(
          _dish(
            'Steak',
            options: const [
              DishOption(name: 'Add pasta', values: ['Penne']),
            ],
          ),
        ),
        isNull,
      );
    });
  });

  group('a starch named alone (issue #276)', () {
    test('is red whatever its description says', () {
      _expectRed(
        ClassificationRules.matchDish(
          _dish('Rice', description: 'Basmati rice with herbs'),
        ),
        label: 'rice',
      );
      _expectRed(
        ClassificationRules.matchDish(
          _dish('פירה', description: 'פירה עם חמאה ושמנת'),
        ),
        label: 'פירה',
      );
      _expectRed(
        ClassificationRules.matchDish(
          _dish('Fries', description: 'With cheddar cheese and jalapeño'),
        ),
        label: 'fries',
      );
    });

    test('garlic bread is the bread', () {
      _expectRed(
        ClassificationRules.matchDish(_dish('Garlic bread')),
        label: 'bread',
      );
      _expectRed(
        ClassificationRules.matchDish(
          _dish('Garlic bread', description: 'Baguette with butter and garlic'),
        ),
        label: 'bread',
      );
      _expectRed(
        ClassificationRules.matchDish(
          _dish('פיתה', description: 'שמן זית וזעתר'),
        ),
        label: 'פיתה',
      );
    });

    test('a starch with a protein, and a filled bread, stay yellow', () {
      _expectYellow(
        ClassificationRules.matchDish(
          _dish('Rice bowl', description: 'Grilled chicken, vegetables'),
        ),
        [carbModifiersEn['rice']],
      );
      _expectYellow(ClassificationRules.matchDish(_dish('Steak with rice')), [
        carbModifiersEn['rice'],
      ]);
      _expectYellow(
        ClassificationRules.matchDish(
          _dish('לאפה', description: 'שווארמה, חומוס וסלט'),
        ),
        [carbModifiersHe['לאפה'], carbModifiersHe['חומוס']],
      );
    });
  });
}

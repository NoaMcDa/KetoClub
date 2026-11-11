// Tests for dough as a non-keto base and for a choice-of-dough option
// group.
//
// A Domino's venue on Wolt (`dominos-pizza-ashdod-city`) showed "29 dishes
// as-is" on its Discovery card. Fourteen of them were pizzas the menu
// names by their topping mix ("בקרנה MIX משפחתית") and describes by their
// toppings; the only text that says "pizza" is the option group "בחרו סוג
// בצק". The rest were dough sticks and fingers whose description says
// "בצק", a cake and ice creams written in the construct form ("עוגת
// שוקולד", "גלידת וניל"), and dips counted as food. The dish shapes below
// are the real ones, trimmed.

import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/utils/classification_rules.dart';
import 'package:ketoclub/utils/constants.dart';

Dish _dish({
  required String name,
  String description = '',
  List<DishOption> options = const <DishOption>[],
}) => Dish(
  id: 'd',
  name: name,
  description: description,
  price: 10,
  options: options,
);

/// The option-base sentence for a Hebrew [base].
String _skipHe(String base) =>
    optionBaseModificationHe.replaceAll('{base}', base);

void main() {
  group('ClassificationRules.matchDish — a choice of dough', () {
    test('a family pizza named by its topping mix is red: only "בחרו סוג '
        'בצק" says it is a pizza', () {
      // Arrange: "בקרנה MIX משפחתית", as Wolt lists it.
      final pizza = _dish(
        name: '\u202Bבקרנה MIX משפחתית',
        description:
            "פרוסות חזה בקר, כדורי בייבי מוצרלה, גבינת פרמז'ן גרנה פדנו "
            'וגבינת מוצרלה משובחת\n\nהתמונה להמחשה בלבד*',
        options: const <DishOption>[
          DishOption(
            name: '\u202Bבחרו סוג בצק - MIX',
            values: <String>[
              'בצק קלאסי',
              'בצק קלאסי דק',
              'בצק קלאסי בלי הקשה',
              'צ׳יזי קראסט מוצרלה',
              'צ׳יזי קראסט מוצרלה ופסטו',
            ],
          ),
        ],
      );
      // Act
      final result = ClassificationRules.matchDish(pizza);
      // Assert
      expect(result.isNonKeto, isTrue);
      expect(result.baseLabel, 'בצק');
      expect(result.instructions, isEmpty);
      expect(ClassificationRules.doughChoiceBase(pizza), 'בצק');
    });

    test('a personal pizza is red through "בצק - אישית"', () {
      // Arrange: "גריק MIX אישית".
      final pizza = _dish(
        name: '\u202Bגריק MIX אישית',
        description:
            'קוביות עגבניות, בצל סגול, זיתי קלמטה וגבינה בולגרית. '
            'שמנו מעל: אורגנו',
        options: const <DishOption>[
          DishOption(name: 'בצק - אישית', values: <String>['בצק קלאסי']),
        ],
      );
      // Act
      final result = ClassificationRules.matchDish(pizza);
      // Assert
      expect(result.isNonKeto, isTrue);
      expect(result.baseLabel, 'בצק');
    });

    test('a gluten-free dough among the choices rescues nothing', () {
      // Arrange
      final pizza = _dish(
        name: 'משפחתית יוונית',
        options: const <DishOption>[
          DishOption(
            name: 'בחרו סוג בצק',
            values: <String>['בצק קלאסי', '\u202Bבצק ללא גלוטן  \u{1F33E}'],
          ),
        ],
      );
      // Act
      final result = ClassificationRules.matchDish(pizza);
      // Assert
      expect(result.isNonKeto, isTrue);
      expect(result.baseLabel, 'בצק');
    });

    test('a group that offers a cauliflower dough is a yellow, not a '
        'red', () {
      // Arrange
      final named = _dish(
        name: 'משפחתית יוונית',
        options: const <DishOption>[
          DishOption(
            name: 'בחרו סוג בצק',
            values: <String>['בצק קלאסי', 'בצק כרובית'],
          ),
        ],
      );
      final bare = _dish(
        name: 'משפחתית יוונית',
        options: const <DishOption>[
          DishOption(name: 'בחרו סוג בצק', values: <String>['קלאסי', 'כרובית']),
        ],
      );
      // Act
      final namedResult = ClassificationRules.matchDish(named);
      final bareResult = ClassificationRules.matchDish(bare);
      // Assert
      expect(ClassificationRules.doughChoiceBase(named), isNull);
      expect(namedResult.isNonKeto, isFalse);
      expect(namedResult.instructions, equals([_skipHe('בצק')]));
      expect(ClassificationRules.doughChoiceBase(bare), isNull);
      expect(bareResult.isNonKeto, isFalse);
      expect(bareResult.instructions, equals([_skipHe('בצק')]));
    });

    test('a removal value never counts as the rescued dough', () {
      // Arrange: "ללא גלוטן" begins with a removal word and is skipped;
      // nothing else in the group is a keto dough.
      final pizza = _dish(
        name: 'משפחתית יוונית',
        options: const <DishOption>[
          DishOption(
            name: 'בחרו סוג בצק',
            values: <String>['קלאסי', 'דק', 'ללא גלוטן'],
          ),
        ],
      );
      // Act
      final result = ClassificationRules.matchDish(pizza);
      // Assert
      expect(result.isNonKeto, isTrue);
    });

    test('a two-pizza deal is red as soon as one dough group offers no '
        'rescued dough', () {
      // Arrange
      final deal = _dish(
        name: '\u202B2 משפחתיות במחיר מיוחד',
        options: const <DishOption>[
          DishOption(
            name: 'בחרו סוג בצק - פיצה #1',
            values: <String>['בצק קלאסי', 'בצק כרובית'],
          ),
          DishOption(
            name: 'בחרו סוג בצק - פיצה #2',
            values: <String>['בצק קלאסי', 'בצק דק'],
          ),
        ],
      );
      // Act
      final result = ClassificationRules.matchDish(deal);
      // Assert
      expect(result.isNonKeto, isTrue);
      expect(result.baseLabel, 'בצק');
    });

    test('a group named for a keto dough is not a choice of dough', () {
      // Arrange
      final pizza = _dish(
        name: 'משפחתית יוונית',
        options: const <DishOption>[
          DishOption(name: 'בחרו בצק קטו', values: <String>['דק', 'עבה']),
        ],
      );
      // Act
      final result = ClassificationRules.matchDish(pizza);
      // Assert
      expect(ClassificationRules.doughChoiceBase(pizza), isNull);
      expect(result.isNonKeto, isFalse);
      expect(result.instructions, isEmpty);
    });

    test('dough offered as an add-on under another heading stays the '
        'issue #192 yellow', () {
      // Arrange: only the group's name can make it a choice of dough.
      final salad = _dish(
        name: 'סלט יווני',
        options: const <DishOption>[
          DishOption(name: 'תרצו משהו נוסף?', values: <String>['מקלות בצק']),
        ],
      );
      // Act
      final result = ClassificationRules.matchDish(salad);
      // Assert
      expect(ClassificationRules.doughChoiceBase(salad), isNull);
      expect(result.isNonKeto, isFalse);
      expect(result.instructions, equals([_skipHe('בצק')]));
    });

    test('an English "Choose your dough" group is red, and a cauliflower '
        'dough among its values makes it a yellow', () {
      // Arrange
      final pizza = _dish(
        name: 'Veggie mix',
        options: const <DishOption>[
          DishOption(name: 'Choose your dough', values: <String>['Classic']),
        ],
      );
      final rescued = _dish(
        name: 'Veggie mix',
        options: const <DishOption>[
          DishOption(
            name: 'Choose your dough',
            values: <String>['Classic', 'Cauliflower dough'],
          ),
        ],
      );
      // Act
      final red = ClassificationRules.matchDish(pizza);
      final yellow = ClassificationRules.matchDish(rescued);
      // Assert
      expect(red.isNonKeto, isTrue);
      expect(red.baseLabel, 'dough');
      expect(yellow.isNonKeto, isFalse);
      expect(
        yellow.instructions,
        equals([optionBaseModificationEn.replaceAll('{base}', 'dough')]),
      );
    });

    test('wings with a choice of sauce stay green', () {
      // Arrange: "דומינו׳ס ווינגס", the one dish of that menu that is
      // plausibly keto as it is.
      final wings = _dish(
        name: 'דומינו׳ס ווינגס',
        description: 'יחידות חצאי כנפיים מעולות ברוטב לבחירה',
        options: const <DishOption>[
          DishOption(
            name: 'בחרו רטבים לכנפיים',
            values: <String>['רוטב סוויט צ׳ילי אריזונה', 'ללא רוטב'],
          ),
        ],
      );
      // Act
      final result = ClassificationRules.matchDish(wings);
      // Assert
      expect(result.isNonKeto, isFalse);
      expect(result.instructions, isEmpty);
    });
  });

  group('ClassificationRules — dough in the dish itself', () {
    const doughDishes = <String, String>{
      'אצבעות מוצרלה': 'אצבעות בצק וגבינה 100% מוצרלה + דיפ עגבניות ושום',
      'מקלות דאבל דיפ מלוח': '8 מקלות בצק בחמאת שום ועשבי תיבול',
      'הוט רולז נקניקיות': '4 נקניקיות בקר עסיסיות עטופות בצק',
      'משפחתית יוונית עבה': 'משפחתית מבצק עבה, עם עגבניות, פטה וזיתים',
      'משפחתית בהרכבה': 'בחרו סוג בצק ותוספות',
      'Garlic Bites': 'כדורי בצק אפויים עם חמאת שום פרמז׳ן',
      'Garlic knots': 'Baked dough balls with garlic butter',
    };
    for (final MapEntry(key: name, value: description) in doughDishes.entries) {
      test('"$name" is red: its description names dough', () {
        // Act
        final result = ClassificationRules.matchDish(
          _dish(name: name, description: description),
        );
        // Assert
        expect(result.isNonKeto, isTrue, reason: description);
        expect(result.baseLabel, anyOf('בצק', 'dough'));
      });
    }

    test('בצק עלים keeps its own label', () {
      // Act
      final result = ClassificationRules.match('מאפה מבצק עלים פריך');
      // Assert: `מאפה` starts first here, so ask for the bare phrase too.
      expect(result.isNonKeto, isTrue);
      expect(ClassificationRules.match('בצק עלים').baseLabel, 'בצק עלים');
    });

    test('a crustless quiche ("ללא בצק") is not red', () {
      // Act
      final result = ClassificationRules.matchDish(
        _dish(name: 'קיש ללא בצק', description: 'ברוקולי, גבינות ושמנת'),
      );
      // Assert
      expect(result.isNonKeto, isFalse);
    });

    test('a removal word after the dough rescues nothing: "בצק ללא '
        'גלוטן" is red', () {
      // Act
      final result = ClassificationRules.match('פוקאצ׳ה מבצק ללא גלוטן');
      // Assert
      expect(result.isNonKeto, isTrue);
    });

    test('a cauliflower, almond or keto dough is not red, in either '
        'language', () {
      // Arrange
      const rescued = <String>[
        'בצק כרובית עם מוצרלה',
        'בצק קמח שקדים',
        'בצק קטו',
        'בצק דל פחמימות',
        'Cauliflower dough with mozzarella',
        'Keto dough',
        'Almond dough',
        'Dough-free bake',
      ];
      // Act, Assert
      for (final text in rescued) {
        expect(
          ClassificationRules.match(text).isNonKeto,
          isFalse,
          reason: text,
        );
      }
    });

    test('sourdough is another word: "Sourdough bun" stays the bun', () {
      // Act
      final result = ClassificationRules.matchDish(
        _dish(name: 'Sourdough bun'),
      );
      // Assert
      expect(result.baseLabel, 'bun');
    });
  });

  group('ClassificationRules.match — construct forms of cake and ice '
      'cream', () {
    const desserts = <String, String>{
      'עוגת שוקולד חמה': 'עוגה',
      'עוגת גבינה פירורים': 'עוגה',
      'עוגות הבית': 'עוגה',
      'גלידת וניל משובחת': 'גלידה',
      'גלידות בטעמים': 'גלידה',
    };
    for (final MapEntry(key: text, value: label) in desserts.entries) {
      test('"$text" is red, read aloud as $label', () {
        // Act
        final result = ClassificationRules.match(text);
        // Assert
        expect(result.isNonKeto, isTrue);
        expect(result.baseLabel, label);
      });
    }
  });
}

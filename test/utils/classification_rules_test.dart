import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/utils/classification_rules.dart';
import 'package:ketoclub/utils/constants.dart';

/// The Hebrew triggers whose pattern deliberately disables the
/// permissive prefix (see `classification_rules.dart`'s
/// `_noPrefixHebrewTriggers`): folded `חלה` also spells a common verb
/// form, and its prefixed form (`החלה`) is itself an ordinary word
/// ("commencement"); `משמרים` is "preservatives"; `הפוך` collides with
/// "to flip" (e.g. `להפוך`); `מחלבה` is "dairy" (issue #273), so `חלבה`
/// and its spelled-out particles are prefix-free too. All of them are
/// excluded from the prefix half of the generated Hebrew trigger tests
/// below.
const Set<String> _noPrefixTriggers = <String>{
  'חלה',
  'שמרים',
  'הפוך',
  'חלבה',
  'וחלבה',
  'בחלבה',
};

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

/// A dish for the name-scoped checks (issues #273, #274).
Dish _dishNamed(String name, {String description = ''}) => Dish(
  id: 'd',
  name: name,
  description: description,
  price: 10,
  options: const [],
);

/// A neutral English wrapper containing no guard vocabulary, so every
/// `carbModifiersEn`/`nonKetoBasesEn` trigger can be dropped in as-is.
String _enText(String trigger) => 'A nice plate with $trigger for dinner';

/// A neutral Hebrew wrapper containing no guard vocabulary, so every
/// `carbModifiersHe`/`nonKetoBasesHe` trigger can be dropped in as-is,
/// bare or with a ה prefix glued directly on.
String _heText(String trigger) => 'מנה טובה עם $trigger להיום';

void main() {
  group('ClassificationRules.match — guards (D-V1)', () {
    test(
      'cauliflower rice is not red and does not carry the rice sentence',
      () {
        // Act
        final result = ClassificationRules.match(
          'Chicken with cauliflower rice',
        );
        // Assert
        expect(result.isNonKeto, isFalse);
        expect(result.instructions, isNot(contains(carbModifiersEn['rice'])));
      },
    );

    test('zucchini noodles is not red', () {
      // Act
      final result = ClassificationRules.match('Zucchini noodles with pesto');
      // Assert
      expect(result.isNonKeto, isFalse);
    });

    test('spaghetti squash is not red', () {
      // Act
      final result = ClassificationRules.match('Roasted spaghetti squash bowl');
      // Assert
      expect(result.isNonKeto, isFalse);
    });

    test('cauliflower pizza is not red', () {
      // Act
      final result = ClassificationRules.match(
        'Cauliflower pizza with veggies',
      );
      // Assert
      expect(result.isNonKeto, isFalse);
    });

    test('kale chips is not yellow (no chips sentence)', () {
      // Act
      final result = ClassificationRules.match('A bowl of kale chips');
      // Assert
      expect(result.instructions, isNot(contains(carbModifiersEn['chips'])));
    });

    test('keto toast is not yellow (no toast sentence)', () {
      // Act
      final result = ClassificationRules.match('Keto toast with avocado');
      // Assert
      expect(result.instructions, isNot(contains(carbModifiersEn['toast'])));
    });

    test('לחם ענן (cloud bread) is not yellow', () {
      // Act
      final result = ClassificationRules.match('לחם ענן עם חמאה');
      // Assert
      expect(result.instructions, isNot(contains(carbModifiersHe['לחם'])));
    });

    test('אורז כרובית (cauliflower rice) is not yellow', () {
      // Act
      final result = ClassificationRules.match('סלט עם אורז כרובית');
      // Assert
      expect(result.instructions, isNot(contains(carbModifiersHe['אורז'])));
    });

    test('פיצה כרובית (cauliflower pizza) is not red', () {
      // Act
      final result = ClassificationRules.match('פיצה כרובית עם גבינה');
      // Assert
      expect(result.isNonKeto, isFalse);
    });

    test('baby corn still matches (corn is deliberately not guarded)', () {
      // Act
      final result = ClassificationRules.match('Salad with baby corn');
      // Assert
      expect(result.instructions, contains(carbModifiersEn['corn']));
    });
  });

  group('ClassificationRules.match — suppression', () {
    test(
      'sweet potato emits one sentence, not the bare potato sentence too',
      () {
        // Act
        final result = ClassificationRules.match('Roasted sweet potato');
        // Assert
        expect(result.instructions, equals([carbModifiersEn['sweet potato']]));
      },
    );

    test("צ'יפס בטטה does not emit three sentences", () {
      // Act
      final result = ClassificationRules.match("צ'יפס בטטה");
      // Assert: chips + sweet potato, not also the bare תפוח אדמה
      // sentence a third time.
      expect(result.instructions, hasLength(2));
      expect(
        result.instructions,
        containsAll([carbModifiersHe["צ'יפס"], carbModifiersHe['בטטה']]),
      );
    });

    test('mashed potatoes does not also emit the bare potato sentence', () {
      // Act
      final result = ClassificationRules.match('A side of mashed potatoes');
      // Assert
      expect(result.instructions, equals([carbModifiersEn['mashed potatoes']]));
    });

    test('date honey does not also emit the bare honey sentence', () {
      // Act
      final result = ClassificationRules.match('Yogurt with date honey');
      // Assert
      expect(result.instructions, equals([carbModifiersEn['date honey']]));
    });

    test('דבש תמרים does not also emit the bare דבש sentence', () {
      // Act
      final result = ClassificationRules.match('יוגורט עם דבש תמרים');
      // Assert: its own sentence fires; the bare דבש sentence is
      // suppressed. (תמרים, "dates", is a separate, unsuppressed
      // trigger that legitimately also fires — "דבש תמרים" literally
      // contains the standalone word "תמרים".)
      expect(result.instructions, contains(carbModifiersHe['דבש תמרים']));
      expect(result.instructions, isNot(contains(carbModifiersHe['דבש'])));
    });
  });

  group('ClassificationRules.match — English word-boundary negatives', () {
    test('price does not match rice', () {
      // Act
      final result = ClassificationRules.match('Ask about the price first');
      // Assert
      expect(result.instructions, isEmpty);
    });

    test('cornichons does not match corn', () {
      // Act
      final result = ClassificationRules.match('Served with cornichons');
      // Assert
      expect(result.instructions, isEmpty);
    });

    test('chipotle does not match chips', () {
      // Act
      final result = ClassificationRules.match('Chipotle mayo on the side');
      // Assert
      expect(result.instructions, isEmpty);
    });

    test('sacramento does not match ramen', () {
      // Act
      final result = ClassificationRules.match('Sacramento tomato salad');
      // Assert
      expect(result.isNonKeto, isFalse);
    });

    test('antipasti does not match pasta', () {
      // Act
      final result = ClassificationRules.match('Antipasti platter to share');
      // Assert
      expect(result.isNonKeto, isFalse);
    });

    test('beetroot does not match bare beets', () {
      // Act
      final result = ClassificationRules.match('Beetroot salad with feta');
      // Assert: beetroot is its own trigger; the *different* "beets"
      // sentence must not also appear.
      expect(result.instructions, isNot(contains(carbModifiersEn['beets'])));
    });

    test('toasted does not match toast', () {
      // Act
      final result = ClassificationRules.match('Toasted almonds on top');
      // Assert
      expect(result.instructions, isEmpty);
    });

    test('pureed does not match puree', () {
      // Act
      final result = ClassificationRules.match('A pureed soup');
      // Assert
      expect(result.instructions, isEmpty);
    });

    test('pennette does not match penne', () {
      // Act
      final result = ClassificationRules.match('Pennette with olive oil');
      // Assert
      expect(result.isNonKeto, isFalse);
    });

    test('honeydew does not match honey', () {
      // Act
      final result = ClassificationRules.match('Honeydew melon slices');
      // Assert
      expect(result.instructions, isEmpty);
    });

    test('sandwiched does not match sandwich', () {
      // Act
      final result = ClassificationRules.match('Cheese sandwiched between');
      // Assert
      expect(result.instructions, isEmpty);
    });
  });

  group('ClassificationRules.match — every carbModifiersEn trigger', () {
    for (final entry in carbModifiersEn.entries) {
      test('"${entry.key}" triggers its waiter sentence', () {
        // Act
        final result = ClassificationRules.match(_enText(entry.key));
        // Assert
        expect(result.isNonKeto, isFalse);
        expect(result.instructions, contains(entry.value));
      });
    }
  });

  group('ClassificationRules.match — every nonKetoBasesEn trigger', () {
    for (final trigger in nonKetoBasesEn) {
      test('"$trigger" is classified red', () {
        // Act
        final result = ClassificationRules.match(_enText(trigger));
        // Assert
        expect(result.isNonKeto, isTrue);
        expect(result.baseLabel, isNotNull);
        expect(result.instructions, isEmpty);
      });
    }
  });

  group('ClassificationRules.match — every carbModifiersHe trigger', () {
    for (final entry in carbModifiersHe.entries) {
      final trigger = entry.key;
      test('"$trigger" triggers its waiter sentence, bare and with a '
          'ב/ה/ו/כ/ל/מ/ש prefix', () {
        // Act
        final bare = ClassificationRules.match(_heText(trigger));
        // Assert
        expect(bare.isNonKeto, isFalse);
        expect(bare.instructions, contains(entry.value));

        if (!_noPrefixTriggers.contains(trigger)) {
          // Act
          final prefixed = ClassificationRules.match(_heText('ה$trigger'));
          // Assert
          expect(prefixed.instructions, contains(entry.value));
        }
      });
    }
  });

  group('ClassificationRules.match — every nonKetoBasesHe trigger', () {
    for (final trigger in nonKetoBasesHe) {
      test('"$trigger" is classified red, bare and with a '
          'ב/ה/ו/כ/ל/מ/ש prefix', () {
        // Act
        final bare = ClassificationRules.match(_heText(trigger));
        // Assert
        expect(bare.isNonKeto, isTrue);
        expect(bare.baseLabel, isNotNull);

        if (!_noPrefixTriggers.contains(trigger)) {
          // Act
          final prefixed = ClassificationRules.match(_heText('ה$trigger'));
          // Assert
          expect(prefixed.isNonKeto, isTrue);
        }
      });
    }

    test('חלה (bare) is classified red', () {
      // Act
      final result = ClassificationRules.match(_heText('חלה'));
      // Assert
      expect(result.isNonKeto, isTrue);
    });

    test('החלה (prefixed) is not classified red — the trap this trigger '
        'is guarding against', () {
      // Act
      final result = ClassificationRules.match(_heText('החלה'));
      // Assert: the strict no-prefix pattern means the prefixed form is
      // simply a different word to this trigger, exactly as intended.
      expect(result.isNonKeto, isFalse);
    });
  });

  group('ClassificationRules.match — nonKetoBaseLabels', () {
    test('noodle base label reads "noodles"', () {
      // Act
      final result = ClassificationRules.match(_enText('noodle'));
      // Assert
      expect(result.baseLabel, equals('noodles'));
    });

    test('battered fish base label names the batter, not the chips', () {
      // Act
      final result = ClassificationRules.match('Fish and chips');
      // Assert
      expect(result.baseLabel, equals('battered fish'));
    });

    test('an unlisted base label defaults to the trigger itself', () {
      // Act
      final result = ClassificationRules.match(_enText('pizza'));
      // Assert
      expect(result.baseLabel, equals('pizza'));
    });

    test('ספאגטי base label reads the canonical ספגטי', () {
      // Act
      final result = ClassificationRules.match(_heText('ספאגטי'));
      // Assert
      expect(result.baseLabel, equals('ספגטי'));
    });

    test('פיצות base label reads the canonical פיצה', () {
      // Act
      final result = ClassificationRules.match(_heText('פיצות'));
      // Assert
      expect(result.baseLabel, equals('פיצה'));
    });
  });

  group('ClassificationRules.match — general behaviour', () {
    test('a plain green dish has no base label and no instructions', () {
      // Act
      final result = ClassificationRules.match('Grilled salmon with butter');
      // Assert
      expect(result.isNonKeto, isFalse);
      expect(result.baseLabel, isNull);
      expect(result.instructions, isEmpty);
    });

    test('a non-keto base wins over a carb modifier in the same text', () {
      // Act
      final result = ClassificationRules.match(
        'Spaghetti with fries on the side',
      );
      // Assert
      expect(result.isNonKeto, isTrue);
      expect(result.instructions, isEmpty);
    });

    test('a mixed-script Israeli dish is matched on both vocabularies', () {
      // Act
      final result = ClassificationRules.match('Beef Burger בלחמנייה');
      // Assert
      expect(result.isNonKeto, isFalse);
      expect(result.instructions, contains(carbModifiersHe['לחמנייה']));
    });

    test('never throws on an empty string', () {
      // Act, Assert
      expect(() => ClassificationRules.match(''), returnsNormally);
    });

    test('never throws on punctuation-only text', () {
      // Act, Assert
      expect(() => ClassificationRules.match('!!! --- ???'), returnsNormally);
    });

    test('never throws on very long text', () {
      // Arrange
      final long = 'salad ' * 5000;
      // Act, Assert
      expect(() => ClassificationRules.match(long), returnsNormally);
    });

    test('a burger on a brioche bun is modifiable, not red (D-V3)', () {
      // Act
      final result = ClassificationRules.match('Beef burger on a brioche bun');

      // Assert: a bare `brioche` red trigger used to hide this dish entirely.
      expect(result.isNonKeto, isFalse);
      expect(result.instructions, isNotEmpty);
    });

    test('fish and chips is red, not a chips swap (D-V2)', () {
      // Act
      final result = ClassificationRules.match('Fish and chips');

      // Assert: the batter cannot be removed, so "replace the chips" would be
      // an instruction that cannot make the dish keto.
      expect(result.isNonKeto, isTrue);
      expect(result.instructions, isEmpty);
    });

    test('potato puree emits one sentence, not two overlapping ones', () {
      // Act
      final result = ClassificationRules.match(
        'Grilled entrecote with potato puree',
      );

      // Assert: `puree` suppresses the generic `potato` sentence.
      expect(result.instructions, hasLength(1));
      expect(result.instructions.single, contains('pur'));
    });
  });

  // Issue #56: the three dietary rules' vocabularies. Every trigger must
  // fire in both wrappers, and every Hebrew one with a prefix glued on
  // too — the unicode-lookaround check that `\b` would silently fail.
  group('ClassificationRules.mentionsSeedOil (issue #56)', () {
    for (final trigger in seedOilTriggersEn) {
      test('"$trigger" is a seed-oil mention', () {
        // Act & Assert
        expect(ClassificationRules.mentionsSeedOil(_enText(trigger)), isTrue);
      });
    }

    for (final trigger in seedOilTriggersHe) {
      test('"$trigger" is a seed-oil mention, bare and with a prefix', () {
        // Act & Assert
        expect(ClassificationRules.mentionsSeedOil(_heText(trigger)), isTrue);
        expect(
          ClassificationRules.mentionsSeedOil(_heText('ה$trigger')),
          isTrue,
        );
      });
    }

    for (final text in <String>[
      'Salmon with soy sauce',
      'Salad with sunflower seeds',
      'Grilled steak with olive oil',
      'סלמון ברוטב סויה',
      'סטייק צלוי בשמן זית',
    ]) {
      test('"$text" is not a seed-oil mention', () {
        // Act & Assert
        expect(ClassificationRules.mentionsSeedOil(text), isFalse);
      });
    }
  });

  group('ClassificationRules.mentionsDairy (issue #56)', () {
    for (final trigger in dairyTriggersEn) {
      test('"$trigger" is a dairy mention', () {
        // Act & Assert
        expect(ClassificationRules.mentionsDairy(_enText(trigger)), isTrue);
      });
    }

    for (final trigger in dairyTriggersHe) {
      test('"$trigger" is a dairy mention, bare and with a prefix', () {
        // Act & Assert
        expect(ClassificationRules.mentionsDairy(_heText(trigger)), isTrue);
        expect(ClassificationRules.mentionsDairy(_heText('ה$trigger')), isTrue);
      });
    }

    for (final text in <String>[
      'Chicken curry in coconut cream',
      'Chia pudding with almond milk',
      'Celery with peanut butter',
      'Tomato salad with vegan cheese',
      'Beef carpaccio with balsamic cream',
      'עוף בחלב קוקוס',
      'סלרי עם חמאת בוטנים',
      'סלט עם גבינה טבעונית',
      'קרפצ׳יו עם קרם בלסמי',
      'שייק חלבון',
    ]) {
      test('"$text" is not a dairy mention', () {
        // Act & Assert
        expect(ClassificationRules.mentionsDairy(text), isFalse);
      });
    }
  });

  group('ClassificationRules.mentionsPlant (issue #56)', () {
    for (final trigger in plantTriggersEn) {
      test('"$trigger" is a plant mention', () {
        // Act & Assert
        expect(ClassificationRules.mentionsPlant(_enText(trigger)), isTrue);
      });
    }

    for (final trigger in plantTriggersHe) {
      test('"$trigger" is a plant mention, bare and with a prefix', () {
        // Act & Assert
        expect(ClassificationRules.mentionsPlant(_heText(trigger)), isTrue);
        expect(ClassificationRules.mentionsPlant(_heText('ה$trigger')), isTrue);
      });
    }

    for (final text in <String>[
      'Ribeye steak with black pepper',
      'Scrambled eggs with butter',
      'אנטריקוט עם פלפל שחור',
      'חביתה מביצים',
    ]) {
      test('"$text" is not a plant mention', () {
        // Act & Assert
        expect(ClassificationRules.mentionsPlant(text), isFalse);
      });
    }
  });

  group('ClassificationRules.carbOnlyBase (issue #191)', () {
    const carbOnlyNames = <String, String>{
      'פיתה רגילה': 'פיתה',
      'לחמניה ללא גלוטן': 'לחמניה',
      // The construct form is labelled by the readable form.
      'לחמניית מחמצת': 'לחמנייה',
      "מגש צ'יפס": "צ'יפס",
      "שקית צ'יפס": "צ'יפס",
      'מנת אורז': 'אורז',
      // A leading ה on a leftover word is stripped before the lookup.
      'לחם הבית': 'לחם',
      'הפיתה הרגילה': 'פיתה',
      // At a tie on start, the longer trigger names the dish.
      'פירה תפוחי אדמה': 'פירה תפוחי אדמה',
      'אורז מלא': 'אורז מלא',
      'Plain pita': 'pita',
      'Sourdough bun': 'bun',
      'Portion of fries': 'fries',
      'French fries': 'fries',
      'Steamed jasmine rice': 'rice',
      'Large bag of chips': 'chips',
      'Sweet potato fries': 'sweet potato',
      'Fries': 'fries',
    };
    for (final MapEntry(key: name, value: label) in carbOnlyNames.entries) {
      test('"$name" is the carb itself, labelled "$label"', () {
        // Act
        final result = ClassificationRules.carbOnlyBase(name);
        // Assert
        expect(result, equals(label));
      });
    }

    const notCarbOnly = <String>[
      'שווארמה בפיתה',
      'סלט טונה עם לחם',
      'Chicken salad with pita on the side',
      'Burger with fries',
      'Burger',
      'המבורגר',
      'כריך',
      'Toast',
      'Grilled sea bream',
      // Not a starch or a bread: a sauce or a vegetable alone is not
      // "built on" itself.
      'Carrots',
      'Honey',
      'Vinaigrette',
      'גזר',
      'דבש',
      // Only qualifier words, no trigger at all.
      'Large portion',
      '',
      '   ',
    ];
    for (final name in notCarbOnly) {
      test('"$name" is not a carb-only dish', () {
        // Act
        final result = ClassificationRules.carbOnlyBase(name);
        // Assert
        expect(result, isNull);
      });
    }

    test('a guarded trigger does not count: "Cauliflower rice" is null', () {
      // Act
      final result = ClassificationRules.carbOnlyBase('Cauliflower rice');
      // Assert: `cauliflower` guards `rice`, so no trigger survives.
      expect(result, isNull);
    });
  });

  group('ClassificationRules.matchDish (issues #191, #192)', () {
    Dish dish({
      required String name,
      String description = '',
      List<DishOption> options = const [],
    }) => Dish(
      id: 'd',
      name: name,
      description: description,
      price: 10,
      options: options,
    );

    test('a carb-only name is red with the trigger as its label', () {
      // Act
      final result = ClassificationRules.matchDish(dish(name: 'פיתה רגילה'));
      // Assert
      expect(result.isNonKeto, isTrue);
      expect(result.baseLabel, 'פיתה');
      expect(result.instructions, isEmpty);
    });

    test('a removal option value does not add its sentence', () {
      // Arrange: the real hamosad burger — the only "אלף האיים" is the
      // option to leave it off.
      final burger = dish(
        name: 'המבורגר',
        options: const [
          DishOption(
            name: 'שינויים אפשריים',
            values: ['ללא חסה', 'ללא אלף האיים', 'ללא מלפפון חמוץ'],
          ),
        ],
      );
      // Act
      final result = ClassificationRules.matchDish(burger);
      // Assert
      expect(result.isNonKeto, isFalse);
      expect(
        result.instructions,
        isNot(contains(carbModifiersHe['אלף האיים'])),
      );
      expect(result.instructions, equals([carbModifiersHe['לחמנייה']]));
    });

    test('an English removal value ("No croutons") does not add its '
        'sentence', () {
      // Arrange
      final salad = dish(
        name: 'Caesar salad',
        options: const [
          DishOption(name: 'Changes', values: ['No croutons', 'No cheese']),
        ],
      );
      // Act
      final result = ClassificationRules.matchDish(salad);
      // Assert
      expect(result.instructions, isEmpty);
    });

    test('a choice-of-side value still makes the dish yellow', () {
      // Arrange
      final chicken = dish(
        name: 'Grilled chicken',
        options: const [
          DishOption(
            name: 'Choice of side',
            values: ['Potato purée', 'Green salad'],
          ),
        ],
      );
      // Act
      final result = ClassificationRules.matchDish(chicken);
      // Assert
      expect(result.isNonKeto, isFalse);
      expect(result.instructions, contains(carbModifiersEn['puree']));
    });

    test('an option group named after a red base does not redden the dish', () {
      // Arrange: a burger with a "nuggets meal" upgrade option.
      final burger = dish(
        name: 'המבורגר',
        options: const [
          DishOption(name: 'ארוחת נאגטס', values: ['נאגטס - 6 יחידות']),
        ],
      );
      // Act
      final result = ClassificationRules.matchDish(burger);
      // Assert: yellow, never red for an optional upgrade — the ask to
      // skip that option comes first, then the bun sentence.
      expect(result.isNonKeto, isFalse);
      expect(
        result.instructions,
        equals([
          optionBaseModificationHe.replaceAll('{base}', 'נאגטס'),
          carbModifiersHe['לחמנייה'],
        ]),
      );
    });

    test('a bread-named dish whose description names a filling is a D-V3 '
        'yellow, not red', () {
      // Arrange
      final laffa = dish(name: 'לאפה', description: 'שווארמה, חומוס, סלט');
      final pita = dish(
        name: 'Pita',
        options: const [
          DishOption(name: 'Choose your filling', values: ['Chicken', 'Beef']),
        ],
      );
      // Act
      final laffaResult = ClassificationRules.matchDish(laffa);
      final pitaResult = ClassificationRules.matchDish(pita);
      // Assert
      expect(laffaResult.isNonKeto, isFalse);
      expect(laffaResult.instructions, contains(carbModifiersHe['לאפה']));
      expect(pitaResult.isNonKeto, isFalse);
      expect(pitaResult.instructions, equals([carbModifiersEn['pita']]));
    });

    test('a bread-named dish whose description names only the bread is '
        'still red', () {
      // Act
      final result = ClassificationRules.matchDish(
        dish(name: 'לחמניית מחמצת', description: 'לחמנייה מקמח מלא, אפויה'),
      );
      // Assert
      expect(result.isNonKeto, isTrue);
      expect(result.baseLabel, 'לחמנייה');
    });

    test('a red base offered only as an option is a yellow asking for the '
        'other option', () {
      // Arrange
      final chicken = dish(
        name: 'Grilled chicken',
        options: const [
          DishOption(name: 'Choice of side', values: ['Pasta', 'Green salad']),
        ],
      );
      final heChicken = dish(
        name: 'חזה עוף',
        options: const [
          DishOption(name: 'תוספת לבחירה', values: ['פסטה', 'סלט ירוק']),
        ],
      );
      // Act
      final en = ClassificationRules.matchDish(chicken);
      final he = ClassificationRules.matchDish(heChicken);
      // Assert
      expect(en.isNonKeto, isFalse);
      expect(
        en.instructions,
        equals([optionBaseModificationEn.replaceAll('{base}', 'pasta')]),
      );
      expect(he.isNonKeto, isFalse);
      expect(
        he.instructions,
        equals([optionBaseModificationHe.replaceAll('{base}', 'פסטה')]),
      );
    });

    test('a red base in the description still reddens the dish', () {
      // Act
      final result = ClassificationRules.matchDish(
        dish(name: 'Special of the day', description: 'Spaghetti bolognese'),
      );
      // Assert
      expect(result.isNonKeto, isTrue);
      expect(result.baseLabel, 'spaghetti');
    });

    test('matchDish and match agree for a dish with no options', () {
      // Arrange
      final steak = dish(name: 'Entrecôte', description: 'with potato purée');
      // Act
      final byDish = ClassificationRules.matchDish(steak);
      final byText = ClassificationRules.match('Entrecôte with potato purée');
      // Assert
      expect(byDish, equals(byText));
    });
  });

  group('ClassificationRules.match — pastry vocabulary (issue #190)', () {
    const pastries = <String>[
      'דניש קינמון',
      'שמרים גבינה',
      'מאפה גבינה',
      'רוגלך שוקולד',
      'Cinnamon danish',
      'Cheese pastry',
      'Blueberry muffin',
      'Plain scone',
    ];
    for (final name in pastries) {
      test('"$name" is red', () {
        // Act
        final result = ClassificationRules.match(name);
        // Assert
        expect(result.isNonKeto, isTrue, reason: name);
      });
    }

    test('"danish blue" and "danish meatballs" are not red (guarded), '
        '"danish cheese" is', () {
      // Act & Assert
      expect(
        ClassificationRules.match('Steak with danish blue').isNonKeto,
        isFalse,
      );
      expect(
        ClassificationRules.match('Danish meatballs in gravy').isNonKeto,
        isFalse,
      );
      expect(ClassificationRules.match('Danish cheese').isNonKeto, isTrue);
    });

    test('an egg muffin or keto muffin is not red (guarded)', () {
      // Act & Assert
      expect(
        ClassificationRules.match('Egg muffins with spinach').isNonKeto,
        isFalse,
      );
      expect(ClassificationRules.match('Keto muffin').isNonKeto, isFalse);
      expect(ClassificationRules.match('Blueberry muffin').isNonKeto, isTrue);
    });

    test('שמרים never matches inside משמרים ("preservatives") and is guarded '
        'for nutritional yeast', () {
      // Act & Assert
      expect(
        ClassificationRules.match('לחם ביתי ללא חומרים משמרים').isNonKeto,
        isFalse,
      );
      expect(
        ClassificationRules.match('סלט עם שמרים תזונתיים').isNonKeto,
        isFalse,
      );
      expect(ClassificationRules.match('שמרים גבינה').isNonKeto, isTrue);
      expect(ClassificationRules.match('עוגת שמרים').isNonKeto, isTrue);
    });

    test('a Hebrew burger wrapped in lettuce or keto is not yellow '
        '(guarded)', () {
      // Act & Assert
      expect(
        ClassificationRules.match('המבורגר עטוף בחסה').instructions,
        isEmpty,
      );
      expect(ClassificationRules.match('המבורגר קטו').instructions, isEmpty);
      expect(
        ClassificationRules.match('Keto cheeseburger').instructions,
        isEmpty,
      );
    });

    test('a bare burger is yellow with the bun sentence, in both '
        'languages', () {
      // Act
      final en = ClassificationRules.match('Burger');
      final he = ClassificationRules.match('המבורגר');
      final cheese = ClassificationRules.match("צ'יזבורגר המוסד");
      // Assert
      expect(en.instructions, equals([carbModifiersEn['burger']]));
      expect(he.instructions, equals([carbModifiersHe['המבורגר']]));
      expect(cheese.instructions, equals([carbModifiersHe["צ'יזבורגר"]]));
    });

    test('a lettuce burger is not yellow (guarded)', () {
      // Act
      final result = ClassificationRules.match('Lettuce burger with bacon');
      // Assert
      expect(result.instructions, isEmpty);
    });

    test('the construct form לחמניית carries the bun sentence', () {
      // Act
      final result = ClassificationRules.match('המבורגר בלחמניית מחמצת');
      // Assert
      expect(result.isNonKeto, isFalse);
      expect(result.instructions, contains(carbModifiersHe['לחמנייה']));
    });
  });

  group('ClassificationRules — false reds (issue #273)', () {
    test('lemon or lime juice is a seasoning, not a drink', () {
      _expectGreen(
        ClassificationRules.match('Grilled salmon, olive oil, lemon juice'),
      );
      _expectGreen(ClassificationRules.match('Ceviche with fresh lime juice'));
      _expectGreen(ClassificationRules.match('דג עם מיץ לימון'));
      _expectGreen(ClassificationRules.match('סלמון עם מיץ ליים ושמן זית'));
    });

    test('a juice in a dressing is a seasoning, not a drink', () {
      _expectGreen(
        ClassificationRules.match('Green salad with orange juice dressing'),
      );
      _expectGreen(ClassificationRules.match('Tomato salad, juice dressing'));
      _expectGreen(ClassificationRules.match('סלט ירוק ברוטב מיץ תפוזים'));
      _expectGreen(ClassificationRules.match('עוף במרינדה מיץ ענבים'));
    });

    test('a glass of juice is still red', () {
      _expectRed(ClassificationRules.match('Fresh orange juice'));
      _expectRed(ClassificationRules.match('Apple juice'));
      _expectRed(ClassificationRules.match('מיץ תפוזים סחוט'));
      _expectRed(ClassificationRules.match('מיץ ענבים'));
    });

    test('bare קריספי is not a red base', () {
      _expectGreen(ClassificationRules.match('סלמון עם עור קריספי'));
      _expectGreen(ClassificationRules.match('בייקון קריספי'));
      _expectGreen(ClassificationRules.match('Salmon with crispy skin'));
      _expectGreen(ClassificationRules.match('Crispy bacon'));
    });

    test('crispy chicken is the breaded dish, crispy skin is not', () {
      _expectRed(ClassificationRules.match('Crispy chicken burger'));
      _expectRed(ClassificationRules.match("קריספי צ'יקן בלחמנייה רכה"));
      _expectRed(ClassificationRules.match('חזה עוף קריספי'));
      _expectGreen(ClassificationRules.match('Crispy chicken skin'));
    });

    test('truffle-parmesan fries are the carb itself, so red', () {
      // The real hamosad dish: once bare קריספי stopped making it red, a
      // fries dish was told to swap its chips.
      _expectRed(
        ClassificationRules.matchDish(
          _dishNamed(
            "צ'יפס פרמז'ן כמהין",
            description: "קריספי צ'יפס מוקפץ בשמן כמהין פלפל שחור ופרמז'ן",
          ),
        ),
        label: "צ'יפס",
      );
      _expectRed(
        ClassificationRules.matchDish(
          _dishNamed(
            'Truffle parmesan fries',
            description: 'Crispy fries, truffle oil and parmesan',
          ),
        ),
        label: 'fries',
      );
    });

    test('a topping is not a filling, but a real filling still is', () {
      _expectYellow(
        ClassificationRules.matchDish(
          _dishNamed('Pita', description: 'Grilled chicken, garlic, parmesan'),
        ),
        [carbModifiersEn['pita']],
      );
      _expectYellow(
        ClassificationRules.matchDish(
          _dishNamed('פיתה', description: 'פלפל קלוי ושום'),
        ),
        [carbModifiersHe['פיתה']],
      );
    });

    test("a cheese after צ'יפס is a topping, before it a parmesan crisp", () {
      _expectYellow(ClassificationRules.match("המבורגר עם צ'יפס פרמזן"), [
        carbModifiersHe['המבורגר'],
        carbModifiersHe["צ'יפס"],
      ]);
      expect(ClassificationRules.match("עוף עם צ'יפס גבינה").instructions, [
        carbModifiersHe["צ'יפס"],
      ]);
      _expectGreen(ClassificationRules.match("סלט עם פרמזן צ'יפס"));
      _expectGreen(ClassificationRules.match("סלט עם גבינה צ'יפס"));
      _expectGreen(ClassificationRules.match('Salad with parmesan chips'));
    });

    test("a vegetable still rescues צ'יפס from either side", () {
      _expectGreen(ClassificationRules.match("עוף עם צ'יפס קישואים"));
      _expectGreen(ClassificationRules.match("עוף עם קייל צ'יפס"));
    });

    test('a crispy coating is still red, in both languages', () {
      _expectRed(ClassificationRules.match('Chicken in a crispy coating'));
      _expectRed(ClassificationRules.match('עוף בציפוי קריספי'));
    });

    test('a keto substitute anywhere in the name rescues pizza', () {
      _expectGreen(ClassificationRules.match('Pizza with cauliflower crust'));
      _expectGreen(ClassificationRules.match('פיצה על בסיס כרובית'));
      _expectGreen(
        ClassificationRules.matchDish(
          _dishNamed(
            'Pizza with cauliflower crust',
            description: 'Tomato, mozzarella and basil',
          ),
        ),
      );
      _expectGreen(
        ClassificationRules.matchDish(
          _dishNamed(
            'פיצה על בסיס כרובית',
            description: 'עגבניות, מוצרלה ובזיליקום',
          ),
        ),
      );
    });

    test('a keto name rescues a base the description names', () {
      _expectGreen(
        ClassificationRules.matchDish(
          _dishNamed('Keto margherita', description: 'Thin pizza, basil'),
        ),
      );
      _expectGreen(
        ClassificationRules.matchDish(
          _dishNamed('מרגריטה קטו', description: 'פיצה דקה, בזיליקום'),
        ),
      );
    });

    test('the name-wide guard never reads the description', () {
      _expectRed(
        ClassificationRules.matchDish(
          _dishNamed(
            'Margherita',
            description: 'Classic pizza. Cauliflower crust on request',
          ),
        ),
      );
      _expectRed(
        ClassificationRules.matchDish(
          _dishNamed(
            'מרגריטה',
            description: 'פיצה קלאסית. בסיס כרובית לפי בקשה',
          ),
        ),
      );
    });

    test('a bare vegetable far from the base still rescues nothing', () {
      _expectYellow(
        ClassificationRules.match('Chicken with rice and roasted cauliflower'),
        [carbModifiersEn['rice']],
      );
      _expectYellow(ClassificationRules.match('עוף עם אורז לבן וירקות'), [
        carbModifiersHe['אורז'],
      ]);
      _expectRed(ClassificationRules.match('Pasta with zucchini'));
      _expectRed(ClassificationRules.match('פסטה ברוטב שמנת ופטריות'));
    });

    test('pasta has the same keto-substitute guard as noodles', () {
      _expectGreen(ClassificationRules.match('Zucchini pasta'));
      _expectGreen(ClassificationRules.match('Shirataki pasta'));
      _expectGreen(ClassificationRules.match('Zucchini noodles'));
      _expectGreen(ClassificationRules.match('פסטת קישואים'));
      _expectGreen(ClassificationRules.match('פסטה שיראטקי'));
      _expectGreen(ClassificationRules.match('נודלס קישואים'));
    });

    test('חלבה with a מ prefix is מחלבה, a dairy', () {
      _expectGreen(ClassificationRules.match('גבינה מחלבה'));
      _expectGreen(ClassificationRules.match('גבינות מהחלבה של הכפר'));
      _expectGreen(ClassificationRules.match('Cheese from the village dairy'));
    });

    test('halva itself is still red, with its common particles', () {
      _expectRed(ClassificationRules.match('פרפה חלבה'), label: 'חלבה');
      _expectRed(ClassificationRules.match('גלידת וניל וחלבה'), label: 'חלבה');
      _expectRed(ClassificationRules.match('עוגיות בחלבה'));
      _expectRed(ClassificationRules.match('Halva parfait'));
    });

    test('בלילה ("at night") is not a base; בבלילה ("in batter") is', () {
      _expectGreen(ClassificationRules.match('מרק חם שמוגש בלילה'));
      _expectGreen(ClassificationRules.match('Hot soup served at night'));
      _expectRed(ClassificationRules.match('דג בבלילה'), label: 'בלילה');
      _expectRed(ClassificationRules.match('Battered fish'));
    });

    test('beer cooked into a dish is not the drink', () {
      _expectGreen(ClassificationRules.match('Beer-braised short rib'));
      _expectGreen(ClassificationRules.match('Short rib braised in stout'));
      _expectGreen(ClassificationRules.match('צלע בקר מבושלת בבירה'));
      _expectGreen(ClassificationRules.match('אסאדו ברוטב בירה'));
    });

    test('a port wine reduction is yellow, not red', () {
      _expectYellow(ClassificationRules.match('Port wine reduction'), [
        carbModifiersEn['port wine reduction'],
      ]);
      _expectYellow(
        ClassificationRules.match('Duck breast, port wine reduction'),
        [carbModifiersEn['port wine reduction']],
      );
      _expectYellow(ClassificationRules.match('חזה ברווז ברוטב יין פורט'), [
        carbModifiersHe['רוטב יין פורט'],
      ]);
    });

    test('a glass of beer or port is still red', () {
      _expectRed(ClassificationRules.match('Draft beer'));
      _expectRed(ClassificationRules.match('Glass of port wine'));
      _expectRed(ClassificationRules.match('בירה מהחבית'));
    });

    test('corn-fed names the feed, not a side of corn', () {
      _expectGreen(ClassificationRules.match('Corn-fed chicken'));
      _expectGreen(ClassificationRules.match('עוף מוזן תירס'));
    });

    test('baby corn is still a trap', () {
      _expectYellow(ClassificationRules.match('Baby corn stir fry'), [
        carbModifiersEn['corn'],
      ]);
      _expectYellow(ClassificationRules.match('סלט עם תירס'), [
        carbModifiersHe['תירס'],
      ]);
    });

    test('rice vinegar is a vinegar', () {
      _expectGreen(
        ClassificationRules.match('Cucumber salad with rice vinegar dressing'),
      );
      _expectGreen(ClassificationRules.match('סלט מלפפונים ברוטב חומץ אורז'));
    });

    test('rice itself is still yellow', () {
      _expectYellow(ClassificationRules.match('Chicken with rice'), [
        carbModifiersEn['rice'],
      ]);
      _expectYellow(ClassificationRules.match('עוף עם אורז'), [
        carbModifiersHe['אורז'],
      ]);
    });
  });

  group('ClassificationRules — false greens (issue #274)', () {
    test('English bases match their regular plurals and compounds', () {
      const dishes = <String, String>{
        'Steamed dumplings': 'dumpling',
        'New York cheesecake': 'cheesecake',
        'Vanilla cupcakes': 'cupcake',
        'Fish tacos': 'taco',
        'Beef burritos': 'burrito',
        'Butter croissants': 'croissant',
        'Sesame bagels': 'bagel',
        'Glazed donuts': 'donut',
        'Chocolate brownies': 'brownie',
        'Chocolate chip cookies': 'cookie',
        'Sweet crepes': 'crepe',
        'Beef empanadas': 'empanada',
        'Potato croquettes': 'croquette',
        'Cheese blintzes': 'blintz',
      };
      for (final entry in dishes.entries) {
        _expectRed(ClassificationRules.match(entry.key), label: entry.value);
      }
    });

    test('a plural keeps its singular guard and label', () {
      _expectGreen(ClassificationRules.match('Cauliflower pizzas'));
      _expectGreen(ClassificationRules.match('Zucchini noodles'));
      _expectGreen(ClassificationRules.match('Egg muffins with spinach'));
      _expectRed(ClassificationRules.match('Pizzas'), label: 'pizza');
      _expectRed(ClassificationRules.match('Noodles'), label: 'noodles');
    });

    test('a plural is never a substring match', () {
      _expectGreen(ClassificationRules.match('Grilled tartare'));
      _expectGreen(ClassificationRules.match('Caked salt crust fish'));
    });

    test('Hebrew construct forms of cake and cookie are red', () {
      _expectRed(ClassificationRules.match('עוגת שוקולד'), label: 'עוגה');
      _expectRed(ClassificationRules.match('עוגת גבינה'), label: 'עוגה');
      _expectRed(
        ClassificationRules.match("עוגיית שוקולד צ'יפס"),
        label: 'עוגיה',
      );
      _expectRed(ClassificationRules.match('עוגות הבית'));
      _expectRed(ClassificationRules.match('Chocolate cake'), label: 'cake');
      _expectRed(ClassificationRules.match('Chocolate chip cookie'));
    });

    test('the plural pitas and tortillas carry their sentence', () {
      _expectYellow(ClassificationRules.match('שווארמה בפיתות'), [
        carbModifiersHe['פיתה'],
      ]);
      _expectYellow(ClassificationRules.match('עוף בטורטיות'), [
        carbModifiersHe['טורטייה'],
      ]);
      _expectYellow(ClassificationRules.match('Shawarma in pita'), [
        carbModifiersEn['pita'],
      ]);
    });

    test('pitas or tortillas named alone are the carb itself', () {
      _expectRed(
        ClassificationRules.matchDish(_dishNamed('פיתות')),
        label: 'פיתות',
      );
      _expectRed(
        ClassificationRules.matchDish(_dishNamed('טורטיות')),
        label: 'טורטיות',
      );
    });

    test('lentil soup is red', () {
      _expectRed(ClassificationRules.match('Lentil soup'));
      _expectRed(ClassificationRules.match('מרק עדשים'));
    });

    test('cranberry sauce is yellow with one sentence', () {
      _expectYellow(ClassificationRules.match('Turkey with cranberry sauce'), [
        carbModifiersEn['cranberry sauce'],
      ]);
      _expectYellow(ClassificationRules.match('הודו עם רוטב חמוציות'), [
        carbModifiersHe['רוטב חמוציות'],
      ]);
    });

    test('hash browns and onion rings are a removable side', () {
      _expectYellow(ClassificationRules.match('Eggs with hash browns'), [
        carbModifiersEn['hash browns'],
      ]);
      _expectYellow(ClassificationRules.match('ביצים עם האש בראון'), [
        carbModifiersHe['האש בראון'],
      ]);
      _expectYellow(ClassificationRules.match('Steak with onion rings'), [
        carbModifiersEn['onion rings'],
      ]);
      _expectYellow(ClassificationRules.match('סטייק עם טבעות בצל'), [
        carbModifiersHe['טבעות בצל'],
      ]);
    });

    test('hash browns, onion rings or naan named alone are red', () {
      for (final name in [
        'Hash browns',
        'האש בראון',
        'Onion rings',
        'טבעות בצל',
        'Naan',
        'נאן',
        'Flatbread',
      ]) {
        _expectRed(ClassificationRules.matchDish(_dishNamed(name)));
      }
    });

    test('naan and flatbread carry a dish like a pita', () {
      _expectYellow(ClassificationRules.match('Butter chicken with naan'), [
        carbModifiersEn['naan'],
      ]);
      _expectYellow(ClassificationRules.match('עוף בחמאה עם נאן'), [
        carbModifiersHe['נאן'],
      ]);
      _expectYellow(ClassificationRules.match('Lamb on flatbread'), [
        carbModifiersEn['flatbread'],
      ]);
      _expectYellow(ClassificationRules.match('טלה על לחם שטוח'), [
        carbModifiersHe['לחם'],
      ]);
    });

    test('nachos are red', () {
      _expectRed(ClassificationRules.match('Loaded nachos'));
      _expectRed(ClassificationRules.match("נאצ'וס עם גבינה"));
    });

    test('sushi and nigiri are rice dishes, sashimi is not', () {
      _expectRed(ClassificationRules.match('Salmon sushi'));
      _expectRed(ClassificationRules.match('Salmon nigiri'));
      _expectRed(ClassificationRules.match('Spicy tuna maki'));
      _expectRed(ClassificationRules.match('סושי סלמון'));
      _expectRed(ClassificationRules.match('ניגירי סלמון'));
      _expectGreen(ClassificationRules.match('Salmon sashimi'));
      _expectGreen(ClassificationRules.match('סשימי סלמון'));
    });

    test('sushi-grade fish is raw fish', () {
      _expectGreen(ClassificationRules.match('Sushi-grade tuna tartare'));
      _expectGreen(ClassificationRules.match('טונה באיכות סושי'));
    });

    test('tiramisu and crème brûlée are red', () {
      _expectRed(ClassificationRules.match('Tiramisu'));
      _expectRed(ClassificationRules.match('טירמיסו'));
      _expectRed(ClassificationRules.match('Crème brûlée'));
      _expectRed(ClassificationRules.match('Creme brulee'));
      _expectRed(ClassificationRules.match('קרם ברולה'));
    });

    test('fried and popcorn chicken are red', () {
      _expectRed(ClassificationRules.match('Korean fried chicken'));
      _expectRed(ClassificationRules.match('Popcorn chicken'));
      _expectRed(ClassificationRules.match("פרייד צ'יקן"));
      _expectRed(ClassificationRules.match('עוף פופקורן'));
    });

    test('pan-, stir- and air-fried chicken carry no breading', () {
      _expectGreen(ClassificationRules.match('Pan-fried chicken breast'));
      _expectGreen(ClassificationRules.match('Stir-fried chicken'));
      _expectGreen(ClassificationRules.match('Air-fried chicken wings'));
    });

    test('French toast is red, not a yellow toast', () {
      _expectRed(ClassificationRules.match('French toast'));
      _expectRed(ClassificationRules.match("פרנץ' טוסט"));
      _expectRed(ClassificationRules.match('טוסט צרפתי'));
    });

    test("Fish 'n' Chips is battered fish, not a chips swap", () {
      _expectRed(
        ClassificationRules.match("Fish 'n' Chips"),
        label: 'battered fish',
      );
      _expectRed(ClassificationRules.match("פיש נ' צ'יפס"), label: 'דג מצופה');
    });

    test('Hebrew mirrors of the plural and compound bases are red', () {
      for (final text in [
        'כופתאות בשר',
        'כיסונים מאודים',
        "צ'יזקייק ניו יורק",
        'קאפקייקס וניל',
        'טאקו דג',
        'בראוני שוקולד',
        'קרואסונים חמאה',
        'בייגלים',
        'דונאטס',
        'אמפנדות בשר',
        'קרוקטים',
        'קרפים מתוקים',
        'סופגניות ריבה',
      ]) {
        _expectRed(ClassificationRules.match(text));
      }
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/utils/classification_rules.dart';
import 'package:ketoclub/utils/constants.dart';

/// The Hebrew triggers whose pattern deliberately disables the
/// permissive prefix (see `classification_rules.dart`'s
/// `_noPrefixHebrewTriggers`): folded `חלה` also spells a common verb
/// form, and its prefixed form (`החלה`) is itself an ordinary word
/// ("commencement"); `משמרים` is "preservatives"; `הפוך` collides with
/// "to flip" (e.g. `להפוך`). All three are excluded from the prefix
/// half of the generated Hebrew trigger tests below.
const Set<String> _noPrefixTriggers = <String>{'חלה', 'שמרים', 'הפוך'};

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
}

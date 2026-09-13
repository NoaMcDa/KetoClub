import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/utils/classification_rules.dart';
import 'package:ketoclub/utils/constants.dart';

/// The one Hebrew trigger whose pattern deliberately disables the
/// permissive prefix (see `classification_rules.dart`'s
/// `_noPrefixHebrewTriggers`): folded `חלה` also spells a common verb
/// form, and its prefixed form (`החלה`) is itself an ordinary word
/// ("commencement"), so it is excluded from the prefix half of the
/// generated Hebrew trigger tests below.
const String _noPrefixTrigger = 'חלה';

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

        if (trigger != _noPrefixTrigger) {
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

        if (trigger != _noPrefixTrigger) {
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

    test('RuleMatch equality holds for two equivalent results', () {
      // Act
      final a = ClassificationRules.match('Fish and chips');
      final b = ClassificationRules.match('Fish and chips');
      // Assert
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('RuleMatch.toString describes a red result', () {
      // Act
      final result = ClassificationRules.match('Margherita pizza');
      // Assert
      expect(result.toString(), contains('nonKeto'));
      expect(result.toString(), contains('pizza'));
    });

    test('RuleMatch.toString describes a modifiable result', () {
      // Act
      final result = ClassificationRules.match('Grilled steak with fries');
      // Assert
      expect(result.toString(), contains('modifiers'));
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
}

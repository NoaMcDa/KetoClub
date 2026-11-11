import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/utils/hebrew_order.dart';

void main() {
  group('looksCharacterReversed (issue #181)', () {
    test('logical-order Hebrew is not reversed', () {
      // Final forms at the ends of words: ם, ן, ך, ף, ץ.
      expect(looksCharacterReversed('סלט ירוק עם שמן זית וחומץ'), isFalse);
      expect(looksCharacterReversed('לחם, כריך, עוף, קיץ'), isFalse);
    });

    test('a word that starts with each final form is reversed', () {
      // "שמן" / "לחם" / "כריך" / "עוף" / "קיץ", each written backwards.
      for (final reversed in ['ןמש', 'םחל', 'ךירכ', 'ףוע', 'ץיק']) {
        expect(
          looksCharacterReversed('סלט $reversed'),
          isTrue,
          reason: reversed,
        );
      }
    });

    test('one reversed word rejects the whole text', () {
      expect(looksCharacterReversed('סלט קיסר\nםע ןמש תיז\nאנטריקוט'), isTrue);
    });

    test('a geresh inside a loanword does not split it (issue #442)', () {
      // Parmesan, carpaccio, Manchego: ASCII, Hebrew and curly geresh.
      for (final word in ["פרמז'ן", "קרפצ'יו", "מנצ'גו", 'פרמז׳ן', 'פרמז’ן']) {
        expect(looksCharacterReversed(word), isFalse, reason: word);
      }
      expect(looksCharacterReversed("סלט עגבניות, פרמז'ן ושמן זית"), isFalse);
    });

    test('an acronym with gershayim is not reversed', () {
      for (final word in ['תנ"ך', 'תנ״ך', 'תנ”ך']) {
        expect(looksCharacterReversed(word), isFalse, reason: word);
      }
    });

    test('pointed Hebrew is not reversed', () {
      // A niqqud mark sits between the letters of "שלום".
      expect(looksCharacterReversed('שָׁלוֹם'), isFalse);
    });

    test('reversed text with a geresh or in quotes is still reversed', () {
      // "פרמז'ן" and "סנדוויץ'" backwards, and a quoted reversed "שמן".
      for (final reversed in ["ן'זמרפ", "'ץיוודנס", 'סלט "ןמש"', "it's ם"]) {
        expect(looksCharacterReversed(reversed), isTrue, reason: reversed);
      }
    });

    test('text with no Hebrew is never reversed', () {
      expect(looksCharacterReversed('Caesar salad 52'), isFalse);
      expect(looksCharacterReversed(''), isFalse);
    });
  });
}

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

    test('text with no Hebrew is never reversed', () {
      expect(looksCharacterReversed('Caesar salad 52'), isFalse);
      expect(looksCharacterReversed(''), isFalse);
    });
  });
}

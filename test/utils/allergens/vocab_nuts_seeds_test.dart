import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/utils/allergens/allergen_matcher.dart';
import 'package:ketoclub/utils/allergens/vocabulary.dart';

/// The restrictions this file's group owns.
const List<RestrictionId> _ids = <RestrictionId>[
  RestrictionId.peanuts,
  RestrictionId.treeNuts,
  RestrictionId.sesame,
];

/// One expectation: what `id` finds in `text` — its strongest certainty,
/// or null when it finds nothing.
typedef _Case = ({
  RestrictionId id,
  String text,
  TriggerCertainty? certainty,
  String why,
});

/// A Hebrew plural ending, to test the strict right boundary.
const String _plural = 'ים';

const TriggerCertainty _stated = TriggerCertainty.stated;
const TriggerCertainty _likely = TriggerCertainty.likely;
const TriggerCertainty _suspected = TriggerCertainty.suspected;

/// The strongest certainty `id` reaches in `text` (stated sorts first), or
/// null when `id` has no hit.
TriggerCertainty? _strongest(RestrictionId id, String text) {
  TriggerCertainty? best;
  for (final hit in AllergenMatcher.find(text)) {
    if (hit.id != id) continue;
    if (best == null || hit.certainty.index < best.index) best = hit.certainty;
  }
  return best;
}

_Case _case(
  RestrictionId id,
  String text,
  TriggerCertainty? certainty,
  String why,
) => (id: id, text: text, certainty: certainty, why: why);

void _expectAll(List<_Case> cases) {
  for (final c in cases) {
    expect(
      _strongest(c.id, c.text),
      c.certainty,
      reason: '${c.id.name}: "${c.text}" (${c.why})',
    );
  }
}

void main() {
  group('nuts and seeds vocabulary', () {
    for (final id in _ids) {
      group(id.name, () {
        final vocabulary = allergenVocabulary[id]!;

        test('is filled, with both languages and a source', () {
          expect(vocabulary.isEmpty, isFalse);
          expect(vocabulary.directEn, isNotEmpty);
          expect(vocabulary.directHe, isNotEmpty);
          expect(vocabulary.hiddenEn, isNotEmpty);
          expect(vocabulary.hiddenHe, isNotEmpty);
          expect(vocabulary.sources, isNotEmpty);
        });

        test('every direct term finds itself as stated', () {
          for (final term in <String>[
            ...vocabulary.directEn,
            ...vocabulary.directHe,
          ]) {
            final hits = AllergenMatcher.find(term)
                .where((hit) => hit.id == id && hit.term == term);
            expect(
              hits.map((hit) => hit.certainty),
              contains(_stated),
              reason: term,
            );
          }
        });

        test('every hidden term finds itself at its own certainty', () {
          for (final trigger in <HiddenTrigger>[
            ...vocabulary.hiddenEn,
            ...vocabulary.hiddenHe,
          ]) {
            final hits = AllergenMatcher.find(trigger.term)
                .where((hit) => hit.id == id && hit.term == trigger.term);
            expect(
              hits.map((hit) => hit.certainty),
              contains(trigger.certainty),
              reason: trigger.term,
            );
          }
        });

        test('every Hebrew term takes the grammatical prefixes ב and וה', () {
          final noPrefix = vocabulary.noPrefixHe.toSet();
          final terms = <String>[
            ...vocabulary.directHe,
            for (final trigger in vocabulary.hiddenHe) trigger.term,
          ];
          for (final term in terms.where((t) => !noPrefix.contains(t))) {
            for (final prefix in <String>['ב', 'וה']) {
              final hits = AllergenMatcher.find('$prefix$term')
                  .where((hit) => hit.id == id && hit.term == term);
              expect(hits, isNotEmpty, reason: '$prefix$term');
            }
          }
        });

        test('no Hebrew term matches inside a longer word', () {
          final terms = <String>[
            ...vocabulary.directHe,
            for (final trigger in vocabulary.hiddenHe) trigger.term,
          ];
          for (final term in terms) {
            final hits = AllergenMatcher.find('$term$_plural')
                .where((hit) => hit.id == id && hit.term == term);
            expect(hits, isEmpty, reason: '$term$_plural');
          }
        });
      });
    }
  });

  group('peanuts', () {
    const id = RestrictionId.peanuts;

    test('direct triggers in English are stated', () {
      _expectAll(<_Case>[
        _case(id, 'Peanut butter sandwich', _stated, 'peanut butter'),
        _case(id, 'Pad thai with crushed peanuts', _stated, 'plural'),
        _case(id, 'Cold-pressed groundnut oil', _stated, 'groundnut'),
        _case(id, 'A bowl of monkey nuts', _stated, 'monkey nut'),
        _case(id, 'Arachis hypogaea', _stated, 'the Latin name'),
        _case(id, 'Bamba', _stated, 'Bamba is 54% peanut'),
        _case(id, 'PEANUT SAUCE', _stated, 'case-insensitive'),
      ]);
    });

    test('direct triggers in Hebrew are stated, with prefixes', () {
      _expectAll(<_Case>[
        _case(id, 'בוטנים', _stated, 'peanuts'),
        _case(id, 'בוטן', _stated, 'one peanut'),
        _case(id, 'אגוזי אדמה', _stated, 'the other Hebrew name'),
        _case(id, 'סלט עם בוטנים קלויים', _stated, 'in a salad'),
        _case(id, 'מקורמל בבוטנים', _stated, 'prefix ב'),
        _case(id, 'עוגיה והבוטנים', _stated, 'prefix וה'),
        _case(id, 'חמאת בוטנים', _stated, 'peanut butter'),
        _case(id, 'במבה', _stated, 'Bamba'),
        _case(id, 'חטיף במבה', _stated, 'Bamba, in a phrase'),
      ]);
    });

    test('hidden sources keep their own certainty', () {
      _expectAll(<_Case>[
        _case(id, 'Chicken satay skewers', _likely, 'satay'),
        _case(id, 'Kung pao chicken', _likely, 'kung pao'),
        _case(id, 'Pork egg rolls', _likely, 'egg rolls'),
        _case(id, 'Massaman beef', _likely, 'massaman'),
        _case(id, 'Pad thai', _suspected, 'pad thai'),
        _case(id, 'Green curry', _suspected, 'curry'),
        _case(id, 'Basil pesto pasta', _suspected, 'pesto'),
        _case(id, 'Granola and yogurt', _suspected, 'granola'),
        _case(id, 'Mixed nuts', _suspected, 'a loose "nuts"'),
        _case(id, 'Sweet chili sauce', _suspected, 'chili sauce'),
        _case(id, 'סאטה עוף', _likely, 'Hebrew satay'),
        _case(id, 'אגרול ירקות', _likely, 'Hebrew egg roll'),
        _case(id, 'קונג פאו', _likely, 'kung pao'),
        _case(id, 'עוף בקארי', _suspected, 'Hebrew curry'),
        _case(id, 'נודלס אסייתי', _suspected, 'Hebrew "Asian"'),
        _case(id, 'פסטו בזיליקום', _suspected, 'Hebrew pesto'),
      ]);
    });

    test('a bare אגוזים is peanut suspected', () {
      _expectAll(<_Case>[
        _case(id, 'אגוזים', _suspected, 'bare Hebrew nuts'),
        _case(id, 'סלט עם אגוזים', _suspected, 'in a salad'),
        _case(id, 'באגוזים', _suspected, 'prefix ב'),
      ]);
    });

    test('guards cancel the hit', () {
      _expectAll(<_Case>[
        _case(id, 'Peanut-free brownie', null, 'peanut-free'),
        _case(id, 'No peanuts, no problem', null, 'no peanuts'),
        _case(id, 'Satay without peanuts', null, 'without'),
        _case(id, 'Pad thai (peanut free)', null, 'after the trigger'),
        _case(id, 'Satay, peanut free', null, 'a hidden trigger too'),
        _case(id, 'ללא בוטנים', null, 'Hebrew ללא'),
        _case(id, 'עוגה ובלי בוטנים', null, 'Hebrew ובלי'),
        _case(id, 'סאטה ללא בוטנים', null, 'a hidden Hebrew trigger'),
        _case(
          id,
          'Free range chicken satay',
          _likely,
          'free before is no guard',
        ),
      ]);
    });

    test('"nut free" is a tree-nut claim and leaves peanut standing', () {
      _expectAll(<_Case>[
        _case(id, 'Nut-free pesto', _suspected, 'pesto is still asked about'),
        _case(id, 'Nut free peanut brittle', _stated, 'peanut stands'),
        _case(id, 'Peanut free pesto', null, 'peanut free clears it'),
      ]);
    });

    test('foods that are not peanut find nothing', () {
      _expectAll(<_Case>[
        _case(id, 'Almond croissant', null, 'almond is a tree nut'),
        _case(id, 'Walnut and pine nut tart', null, 'tree nuts'),
        _case(id, 'Coconut milk soup', null, 'coconut'),
        _case(id, 'Butternut squash', null, 'butternut is not a nut'),
        _case(id, 'Nutmeg', null, 'nutmeg'),
        _case(id, 'שקדים ופיסטוק', null, 'Hebrew tree nuts'),
        _case(id, 'אגוז מוסקט', null, 'nutmeg'),
        _case(id, 'Sesame bun', null, 'a different restriction'),
      ]);
    });

    test('a bare אגוזים reads as tree nuts likely and peanut suspected', () {
      // Act
      final hits = AllergenMatcher.find('סלט אגוזים');

      // Assert
      final seen = <String>[
        for (final hit in hits)
          if (hit.id == RestrictionId.treeNuts ||
              hit.id == RestrictionId.peanuts)
            '${hit.id.name}:${hit.certainty.name}',
      ];
      expect(seen, <String>['peanuts:suspected', 'treeNuts:likely']);
    });
  });

  group('treeNuts', () {
    const id = RestrictionId.treeNuts;

    test('the named nuts in English are stated', () {
      _expectAll(<_Case>[
        _case(id, 'Almond croissant', _stated, 'almond'),
        _case(id, 'Roasted almonds', _stated, 'plural'),
        _case(id, 'Walnut cake', _stated, 'walnut'),
        _case(id, 'Cashew chicken', _stated, 'cashew'),
        _case(id, 'Pistachio ice cream', _stated, 'pistachio'),
        _case(id, 'Hazelnut spread', _stated, 'hazelnut'),
        _case(id, 'Pecan pie', _stated, 'pecan'),
        _case(id, 'Macadamia cookies', _stated, 'macadamia'),
        _case(id, 'Brazil nuts', _stated, 'Brazil nut'),
        _case(id, 'Rice with pine nuts', _stated, 'pine nuts'),
        _case(id, 'Pignoli cookies', _stated, 'pine nut, Italian'),
        _case(id, 'Marzipan fruits', _stated, 'marzipan'),
        _case(id, 'Hazelnut praline', _stated, 'praline'),
        _case(id, 'Almond-free tree nut mix', _stated, 'tree nut'),
        _case(id, 'FRANGIPANE TART', _stated, 'case-insensitive'),
      ]);
    });

    test('the named nuts in Hebrew are stated, with prefixes', () {
      _expectAll(<_Case>[
        _case(id, 'שקדים', _stated, 'almonds'),
        _case(id, 'קרואסון שקדים', _stated, 'almond croissant'),
        _case(id, 'אגוזי מלך', _stated, 'walnuts'),
        _case(id, 'באגוזי מלך', _stated, 'prefix ב'),
        _case(id, 'עוגה והאגוזי מלך', _stated, 'prefix וה'),
        _case(id, 'גלידת לוז', _stated, 'hazelnut'),
        _case(id, 'פיסטוק', _stated, 'pistachio'),
        _case(id, 'פיסטוקים', _stated, 'pistachios'),
        _case(id, 'צנוברים', _stated, 'pine nuts'),
        _case(id, 'אורז בצנוברים', _stated, 'prefix ב'),
        _case(id, 'קשיו', _stated, 'cashew'),
        _case(id, 'פקאן', _stated, 'pecan'),
        _case(id, 'מקדמיה', _stated, 'macadamia'),
        _case(id, 'אגוזי ברזיל', _stated, 'Brazil nuts'),
        _case(id, 'מרציפן', _stated, 'marzipan'),
        _case(id, 'אגוזי עץ', _stated, 'tree nuts'),
      ]);
    });

    test('hidden sources keep their own certainty', () {
      _expectAll(<_Case>[
        _case(id, 'Basil pesto pasta', _likely, 'pesto'),
        _case(id, 'Baklava', _likely, 'baklava'),
        _case(id, 'Mixed nuts', _likely, 'a loose "nuts"'),
        _case(id, 'Nut butter toast', _likely, 'nut butter'),
        _case(id, 'Nougat bar', _likely, 'nougat'),
        _case(id, 'Granola bowl', _suspected, 'granola'),
        _case(id, 'Thai green curry', _suspected, 'curry'),
        _case(id, 'Chicken korma', _suspected, 'korma'),
        _case(id, 'Chicken satay', _suspected, 'satay'),
        _case(id, 'Cannoli', _suspected, 'cannoli'),
        _case(id, 'אגוזים', _likely, 'bare Hebrew nuts'),
        _case(id, 'פסטו', _likely, 'Hebrew pesto'),
        _case(id, 'בקלאווה', _likely, 'baklava'),
        _case(id, 'נוטלה', _likely, 'hazelnut spread'),
        _case(id, 'חטיף במבה במילוי נוגט', _likely, 'filled Bamba'),
        _case(id, 'גרנולה', _suspected, 'granola'),
        _case(id, 'עוף בקארי', _suspected, 'curry'),
      ]);
    });

    test('guards cancel the hit', () {
      _expectAll(<_Case>[
        _case(id, 'Nut-free pesto', null, 'nut-free'),
        _case(id, 'Pesto (nut free)', null, 'after the trigger'),
        _case(id, 'No nuts', null, 'no nuts'),
        _case(id, 'Salad without almonds', null, 'without'),
        _case(id, 'Pesto without nuts', null, 'a hidden trigger too'),
        _case(id, 'Almond free', null, 'after-guard free'),
        _case(id, 'ללא אגוזים', null, 'Hebrew ללא'),
        _case(id, 'פסטו ללא אגוזים', null, 'a hidden Hebrew trigger'),
        _case(id, 'עוגה ובלי שקדים', null, 'Hebrew ובלי'),
      ]);
    });

    test('"peanut free" is a peanut claim and leaves tree nuts standing', () {
      _expectAll(<_Case>[
        _case(id, 'Peanut-free pesto', _likely, 'pesto is still asked about'),
      ]);
    });

    test('foods that are not tree nuts find nothing', () {
      _expectAll(<_Case>[
        _case(id, 'Coconut cream pie', null, 'coconut'),
        _case(id, 'Nutmeg latte', null, 'nutmeg'),
        _case(id, 'Chestnut soup', null, 'chestnut'),
        _case(id, 'Water chestnuts', null, 'water chestnut'),
        _case(id, 'Butternut squash', null, 'butternut'),
        _case(id, 'Peanut butter', null, 'peanut is a legume'),
        _case(id, 'Doughnut', null, 'a doughnut'),
        _case(id, 'אגוז מוסקט', null, 'Hebrew nutmeg'),
        _case(id, 'אגוז קוקוס', null, 'Hebrew coconut'),
        _case(id, 'אגוזי אדמה', null, 'Hebrew peanuts'),
        _case(id, 'שקדי מרק', null, 'soup croutons, not almonds'),
        _case(id, 'Sesame bun', null, 'a different restriction'),
      ]);
    });
  });

  group('sesame', () {
    const id = RestrictionId.sesame;

    test('direct triggers in English are stated', () {
      _expectAll(<_Case>[
        _case(id, 'Sesame bagel', _stated, 'sesame'),
        _case(id, 'Seared tuna with sesame oil', _stated, 'sesame oil'),
        _case(id, 'Tahini sauce', _stated, 'tahini'),
        _case(id, 'Tahina and olives', _stated, 'tahina'),
        _case(id, 'Tehina dressing', _stated, 'tehina'),
        _case(id, 'Techina', _stated, 'techina'),
        _case(id, 'Pistachio halva', _stated, 'halva'),
        _case(id, 'Halvah ice cream', _stated, 'halvah'),
        _case(id, 'Benne seeds', _stated, 'benne'),
        _case(id, 'Gomasio', _stated, 'gomasio'),
        _case(id, 'TAHINI', _stated, 'case-insensitive'),
      ]);
    });

    test('direct triggers in Hebrew are stated, with prefixes', () {
      _expectAll(<_Case>[
        _case(id, 'שומשום', _stated, 'sesame'),
        _case(id, 'סומסום', _stated, 'sesame, the other spelling'),
        _case(id, 'שומשומין', _stated, 'sesame, plural'),
        _case(id, 'טחינה', _stated, 'tahini'),
        _case(id, 'טחינא', _stated, 'tahini, the other spelling'),
        _case(id, 'חלבה', _stated, 'halva'),
        _case(id, 'סלט בטחינה', _stated, 'prefix ב'),
        _case(id, 'בורקס והשומשום מעל', _stated, 'prefix וה'),
        _case(id, 'עוגיות לחלבה', _stated, 'prefix ל'),
        _case(id, 'שמן שומשום', _stated, 'sesame oil'),
      ]);
    });

    test('hidden sources keep their own certainty', () {
      _expectAll(<_Case>[
        _case(id, 'Hummus with pine nuts', _likely, 'hummus'),
        _case(id, 'Houmous', _likely, 'hummus, the other spelling'),
        _case(id, 'Baba ghanoush', _likely, 'baba ghanoush'),
        _case(id, 'Cheese bourekas', _likely, 'bourekas'),
        _case(id, 'Sabich in a pita', _likely, 'sabich'),
        _case(id, "Za'atar flatbread", _likely, "za'atar"),
        _case(id, 'Jerusalem bagel', _likely, 'Jerusalem bagel'),
        _case(id, 'Falafel plate', _suspected, 'falafel'),
        _case(id, 'Burger on a bun', _suspected, 'bun'),
        _case(id, 'Seeded loaf', _suspected, 'seeds in dough'),
        _case(id, 'Vegetable stir fry', _suspected, 'stir-fry oil'),
        _case(id, 'Eggplant salad', _suspected, 'tahini-dressed salad'),
        _case(id, 'Natural flavors', _suspected, 'natural flavors'),
        _case(id, 'חומוס', _likely, 'hummus'),
        _case(id, 'חומוס מסבחה', _likely, 'hummus, in a dish'),
        _case(id, 'בורקס תפוח אדמה', _likely, 'bourekas'),
        _case(id, 'סביח', _likely, 'sabich'),
        _case(id, 'פיתה עם זעתר', _likely, "za'atar"),
        _case(id, 'פלאפל', _suspected, 'falafel'),
        _case(id, 'לחמנייה', _suspected, 'roll'),
        _case(id, 'לחמניה', _suspected, 'roll, the short spelling'),
        _case(id, 'סלט חצילים', _suspected, 'eggplant salad'),
        _case(id, 'פיתה', _suspected, 'pita'),
        _case(id, 'בייגל ירושלמי', _likely, 'Jerusalem bagel'),
      ]);
    });

    test('guards cancel the hit', () {
      _expectAll(<_Case>[
        _case(id, 'Sesame-free bun', null, 'sesame-free'),
        _case(id, 'Hummus, no tahini', null, 'no tahini'),
        _case(id, 'Hummus without sesame', null, 'without sesame'),
        _case(id, 'Tahini free hummus', null, 'tahini free'),
        _case(id, 'Bun (sesame free)', null, 'after the trigger'),
        _case(id, 'ללא שומשום', null, 'Hebrew ללא'),
        _case(id, 'חומוס ללא טחינה', null, 'a hidden Hebrew trigger'),
        _case(id, 'פלאפל בלי טחינה', null, 'Hebrew בלי'),
        _case(id, 'סלט וללא טחינה', null, 'Hebrew וללא'),
        _case(id, 'Plain hummus', _likely, 'no guard'),
      ]);
    });

    test('foods that are not sesame find nothing', () {
      _expectAll(<_Case>[
        _case(id, 'Sesamestreet salad', null, 'a Latin trigger has a boundary'),
        _case(id, 'Almond croissant', null, 'tree nuts'),
        _case(id, 'Peanut butter', null, 'peanuts'),
        _case(id, 'Green salad with olive oil', null, 'plain food'),
        _case(id, 'חלב', null, 'milk is not halva'),
        _case(id, 'חלבון', null, 'protein'),
        _case(id, 'שומן', null, 'fat'),
      ]);
    });
  });
}

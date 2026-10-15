// The extended restrictions' vocabulary (Banto, ALG-17, issue #359):
// alpha-gal, FODMAP, histamine and small portions (GLP-1), in English and
// Hebrew, with their prefix forms, their no-prefix traps and their guards.

import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/utils/allergens/allergen_matcher.dart';
import 'package:ketoclub/utils/allergens/vocab_extended.dart';
import 'package:ketoclub/utils/allergens/vocabulary.dart';

// One expectation: `text` gives `id` a hit on `term` at certainty `c`.
typedef _Hit = (String text, RestrictionId id, String term, TriggerCertainty c);

const TriggerCertainty _stated = TriggerCertainty.stated;
const TriggerCertainty _likely = TriggerCertainty.likely;
const TriggerCertainty _suspected = TriggerCertainty.suspected;

const RestrictionId _alphaGal = RestrictionId.alphaGal;
const RestrictionId _fodmap = RestrictionId.fodmap;
const RestrictionId _histamine = RestrictionId.histamine;
const RestrictionId _glp1 = RestrictionId.glp1;

const List<RestrictionId> _ids = <RestrictionId>[
  _alphaGal,
  _fodmap,
  _histamine,
  _glp1,
];

/// Every hit [id] gets on [text].
List<AllergenHit> _hits(String text, RestrictionId id) =>
    AllergenMatcher.find(text)
        .where((hit) => hit.id == id)
        .toList(growable: false);

/// The certainty of [id]'s hit on [term] in [text], or null.
TriggerCertainty? _certaintyOf(String text, RestrictionId id, String term) {
  for (final hit in _hits(text, id)) {
    if (hit.term == term) return hit.certainty;
  }
  return null;
}

/// Whether [id]'s hits on [text] are all lowered by a guard, and there is
/// one (a guard lowers to suspected, never cancels; ALG-04a).
bool _lowered(String text, RestrictionId id) {
  final hits = _hits(text, id);
  return hits.isNotEmpty &&
      hits.every((hit) => hit.guarded && hit.certainty == _suspected);
}

/// Every term of [vocabulary] with its declared certainty and script.
List<({String term, TriggerCertainty certainty, bool hebrew})> _terms(
  RestrictionVocabulary vocabulary,
) => <({String term, TriggerCertainty certainty, bool hebrew})>[
  for (final term in vocabulary.directEn)
    (term: term, certainty: _stated, hebrew: false),
  for (final term in vocabulary.directHe)
    (term: term, certainty: _stated, hebrew: true),
  for (final t in vocabulary.hiddenEn)
    (term: t.term, certainty: t.certainty, hebrew: false),
  for (final t in vocabulary.hiddenHe)
    (term: t.term, certainty: t.certainty, hebrew: true),
];

void main() {
  group('extended vocabulary', () {
    test('covers the four ALG-17 restrictions and the empty own entry', () {
      expect(extendedVocabulary.keys.toSet(), <RestrictionId>{
        ..._ids,
        RestrictionId.custom,
      });
      expect(extendedVocabulary[RestrictionId.custom]!.isEmpty, isTrue);
      expect(allergenVocabulary[RestrictionId.custom]!.isEmpty, isTrue);
    });

    for (final id in _ids) {
      group(id.name, () {
        final vocabulary = allergenVocabulary[id]!;

        test('is filled in both languages and cites its sources', () {
          expect(vocabulary.hiddenEn, isNotEmpty);
          expect(vocabulary.hiddenHe, isNotEmpty);
          expect(vocabulary.sources, isNotEmpty);
          if (id != _glp1) {
            expect(vocabulary.directEn, isNotEmpty);
            expect(vocabulary.directHe, isNotEmpty);
          }
        });

        test('every term is found when it stands alone, at its certainty', () {
          for (final entry in _terms(vocabulary)) {
            expect(
              _certaintyOf(entry.term, id, entry.term),
              entry.certainty,
              reason: entry.term,
            );
          }
        });

        test('every Hebrew term takes ב, ו and ה in front', () {
          final noPrefix = vocabulary.noPrefixHe.toSet();
          for (final entry in _terms(vocabulary)) {
            if (!entry.hebrew || noPrefix.contains(entry.term)) continue;
            for (final prefix in <String>['ב', 'ו', 'ה']) {
              expect(
                _hits('עם $prefix${entry.term}', id).map((hit) => hit.term),
                contains(entry.term),
                reason: '$prefix${entry.term}',
              );
            }
          }
        });

        test('every English term matches in capitals too', () {
          for (final entry in _terms(vocabulary)) {
            if (entry.hebrew) continue;
            expect(
              _certaintyOf(
                'Served with ${entry.term.toUpperCase()} today',
                id,
                entry.term,
              ),
              entry.certainty,
              reason: entry.term,
            );
          }
        });
      });
    }
  });

  group('hits', () {
    const cases = <_Hit>[
      // Alpha-gal: a named mammal meat is stated; a dish that may be
      // chicken is likely; a casing or a stock is suspected.
      ('Beef with broccoli', _alphaGal, 'beef', _stated),
      ('Roast lamb shoulder', _alphaGal, 'lamb', _stated),
      ('Pulled pork bun', _alphaGal, 'pork', _stated),
      ('Panna cotta with berries', _alphaGal, 'panna cotta', _likely),
      ('Gelatin dessert', _alphaGal, 'gelatin', _stated),
      ('Classic cheeseburger', _alphaGal, 'cheeseburger', _likely),
      ('Pork sausages', _alphaGal, 'sausages', _suspected),
      ('Chicken stock', _alphaGal, 'stock', _suspected),
      ('שישליק בקר', _alphaGal, 'בקר', _stated),
      ('צלעות טלה', _alphaGal, 'טלה', _stated),
      ('מצוואדי כבש', _alphaGal, 'כבש', _stated),
      ('קינוח עם ג׳לטין', _alphaGal, "ג'לטין", _stated),
      ('קבב בלאפה', _alphaGal, 'קבב', _likely),
      ('המבורגר 250 גרם', _alphaGal, 'המבורגר', _likely),
      ('ברוטב בשר', _alphaGal, 'בשר', _likely),
      ('שווארמה בפיתה', _alphaGal, 'שווארמה', _suspected),
      // FODMAP: the foods are stated; the carriers likely or suspected.
      ('Caramelised onion', _fodmap, 'onion', _stated),
      ('Garlic prawns', _fodmap, 'garlic', _stated),
      ('Honey glazed carrots', _fodmap, 'honey', _stated),
      ('Lentil soup', _fodmap, 'lentil', _stated),
      ('Apple crumble', _fodmap, 'apple', _stated),
      ('Hummus plate', _fodmap, 'hummus', _likely),
      ('Chicken broth', _fodmap, 'broth', _suspected),
      ('סלט עם בצל', _fodmap, 'בצל', _stated),
      ('שרימפס בשום', _fodmap, 'בשום', _stated),
      ('שרימפס בשמן שום', _fodmap, 'שום', _stated),
      ('מרק עדשים', _fodmap, 'עדשים', _stated),
      ('עוגת דבש', _fodmap, 'דבש', _stated),
      ('צלחת חומוס', _fodmap, 'חומוס', _likely),
      ('פלאפל בפיתה', _fodmap, 'פלאפל', _likely),
      ('פלאפל בפיתה', _fodmap, 'פיתה', _suspected),
      // Histamine: aged, cured, fermented and fish are stated; the
      // vegetables and "liberators" suspected.
      ('Shaved parmesan', _histamine, 'parmesan', _stated),
      ('Salami board', _histamine, 'salami', _stated),
      ('Tuna steak', _histamine, 'tuna', _stated),
      ('Kimchi fried rice', _histamine, 'kimchi', _stated),
      ('Balsamic glaze', _histamine, 'balsamic', _stated),
      ('A glass of wine', _histamine, 'wine', _stated),
      ('Soy sauce dip', _histamine, 'soy sauce', _likely),
      ('Smoked brisket', _histamine, 'smoked', _likely),
      ('Tomato salad', _histamine, 'tomato', _suspected),
      ('Spinach pie', _histamine, 'spinach', _suspected),
      ('פסטה עם פרמזן', _histamine, 'פרמזן', _stated),
      ('סלט טונה', _histamine, 'טונה', _stated),
      ('כרוב כבוש בצד', _histamine, 'כרוב כבוש', _stated),
      ('רוטב חומץ בלסמי', _histamine, 'חומץ', _stated),
      ('כוס יין', _histamine, 'יין', _stated),
      ('סלמון מעושן', _histamine, 'סלמון מעושן', _stated),
      ('סלט עגבניות', _histamine, 'עגבניות', _suspected),
      ('פשטידת תרד', _histamine, 'תרד', _suspected),
      // Small portions: every cue is hidden; "large" only suspected.
      ('Fried chicken', _glp1, 'fried', _likely),
      ('Creamy mushroom pasta', _glp1, 'creamy', _likely),
      ('Double burger', _glp1, 'double', _likely),
      ('Family size pizza', _glp1, 'family size', _likely),
      ('Chocolate cake', _glp1, 'cake', _likely),
      ('Large fries', _glp1, 'large', _suspected),
      ('Large fries', _glp1, 'fries', _likely),
      ('חזה עוף מטוגן', _glp1, 'מטוגן', _likely),
      ('פסטה ברוטב שמנת', _glp1, 'שמנת', _likely),
      ('המבורגר כפול', _glp1, 'כפול', _likely),
      ('מגש משפחתי', _glp1, 'מגש', _likely),
      ('עוגת שוקולד', _glp1, 'עוגת', _likely),
      ('שניצל עם צ׳יפס', _glp1, "צ'יפס", _likely),
      ('פיצה גדולה', _glp1, 'גדולה', _suspected),
    ];
    for (final (text, id, term, certainty) in cases) {
      test('$text gives ${id.name} "$term" (${certainty.name})', () {
        expect(_certaintyOf(text, id, term), certainty);
      });
    }
  });

  group('no-prefix traps', () {
    const misses = <(String, RestrictionId)>[
      // "משום" is "because", not garlic; "כפול" is "double", not fava.
      ('משום שזה טעים', _fodmap),
      ('המבורגר כפול', _fodmap),
      // "מבקר" is a visitor, "מעגל" a circle, "מטלה" a task, "מחזיר"
      // returns: none of them is meat.
      ('המבקר המליץ', _alphaGal),
      ('מעגל של טעמים', _alphaGal),
      ('מחזיר את הטעם', _alphaGal),
      ('מטלה קלה', _alphaGal),
      // "בציר" is a vintage on a wine list, not a stock.
      ('יין אדום בציר 2019', _alphaGal),
      // "מענק" is a grant, not a giant portion.
      ('מענק לבעלי עסקים', _glp1),
    ];
    for (final (text, id) in misses) {
      test('"$text" gives ${id.name} nothing', () {
        expect(_hits(text, id), isEmpty);
      });
    }
  });

  group('guards lower, never cancel', () {
    const lowered = <(String, RestrictionId)>[
      ('Chicken burger', _alphaGal),
      ('Tuna steak', _alphaGal),
      ('Chicken liver', _alphaGal),
      ('Vegan sausage', _alphaGal),
      ('Kidney beans', _alphaGal),
      ('Turkey bacon', _alphaGal),
      ('קבב עוף', _alphaGal),
      ('כבד עוף', _alphaGal),
      ('פסטרמה הודו', _alphaGal),
      ('נקניקיות עוף', _alphaGal),
      ('Green beans', _fodmap),
      ('Oat milk latte', _fodmap),
      ('Cherry tomatoes', _fodmap),
      ('שעועית ירוקה', _fodmap),
      ('חלב שקדים', _fodmap),
      ('Smoked paprika', _histamine),
      ('Air fried chicken', _glp1),
      ('Stir fried noodles', _glp1),
      ('Double espresso', _glp1),
      ('Rice cake', _glp1),
      ('Diet cola', _glp1),
      ('לא מטוגן', _glp1),
    ];
    for (final (text, id) in lowered) {
      test('"$text" lowers ${id.name} to a guarded suspicion', () {
        expect(_lowered(text, id), isTrue, reason: '${_hits(text, id)}');
      });
    }

    test('a potato is not an apple', () {
      expect(_lowered('תפוח אדמה אפוי', _fodmap), isTrue);
    });

    test('a beef burger stays likely', () {
      expect(_certaintyOf('Beef burger', _alphaGal, 'burger'), _likely);
      expect(_certaintyOf('Beef burger', _alphaGal, 'beef'), _stated);
    });
  });

  group('alpha-gal leaves dairy to the milk entry', () {
    test('cheese, butter, cream and milk give alpha-gal nothing', () {
      for (final text in <String>[
        'Cheese plate',
        'Butter croissant',
        'Whipped cream',
        'Glass of milk',
        'גבינה צהובה',
        'חמאה',
        'שמנת מתוקה',
      ]) {
        expect(_hits(text, _alphaGal), isEmpty, reason: text);
      }
    });
  });
}

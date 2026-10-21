// The foods-extra vocabulary (Banto, issue #342): buckwheat and the foods
// on Japan's recommended list — kiwi, peach, apple, banana, orange, beef,
// pork, chicken, gelatin and yam — in English and Hebrew, with their
// prefix forms, their no-prefix traps and their guards.

import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/utils/allergens/allergen_matcher.dart';
import 'package:ketoclub/utils/allergens/taxonomy.dart';
import 'package:ketoclub/utils/allergens/vocab_foods_extra.dart';
import 'package:ketoclub/utils/allergens/vocabulary.dart';
import 'package:ketoclub/widgets/restriction_picker_sheet.dart';

// One expectation: `text` gives `id` a hit on `term` at certainty `c`.
typedef _Hit = (String text, RestrictionId id, String term, TriggerCertainty c);

const TriggerCertainty _stated = TriggerCertainty.stated;
const TriggerCertainty _likely = TriggerCertainty.likely;
const TriggerCertainty _suspected = TriggerCertainty.suspected;

const RestrictionId _buckwheat = RestrictionId.buckwheat;
const RestrictionId _kiwi = RestrictionId.kiwi;
const RestrictionId _peach = RestrictionId.peach;
const RestrictionId _apple = RestrictionId.apple;
const RestrictionId _banana = RestrictionId.banana;
const RestrictionId _orange = RestrictionId.orange;
const RestrictionId _beef = RestrictionId.beef;
const RestrictionId _pork = RestrictionId.pork;
const RestrictionId _chicken = RestrictionId.chicken;
const RestrictionId _gelatin = RestrictionId.gelatin;
const RestrictionId _yam = RestrictionId.yam;

const List<RestrictionId> _ids = <RestrictionId>[
  _buckwheat,
  _kiwi,
  _peach,
  _apple,
  _banana,
  _orange,
  _beef,
  _pork,
  _chicken,
  _gelatin,
  _yam,
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
  group('foods extra vocabulary', () {
    test('owns exactly its eleven restrictions', () {
      expect(foodsExtraVocabulary.keys.toSet(), _ids.toSet());
    });

    test('every one is strict and now offered in the picker', () {
      for (final id in _ids) {
        expect(restrictionFor(id).isStrict, isTrue, reason: id.name);
        expect(restrictionOffered(id), isTrue, reason: id.name);
      }
    });

    for (final id in _ids) {
      group(id.name, () {
        final vocabulary = allergenVocabulary[id]!;

        test('is filled in both languages and cites its sources', () {
          expect(vocabulary.directEn, isNotEmpty);
          expect(vocabulary.directHe, isNotEmpty);
          expect(vocabulary.sources, isNotEmpty);
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

        test('cites only file 11 §26 and file 12 §10', () {
          for (final source in <String>[
            ...vocabulary.sources,
            for (final trigger in vocabulary.hiddenEn) trigger.source,
            for (final trigger in vocabulary.hiddenHe) trigger.source,
          ]) {
            expect(source, matches(RegExp(r'^(11 §26|12 §10)\.\d+$')));
          }
        });
      });
    }
  });

  group('hits', () {
    const cases = <_Hit>[
      // Buckwheat: the grain and soba are stated; a galette may be wheat.
      ('Buckwheat crêpe with ham', _buckwheat, 'buckwheat', _stated),
      ('Cold soba noodles', _buckwheat, 'soba', _stated),
      ('Kasha varnishkes', _buckwheat, 'kasha', _stated),
      ('Galette de sarrasin', _buckwheat, 'sarrasin', _stated),
      ('Pizzoccheri della Valtellina', _buckwheat, 'pizzoccheri', _likely),
      ('Blinis with salmon roe', _buckwheat, 'blinis', _suspected),
      ('Gluten-free bun', _buckwheat, 'gluten-free', _suspected),
      ('סלט כוסמת', _buckwheat, 'כוסמת', _stated),
      ('אטריות סובה קרות', _buckwheat, 'סובה', _stated),
      ('לחמנייה ללא גלוטן', _buckwheat, 'ללא גלוטן', _suspected),
      // The fruits.
      ('Kiwi sorbet', _kiwi, 'kiwi', _stated),
      ('Fresh fruit salad', _kiwi, 'fruit salad', _suspected),
      ('קינוח קיווי ותותים', _kiwi, 'קיווי', _stated),
      ('Peach melba', _peach, 'peach', _stated),
      ('Grilled nectarines', _peach, 'nectarines', _likely),
      ('סלט אפרסקים', _peach, 'אפרסקים', _stated),
      ('Apple crumble', _apple, 'apple', _stated),
      ('Pork chop with applesauce', _apple, 'applesauce', _stated),
      ('A pint of cider', _apple, 'cider', _suspected),
      ('עוגת תפוחים', _apple, 'תפוחים', _stated),
      ('מיץ תפוחי עץ', _apple, 'תפוחי עץ', _stated),
      ('Banana bread', _banana, 'banana', _stated),
      ('Banoffee pie', _banana, 'banoffee', _likely),
      ('פנקייק בננה', _banana, 'בננה', _stated),
      ("Duck à l'orange", _orange, "l'orange", _stated),
      ('Fresh orange juice', _orange, 'orange', _stated),
      (
        'Crêpes Suzette with Grand Marnier',
        _orange,
        'Grand Marnier',
        _suspected,
      ),
      ('מיץ תפוזים סחוט', _orange, 'תפוזים', _stated),
      // The meats.
      ('Beef stroganoff', _beef, 'beef', _stated),
      ('Veal Milanese', _beef, 'veal', _stated),
      ('Ribeye 300g', _beef, 'ribeye', _stated),
      ('Steak frites', _beef, 'steak', _likely),
      ('Classic cheeseburger', _beef, 'cheeseburger', _likely),
      ('Spaghetti bolognese', _beef, 'bolognese', _likely),
      ('Meatballs in tomato sauce', _beef, 'meatballs', _suspected),
      ('שיפודי בקר', _beef, 'בקר', _stated),
      ('אנטריקוט על האש', _beef, 'אנטריקוט', _stated),
      ('המבורגר 250 גרם', _beef, 'המבורגר', _likely),
      ('פסטרמה בכריך', _beef, 'פסטרמה', _suspected),
      ('Pulled pork bun', _pork, 'pork', _stated),
      ('Crispy bacon', _pork, 'bacon', _stated),
      ('Ham and cheese toastie', _pork, 'ham', _stated),
      ('Spaghetti carbonara', _pork, 'carbonara', _suspected),
      ('Chorizo tacos', _pork, 'chorizo', _likely),
      ('צלעות חזיר', _pork, 'חזיר', _stated),
      ('סטייק בשר לבן', _pork, 'בשר לבן', _likely),
      ('פיצה עם בייקון', _pork, 'בייקון', _likely),
      ('Chicken Caesar salad', _chicken, 'chicken', _stated),
      ('Buffalo wings', _chicken, 'wings', _likely),
      ('Kids nuggets', _chicken, 'nuggets', _likely),
      ('Chicken stock', _chicken, 'chicken', _stated),
      ('Vegetable stock', _chicken, 'stock', _suspected),
      ('חזה עוף בגריל', _chicken, 'עוף', _stated),
      ('פרגית על האש', _chicken, 'פרגית', _stated),
      ('שניצל עם צ׳יפס', _chicken, 'שניצל', _likely),
      ('שווארמה בלאפה', _chicken, 'שווארמה', _suspected),
      // Gelatin.
      ('Fish gelatin', _gelatin, 'gelatin', _stated),
      ('Vanilla panna cotta', _gelatin, 'panna cotta', _likely),
      ('Toasted marshmallows', _gelatin, 'marshmallows', _likely),
      ('Chocolate mousse', _gelatin, 'mousse', _suspected),
      ('קינוח עם ג׳לטין', _gelatin, "ג'לטין", _stated),
      ('פנקוטה וניל', _gelatin, 'פנקוטה', _likely),
      ('מוס שוקולד', _gelatin, 'מוס', _suspected),
      // Yam: Japan's mountain yam.
      ('Soba with tororo', _yam, 'tororo', _stated),
      ('Nagaimo salad', _yam, 'nagaimo', _stated),
      ('Okonomiyaki', _yam, 'okonomiyaki', _suspected),
      ('אורז עם טורורו', _yam, 'טורורו', _stated),
    ];
    for (final (text, id, term, certainty) in cases) {
      test('$text gives ${id.name} "$term" (${certainty.name})', () {
        expect(_certaintyOf(text, id, term), certainty);
      });
    }
  });

  group('words that are not these foods', () {
    const misses = <(String, RestrictionId)>[
      // Buckwheat is not wheat, and spelt (כוסמין) is not buckwheat.
      ('Wheat bread', _buckwheat),
      ('לחם כוסמין', _buckwheat),
      // Yakisoba is wheat noodles, one word to the matcher.
      ('Yakisoba', _buckwheat),
      ('יאקיסובה עוף', _buckwheat),
      // Pineapple is not apple; the plural potato never matches.
      ('Pineapple salsa', _apple),
      ('תפוחי אדמה אפויים', _apple),
      ('סלט אננס', _apple),
      // An orange and an apple are different words in Hebrew too.
      ('מיץ תפוזים', _apple),
      ('עוגת תפוחים', _orange),
      // Persimmon is not peach.
      ('אפרסמון טרי', _peach),
      // Yam is not sweet potato: "candied yams" are sweet potatoes, and
      // בטטה is never yam.
      ('Candied yams', _yam),
      ('Sweet potato fries', _yam),
      ('בטטה צלויה', _yam),
      // Visitors, circles and returns are not meat (no free prefix).
      ('המבקר המליץ', _beef),
      ('מעגל של טעמים', _beef),
      ('מחזיר את הטעם', _pork),
      // A vintage is not a stock.
      ('יין אדום בציר 2019', _chicken),
      ('יין אדום בציר 2019', _beef),
      // A chickpea is not a chicken.
      ('Chickpea curry', _chicken),
      // Hamachi is a fish, a hamburger is not ham.
      ('Hamachi crudo', _pork),
      ('Hamburger', _pork),
    ];
    for (final (text, id) in misses) {
      test('"$text" gives ${id.name} nothing', () {
        expect(_hits(text, id), isEmpty, reason: '${_hits(text, id)}');
      });
    }
  });

  group('guards lower, never cancel', () {
    const lowered = <(String, RestrictionId)>[
      ('No kiwi please', _kiwi),
      ('Kiwi-free sorbet', _kiwi),
      ('Buckwheat honey', _buckwheat),
      ('Yaki soba', _buckwheat),
      ('יאקי סובה', _buckwheat),
      ('ללא כוסמת', _buckwheat),
      ('תפוח אדמה אפוי', _apple),
      ('Custard apple', _apple),
      ('Pear cider', _apple),
      ('Banana peppers', _banana),
      ('Fish in banana leaf', _banana),
      ('Pan-fried orange roughy', _orange),
      ('A glass of orange wine', _orange),
      ('Tuna steak', _beef),
      ('Chicken burger', _beef),
      ('Beet carpaccio', _beef),
      ('Turkey pastrami', _beef),
      ('Vegan burger', _beef),
      ('המבורגר עוף', _beef),
      ('קרפצ׳יו סלק', _beef),
      ('Turkey bacon', _pork),
      ('Turkey ham', _pork),
      ('Chicken sausage', _pork),
      ('Guinea pig', _pork),
      ('בייקון בקר', _pork),
      ('פרושוטו אווז', _pork),
      ('Chicken-fried steak', _chicken),
      ('Chicken of the woods', _chicken),
      ('Cauliflower wings', _chicken),
      ('Vegan nuggets', _chicken),
      ('שניצל תירס', _chicken),
      ('שניצל טבעוני', _chicken),
      ('שווארמה הודו', _chicken),
      ('Vegan panna cotta', _gelatin),
      ('Agar jelly', _gelatin),
      ('Gelatin-free dessert', _gelatin),
    ];
    for (final (text, id) in lowered) {
      test('"$text" lowers ${id.name} to a guarded suspicion', () {
        expect(_lowered(text, id), isTrue, reason: '${_hits(text, id)}');
      });
    }

    test('a chicken-fried steak stays a likely beef dish', () {
      expect(_certaintyOf('Chicken-fried steak', _beef, 'steak'), _likely);
    });

    test('a beef burger stays likely and beef stated', () {
      expect(_certaintyOf('Beef burger', _beef, 'burger'), _likely);
      expect(_certaintyOf('Beef burger', _beef, 'beef'), _stated);
    });

    test('kosher beef bacon is beef, stated', () {
      expect(_certaintyOf('Beef bacon', _beef, 'beef'), _stated);
      expect(_certaintyOf('בייקון בקר', _beef, 'בקר'), _stated);
    });
  });

  group('buckwheat is never lowered by the wheat guard', () {
    test('buckwheat flour: wheat lowered, buckwheat stated', () {
      const text = 'Pancakes made with buckwheat flour';
      expect(_certaintyOf(text, _buckwheat, 'buckwheat'), _stated);
      final wheat = _hits(text, RestrictionId.wheat);
      expect(
        wheat.where((hit) => hit.term == 'flour').every((hit) => hit.guarded),
        isTrue,
        reason: '$wheat',
      );
    });

    test('קמח כוסמת: buckwheat stated', () {
      expect(_certaintyOf('קמח כוסמת', _buckwheat, 'כוסמת'), _stated);
    });
  });

  group('beef leaves milk, chicken leaves eggs', () {
    test('dairy gives beef nothing', () {
      for (final text in <String>['Cheese plate', 'Glass of milk', 'חמאה']) {
        expect(_hits(text, _beef), isEmpty, reason: text);
      }
    });

    test('an omelette and chicken eggs give chicken no stated hit', () {
      expect(_hits('Omelette with herbs', _chicken), isEmpty);
      expect(_lowered('Free range chicken eggs', _chicken), isTrue);
    });
  });
}

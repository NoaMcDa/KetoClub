import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/utils/allergens/allergen_matcher.dart';
import 'package:ketoclub/utils/allergens/vocabulary.dart';

// One expectation: `text` gives `id` a hit on `term` at certainty `c`.
typedef _Hit = (String text, RestrictionId id, String term, TriggerCertainty c);

const TriggerCertainty _stated = TriggerCertainty.stated;
const TriggerCertainty _likely = TriggerCertainty.likely;
const TriggerCertainty _suspected = TriggerCertainty.suspected;

const RestrictionId _wheat = RestrictionId.wheat;
const RestrictionId _gluten = RestrictionId.gluten;
const RestrictionId _lupin = RestrictionId.lupin;

const List<RestrictionId> _ids = <RestrictionId>[_wheat, _gluten, _lupin];

/// Every hit [id] gets on [text].
List<AllergenHit> _hits(String text, RestrictionId id) =>
    AllergenMatcher.find(text)
        .where((hit) => hit.id == id)
        .toList(growable: false);

/// Whether [hits] are all lowered by a guard, and there is one (a guard
/// lowers a hit to suspected, never cancels it; ALG-04a).
bool _lowered(List<AllergenHit> hits) =>
    hits.isNotEmpty &&
    hits.every((hit) => hit.guarded && hit.certainty == _suspected);

/// The certainty of [id]'s hit on [term] in [text], or null.
TriggerCertainty? _certaintyOf(String text, RestrictionId id, String term) {
  for (final hit in _hits(text, id)) {
    if (hit.term == term) return hit.certainty;
  }
  return null;
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
  group('gluten and grains vocabulary', () {
    for (final id in _ids) {
      group(id.name, () {
        final vocabulary = allergenVocabulary[id]!;

        test('is filled and cites its sources', () {
          expect(vocabulary.isEmpty, isFalse);
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

        test('every prefixable Hebrew term takes ב, ו and ה in front', () {
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

        test('every no-prefix term refuses a prefix letter', () {
          for (final term in vocabulary.noPrefixHe) {
            expect(_certaintyOf('עם ש$term', id, term), isNull, reason: term);
          }
        });
      });
    }

    test('gluten holds every wheat term and more', () {
      // Arrange
      final wheat = allergenVocabulary[_wheat]!;
      final gluten = allergenVocabulary[_gluten]!;

      // Assert
      expect(gluten.directEn, containsAll(wheat.directEn));
      expect(gluten.directHe, containsAll(wheat.directHe));
      expect(
        gluten.hiddenEn.map((t) => t.term),
        containsAll(wheat.hiddenEn.map((t) => t.term)),
      );
      expect(gluten.directEn.length, greaterThan(wheat.directEn.length));
    });
  });

  group('direct hits', () {
    const cases = <_Hit>[
      ('Whole wheat pita', _wheat, 'wheat', _stated),
      ('Whole wheat pita', _wheat, 'pita', _stated),
      ('Whole wheat pita', _gluten, 'pita', _stated),
      ('Spaghetti carbonara', _wheat, 'spaghetti', _stated),
      ('Beef burger on a brioche bun', _wheat, 'bun', _stated),
      ('Fresh egg noodles', _wheat, 'noodles', _stated),
      ('Chicken in panko breadcrumbs', _wheat, 'panko', _stated),
      ('Lamb with couscous and bulgur', _wheat, 'couscous', _stated),
      ('Lamb with couscous and bulgur', _wheat, 'bulgur', _stated),
      ('Spelt sourdough', _wheat, 'spelt', _stated),
      ('Chocolate cake', _wheat, 'cake', _stated),
      ('Oatmeal cookies', _wheat, 'cookies', _stated),
      ('Almond croissant', _wheat, 'croissant', _stated),
      ('Fish in beer batter', _wheat, 'batter', _stated),
      ('Crispy breaded chicken', _wheat, 'breaded', _stated),
      ('Seitan steak', _wheat, 'seitan', _stated),
      ('Seitan steak', _gluten, 'seitan', _stated),
      ('פיתה עם חומוס', _wheat, 'פיתה', _stated),
      ('חומוס בפיתה', _wheat, 'פיתה', _stated),
      ('סלט והקוסקוס', _wheat, 'קוסקוס', _stated),
      ('סלט והקוסקוס', _gluten, 'קוסקוס', _stated),
      ('קבב בלאפה', _wheat, 'לאפה', _stated),
      ('המבורגר בלחמנייה', _wheat, 'לחמנייה', _stated),
      ('לחם שום', _wheat, 'לחם', _stated),
      ('פסטה ברוטב שמנת', _wheat, 'פסטה', _stated),
      ('אטריות מוקפצות', _wheat, 'אטריות', _stated),
      ('נודלס עם ירקות', _wheat, 'נודלס', _stated),
      ('פתיתים עם גבינה', _wheat, 'פתיתים', _stated),
      ('בורגול ועלי גפן', _wheat, 'בורגול', _stated),
      ('סולת וחמאה', _wheat, 'סולת', _stated),
      ('קוביות כוסמין', _wheat, 'כוסמין', _stated),
      ('קוביות כוסמין', _gluten, 'כוסמין', _stated),
      ('בורקס גבינה', _wheat, 'בורקס', _stated),
      ('בורקס גבינה', _gluten, 'בורקס', _stated),
      ('מלאווח עם ביצה', _wheat, 'מלאווח', _stated),
      ('מלווח עם ביצה', _wheat, 'מלווח', _stated),
      ('כובאנה עם ביצה', _wheat, 'כובאנה', _stated),
      ('פירורי לחם', _wheat, 'פירורי לחם', _stated),
      ('מרק עוף עם שקדי מרק', _wheat, 'שקדי מרק', _stated),
      ('עוגת גבינה', _wheat, 'עוגת', _stated),
      ('עוגיות שוקולד', _wheat, 'עוגיות', _stated),
      ('מאפה גבינה', _wheat, 'מאפה', _stated),
      ('פיצה מרגריטה', _wheat, 'פיצה', _stated),
      ('חלה לשבת', _wheat, 'חלה', _stated),
      ('בחלה טרייה', _wheat, 'בחלה', _stated),
      ('חיטה מלאה', _wheat, 'חיטה', _stated),
      ('מחיטה מלאה', _wheat, 'מחיטה', _stated),
      ('Sliced ribeye on a hoagie roll', _wheat, 'hoagie', _stated),
      ('Sliced ribeye on a hoagie roll', _gluten, 'hoagie', _stated),
      ('Cheese khachapuri', _wheat, 'khachapuri', _stated),
      ('פוקאצ׳ה שום', _wheat, 'פוקאצ׳ה', _stated),
      ("פוקאצ'ה שום", _gluten, 'פוקאצ׳ה', _stated),
      ('חצ׳פורי מגרולי', _wheat, 'חצ׳פורי', _stated),
      ("חצ'פורי עם ביצה", _gluten, 'חצ׳פורי', _stated),
      ('בחצ׳פורי', _wheat, 'חצ׳פורי', _stated),
      ('מסקרפונה וביסקוויטים', _wheat, 'ביסקוויטים', _stated),
      ('מסקרפונה וביסקוויטים', _gluten, 'ביסקוויטים', _stated),
      ('ביסקוויט שוקולד', _wheat, 'ביסקוויט', _stated),
      ('Barley soup', _gluten, 'barley', _stated),
      ('Rye bread', _gluten, 'rye', _stated),
      ('Malt vinegar', _gluten, 'malt', _stated),
      ("Brewer's yeast", _gluten, "brewer's yeast", _stated),
      ('Pint of lager', _gluten, 'lager', _stated),
      ('Contains gluten', _gluten, 'gluten', _stated),
      ('מכיל גלוטן', _gluten, 'גלוטן', _stated),
      ('מרק שעורה', _gluten, 'שעורה', _stated),
      ('לחם שיפון', _gluten, 'שיפון', _stated),
      ('בירה מהחבית', _gluten, 'בירה', _stated),
      ('הבירה של הבית', _gluten, 'הבירה', _stated),
      ('מבושל בבירה', _gluten, 'בבירה', _stated),
      ('מאלט שעורה', _gluten, 'מאלט', _stated),
      ('Lupin flour flatbread', _lupin, 'lupin', _stated),
      ('Lupini beans', _lupin, 'lupini', _stated),
      ('Tremoços', _lupin, 'tremoços', _stated),
      ('תורמוס כבוש', _lupin, 'תורמוס', _stated),
      ('חטיף בתורמוס', _lupin, 'תורמוס', _stated),
      ('קמח לופין', _lupin, 'לופין', _stated),
    ];
    for (final (text, id, term, certainty) in cases) {
      test('$text gives ${id.name} "$term" (${certainty.name})', () {
        expect(_certaintyOf(text, id, term), certainty);
      });
    }

    test('wheat alone is not a gluten cereal beyond wheat', () {
      expect(_hits('Barley soup', _wheat), isEmpty);
      expect(_hits('Rye bread', _wheat).map((hit) => hit.term), <String>[
        'bread',
      ]);
      expect(_hits('בירה מהחבית', _wheat), isEmpty);
    });

    test('both apostrophes of ג׳חנון match, with or without a prefix', () {
      for (final text in <String>[
        "ג'חנון עם ביצה",
        'ג׳חנון עם ביצה',
        "ג'חנון",
        'ג׳חנון',
        "בג'חנון",
        'והג׳חנון',
        "ג'חנונים",
      ]) {
        final expected = text == "ג'חנונים" ? isNull : isNotNull;
        expect(_certaintyOf(text, _wheat, "ג'חנון"), expected, reason: text);
      }
    });
  });

  group('hidden sources keep their certainty', () {
    const cases = <_Hit>[
      ('Salmon in soy sauce', _wheat, 'soy sauce', _likely),
      ('Salmon in soy sauce', _gluten, 'soy sauce', _likely),
      ('Teriyaki chicken', _wheat, 'teriyaki', _likely),
      ('Hoisin duck', _gluten, 'hoisin', _likely),
      ('Chicken schnitzel', _wheat, 'schnitzel', _likely),
      ('Chicken schnitzel', _gluten, 'schnitzel', _likely),
      ('Crispy nuggets', _wheat, 'nuggets', _likely),
      ('Beer batter onion rings', _wheat, 'beer batter', _likely),
      ('Beer batter onion rings', _gluten, 'beer batter', _likely),
      ('Plain flour dusting', _wheat, 'flour', _likely),
      ('Pork and cabbage egg rolls', _wheat, 'egg rolls', _likely),
      ('Pork and cabbage egg rolls', _gluten, 'egg rolls', _likely),
      ('Crispy egg roll', _wheat, 'egg roll', _likely),
      ('Part-baked dinner rolls', _wheat, 'rolls', _likely),
      ('Part-baked dinner rolls', _gluten, 'rolls', _likely),
      ('Lobster roll', _wheat, 'roll', _likely),
      ('Lobster roll', _gluten, 'roll', _likely),
      ('Wholemeal loaf with figs', _wheat, 'loaf', _likely),
      ('Wholemeal loaf with figs', _gluten, 'wholemeal', _likely),
      ('Meat loaf', _wheat, 'loaf', _likely),
      ('Two crusty loaves', _wheat, 'loaves', _likely),
      ('Chowder with oyster crackers', _wheat, 'crackers', _likely),
      ('Chowder with oyster crackers', _gluten, 'crackers', _likely),
      ('Water cracker', _wheat, 'cracker', _likely),
      ('Warm apple pie', _wheat, 'pie', _likely),
      ('Warm apple pie', _gluten, 'pie', _likely),
      ('Pecan pies', _wheat, 'pies', _likely),
      ('פאי תפוחים', _wheat, 'פאי', _likely),
      ('פנה פסטו', _wheat, 'פנה', _likely),
      ('פנה פסטו', _gluten, 'פנה', _likely),
      ('פילה בגלייז סויה־דבש', _wheat, 'גלייז סויה', _likely),
      ('פילה בגלייז סויה־דבש', _gluten, 'גלייז סויה', _likely),
      ('Floured potatoes', _wheat, 'floured', _suspected),
      ('Floured potatoes', _gluten, 'floured', _suspected),
      ('Vegetable stock cube', _gluten, 'stock cube', _suspected),
      ('Rich gravy', _wheat, 'gravy', _suspected),
      ('Imitation crab salad', _wheat, 'imitation crab', _suspected),
      ('Italian sausage', _gluten, 'sausage', _suspected),
      ('Chicken burger', _wheat, 'burger', _suspected),
      ('Corn tortilla tacos', _wheat, 'tortilla', _suspected),
      ('Rolled oats', _gluten, 'oats', _suspected),
      ('Oat milk latte', _gluten, 'oat', _suspected),
      ('Granola bowl', _gluten, 'granola', _suspected),
      ('Goldstar', _gluten, 'goldstar', _likely),
      ('A pint of Goldstar', _gluten, 'goldstar', _likely),
      ('San Miguel', _gluten, 'san miguel', _likely),
      ('גולדסטאר', _gluten, 'גולדסטאר', _likely),
      ('בקבוק גולדסטאר', _gluten, 'גולדסטאר', _likely),
      ('סאן מיגל', _gluten, 'סאן מיגל', _likely),
      ('פרסקה סאן מיגל', _gluten, 'סאן מיגל', _likely),
      ('רוטב סויה ושומשום', _wheat, 'רוטב סויה', _likely),
      ('רוטב סויה ושומשום', _gluten, 'רוטב סויה', _likely),
      ('עוף בטריאקי', _wheat, 'טריאקי', _likely),
      ('שניצל עוף', _wheat, 'שניצל', _likely),
      ('שניצל עוף', _gluten, 'שניצל', _likely),
      ('בבלילת בירה', _wheat, 'בלילת בירה', _likely),
      ('קמח מלא', _wheat, 'קמח', _likely),
      ('תפוחי אדמה מקומחים', _wheat, 'מקומחים', _suspected),
      ('ציר ירקות', _wheat, 'ציר', _suspected),
      ('ציר ירקות', _gluten, 'ציר', _suspected),
      ('קוביות מרק', _gluten, 'קוביות מרק', _suspected),
      ('קציצות בקר', _wheat, 'קציצות', _suspected),
      ('המבורגר 200 גרם', _wheat, 'המבורגר', _suspected),
      ('שיבולת שועל', _gluten, 'שיבולת שועל', _suspected),
      ('גרנולה ביתית', _gluten, 'גרנולה', _suspected),
      ('Wheat-free brownie', _gluten, 'wheat free', _suspected),
      ('ללא חיטה', _gluten, 'ללא חיטה', _suspected),
      ('Gluten free bread', _lupin, 'gluten free bread', _suspected),
      ('Gluten-free pizza base', _lupin, 'gluten free pizza', _suspected),
      ('לחם ללא גלוטן', _lupin, 'לחם ללא גלוטן', _suspected),
      ('עוגה נטולת גלוטן', _lupin, 'עוגה נטולת גלוטן', _suspected),
    ];
    for (final (text, id, term, certainty) in cases) {
      test('$text gives ${id.name} "$term" (${certainty.name})', () {
        expect(_certaintyOf(text, id, term), certainty);
      });
    }

    test('a beer brand is gluten, not wheat', () {
      expect(_hits('Goldstar', _wheat), isEmpty);
      expect(_hits('סאן מיגל', _wheat), isEmpty);
    });

    test('plain soy is not wheat, only the soy glaze is', () {
      expect(_hits('סלמון בסויה', _wheat), isEmpty);
      expect(_hits('סלמון בסויה', _gluten), isEmpty);
      expect(_hits('Soy glazed salmon', _wheat), isEmpty);
    });

    test('a roll is bread unless a guard names another food', () {
      for (final id in <RestrictionId>[_wheat, _gluten]) {
        for (final text in <String>[
          'Spring roll',
          'Spring rolls',
          'Sushi roll',
          'California roll',
          'Salmon avocado roll',
          'Summer rolls',
          'Rice paper rolls',
          'Vietnamese roll',
          'Lettuce rolls',
          'Cabbage rolls',
        ]) {
          final hits = _hits(
            text,
            id,
          ).where((hit) => hit.term == 'roll' || hit.term == 'rolls');
          expect(_lowered(hits.toList()), isTrue, reason: '$text: $hits');
        }
        expect(_certaintyOf('Egg rolls', id, 'egg rolls'), _likely);
        expect(_certaintyOf('Bread rolls', id, 'rolls'), _likely);
        expect(_certaintyOf('Cinnamon roll', id, 'roll'), _likely);
        expect(_certaintyOf('Roll with butter', id, 'roll'), _likely);
      }
    });

    test('rock and roll and rolled are no bread', () {
      expect(_hits('Rock and roll burger', _wheat).map((h) => h.term), <String>[
        'roll',
        'burger',
      ]);
      expect(_hits('Rolled lamb', _wheat), isEmpty);
      expect(_hits('Enrolled', _wheat), isEmpty);
    });

    test('rice, seaweed and seed crackers are lowered, never dropped', () {
      for (final text in <String>[
        'Rice crackers',
        'Seaweed crackers',
        'Cassava crackers',
        'Almond crackers',
        'Seed crackers',
      ]) {
        final hits = _hits(text, _wheat).where((hit) => hit.term == 'crackers');
        expect(_lowered(hits.toList()), isTrue, reason: '$text: $hits');
      }
      expect(_certaintyOf('Cheese crackers', _wheat, 'crackers'), _likely);
    });

    test('gluten-free rolls and crackers are lowered by the global guard', () {
      expect(_lowered(_hits('Gluten-free rolls', _wheat)), isTrue);
      expect(
        _hits('Gluten free crackers', _gluten).where((h) => !h.guarded),
        isEmpty,
      );
    });

    test('penne (פנה) is a whole word: no prefix letter, no longer word', () {
      expect(_certaintyOf('עם פנה', _wheat, 'פנה'), _likely);
      expect(_certaintyOf('הפנה אותי', _wheat, 'פנה'), isNull);
      expect(_certaintyOf('בפנה', _wheat, 'פנה'), isNull);
      expect(_certaintyOf('פנים', _wheat, 'פנה'), isNull);
      expect(_certaintyOf('פינה', _wheat, 'פנה'), isNull);
      expect(_certaintyOf('פנהו', _wheat, 'פנה'), isNull);
    });

    test('oats, beer and "wheat free" are not wheat', () {
      expect(_hits('Rolled oats', _wheat), isEmpty);
      expect(_lowered(_hits('Wheat-free brownie', _wheat)), isTrue);
      expect(
        _hits(
          'Wheat-free brownie',
          _gluten,
        ).map((h) => '${h.term}${h.guarded ? ':guarded' : ''}'),
        <String>['wheat:guarded', 'wheat free', 'brownie'],
      );
    });
  });

  group('guards', () {
    const gone = <(String, RestrictionId)>[
      ('Gluten-free bun', _wheat),
      ('Gluten-free bun', _gluten),
      ('Gluten free pasta', _wheat),
      ('Gluten free pasta', _gluten),
      ('Pizza, gluten free', _wheat),
      ('Pizza, gluten free', _gluten),
      ('Pizza GF', _gluten),
      ('GF pizza', _wheat),
      ('Brownie (GF)', _gluten),
      ('Gluten-free oats', _gluten),
      ('Gluten-free soy sauce', _wheat),
      ('Gluten-free soy sauce', _gluten),
      ('Contains no gluten', _gluten),
      ('Made without gluten', _gluten),
      ('Free from gluten', _gluten),
      ('Burger with no bun', _wheat),
      ('Wheat-free bread', _wheat),
      ('Wheat free pasta', _wheat),
      ('Without wheat', _wheat),
      ('פיתה ללא גלוטן', _wheat),
      ('פיתה ללא גלוטן', _gluten),
      ('ללא גלוטן פיצה', _gluten),
      ('פסטה נטול גלוטן', _wheat),
      ('פסטה בלי גלוטן', _gluten),
      ('מנה ללא גלוטן', _gluten),
      ('המבורגר ללא לחמנייה', _wheat),
      ('ללא חיטה', _wheat),
      ('נטול חיטה', _wheat),
      ('עוגה ללא קמח', _wheat),
      ('Without lupin', _lupin),
      ('Lupin-free', _lupin),
      ('ללא לופין', _lupin),
    ];
    for (final (text, id) in gone) {
      test('$text: ${id.name} has the guarded trigger only lowered', () {
        final hits = _hits(text, id);
        expect(hits.where((hit) => hit.guarded), isNotEmpty);
        expect(
          hits.where((hit) => hit.guarded).map((hit) => hit.certainty),
          everyElement(_suspected),
        );
        final remaining = <String>[
          for (final hit in hits)
            if (!hit.guarded) hit.term,
        ];
        final guarded = <String>{
          'bun',
          'pasta',
          'pizza',
          'oats',
          'oat',
          'soy sauce',
          'brownie',
          'bread',
          'wheat',
          'gluten',
          'פיתה',
          'פיצה',
          'פסטה',
          'לחמנייה',
          'חיטה',
          'גלוטן',
          'קמח',
          'lupin',
          'לופין',
        };
        expect(
          remaining.where(guarded.contains),
          isEmpty,
          reason: '$remaining',
        );
      });
    }

    test('a flour that is not wheat is lowered, never dropped', () {
      for (final id in <RestrictionId>[_wheat, _gluten]) {
        for (final (text, term) in <(String, String)>[
          ('Rice flour pancakes', 'flour'),
          ('Chickpea flour batter', 'flour'),
          ('עוגה מקמח אורז', 'קמח'),
          ('קמח תפוחי אדמה', 'קמח'),
        ]) {
          final hits = _hits(text, id).where((hit) => hit.term == term);
          expect(_lowered(hits.toList()), isTrue, reason: '$text: $hits');
        }
        expect(_certaintyOf('Oat flour', id, 'flour'), _likely);
        expect(_certaintyOf('Rice and flour', id, 'flour'), _likely);
      }
    });

    test('a guard never makes wheat-free read as gluten-free', () {
      expect(_certaintyOf('Wheat-free', _gluten, 'wheat free'), _suspected);
      expect(_lowered(_hits('Wheat-free', _wheat)), isTrue);
      expect(_lowered(_hits('נטול חיטה', _wheat)), isTrue);
      expect(_certaintyOf('נטול חיטה', _gluten, 'נטול חיטה'), _suspected);
    });

    test('wheat free and gluten free together lower both ids', () {
      expect(_lowered(_hits('Gluten free, wheat free bread', _wheat)), isTrue);
      expect(_lowered(_hits('Gluten free bread', _gluten)), isTrue);
    });

    test('gluten-free bakery still raises lupin, even as it lowers gluten', () {
      expect(_lowered(_hits('Gluten-free bun', _gluten)), isTrue);
      expect(
        _certaintyOf('Gluten-free bun', _lupin, 'gluten free bun'),
        _suspected,
      );
    });

    test('a guard never reaches past two words', () {
      expect(
        _certaintyOf('Gluten free option available: pita', _wheat, 'pita'),
        _stated,
      );
      expect(
        _certaintyOf('פיתה עם חומוס טחינה ללא גלוטן', _wheat, 'פיתה'),
        _stated,
      );
    });

    test(
      'vegetarian and rice are not guards: a pita beside rice still hits',
      () {
        expect(
          _certaintyOf('Chicken with rice, pita and salad', _wheat, 'pita'),
          _stated,
        );
        expect(_certaintyOf('עוף עם אורז ופיתה', _wheat, 'פיתה'), _stated);
      },
    );
  });

  group('confusions produce no hit', () {
    const texts = <String>[
      'Roasted buckwheat',
      'Buckwheat groats',
      'כוסמת מבושלת',
      'סלט כוסמת',
      'פתיתי אורז',
      'פתיתי אורז עם ירקות',
      'שחיטה כשרה',
      'חולה במחלה',
      'מחלות',
      'כבירה',
      'אורז בסמטי',
      'Basmati rice',
      'Quinoa salad',
      'סלט קינואה',
    ];
    for (final text in texts) {
      test('"$text" is neither wheat nor gluten', () {
        expect(_hits(text, _wheat), isEmpty);
        expect(_hits(text, _gluten), isEmpty);
      });
    }

    test('buckwheat is no wheat even next to the word wheat', () {
      expect(
        _hits('Buckwheat and wheat', _wheat).map((hit) => hit.term),
        <String>['wheat'],
      );
    });

    test('challah is a hit but an illness is not', () {
      expect(_certaintyOf('חלה', _wheat, 'חלה'), _stated);
      expect(_hits('מחלה', _wheat), isEmpty);
      expect(_hits('שחלה', _wheat), isEmpty);
    });

    test('a vast sum is not a beer, a beer is', () {
      expect(_hits('כמות כבירה', _gluten), isEmpty);
      expect(_hits('כבירה', _gluten), isEmpty);
      expect(_certaintyOf('בירה', _gluten, 'בירה'), _stated);
    });

    test('rice ptitim is not wheat but ptitim is', () {
      expect(_hits('פתיתי אורז', _wheat), isEmpty);
      expect(_certaintyOf('פתיתים', _wheat, 'פתיתים'), _stated);
    });

    test('lupin has no hit in an unrelated menu', () {
      expect(_hits('Grilled salmon with rice', _lupin), isEmpty);
      expect(_hits('סלט ירקות', _lupin), isEmpty);
    });
  });

  group('hidden sources added for the recall gate (issue #352)', () {
    // Wheat: sauces with flour or soy, roux dishes, deep-fried food (11 §7.2,
    // 11 §7.4, 12 §5). Lupin: the baked goods Anaphylaxis UK names (11 §14.2).
    // Each term is suspected, in a plain sentence and behind a Hebrew prefix.
    const cases = <_Hit>[
      ('Served with stir fry', _wheat, 'stir fry', _suspected),
      ('Served with oyster sauce', _wheat, 'oyster sauce', _suspected),
      ('Served with cream sauce', _wheat, 'cream sauce', _suspected),
      ('Served with risotto', _wheat, 'risotto', _suspected),
      ('Served with fried fish', _wheat, 'fried fish', _suspected),
      ('Served with baked potato', _wheat, 'baked potato', _suspected),
      ('Served with garlic sauce', _wheat, 'garlic sauce', _suspected),
      (
        'Served with garlic chili sauce',
        _wheat,
        'garlic chili sauce',
        _suspected,
      ),
      (
        'Served with garlic and chili sauce',
        _wheat,
        'garlic and chili sauce',
        _suspected,
      ),
      ('Served with deep fried', _wheat, 'deep fried', _suspected),
      ('Served with sashimi', _wheat, 'sashimi', _suspected),
      ('מנה עם רוטב צדפות', _wheat, 'רוטב צדפות', _suspected),
      ('מנה ברוטב צדפות', _wheat, 'רוטב צדפות', _suspected),
      ('מנה עם רוטב שמנת', _wheat, 'רוטב שמנת', _suspected),
      ('מנה ברוטב שמנת', _wheat, 'רוטב שמנת', _suspected),
      ('מנה עם ריזוטו', _wheat, 'ריזוטו', _suspected),
      ('מנה בריזוטו', _wheat, 'ריזוטו', _suspected),
      ('מנה עם דג מטוגן', _wheat, 'דג מטוגן', _suspected),
      ('מנה בדג מטוגן', _wheat, 'דג מטוגן', _suspected),
      ('מנה עם סשימי', _wheat, 'סשימי', _suspected),
      ('מנה בסשימי', _wheat, 'סשימי', _suspected),
      ('Served with croissant', _lupin, 'croissant', _suspected),
      ('Served with croissants', _lupin, 'croissants', _suspected),
      ('Served with quiche', _lupin, 'quiche', _suspected),
      ('Served with rolls', _lupin, 'rolls', _suspected),
      ('Served with gluten free base', _lupin, 'gluten free base', _suspected),
      ('מנה עם קרואסון', _lupin, 'קרואסון', _suspected),
      ('מנה בקרואסון', _lupin, 'קרואסון', _suspected),
      ('מנה עם קיש', _lupin, 'קיש', _suspected),
      ('מנה בקיש', _lupin, 'קיש', _suspected),
      ('מנה עם לחמניות', _lupin, 'לחמניות', _suspected),
      ('מנה בלחמניות', _lupin, 'לחמניות', _suspected),
      ('מנה עם בסיס ללא גלוטן', _lupin, 'בסיס ללא גלוטן', _suspected),
      ('מנה בבסיס ללא גלוטן', _lupin, 'בסיס ללא גלוטן', _suspected),
    ];
    for (final (text, id, term, certainty) in cases) {
      test('$text gives ${id.name} "$term" (${certainty.name})', () {
        expect(_certaintyOf(text, id, term), certainty);
      });
    }
  });
}

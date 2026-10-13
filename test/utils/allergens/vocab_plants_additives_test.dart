import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/utils/allergens/allergen_matcher.dart';
import 'package:ketoclub/utils/allergens/vocabulary.dart';
import 'package:ketoclub/utils/text_normaliser.dart';

/// The restrictions `vocab_plants_additives.dart` owns.
const List<RestrictionId> _ids = <RestrictionId>[
  RestrictionId.soy,
  RestrictionId.celery,
  RestrictionId.mustard,
  RestrictionId.sulphites,
  RestrictionId.legumes,
];

/// The hits [AllergenMatcher.find] reports for [id] in [text], each as
/// `term:certainty`. Filtered by id so the other groups' vocabularies
/// (filled by their own pull requests) cannot change these tests.
List<String> _hits(String text, RestrictionId id) => <String>[
  for (final hit in AllergenMatcher.find(text))
    if (hit.id == id) '${hit.term}:${hit.certainty.name}',
];

/// One expectation: `text` reports every entry of `has` for `id` and none
/// of the terms in `lacks`; with both empty it reports nothing at all.
typedef _Case = ({
  String text,
  RestrictionId id,
  List<String> has,
  List<String> lacks,
  String why,
});

_Case _hit(
  String text,
  RestrictionId id,
  List<String> has, {
  String why = '',
}) => (text: text, id: id, has: has, lacks: const <String>[], why: why);

_Case _miss(
  String text,
  RestrictionId id, {
  List<String> lacks = const <String>[],
  String why = '',
}) => (text: text, id: id, has: const <String>[], lacks: lacks, why: why);

void _run(List<_Case> cases) {
  for (final c in cases) {
    test('${c.id.name}: "${c.text}" ${c.why}', () {
      // Act
      final hits = _hits(c.text, c.id);

      // Assert
      for (final expected in c.has) {
        expect(hits, contains(expected));
      }
      if (c.has.isEmpty && c.lacks.isEmpty) expect(hits, isEmpty);
      for (final term in c.lacks) {
        expect(hits.where((hit) => hit.startsWith('$term:')), isEmpty);
      }
    });
  }
}

void main() {
  group('soy', () {
    _run(<_Case>[
      _hit('Tofu stir fry', RestrictionId.soy, <String>['tofu:stated']),
      _hit('Soy sauce', RestrictionId.soy, <String>[
        'soy:stated',
        'soy sauce:stated',
      ]),
      _hit('Edamame', RestrictionId.soy, <String>['edamame:stated']),
      _hit('Miso soup', RestrictionId.soy, <String>['miso:stated']),
      _hit('Tamari glaze', RestrictionId.soy, <String>['tamari:stated']),
      _hit('Chicken teriyaki', RestrictionId.soy, <String>[
        'teriyaki:likely',
      ], why: 'is a likely hidden source'),
      _hit('Hoisin duck', RestrictionId.soy, <String>['hoisin:likely']),
      _hit('Chocolate with soy lecithin', RestrictionId.soy, <String>[
        'soy:stated',
        'lecithin:suspected',
      ]),
      _hit('Fried in margarine', RestrictionId.soy, <String>[
        'margarine:suspected',
      ]),
      _hit('Hydrolysed vegetable protein', RestrictionId.soy, <String>[
        'hydrolysed vegetable protein:suspected',
        'vegetable protein:suspected',
      ]),
      _hit('Vegan sausage in a bun', RestrictionId.soy, <String>[
        'vegan sausage:suspected',
      ]),
      _hit('טופו מוקפץ', RestrictionId.soy, <String>['טופו:stated']),
      _hit('אורז ברוטב סויה', RestrictionId.soy, <String>[
        'סויה:stated',
        'רוטב סויה:stated',
      ], why: 'with the Hebrew prefix ב'),
      _hit('מוקפץ בסויה', RestrictionId.soy, <String>['סויה:stated']),
      _hit('מרק מיסו', RestrictionId.soy, <String>['מיסו:stated']),
      _hit('ירקות והמיסו', RestrictionId.soy, <String>['מיסו:stated']),
      _hit('אדממה מלוח', RestrictionId.soy, <String>['אדממה:stated']),
      _hit('סלמון בטריאקי', RestrictionId.soy, <String>['טריאקי:likely']),
      _hit('ממרח עם לציטין', RestrictionId.soy, <String>['לציטין:suspected']),
      _hit('נקניקיות טבעוניות', RestrictionId.soy, <String>[
        'נקניקיות טבעוניות:suspected',
      ]),
      _hit('פילה סלמון בגלייז סויה־דבש וסומסום', RestrictionId.soy, <String>[
        'סויה־דבש:stated',
      ], why: 'with a maqaf, which the normaliser deletes'),
      _hit('רול טמפורה שרימפס ורוטב אונאגי', RestrictionId.soy, <String>[
        'אונאגי:likely',
      ]),
      _hit('ירקות בטמפורה עם רוטב טנצוי', RestrictionId.soy, <String>[
        'טנצוי:likely',
      ]),
      _hit('חטיף במבה במילוי נוגט', RestrictionId.soy, <String>[
        'במבה:likely',
      ], why: 'Bamba lists soy (12 §1.2)'),
      _hit('Peking duck with hoisin sauce', RestrictionId.soy, <String>[
        'hoisin:likely',
      ]),
      _hit('סושי סלמון', RestrictionId.soy, <String>['סושי:suspected']),
      _miss('בלי גלוטן וללא סויה', RestrictionId.soy, why: 'ו before ללא'),
      _miss('Soy-free dressing', RestrictionId.soy, why: 'is guarded'),
      _miss('Made with no soy', RestrictionId.soy, why: 'is guarded'),
      _miss('Tofu soy free', RestrictionId.soy, lacks: <String>['soy']),
      _miss('ללא סויה', RestrictionId.soy, why: 'is guarded'),
      _miss('נטול סויה', RestrictionId.soy, why: 'is guarded'),
      _miss('טירמיסו', RestrictionId.soy, why: 'is not miso (tiramisu)'),
      _miss('עוגת טירמיסו קלאסית', RestrictionId.soy),
      _miss('Tiramisu', RestrictionId.soy),
    ]);
  });

  group('celery', () {
    _run(<_Case>[
      _hit('Celery soup', RestrictionId.celery, <String>['celery:stated']),
      _hit('Celeriac purée', RestrictionId.celery, <String>['celeriac:stated']),
      _hit('Fries with celery salt', RestrictionId.celery, <String>[
        'celery:stated',
        'celery salt:stated',
      ]),
      _hit('Chicken stock reduction', RestrictionId.celery, <String>[
        'stock:suspected',
      ], why: 'keeps the hidden certainty'),
      _hit('Vegetable broth', RestrictionId.celery, <String>[
        'broth:suspected',
      ]),
      _hit('Beef bouillon', RestrictionId.celery, <String>[
        'bouillon:suspected',
      ]),
      _hit('Waldorf salad', RestrictionId.celery, <String>['waldorf:likely']),
      _hit('Mirepoix base', RestrictionId.celery, <String>['mirepoix:likely']),
      _hit('Bloody Mary', RestrictionId.celery, <String>[
        'bloody mary:suspected',
      ]),
      _hit('מרק סלרי', RestrictionId.celery, <String>['סלרי:stated']),
      _hit('מוגש עם שורש סלרי', RestrictionId.celery, <String>[
        'שורש סלרי:stated',
        'סלרי:stated',
      ]),
      _hit('סלט וולדורף', RestrictionId.celery, <String>['וולדורף:likely']),
      _hit('מרק ירקות ביתי', RestrictionId.celery, <String>[
        'מרק ירקות:suspected',
      ]),
      _hit('מרק עוף', RestrictionId.celery, <String>['מרק עוף:suspected']),
      _hit('ציר עצמות', RestrictionId.celery, <String>['ציר:suspected']),
      _hit('בישול בציר', RestrictionId.celery, <String>[
        'ציר:suspected',
      ], why: 'with the Hebrew prefix ב'),
      _hit('אבקת מרק', RestrictionId.celery, <String>['אבקת מרק:suspected']),
      _hit('מרק דגים', RestrictionId.celery, <String>['מרק:suspected']),
      _hit('Tomato soup', RestrictionId.celery, <String>['soup:suspected']),
      _hit('ספגטי בולונז', RestrictionId.celery, <String>['בולונז:suspected']),
      _hit('Mushroom risotto', RestrictionId.celery, <String>[
        'risotto:suspected',
      ]),
      _miss('Celery-free sauce', RestrictionId.celery, why: 'is guarded'),
      _miss('No celery please', RestrictionId.celery, why: 'is guarded'),
      _miss('ללא סלרי', RestrictionId.celery, why: 'is guarded'),
      _miss('ליצירת מופת', RestrictionId.celery, why: 'is not ציר (stock)'),
      _miss('יצירת אמנות', RestrictionId.celery),
      _miss('Stockholm', RestrictionId.celery, why: 'is another word'),
    ]);
  });

  group('mustard', () {
    _run(<_Case>[
      _hit('Mustard sauce', RestrictionId.mustard, <String>['mustard:stated']),
      _hit('Dijon vinaigrette', RestrictionId.mustard, <String>[
        'dijon:stated',
        'vinaigrette:suspected',
      ]),
      _hit('Honey-mustard glaze', RestrictionId.mustard, <String>[
        'honey mustard:stated',
        'mustard:stated',
      ]),
      _hit('Wholegrain mustard mash', RestrictionId.mustard, <String>[
        'wholegrain mustard:stated',
      ]),
      _hit('Mustard seeds', RestrictionId.mustard, <String>[
        'mustard seeds:stated',
      ]),
      _hit('Garlic mayonnaise', RestrictionId.mustard, <String>[
        'mayonnaise:suspected',
      ], why: 'keeps the hidden certainty'),
      _hit('Chicken aioli', RestrictionId.mustard, <String>['aioli:suspected']),
      _hit('Pickles and gherkins', RestrictionId.mustard, <String>[
        'pickles:suspected',
        'gherkins:suspected',
      ]),
      _hit('Green curry paste', RestrictionId.mustard, <String>[
        'curry paste:suspected',
      ]),
      _hit('BBQ sauce', RestrictionId.mustard, <String>['bbq sauce:suspected']),
      _hit('חרדל דיז׳ון', RestrictionId.mustard, <String>[
        'חרדל:stated',
        "חרדל דיז'ון:stated",
      ], why: 'with a Hebrew geresh'),
      _hit('סלמון בחרדל', RestrictionId.mustard, <String>['חרדל:stated']),
      _hit('בורגר עם לחרדל', RestrictionId.mustard, <String>['חרדל:stated']),
      _hit('רוטב חרדל-דבש', RestrictionId.mustard, <String>['חרדל:stated']),
      _hit('סלט חצילים במיונז', RestrictionId.mustard, <String>[
        'מיונז:suspected',
      ]),
      _hit('ויניגרט לימון', RestrictionId.mustard, <String>[
        'ויניגרט:suspected',
      ]),
      _hit('מלפפונים חמוצים', RestrictionId.mustard, <String>[
        'מלפפונים חמוצים:suspected',
        'חמוצים:suspected',
      ]),
      _hit('סלק צלוי בחרדל־דבש', RestrictionId.mustard, <String>[
        'חרדל־דבש:stated',
      ], why: 'with a maqaf, which the normaliser deletes'),
      _hit('Caesar salad', RestrictionId.mustard, <String>[
        'caesar salad:suspected',
      ]),
      _hit('סלט קיסר', RestrictionId.mustard, <String>['סלט קיסר:suspected']),
      _miss(
        'Mustard-free dressing',
        RestrictionId.mustard,
        lacks: <String>['mustard'],
      ),
      _miss('No mustard', RestrictionId.mustard, why: 'is guarded'),
      _miss(
        'Without mustard',
        RestrictionId.mustard,
        lacks: <String>['mustard'],
      ),
      _miss('ללא חרדל', RestrictionId.mustard, why: 'is guarded'),
      _miss('בלי חרדל', RestrictionId.mustard, why: 'is guarded'),
    ]);
  });

  group('sulphites', () {
    _run(<_Case>[
      _hit('Contains sulphites', RestrictionId.sulphites, <String>[
        'sulphites:stated',
      ]),
      _hit('Dried apricots (sulfites added)', RestrictionId.sulphites, <String>[
        'sulfites:stated',
        'dried apricots:likely',
      ]),
      _hit('Preservative E223', RestrictionId.sulphites, <String>[
        'E223:stated',
      ], why: 'is found whatever the case'),
      _hit('e220, e228', RestrictionId.sulphites, <String>[
        'E220:stated',
        'E228:stated',
      ]),
      _hit('Sodium metabisulphite', RestrictionId.sulphites, <String>[
        'sodium metabisulphite:stated',
      ]),
      _hit('Mussels in white wine', RestrictionId.sulphites, <String>[
        'wine:likely',
      ], why: 'keeps the hidden certainty'),
      _hit('Organic red wine reduction', RestrictionId.sulphites, <String>[
        'wine:likely',
      ], why: '"organic" is not a guard'),
      _hit('Balsamic vinegar', RestrictionId.sulphites, <String>[
        'vinegar:suspected',
        'balsamic:suspected',
      ]),
      _hit('Raisins and prunes', RestrictionId.sulphites, <String>[
        'raisins:likely',
        'prunes:likely',
      ]),
      _hit('Garlic prawns', RestrictionId.sulphites, <String>[
        'prawns:suspected',
      ]),
      _hit('Pickled onions', RestrictionId.sulphites, <String>[
        'pickled:suspected',
      ]),
      _hit('Fish and chips', RestrictionId.sulphites, <String>[
        'chips:suspected',
      ]),
      _hit('Beer battered cod', RestrictionId.sulphites, <String>[
        'beer:suspected',
      ]),
      _hit('Fresh grape juice', RestrictionId.sulphites, <String>[
        'grape juice:suspected',
      ]),
      _hit('יין אדום', RestrictionId.sulphites, <String>['יין:likely']),
      _hit('צלי ביין לבן', RestrictionId.sulphites, <String>[
        'ביין:likely',
      ], why: 'is wine with the prefix ב'),
      _hit('פסטה ויין', RestrictionId.sulphites, <String>['ויין:likely']),
      _hit('משמש מיובש', RestrictionId.sulphites, <String>[
        'משמש מיובש:likely',
      ]),
      _hit('סלט עם פירות יבשים', RestrictionId.sulphites, <String>[
        'פירות יבשים:likely',
      ]),
      _hit('קוסקוס עם צימוקים', RestrictionId.sulphites, <String>[
        'צימוקים:likely',
      ]),
      _hit('סלט עם חומץ בלסמי', RestrictionId.sulphites, <String>[
        'חומץ:suspected',
      ]),
      _hit('מיץ ענבים', RestrictionId.sulphites, <String>[
        'מיץ ענבים:suspected',
      ]),
      _hit("צ'יפס ושרימפס", RestrictionId.sulphites, <String>[
        "צ'יפס:suspected",
        'שרימפס:suspected',
      ]),
      _hit('סולפיטים', RestrictionId.sulphites, <String>['סולפיטים:stated']),
      _hit('Hot cross bun with currants', RestrictionId.sulphites, <String>[
        'currants:likely',
      ]),
      _hit('חרדל דיז׳ון', RestrictionId.sulphites, <String>[
        'חרדל:suspected',
      ], why: 'ready-made mustard (11 §15.2)'),
      _hit('Grilled sausages', RestrictionId.sulphites, <String>[
        'sausages:suspected',
      ]),
      _hit('סלט עם גוואקמולי', RestrictionId.sulphites, <String>[
        'גוואקמולי:suspected',
      ]),
      _miss(
        'Sulphite-free wine',
        RestrictionId.sulphites,
        lacks: <String>['sulphite'],
      ),
      _miss('No added sulphites', RestrictionId.sulphites, why: 'is guarded'),
      _miss('ללא סולפיטים', RestrictionId.sulphites, why: 'is guarded'),
      _miss('ללא תוספת סולפיטים', RestrictionId.sulphites),
      _miss('הזמנה ממיין', RestrictionId.sulphites, why: 'is not wine'),
      _miss('Winery tour', RestrictionId.sulphites, why: 'is another word'),
    ]);
  });

  group('legumes', () {
    _run(<_Case>[
      _hit('Chickpea salad', RestrictionId.legumes, <String>[
        'chickpea:stated',
      ]),
      _hit('Hummus plate', RestrictionId.legumes, <String>['hummus:stated']),
      _hit('Falafel wrap', RestrictionId.legumes, <String>['falafel:stated']),
      _hit('Red lentil dal', RestrictionId.legumes, <String>[
        'lentil:stated',
        'dal:stated',
      ]),
      _hit('Green peas and pea protein', RestrictionId.legumes, <String>[
        'green peas:stated',
        'pea protein:stated',
      ]),
      _hit('Fava bean purée', RestrictionId.legumes, <String>['fava:stated']),
      _hit('Black beans and kidney beans', RestrictionId.legumes, <String>[
        'black beans:stated',
        'kidney beans:stated',
      ]),
      _hit('Fenugreek curry', RestrictionId.legumes, <String>[
        'fenugreek:stated',
      ]),
      _hit('Peanut butter', RestrictionId.legumes, <String>[
        'peanut butter:stated',
        'peanut:stated',
      ], why: 'a peanut is a legume'),
      _hit('Tofu', RestrictionId.legumes, <String>['tofu:stated']),
      _hit('Lupin flour bread', RestrictionId.legumes, <String>[
        'lupin:stated',
        'lupin flour:stated',
      ]),
      _hit('Veggie burger', RestrictionId.legumes, <String>[
        'veggie burger:suspected',
      ]),
      _hit('Vegetable protein', RestrictionId.legumes, <String>[
        'vegetable protein:suspected',
      ]),
      _hit('Chickpea flour pakora', RestrictionId.legumes, <String>[
        'chickpea:stated',
        'pakora:suspected',
      ]),
      _hit('חומוס עם טחינה', RestrictionId.legumes, <String>['חומוס:stated']),
      _hit('סלט והחומוס', RestrictionId.legumes, <String>[
        'חומוס:stated',
      ], why: 'with the Hebrew prefix וה'),
      _hit('פלאפל בפיתה', RestrictionId.legumes, <String>['פלאפל:stated']),
      _hit('מרק עדשים', RestrictionId.legumes, <String>['עדשים:stated']),
      _hit('אפונה וגזר', RestrictionId.legumes, <String>['אפונה:stated']),
      _hit('שעועית ירוקה', RestrictionId.legumes, <String>['שעועית:stated']),
      _hit("אורז מג'דרה", RestrictionId.legumes, <String>["מג'דרה:stated"]),
      _hit('לחם חילבה', RestrictionId.legumes, <String>['חילבה:stated']),
      _hit('תורמוס כבוש', RestrictionId.legumes, <String>['תורמוס:stated']),
      _hit('קמח חומוס', RestrictionId.legumes, <String>['חומוס:stated']),
      _hit('חמאת בוטנים', RestrictionId.legumes, <String>['בוטנים:stated']),
      _hit('קציצות אגוזי אדמה', RestrictionId.legumes, <String>[
        'אגוזי אדמה:stated',
      ]),
      _hit('אדממה וטופו', RestrictionId.legumes, <String>[
        'אדממה:stated',
        'טופו:stated',
      ]),
      _hit('סביח', RestrictionId.legumes, <String>['סביח:suspected']),
      _hit('פול מדמס', RestrictionId.legumes, <String>['פול:stated']),
      _hit('חומוס ופול', RestrictionId.legumes, <String>['ופול:stated']),
      _hit('חומוס הפול', RestrictionId.legumes, <String>['הפול:stated']),
      _hit('מנה של בפול', RestrictionId.legumes, <String>['בפול:stated']),
      _hit('גיוזה ירקות ברוטב פונזו', RestrictionId.legumes, <String>[
        'פונזו:likely',
      ], why: 'soy is a legume'),
      _hit('אודון מוקפץ עם טריאקי', RestrictionId.legumes, <String>[
        'טריאקי:likely',
      ]),
      _hit('רול עם רוטב אונאגי', RestrictionId.legumes, <String>[
        'אונאגי:likely',
      ]),
      _hit('חטיף במבה', RestrictionId.legumes, <String>[
        'במבה:stated',
      ], why: 'a direct peanut term, so a direct legume term'),
      _hit('Peking duck with hoisin sauce', RestrictionId.legumes, <String>[
        'hoisin:likely',
      ]),
      _hit('פילה סלמון בגלייז סויה־דבש', RestrictionId.legumes, <String>[
        'סויה־דבש:stated',
      ]),
      _hit('Fried in margarine', RestrictionId.legumes, <String>[
        'margarine:suspected',
      ], why: 'every hidden soy source is a legume source'),
      _miss('אספרסו כפול', RestrictionId.legumes, why: 'is "double", not פול'),
      _miss('שניצל כפול', RestrictionId.legumes),
      _miss('Coffee beans', RestrictionId.legumes, why: 'are not a legume'),
      _miss('Vanilla bean ice cream', RestrictionId.legumes),
      _miss('Cocoa beans', RestrictionId.legumes),
      _miss('Legume-free', RestrictionId.legumes, why: 'is guarded'),
      _miss('No legumes', RestrictionId.legumes, why: 'is guarded'),
      _miss('ללא קטניות', RestrictionId.legumes, why: 'is guarded'),
      _miss(
        'Chickpea',
        RestrictionId.legumes,
        lacks: <String>['pea'],
        why: 'is not the word "pea"',
      ),
      _miss('Pea-free', RestrictionId.legumes, lacks: <String>['pea']),
    ]);
  });

  group('every term, in its own sentence', () {
    for (final id in _ids) {
      final vocabulary = allergenVocabulary[id]!;
      group(id.name, () {
        test('has triggers in both languages', () {
          expect(vocabulary.directEn, isNotEmpty);
          expect(vocabulary.directHe, isNotEmpty);
          expect(vocabulary.hiddenEn, isNotEmpty);
          expect(vocabulary.hiddenHe, isNotEmpty);
          expect(vocabulary.sources, isNotEmpty);
          expect(vocabulary.guards.beforeEn, isNotEmpty);
          expect(vocabulary.guards.beforeHe, isNotEmpty);
        });

        test('every direct English term is found, stated', () {
          for (final term in vocabulary.directEn) {
            for (final text in <String>[
              term,
              'Served with $term on the side',
              'Served with ${term.toUpperCase()} on the side',
            ]) {
              expect(_hits(text, id), contains('$term:stated'), reason: text);
            }
          }
        });

        test('every direct Hebrew term is found, stated, with prefixes', () {
          final noPrefix = vocabulary.noPrefixHe.toSet();
          for (final term in vocabulary.directHe) {
            expect(_hits(term, id), contains('$term:stated'), reason: term);
            expect(
              _hits('מוגש עם $term בצד', id),
              contains('$term:stated'),
              reason: term,
            );
            if (noPrefix.contains(term)) continue;
            for (final text in <String>['ה$term', 'וב$term']) {
              expect(
                _hits('מוגש עם $text בצד', id),
                contains('$term:stated'),
                reason: text,
              );
            }
          }
        });

        test('every hidden term is found with its own certainty', () {
          for (final trigger in vocabulary.hiddenEn) {
            expect(
              _hits('Served with ${trigger.term} on the side', id),
              contains('${trigger.term}:${trigger.certainty.name}'),
              reason: trigger.term,
            );
          }
          final noPrefix = vocabulary.noPrefixHe.toSet();
          for (final trigger in vocabulary.hiddenHe) {
            final expected = '${trigger.term}:${trigger.certainty.name}';
            expect(
              _hits('מוגש עם ${trigger.term} בצד', id),
              contains(expected),
              reason: trigger.term,
            );
            if (noPrefix.contains(trigger.term)) continue;
            expect(
              _hits('מוגש עם ה${trigger.term} בצד', id),
              contains(expected),
              reason: trigger.term,
            );
          }
        });

        test('a no-prefix Hebrew term is not found behind a prefix', () {
          for (final term in vocabulary.noPrefixHe) {
            for (final text in <String>['מוגש עם ל$term בצד', 'מ$term']) {
              expect(
                _hits(text, id).where((hit) => hit.startsWith('$term:')),
                isEmpty,
                reason: text,
              );
            }
          }
        });

        test('the guard words cancel a trigger beside them', () {
          final guards = vocabulary.guards;
          final term = vocabulary.directEn.first;
          final he = vocabulary.directHe.first;
          for (final word in guards.beforeEn) {
            expect(
              _hits('$word $term', id).where((h) => h.startsWith('$term:')),
              isEmpty,
              reason: '$word $term',
            );
          }
          for (final word in guards.afterEn) {
            expect(
              _hits('$term $word', id).where((h) => h.startsWith('$term:')),
              isEmpty,
              reason: '$term $word',
            );
          }
          for (final word in guards.beforeHe) {
            expect(
              _hits('$word $he', id).where((h) => h.startsWith('$he:')),
              isEmpty,
              reason: '$word $he',
            );
          }
        });

        test('a guard three words away no longer cancels', () {
          final term = vocabulary.directEn.first;
          expect(_hits('no big fat $term', id), contains('$term:stated'));
        });
      });
    }
  });

  group('legumes contains peanut, soy and lupin', () {
    String key(String term) => TextNormaliser.normalise(term);

    Set<String> legumeTerms({required bool hebrew}) {
      final vocabulary = allergenVocabulary[RestrictionId.legumes]!;
      return <String>{
        for (final term in hebrew ? vocabulary.directHe : vocabulary.directEn)
          key(term),
        for (final trigger
            in hebrew ? vocabulary.hiddenHe : vocabulary.hiddenEn)
          key(trigger.term),
      };
    }

    for (final id in <RestrictionId>[
      RestrictionId.peanuts,
      RestrictionId.soy,
      RestrictionId.lupin,
    ]) {
      test('every direct ${id.name} term is also a legumes term', () {
        // While a sibling group is still a stub its list is empty and this
        // comparison is vacuous; the fixed spellings below hold either way.
        final vocabulary = allergenVocabulary[id]!;
        for (final term in vocabulary.directEn) {
          expect(legumeTerms(hebrew: false), contains(key(term)));
        }
        for (final term in vocabulary.directHe) {
          expect(legumeTerms(hebrew: true), contains(key(term)));
        }
      });
    }

    test('the documented peanut, soy and lupin spellings are present', () {
      // Arrange: 11 §1.1, §6.1, §14.1 and 12 §1.2, §1.3, §1.11.
      const english = <String>[
        'peanut',
        'peanuts',
        'peanut butter',
        'groundnut',
        'soy',
        'soya',
        'tofu',
        'edamame',
        'miso',
        'soy sauce',
        'lupin',
        'lupine',
      ];
      const hebrew = <String>[
        'בוטנים',
        'אגוזי אדמה',
        'סויה',
        'טופו',
        'אדממה',
        'מיסו',
        'רוטב סויה',
        'תורמוס',
        'לופין',
      ];

      // Assert
      for (final term in english) {
        expect(legumeTerms(hebrew: false), contains(key(term)), reason: term);
      }
      for (final term in hebrew) {
        expect(legumeTerms(hebrew: true), contains(key(term)), reason: term);
      }
    });

    test('soy sauce reads as soy and as a legume, in both scripts', () {
      for (final text in <String>['Soy sauce', 'רוטב סויה']) {
        expect(_hits(text, RestrictionId.soy), isNotEmpty, reason: text);
        expect(_hits(text, RestrictionId.legumes), isNotEmpty, reason: text);
      }
    });
  });
}

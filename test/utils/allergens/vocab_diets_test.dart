import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/utils/allergens/allergen_matcher.dart';
import 'package:ketoclub/utils/allergens/vocabulary.dart';
import 'package:ketoclub/utils/text_normaliser.dart';

const RestrictionId _vegan = RestrictionId.vegan;
const RestrictionId _veg = RestrictionId.vegetarian;

/// The hits [AllergenMatcher.find] reports for [id] in [text], each as
/// `term:certainty`. Filtered by id so the other groups' vocabularies
/// (filled by their own pull requests) cannot change these tests.
List<String> _hits(String text, RestrictionId id) => <String>[
  for (final hit in AllergenMatcher.find(text))
    if (hit.id == id) '${hit.term}:${hit.certainty.name}',
];

/// What one text does to the two diets: `vegan` and `vegetarian` are the
/// `term:certainty` entries each must report; a null list means "reports
/// nothing at all".
typedef _Case = ({
  String text,
  List<String>? vegan,
  List<String>? vegetarian,
  String why,
});

_Case _case(
  String text, {
  List<String>? vegan,
  List<String>? vegetarian,
  String why = '',
}) => (text: text, vegan: vegan, vegetarian: vegetarian, why: why);

void _run(List<_Case> cases) {
  for (final c in cases) {
    test('"${c.text}" ${c.why}', () {
      for (final (id, expected) in <(RestrictionId, List<String>?)>[
        (_vegan, c.vegan),
        (_veg, c.vegetarian),
      ]) {
        // Act
        final hits = _hits(c.text, id);

        // Assert
        if (expected == null) {
          expect(hits, isEmpty, reason: id.name);
        } else {
          for (final entry in expected) {
            expect(hits, contains(entry), reason: id.name);
          }
        }
      }
    });
  }
}

void main() {
  group('meat and fish: both diets', () {
    _run(<_Case>[
      _case(
        'Chicken schnitzel',
        vegan: <String>['chicken:stated'],
        vegetarian: <String>['chicken:stated'],
      ),
      _case(
        'Beef burger',
        vegan: <String>['beef:stated'],
        vegetarian: <String>['beef:stated'],
      ),
      _case(
        'Roast lamb and pork belly',
        vegan: <String>['lamb:stated', 'pork:stated'],
        vegetarian: <String>['lamb:stated', 'pork:stated'],
      ),
      _case(
        'Bacon and ham',
        vegan: <String>['bacon:stated', 'ham:stated'],
        vegetarian: <String>['bacon:stated', 'ham:stated'],
      ),
      _case(
        'Grilled salmon',
        vegan: <String>['salmon:stated'],
        vegetarian: <String>['salmon:stated'],
      ),
      _case(
        'Fish and chips',
        vegan: <String>['fish:stated'],
        vegetarian: <String>['fish:stated'],
      ),
      _case(
        'Shrimp tempura',
        vegan: <String>['shrimp:stated'],
        vegetarian: <String>['shrimp:stated'],
      ),
      _case(
        'Grilled squid',
        vegan: <String>['squid:stated'],
        vegetarian: <String>['squid:stated'],
      ),
      _case(
        'Panna cotta with berries',
        vegan: <String>['panna cotta:likely'],
        vegetarian: <String>['panna cotta:likely'],
        why: 'sets with gelatin',
      ),
      _case(
        'Gelatin dessert',
        vegan: <String>['gelatin:stated'],
        vegetarian: <String>['gelatin:stated'],
      ),
      _case(
        "ג'לטין בטעם תות",
        vegan: <String>["ג'לטין:stated"],
        vegetarian: <String>["ג'לטין:stated"],
      ),
      _case(
        'Caesar dressing with worcestershire',
        vegan: <String>['worcestershire:suspected'],
        vegetarian: <String>[
          'worcestershire:suspected',
          'caesar dressing:suspected',
        ],
      ),
      _case(
        'שניצל עוף בפירורי לחם',
        vegan: <String>['עוף:stated'],
        vegetarian: <String>['עוף:stated'],
      ),
      _case(
        'המבורגר בקר 200 גרם',
        vegan: <String>['בקר:stated'],
        vegetarian: <String>['בקר:stated'],
      ),
      _case(
        'כבש ועוף על האש',
        vegan: <String>['כבש:stated', 'ועוף:stated'],
        vegetarian: <String>['כבש:stated', 'ועוף:stated'],
        why: 'ו before עוף is "and", a listed form',
      ),
      _case(
        'פילה סלמון בתנור',
        vegan: <String>['סלמון:stated'],
        vegetarian: <String>['סלמון:stated'],
      ),
      _case(
        'דג של היום',
        vegan: <String>['דג:stated'],
        vegetarian: <String>['דג:stated'],
      ),
      _case(
        'שרימפס בשום',
        vegan: <String>['שרימפס:stated'],
        vegetarian: <String>['שרימפס:stated'],
      ),
      _case(
        'צלי בשר עם ירקות',
        vegan: <String>['בשר:stated'],
        vegetarian: <String>['בשר:stated'],
      ),
      _case(
        'הבשר טרי ובשר טחון',
        vegan: <String>['הבשר:stated', 'ובשר:stated'],
        vegetarian: <String>['הבשר:stated', 'ובשר:stated'],
        why: 'prefixed forms of בשר are terms of their own',
      ),
      _case(
        'מנה בשרית',
        vegan: <String>['בשרית:likely'],
        vegetarian: <String>['בשרית:likely'],
        why: 'is the kosher meat sense',
      ),
      _case(
        'בשרי',
        vegan: <String>['בשרי:likely'],
        vegetarian: <String>['בשרי:likely'],
        why: 'means the dish contains meat (12 §2.1)',
      ),
    ]);
  });

  group('dairy, eggs and honey: vegan only', () {
    _run(<_Case>[
      _case(
        'Cheese omelette',
        vegan: <String>['cheese:stated', 'omelette:stated'],
      ),
      _case('Fried egg on toast', vegan: <String>['egg:stated']),
      _case('Honey glazed carrots', vegan: <String>['honey:stated']),
      _case('Honey mustard dressing', vegan: <String>['honey:stated']),
      _case(
        'Vegetarian lasagne with ricotta',
        vegan: <String>['ricotta:stated'],
        why: 'vegetarian is not a vegan guard',
      ),
      _case('Strawberry yoghurt', vegan: <String>['yoghurt:stated']),
      _case('Whey protein shake', vegan: <String>['whey:stated']),
      _case('Garlic mayonnaise', vegan: <String>['mayonnaise:likely']),
      _case('Carbonara', vegan: <String>['carbonara:likely']),
      _case('Lemon meringue pie', vegan: <String>['meringue:likely']),
      _case(
        'Warm milk and butter',
        vegan: <String>['milk:likely', 'butter:likely'],
      ),
      _case('Fresh cream', vegan: <String>['cream:likely']),
      _case(
        'Mozzarella and feta',
        vegan: <String>['mozzarella:stated', 'feta:stated'],
      ),
      _case('Vanilla ice cream', vegan: <String>['ice cream:stated']),
      _case('בורקס גבינה', vegan: <String>['גבינה:stated']),
      _case('גבינת עיזים', vegan: <String>['גבינת:stated']),
      _case('שקשוקה עם ביצים', vegan: <String>['ביצים:stated']),
      _case('ביצת עין', vegan: <String>['ביצת:stated']),
      _case('חביתה', vegan: <String>['חביתה:stated']),
      _case('לאבנה וזיתים', vegan: <String>['לאבנה:stated']),
      _case('פסטה ברוטב שמנת', vegan: <String>['שמנת:likely']),
      _case('קפה עם חלב', vegan: <String>['חלב:likely']),
      _case('חמאה ולחם', vegan: <String>['חמאה:likely']),
      _case('סלט עם דבש ופטה', vegan: <String>['דבש:stated', 'פטה:stated']),
      _case('מנה חלבית', vegan: <String>['חלבית:likely']),
      _case(
        'חלבי',
        vegan: <String>['חלבי:likely'],
        why: 'is dairy for the vegan and meat-free for the vegetarian',
      ),
      _case('איולי שום', vegan: <String>['איולי:likely']),
      _case('מיונז ביתי', vegan: <String>['מיונז:likely']),
    ]);
  });

  group("guards: the restaurant's own declaration", () {
    _run(<_Case>[
      _case('Vegan cheese'),
      _case('Vegan chicken nuggets'),
      _case('Plant-based chicken burger'),
      _case('Plant based sausage'),
      _case('Dairy free cheese'),
      _case('Chicken alternative'),
      _case('Meat substitute'),
      _case('Imitation bacon'),
      _case('No cheese, no egg'),
      _case('Without meat'),
      _case('Eggless mayonnaise'),
      _case('גבינה טבעונית'),
      _case('נקניקיות טבעוניות'),
      _case('שניצל עוף טבעוני'),
      _case('בשר צמחי'),
      _case('חלב צמחי'),
      _case('שמנת על בסיס צמחי'),
      _case('תחליף גבינה'),
      _case('ללא ביצים'),
      _case('בלי בשר'),
    ]);

    test('a vegetarian declaration cancels the vegetarian hit only', () {
      expect(_hits('Vegetarian sausage', _veg), isEmpty);
      expect(_hits('Vegetarian sausage', _vegan), contains('sausage:stated'));
    });

    test('a vegan declaration cancels both diets', () {
      for (final text in <String>['Vegan sausage', 'נקניק טבעוני']) {
        expect(_hits(text, _veg), isEmpty, reason: text);
        expect(_hits(text, _vegan), isEmpty, reason: text);
      }
    });

    test('the declaration must sit beside the trigger', () {
      expect(
        _hits('Vegan burger with cheese', _vegan),
        contains('cheese:stated'),
      );
      expect(
        _hits('המבורגר טבעוני עם גבינה', _vegan),
        contains('גבינה:stated'),
      );
    });

    test('a plant adjective is not a guard: it would hide shrimp', () {
      for (final text in <String>[
        'Coconut shrimp',
        'Almond chicken',
        'Peanut chicken',
        'Oat crusted salmon',
      ]) {
        expect(_hits(text, _veg), isNotEmpty, reason: text);
        expect(_hits(text, _vegan), isNotEmpty, reason: text);
      }
    });

    test('plant milk and butter read as likely, never stated', () {
      expect(_hits('Oat milk latte', _vegan), <String>['milk:likely']);
      expect(_hits('Peanut butter', _vegan), <String>['butter:likely']);
      expect(_hits('Coconut cream', _vegan), <String>['cream:likely']);
      expect(_hits('חלב שקדים', _vegan), <String>['חלב:likely']);
    });

    test('the plant emoji is dropped by the normaliser', () {
      // The 🌱 declaration cannot be a guard phrase: it normalises to
      // nothing, so it never appears in the text the matcher reads.
      expect(TextNormaliser.normalise('🌱'), isEmpty);
      expect(TextNormaliser.normalise('🌱 vegan'), 'vegan');
      expect(_hits('Burger 🌱 with cheese', _vegan), contains('cheese:stated'));
    });
  });

  group('words that look like a trigger and are not', () {
    _run(<_Case>[
      _case('חלבון איכותי', why: 'protein is not חלב (milk)'),
      _case('חלבה בטחינה', why: 'halva is not חלב'),
      _case('לבקר במסעדה', why: 'to visit is not בקר'),
      _case('הזמנה ממבקר', why: 'a visitor is not בקר'),
      _case('מעוף הציפור', why: 'flight is not עוף'),
      _case('לעוף גבוה', why: 'to fly is not עוף'),
      _case('לבשר חדשות', why: 'to announce is not בשר'),
      _case('מבשר טוב', why: 'a herald is not בשר'),
      _case('מכבש כבישים', why: 'a press is not כבש'),
      _case('Eggplant salad', why: 'eggplant is not egg'),
      _case('Chickpea stew', why: 'chickpea is not chicken'),
      _case('Hamburger bun', why: 'hamburger is not ham'),
      _case('Butternut squash', why: 'butternut is not butter'),
    ]);
  });

  group('every term, in its own sentence', () {
    for (final id in <RestrictionId>[_vegan, _veg]) {
      final vocabulary = allergenVocabulary[id]!;
      group(id.name, () {
        test('has triggers, guards and sources in both languages', () {
          expect(vocabulary.directEn, isNotEmpty);
          expect(vocabulary.directHe, isNotEmpty);
          expect(vocabulary.hiddenEn, isNotEmpty);
          expect(vocabulary.hiddenHe, isNotEmpty);
          expect(vocabulary.sources, isNotEmpty);
          expect(vocabulary.guards.beforeEn, contains('vegan'));
          expect(vocabulary.guards.afterHe, contains('טבעוני'));
          expect(vocabulary.noPrefixHe, <String>['בשר', 'עוף', 'בקר', 'כבש']);
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
          for (final trigger in vocabulary.hiddenHe) {
            expect(
              _hits('מוגש עם ${trigger.term} בצד', id),
              contains('${trigger.term}:${trigger.certainty.name}'),
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

        test('every guard word cancels a trigger beside it', () {
          final guards = vocabulary.guards;
          for (final word in guards.beforeEn) {
            expect(_hits('$word chicken', id), isEmpty, reason: word);
          }
          for (final word in guards.afterEn) {
            expect(_hits('chicken $word', id), isEmpty, reason: word);
          }
          for (final word in guards.beforeHe) {
            expect(_hits('$word עוף', id), isEmpty, reason: word);
          }
          for (final word in guards.afterHe) {
            expect(_hits('עוף $word', id), isEmpty, reason: word);
          }
        });
      });
    }
  });

  group('the two diets relate as the corpus expects', () {
    String key(String term) => TextNormaliser.normalise(term);

    Set<String> terms(RestrictionId id) {
      final vocabulary = allergenVocabulary[id]!;
      return <String>{
        for (final term in vocabulary.directEn) key(term),
        for (final term in vocabulary.directHe) key(term),
        for (final trigger in vocabulary.hiddenEn) key(trigger.term),
        for (final trigger in vocabulary.hiddenHe) key(trigger.term),
      };
    }

    test('every vegetarian trigger is a vegan trigger too', () {
      expect(terms(_vegan).containsAll(terms(_veg)), isTrue);
    });

    test('dairy, eggs and honey are vegan triggers and not vegetarian', () {
      for (final text in <String>[
        'milk',
        'cheese',
        'egg',
        'honey',
        'butter',
        'חלב',
        'גבינה',
        'ביצה',
        'דבש',
        'חמאה',
        'חלבי',
      ]) {
        expect(_hits(text, _vegan), isNotEmpty, reason: text);
        expect(_hits(text, _veg), isEmpty, reason: text);
      }
    });

    test('vegan covers the fish, crustacean and mollusc words', () {
      for (final text in <String>[
        'tuna',
        'crab',
        'mussels',
        'טונה',
        'סרטנים',
        'מולים',
      ]) {
        expect(_hits(text, _vegan), isNotEmpty, reason: text);
        expect(_hits(text, _veg), isNotEmpty, reason: text);
      }
    });

    test('keto stays empty: its vocabulary lives in constants.dart', () {
      expect(allergenVocabulary[RestrictionId.keto]!.isEmpty, isTrue);
    });
  });
}

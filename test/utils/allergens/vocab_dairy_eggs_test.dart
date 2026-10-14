import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/utils/allergens/allergen_matcher.dart';
import 'package:ketoclub/utils/allergens/vocabulary.dart';

/// The restrictions this file's group owns.
const List<RestrictionId> _ids = <RestrictionId>[
  RestrictionId.milk,
  RestrictionId.lactose,
  RestrictionId.eggs,
];

/// One expectation: what `id` finds in `text` — its strongest certainty,
/// or null when it finds nothing — and, when `guarded`, that every hit is
/// guarded (a guard lowers a hit to suspected, never cancels it; ALG-04a).
typedef _Case = ({
  RestrictionId id,
  String text,
  TriggerCertainty? certainty,
  bool guarded,
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

/// Whether every hit of `id` in `text` is guarded (and there is one).
bool _allGuarded(RestrictionId id, String text) {
  final hits = AllergenMatcher.find(text).where((hit) => hit.id == id);
  return hits.isNotEmpty && hits.every((hit) => hit.guarded);
}

_Case _case(
  RestrictionId id,
  String text,
  TriggerCertainty? certainty,
  String why,
) => (id: id, text: text, certainty: certainty, guarded: false, why: why);

/// A text whose every hit of `id` a guard lowered to suspected.
_Case _guard(RestrictionId id, String text, String why) =>
    (id: id, text: text, certainty: _suspected, guarded: true, why: why);

void _expectAll(List<_Case> cases) {
  final wrong = <String>[
    for (final c in cases)
      if (_strongest(c.id, c.text) != c.certainty ||
          (c.guarded && !_allGuarded(c.id, c.text)))
        <String>[
          '${c.id.name}: "${c.text}" (${c.why}): expected',
          '${c.certainty?.name}${c.guarded ? ' guarded' : ''}, found',
          '${_strongest(c.id, c.text)?.name}',
          if (_allGuarded(c.id, c.text)) 'guarded',
        ].join(' '),
  ];
  expect(wrong, isEmpty);
}

void main() {
  group('dairy and eggs vocabulary', () {
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

        test('a no-prefix term refuses a prefix letter', () {
          for (final term in vocabulary.noPrefixHe) {
            for (final prefix in <String>['ב', 'ל', 'ש']) {
              final hits = AllergenMatcher.find('$prefix$term')
                  .where((hit) => hit.id == id && hit.term == term);
              expect(hits, isEmpty, reason: '$prefix$term');
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

  group('milk', () {
    const id = RestrictionId.milk;

    test('direct triggers in English are stated', () {
      _expectAll(<_Case>[
        _case(id, 'Whole milk', _stated, 'milk'),
        _case(id, 'Butter chicken', _stated, 'butter'),
        _case(id, 'Garlic buttered bread', _stated, 'buttered'),
        _case(id, 'Cream of mushroom soup', _stated, 'cream'),
        _case(id, 'Goat cheese salad', _stated, 'cheese'),
        _case(id, 'Greek yogurt', _stated, 'yogurt'),
        _case(id, 'Ghee rice', _stated, 'ghee'),
        _case(id, 'Buttermilk pancakes', _stated, 'buttermilk'),
        _case(id, 'Chocolate milkshake', _stated, 'milkshake'),
        _case(id, 'Cheeseburger', _stated, 'cheeseburger'),
        _case(id, 'Whey protein', _stated, 'whey'),
        _case(id, 'Sodium caseinate', _stated, 'caseinate'),
        _case(id, 'Fresh parmesan', _stated, 'a named cheese'),
        _case(id, 'Feta and olives', _stated, 'a named cheese'),
        _case(id, 'Vanilla custard', _stated, 'custard'),
        _case(id, 'LACTOSE', _stated, 'lactose is in the EU milk entry'),
      ]);
    });

    test('direct triggers in Hebrew are stated, with prefixes', () {
      _expectAll(<_Case>[
        _case(id, 'חלב', _stated, 'milk'),
        _case(id, 'קפה בחלב', _stated, 'prefix ב'),
        _case(id, 'מוגש עם לחלב', _stated, 'prefix ל'),
        _case(id, 'חמאה', _stated, 'butter'),
        _case(id, 'מוקפץ בחמאה', _stated, 'prefix ב'),
        _case(id, 'חמאת שום', _stated, 'construct form'),
        _case(id, 'גבינה', _stated, 'cheese'),
        _case(id, 'גבינת עיזים', _stated, 'construct form'),
        _case(id, 'גבינות', _stated, 'plural'),
        _case(id, 'שמנת', _stated, 'cream'),
        _case(id, 'פסטה ברוטב שמנת', _stated, 'prefix ב'),
        _case(id, 'יוגורט', _stated, 'yogurt'),
        _case(id, 'לאבנה', _stated, 'labneh'),
        _case(id, 'גבינה צפתית', _stated, 'Tzfat cheese'),
        _case(id, 'פטה בולגרית', _stated, 'feta'),
        _case(id, 'פרמזן', _stated, 'parmesan'),
        _case(id, 'שוקו קר', _stated, 'chocolate milk'),
        _case(id, 'סמנה', _stated, 'clarified butter'),
        _case(id, 'עוגה והחלב', _stated, 'prefix וה'),
      ]);
    });

    test('hidden sources keep their own certainty', () {
      _expectAll(<_Case>[
        _case(id, 'Salmon in beurre blanc', _likely, 'beurre blanc'),
        _case(id, 'Brioche bun', _likely, 'brioche'),
        _case(id, 'Cappuccino', _likely, 'cappuccino'),
        _case(id, 'Iced latte', _likely, 'latte'),
        _case(id, 'Potato gratin', _likely, 'gratin'),
        _case(id, 'Caesar salad', _likely, 'Caesar dressing'),
        _case(id, 'Mashed potatoes', _suspected, 'mashed potato'),
        _case(id, 'Mushroom risotto', _suspected, 'risotto'),
        _case(id, 'Buffalo sauce wings', _suspected, 'buffalo sauce'),
        _case(id, 'Grilled steak', _suspected, 'butter on the steak'),
        _case(id, 'Chocolate cake', _suspected, 'baked goods'),
        _case(id, 'Lemon curd tart', _stated, 'curd is a direct trigger'),
        _case(id, 'Dairy dessert', _likely, 'dairy'),
        _case(id, 'Non-dairy creamer', _likely, 'non-dairy is not a guard'),
        _case(id, 'Hot dog', _suspected, 'casein as a binder'),
        _case(id, 'חלבי', _likely, 'the dairy kosher category'),
        _case(id, 'ארוחה חלבית', _likely, 'feminine dairy'),
        _case(id, 'הפוך', _likely, 'a milk coffee'),
        _case(id, 'קפה הפוך גדול', _likely, 'a milk coffee in a phrase'),
        _case(id, 'לאטה', _likely, 'latte'),
        _case(id, 'בריוש', _likely, 'brioche'),
        _case(id, 'פירה', _suspected, 'mashed potato'),
        _case(id, 'ריזוטו פטריות', _suspected, 'risotto'),
        _case(id, "ג'חנון", _suspected, 'butter or margarine'),
        _case(id, 'אנטריקוט', _suspected, 'butter on the steak'),
        _case(id, 'עוגת שוקולד', _suspected, 'baked goods'),
      ]);
    });

    test('plant milks and other butters are lowered, never dropped', () {
      _expectAll(<_Case>[
        _guard(id, 'Coconut milk curry', 'coconut milk'),
        _case(id, 'Almond milk latte', _likely, 'the latte is still asked'),
        _guard(id, 'Oat milk', 'oat milk'),
        _guard(id, 'Soy milk', 'soy milk'),
        _guard(id, 'Cashew cheese', 'cashew cheese'),
        _guard(id, 'Coconut cream', 'coconut cream'),
        _guard(id, 'Coconut yogurt', 'coconut yogurt'),
        _guard(id, 'Peanut butter', 'peanut butter'),
        _guard(id, 'Almond butter', 'almond butter'),
        _guard(id, 'Cocoa butter', 'cocoa butter'),
        _guard(id, 'Cream of tartar', 'cream of tartar'),
        _guard(id, 'Milk thistle tea', 'milk thistle'),
        _case(id, 'Butternut squash', null, 'butternut is one word'),
        _case(id, 'Eggplant', null, 'eggplant'),
        _guard(id, 'חלב שקדים', 'almond milk'),
        _guard(id, 'חלב שיבולת שועל', 'oat milk'),
        _guard(id, 'חלב קוקוס', 'coconut milk'),
        _guard(id, 'חלב סויה', 'soy milk'),
        _guard(id, 'שמנת קוקוס', 'coconut cream'),
        _guard(id, 'חמאת בוטנים', 'peanut butter'),
        _guard(id, 'חמאת קקאו', 'cocoa butter'),
        _guard(id, 'חמאת שקדים', 'almond butter'),
        _guard(id, 'גבינת קשיו', 'cashew cheese'),
        _case(id, 'חלבון', null, 'protein is not milk'),
        _case(id, 'חלבה', null, 'halva is sesame'),
        _case(id, 'חלבונים', null, 'protein, plural'),
      ]);
    });

    test('peanut butter is peanut and not milk', () {
      _expectAll(<_Case>[
        _guard(id, 'חמאת בוטנים', 'not milk'),
        _case(RestrictionId.peanuts, 'חמאת בוטנים', _stated, 'peanut'),
        _case(id, 'Peanut butter cookies', _suspected, 'cookies still asked'),
        _case(RestrictionId.peanuts, 'Peanut butter', _stated, 'peanut'),
      ]);
    });

    test('guards lower the hit', () {
      _expectAll(<_Case>[
        _guard(id, 'Dairy-free cheese', 'dairy-free'),
        _guard(id, 'Dairy-free ice cream', 'dairy-free ice cream'),
        _guard(id, 'Cheese (dairy free)', 'after the trigger'),
        _guard(id, 'Milk free', 'milk free'),
        _guard(id, 'No butter', 'no'),
        _guard(id, 'Burger without cheese', 'without'),
        _case(id, 'Vegan cheese', _suspected, 'a substitute is still asked'),
        _case(id, 'Vegan butter', _suspected, 'a substitute is still asked'),
        _guard(id, 'ללא חלב', 'Hebrew ללא'),
        _guard(id, 'עוגה ללא חלב', 'a hidden Hebrew trigger'),
        _guard(id, 'עוגה בלי מוצרי חלב', 'without dairy products'),
        _guard(id, 'פסטה וללא גבינה', 'Hebrew וללא'),
        _case(id, 'גבינה טבעונית', _suspected, 'a substitute is still asked'),
        _case(id, 'שמנת צמחית', _suspected, 'a plant cream is still asked'),
      ]);
    });

    test('lactose-free and pareve never clear a milk allergy', () {
      _expectAll(<_Case>[
        _case(id, 'Lactose-free milk', _stated, 'lactose-free milk'),
        _case(id, 'Lactose free cheese', _stated, 'lactose-free cheese'),
        _case(id, 'Low lactose yogurt', _stated, 'low-lactose yogurt'),
        _case(id, 'חלב ללא לקטוז', _stated, 'Hebrew lactose-free milk'),
        _case(id, 'גבינה ללא לקטוז', _stated, 'Hebrew lactose-free cheese'),
        _case(id, 'שמנת פרווה', _stated, 'pareve cream'),
        _case(id, 'גבינה פרווה', _stated, 'pareve cheese'),
        _guard(id, 'ללא לקטוז', 'the word lactose alone is lowered'),
      ]);
    });

    test('הפוך takes no prefix, so "to flip" is not a coffee', () {
      _expectAll(<_Case>[
        _case(id, 'ניתן להפוך למנה טבעונית', null, 'to flip'),
        _case(id, 'הפוך', _likely, 'the coffee'),
      ]);
    });
  });

  group('lactose', () {
    const id = RestrictionId.lactose;

    test('direct triggers in English are stated', () {
      _expectAll(<_Case>[
        _case(id, 'Whole milk', _stated, 'milk'),
        _case(id, 'Cream sauce', _stated, 'cream'),
        _case(id, 'Vanilla ice cream', _stated, 'ice cream'),
        _case(id, 'Cottage cheese', _stated, 'soft cheese'),
        _case(id, 'Ricotta ravioli', _stated, 'fresh cheese'),
        _case(id, 'Condensed milk', _stated, 'condensed milk'),
        _case(id, 'Milk chocolate', _stated, 'milk chocolate'),
        _case(id, 'Whey', _stated, 'whey'),
        _case(id, 'Egg custard', _stated, 'custard'),
        _case(id, 'LACTOSE', _stated, 'lactose'),
      ]);
    });

    test('direct triggers in Hebrew are stated, with prefixes', () {
      _expectAll(<_Case>[
        _case(id, 'חלב', _stated, 'milk'),
        _case(id, 'קפה בחלב', _stated, 'prefix ב'),
        _case(id, 'שמנת', _stated, 'cream'),
        _case(id, 'גבינה לבנה', _stated, 'cheese'),
        _case(id, 'גבינת שמנת', _stated, 'cream cheese'),
        _case(id, 'ריקוטה', _stated, 'ricotta'),
        _case(id, "קוטג'", _stated, 'cottage cheese'),
        _case(id, 'שוקו', _stated, 'chocolate milk'),
        _case(id, 'לקטוז', _stated, 'lactose'),
      ]);
    });

    test('hidden sources keep their own certainty', () {
      _expectAll(<_Case>[
        _case(id, 'Brioche', _likely, 'brioche is named in 11 §4.1'),
        _case(id, 'Latte', _likely, 'a milk coffee'),
        _case(id, 'Dairy dessert', _likely, 'dairy'),
        _case(id, 'Bechamel lasagne', _likely, 'bechamel'),
        _case(id, 'Fresh parmesan', _suspected, 'hard cheese'),
        _case(id, 'Cheddar', _suspected, 'hard cheese'),
        _case(id, 'Hard cheese', _suspected, 'hard cheese'),
        _case(id, 'Hard aged cheese', _suspected, 'hard aged cheese'),
        _case(id, 'Butter sauce', _suspected, 'butter holds little lactose'),
        _case(id, 'Greek yogurt', _suspected, 'cultured milk'),
        _case(id, 'Feta salad', _suspected, 'brined cheese'),
        _case(id, 'Mashed potatoes', _suspected, 'mashed potato'),
        _case(id, 'Chocolate brownie', _suspected, 'baked goods'),
        _case(id, 'חלבי', _likely, 'the dairy kosher category'),
        _case(id, 'הפוך', _likely, 'a milk coffee'),
        _case(id, 'גלידת וניל', _likely, 'ice cream'),
        _case(id, 'פרמזן', _suspected, 'hard cheese'),
        _case(id, 'מוקפץ בחמאה', _suspected, 'butter'),
        _case(id, 'יוגורט', _suspected, 'cultured milk'),
        _case(id, 'פטה', _suspected, 'brined cheese'),
        _case(id, 'פירה', _suspected, 'mashed potato'),
      ]);
    });

    test('lactose-free lowers lactose', () {
      _expectAll(<_Case>[
        _guard(id, 'Lactose-free milk', 'lactose-free milk'),
        _guard(id, 'Lactose free yogurt', 'lactose-free yogurt'),
        _case(id, 'Latte with lactose free milk', _likely, 'the latte stays'),
        _case(id, 'Low lactose cream', _stated, 'the word lactose stays'),
        _guard(id, 'Cheese, lactose free', 'after the trigger'),
        _guard(id, 'חלב ללא לקטוז', 'Hebrew lactose-free milk'),
        _guard(id, 'גבינה ללא לקטוז', 'Hebrew lactose-free cheese'),
        _guard(id, 'חלב דל לקטוז', 'Hebrew low-lactose milk'),
        _guard(id, 'ללא לקטוז', 'the word lactose alone is lowered'),
      ]);
    });

    test('hard aged cheese lowers lactose to a question', () {
      _expectAll(<_Case>[
        _case(id, 'Parmesan cheese', _suspected, 'cheese is lowered'),
        _case(id, 'Aged cheese', _suspected, 'cheese is lowered'),
        _guard(id, 'Mature cheddar', 'mature lowers a cheddar'),
        _case(id, 'Gruyere cheese', _suspected, 'gruyere is a hard cheese'),
        _case(id, 'גבינת פרמזן', _suspected, 'Hebrew construct form'),
        _case(id, 'Soft cheese', _stated, 'soft cheese stays stated'),
      ]);
    });

    test('plant milks, vegan and pareve lower lactose', () {
      _expectAll(<_Case>[
        _guard(id, 'Oat milk', 'oat milk'),
        _guard(id, 'Almond milk', 'almond milk'),
        _guard(id, 'Soy milk', 'soy milk'),
        _guard(id, 'Coconut milk', 'coconut milk'),
        _guard(id, 'Vegan cheese', 'vegan'),
        _guard(id, 'Dairy-free ice cream', 'dairy-free'),
        _guard(id, 'Peanut butter', 'peanut butter'),
        _guard(id, 'Cream of tartar', 'cream of tartar'),
        _guard(id, 'חלב שקדים', 'almond milk'),
        _guard(id, 'חלב שיבולת שועל', 'oat milk'),
        _guard(id, 'עוגה פרווה', 'pareve'),
        _guard(id, 'גבינה טבעונית', 'vegan'),
        _guard(id, 'חמאת בוטנים', 'peanut butter'),
        _case(id, 'חלבון', null, 'protein is not milk'),
        _case(id, 'חלבה', null, 'halva is sesame'),
      ]);
    });

    test('the lactose and milk guards differ', () {
      // Arrange
      const phrases = <String>[
        'Lactose-free milk',
        'Lactose free cheese',
        'חלב ללא לקטוז',
        'עוגה פרווה',
      ];

      // Act
      final milk = <TriggerCertainty?>[
        for (final text in phrases) _strongest(RestrictionId.milk, text),
      ];
      final lactose = <TriggerCertainty?>[
        for (final text in phrases) _strongest(RestrictionId.lactose, text),
      ];

      // Assert
      expect(milk, <TriggerCertainty?>[_stated, _stated, _stated, _suspected]);
      expect(lactose, <TriggerCertainty?>[
        _suspected,
        _suspected,
        _suspected,
        _suspected,
      ]);
      for (final text in phrases) {
        expect(_allGuarded(RestrictionId.lactose, text), isTrue, reason: text);
      }
    });
  });

  group('eggs', () {
    const id = RestrictionId.eggs;

    test('direct triggers in English are stated', () {
      _expectAll(<_Case>[
        _case(id, 'Fried eggs', _stated, 'eggs'),
        _case(id, 'Egg salad', _stated, 'egg'),
        _case(id, 'Egg white omelette', _stated, 'egg and omelette'),
        _case(id, 'Free range eggs', _stated, 'free before is no guard'),
        _case(id, 'Garlic aioli', _stated, 'aioli'),
        _case(id, 'Mayonnaise', _stated, 'mayonnaise'),
        _case(id, 'Tuna with mayo', _stated, 'mayo'),
        _case(id, 'Lemon meringue pie', _stated, 'meringue'),
        _case(id, 'Shakshuka', _stated, 'shakshuka'),
        _case(id, 'Eggnog', _stated, 'eggnog'),
        _case(id, 'Frittata', _stated, 'frittata'),
        _case(id, 'Sauce with yolks', _stated, 'yolks'),
        _case(id, 'Pork egg rolls', _stated, 'an egg roll names an egg'),
        _case(id, 'EGGS BENEDICT', _stated, 'case-insensitive'),
      ]);
    });

    test('direct triggers in Hebrew are stated, with prefixes', () {
      _expectAll(<_Case>[
        _case(id, 'ביצה קשה', _stated, 'egg'),
        _case(id, 'ביצים', _stated, 'eggs'),
        _case(id, 'ביצת עין', _stated, 'construct form'),
        _case(id, 'טוסט בביצה', _stated, 'prefix ב'),
        _case(id, 'סלט והביצים', _stated, 'prefix וה'),
        _case(id, 'חלמון', _stated, 'yolk'),
        _case(id, 'חביתה', _stated, 'omelette'),
        _case(id, 'חביתת ירק', _stated, 'omelette, construct form'),
        _case(id, 'שקשוקה', _stated, 'shakshuka'),
        _case(id, 'כריך מיונז', _stated, 'mayonnaise'),
        _case(id, 'איולי', _stated, 'aioli'),
        _case(id, 'מרנג לימון', _stated, 'meringue'),
        _case(id, 'ליזוזים', _stated, 'lysozyme'),
      ]);
    });

    test('hidden sources keep their own certainty', () {
      _expectAll(<_Case>[
        _case(id, 'Brioche bun', _likely, 'brioche'),
        _case(id, 'Wiener schnitzel', _likely, 'schnitzel'),
        _case(id, 'Breaded chicken', _likely, 'breaded'),
        _case(id, 'Crumbed fish', _likely, 'crumbed'),
        _case(id, 'Caesar salad', _likely, 'Caesar dressing'),
        _case(id, 'Eggs with hollandaise', _stated, 'eggs outrank'),
        _case(id, 'Salmon with hollandaise', _likely, 'hollandaise'),
        _case(id, 'Fish with tartare', _likely, 'tartare sauce'),
        _case(id, 'Beef tartare', _likely, 'raw yolk'),
        _case(id, 'טרטר דג', _likely, 'Hebrew tartare'),
        _case(id, 'Steak with bearnaise', _likely, 'bearnaise'),
        _case(id, 'Spaghetti carbonara', _likely, 'carbonara'),
        _case(id, 'Quiche Lorraine', _likely, 'quiche'),
        _case(id, 'Sabich', _likely, 'sabich'),
        _case(id, 'Fresh pasta', _suspected, 'fresh pasta'),
        _case(id, 'Crab surimi', _suspected, 'surimi'),
        _case(id, 'Shrimp tempura', _suspected, 'tempura'),
        _case(id, 'Fish and chips', _suspected, 'battered'),
        _case(id, 'Chocolate cake', _suspected, 'baked goods'),
        _case(id, 'Almond croissant', _suspected, 'egg wash'),
        _case(id, 'Meatballs', _suspected, 'binder'),
        _case(id, 'Soy lecithin', _suspected, 'lecithin is soy or egg'),
        _case(id, 'שניצל', _likely, 'schnitzel'),
        _case(id, 'שניצל בפיתה', _likely, 'schnitzel in a phrase'),
        _case(id, 'בציפוי פירורי לחם', _likely, 'breadcrumbs'),
        _case(id, 'סלט קיסר', _likely, 'Caesar'),
        _case(id, 'סביח', _likely, 'sabich'),
        _case(id, 'רוטב אלף האיים', _likely, 'thousand island'),
        _case(id, 'בריוש', _likely, 'brioche'),
        _case(id, 'פסטה טרייה', _suspected, 'fresh pasta'),
        _case(id, 'סורימי', _suspected, 'surimi'),
        _case(id, 'קציצות בקר', _suspected, 'patties'),
        _case(id, 'בורקס גבינה', _suspected, 'egg wash'),
        _case(id, 'עוגת גבינה', _suspected, 'baked goods'),
        _case(id, 'חלה', _suspected, 'challah'),
        _case(id, 'חלות שבת', _suspected, 'challahs'),
      ]);
    });

    test('guards lower the hit', () {
      _expectAll(<_Case>[
        _guard(id, 'Egg-free mayo', 'egg-free'),
        _guard(id, 'Mayo (egg free)', 'after the trigger'),
        _guard(id, 'Vegan mayo', 'vegan'),
        _guard(id, 'Eggless brownie', 'eggless'),
        _guard(id, 'Plant based egg', 'plant based'),
        _guard(id, 'No eggs', 'no'),
        _guard(id, 'Salad without egg', 'without'),
        _guard(id, 'ללא ביצים', 'Hebrew ללא'),
        _guard(id, 'עוגה בלי ביצים', 'Hebrew בלי'),
        _guard(id, 'סלט וללא ביצים', 'Hebrew וללא'),
        _guard(id, 'עוגה ללא ביצים', 'a hidden Hebrew trigger'),
        _guard(id, 'מיונז טבעוני', 'vegan mayo'),
        _guard(id, 'מיונז צמחי', 'plant mayo'),
        _guard(id, 'Eggs, free range chicken', 'a free after the trigger'),
      ]);
    });

    test('foods that are not egg find nothing', () {
      _expectAll(<_Case>[
        _case(id, 'Grilled eggplant', null, 'eggplant'),
        _case(id, 'Eggplant parmigiana', null, 'eggplant'),
        _case(id, 'Nutmeg', null, 'nutmeg'),
        _case(id, 'Dried pasta', null, 'dried pasta is egg-free'),
        _case(id, 'Cheese pizza', null, 'a different restriction'),
        _case(id, 'לחם', null, 'plain bread'),
        _case(id, 'החלה', null, 'with a prefix, החלה is "began"'),
        _case(id, 'בחלה', null, 'with a prefix ב, not challah'),
        _case(id, 'חלבון', null, 'protein'),
        _case(id, 'חצילים', null, 'eggplants'),
      ]);
    });
  });
}

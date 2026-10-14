import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/utils/allergens/allergen_matcher.dart';
import 'package:ketoclub/utils/allergens/vocabulary.dart';
import 'package:ketoclub/utils/text_normaliser.dart';

/// A test-only vocabulary, so these tests pin the matcher and not the
/// group files (which ALG-01b/c/d fill). Not a safety claim.
const Map<RestrictionId, RestrictionVocabulary> _vocabulary =
    <RestrictionId, RestrictionVocabulary>{
      RestrictionId.sesame: RestrictionVocabulary(
        directEn: <String>['sesame', 'tahini'],
        directHe: <String>['שומשום', 'טחינה'],
        guards: AllergenGuards(
          beforeEn: <String>['no', 'without'],
          afterEn: <String>['free'],
          beforeHe: <String>['ללא', 'בלי'],
        ),
        sources: <String>['11 §11'],
      ),
      RestrictionId.milk: RestrictionVocabulary(
        directEn: <String>['milk', 'cream'],
        directHe: <String>['חלב'],
        guards: AllergenGuards(
          beforeEn: <String>['oat', 'coconut'],
          afterHe: <String>['סויה'],
        ),
        termGuards: <String, AllergenGuards>{
          'חלב': AllergenGuards(afterHe: <String>['קוקוס']),
        },
      ),
      RestrictionId.lactose: RestrictionVocabulary(
        directEn: <String>['milk'],
        guards: AllergenGuards(beforeEn: <String>['lactose free']),
      ),
      RestrictionId.eggs: RestrictionVocabulary(
        directEn: <String>['eggs'],
        guards: AllergenGuards(afterEn: <String>['free']),
      ),
      RestrictionId.wheat: RestrictionVocabulary(
        directHe: <String>['חיטה'],
        hiddenEn: <HiddenTrigger>[
          HiddenTrigger(
            term: 'soy sauce',
            certainty: TriggerCertainty.likely,
            source: '11 §7.2',
          ),
        ],
        hiddenHe: <HiddenTrigger>[
          HiddenTrigger(
            term: 'רוטב סויה',
            certainty: TriggerCertainty.likely,
            source: '11 §7.2',
          ),
        ],
        noPrefixHe: <String>['חיטה'],
      ),
      RestrictionId.soy: RestrictionVocabulary(
        directEn: <String>['soy'],
        directHe: <String>['סויה'],
      ),
      RestrictionId.fish: RestrictionVocabulary(
        hiddenEn: <HiddenTrigger>[
          HiddenTrigger(
            term: 'Worcestershire',
            certainty: TriggerCertainty.likely,
            source: '11 §8.2',
          ),
        ],
      ),
      RestrictionId.celery: RestrictionVocabulary(
        hiddenEn: <HiddenTrigger>[
          HiddenTrigger(
            term: 'vegetable stock',
            certainty: TriggerCertainty.suspected,
            source: '11 §12.2',
          ),
        ],
      ),
      RestrictionId.mustard: RestrictionVocabulary(directEn: <String>['!!']),
      RestrictionId.peanuts: RestrictionVocabulary(
        directEn: <String>['peanut butter'],
        directHe: <String>['חמאת בוטנים'],
        guards: AllergenGuards(afterEn: <String>['free']),
      ),
      RestrictionId.treeNuts: RestrictionVocabulary(
        directEn: <String>['almond milk'],
      ),
      RestrictionId.gluten: RestrictionVocabulary(
        directEn: <String>['flour'],
        guards: AllergenGuards(beforeEn: <String>['gluten free']),
        termGuards: <String, AllergenGuards>{
          'flour': AllergenGuards(beforeEn: <String>['rice']),
        },
      ),
      RestrictionId.molluscs: RestrictionVocabulary(
        directEn: <String>['oyster'],
        termGuards: <String, AllergenGuards>{
          'oyster': AllergenGuards(afterEn: <String>['mushroom']),
        },
      ),
    };

/// The hits for [text] as `id:term:certainty`, with `:guarded` appended
/// to a guarded hit, in order.
List<String> _found(String text) => <String>[
  for (final hit in AllergenMatcher.findWith(text, _vocabulary))
    [
      hit.id.name,
      hit.term,
      hit.certainty.name,
      if (hit.guarded) 'guarded',
    ].join(':'),
];

/// A dish named [name] with [description] and [options].
Dish _dish(
  String name, {
  String description = '',
  List<DishOption> options = const <DishOption>[],
}) => Dish(
  id: 'd',
  name: name,
  description: description,
  price: 10,
  options: options,
);

void main() {
  group('AllergenMatcher.findWith', () {
    final cases = <({String text, List<String> hits, String why})>[
      (
        text: 'Bagel with sesame seeds',
        hits: <String>['sesame:sesame:stated'],
        why: 'English direct trigger',
      ),
      (
        text: 'Toasted SESAME bun',
        hits: <String>['sesame:sesame:stated'],
        why: 'case-insensitive',
      ),
      (
        text: 'Sesamestreet salad',
        hits: <String>[],
        why: 'a Latin trigger needs a word boundary',
      ),
      (
        text: 'סלט ירקות עם טחינה',
        hits: <String>['sesame:טחינה:stated'],
        why: 'Hebrew direct trigger',
      ),
      (
        text: 'חומוס בטחינה',
        hits: <String>['sesame:טחינה:stated'],
        why: 'Hebrew prefix ב',
      ),
      (
        text: 'בורקס והשומשום מעל',
        hits: <String>['sesame:שומשום:stated'],
        why: 'Hebrew double prefix וה',
      ),
      (
        text: 'חלבה',
        hits: <String>[],
        why: 'a Hebrew suffix is another word (חלבה is not חלב)',
      ),
      (
        text: 'Sesame-free bun',
        hits: <String>['sesame:sesame:suspected:guarded'],
        why: 'an after-guard lowers the hit, never cancels it',
      ),
      (
        text: 'Hummus, no tahini',
        hits: <String>['sesame:tahini:suspected:guarded'],
        why: 'a before-guard lowers the hit, never cancels it',
      ),
      (
        text: 'חומוס ללא טחינה',
        hits: <String>['sesame:טחינה:suspected:guarded'],
        why: 'a Hebrew before-guard lowers the hit',
      ),
      (
        text: 'Free range eggs',
        hits: <String>['eggs:eggs:stated'],
        why: 'a guard only works on its own side',
      ),
      (
        text: 'שומשום free',
        hits: <String>['sesame:שומשום:stated'],
        why: 'English guards do not apply to Hebrew triggers',
      ),
      (
        text: 'Latte with oat milk',
        hits: <String>['milk:milk:suspected:guarded', 'lactose:milk:stated'],
        why: "a guard is the restriction's own: oat lowers milk only",
      ),
      (
        text: 'Lactose-free milk',
        hits: <String>['milk:milk:stated', 'lactose:milk:suspected:guarded'],
        why: 'lactose-free lowers lactose, never the milk allergy',
      ),
      (
        text: 'קפה עם חלב סויה',
        hits: <String>['milk:חלב:suspected:guarded', 'soy:סויה:stated'],
        why: 'a Hebrew after-guard lowers the milk hit',
      ),
      (
        text: 'Salad with milk dressing',
        hits: <String>['milk:milk:stated', 'lactose:milk:stated'],
        why: 'one span, two restrictions, taxonomy order',
      ),
      (
        text: 'Tahini and cream',
        hits: <String>['sesame:tahini:stated', 'milk:cream:stated'],
        why: 'ordered by start',
      ),
      (
        text: 'Steak with Worcestershire butter',
        hits: <String>['fish:Worcestershire:likely'],
        why: 'a hidden trigger keeps its certainty',
      ),
      (
        text: 'Soup on vegetable stock',
        hits: <String>['celery:vegetable stock:suspected'],
        why: 'a suspected hidden trigger',
      ),
      (
        text: 'Noodles in soy sauce',
        hits: <String>['soy:soy:stated', 'wheat:soy sauce:likely'],
        why: 'a direct and a hidden hit at one start, taxonomy order',
      ),
      (
        text: 'עוף ברוטב סויה',
        hits: <String>['wheat:רוטב סויה:likely', 'soy:סויה:stated'],
        why: 'Hebrew hidden trigger with a prefix',
      ),
      (
        text: 'לחם מקמח חיטה מלא',
        hits: <String>['wheat:חיטה:stated'],
        why: 'a no-prefix term still matches on its own',
      ),
      (
        text: 'שחיטה כשרה',
        hits: <String>[],
        why: 'a no-prefix term does not match after ש (שחיטה)',
      ),
      (
        text: '!! mustard',
        hits: <String>[],
        why: 'a term that normalises to nothing is skipped',
      ),
      (text: '', hits: <String>[], why: 'empty text'),
      // ALG-04a: a guard counts only in the slot adjacent to its term.
      (
        text: 'Hummus, no sesame or tahini',
        hits: <String>[
          'sesame:sesame:suspected:guarded',
          'sesame:tahini:stated',
        ],
        why: 'a guard beside one term never reaches its neighbour',
      ),
      (
        text: 'Sesame-free tahini',
        hits: <String>[
          'sesame:sesame:suspected:guarded',
          'sesame:tahini:stated',
        ],
        why: 'an after-guard lowers the term before it, not the one after',
      ),
      (
        text: 'No big tahini',
        hits: <String>['sesame:tahini:stated'],
        why: 'a before-guard one word away is not adjacent',
      ),
      (
        text: 'Tahini, big free',
        hits: <String>['sesame:tahini:stated'],
        why: 'an after-guard one word away is not adjacent',
      ),
      (
        text: 'Lactose big free milk',
        hits: <String>['milk:milk:stated', 'lactose:milk:stated'],
        why: 'every word of a multi-word guard must be adjacent',
      ),
      (
        text: 'חומוס וללא טחינה',
        hits: <String>['sesame:טחינה:suspected:guarded'],
        why: 'a Hebrew before-guard may carry a prefix letter',
      ),
      (
        text: 'חומוס ובללא טחינה',
        hits: <String>['sesame:טחינה:suspected:guarded'],
        why: 'a Hebrew before-guard may carry two prefix letters',
      ),
      (
        text: 'חומוס אללא טחינה',
        hits: <String>['sesame:טחינה:stated'],
        why: 'a letter that is no prefix makes another word',
      ),
      (
        text: 'קפה עם חלב הסויה',
        hits: <String>['milk:חלב:suspected:guarded', 'soy:סויה:stated'],
        why: 'a Hebrew after-guard may carry the article ה',
      ),
      (
        text: 'קפה עם חלב וסויה',
        hits: <String>['milk:חלב:stated', 'soy:סויה:stated'],
        why: 'milk and soy: ו is not a prefix an after-guard takes',
      ),
      (
        text: 'ללא גלוטן ועם טחינה',
        hits: <String>['sesame:טחינה:stated'],
        why: 'a guard one word away lowers nothing',
      ),
      (
        text: 'Gluten-free tahini',
        hits: <String>['sesame:tahini:stated'],
        why: "another restriction's guard lowers nothing",
      ),
      // ALG-04a: per-term guards.
      (
        text: 'Bun with rice flour',
        hits: <String>['gluten:flour:suspected:guarded'],
        why: 'a term guard lowers its own term',
      ),
      (
        text: 'Rice flour and wheat flour',
        hits: <String>['gluten:flour:suspected:guarded', 'gluten:flour:stated'],
        why: 'a term guard lowers only the occurrence beside it',
      ),
      (
        text: 'Gluten-free flour',
        hits: <String>['gluten:flour:suspected:guarded'],
        why: "a term's own guards add to its restriction's",
      ),
      (
        text: 'קארי בחלב קוקוס',
        hits: <String>['milk:חלב:suspected:guarded'],
        why: 'a Hebrew term guard',
      ),
      (
        text: 'Flat white with almond milk',
        hits: <String>[
          'treeNuts:almond milk:stated',
          'milk:milk:stated',
          'lactose:milk:stated',
        ],
        why: 'a compound hits its own allergen; no guard, no lowering',
      ),
      (
        text: 'Oyster mushroom risotto',
        hits: <String>['molluscs:oyster:suspected:guarded'],
        why: 'oyster mushroom is lowered, never dropped',
      ),
      (
        text: 'Mushroom and oyster',
        hits: <String>['molluscs:oyster:stated'],
        why: 'a term guard keeps its side',
      ),
      // ALG-04a: the maqaf joins words.
      (
        text: 'טוסט עם חמאת־בוטנים',
        hits: <String>['peanuts:חמאת בוטנים:stated'],
        why: 'a maqaf reads as a space',
      ),
      (
        text: 'חומוס ללא־טחינה',
        hits: <String>['sesame:טחינה:suspected:guarded'],
        why: 'a guard joined by a maqaf is adjacent',
      ),
    ];

    for (final entry in cases) {
      test('${entry.why}: "${entry.text}"', () {
        expect(_found(entry.text), entry.hits);
      });
    }

    test('offsets index the normalised text; a prefix is in the span', () {
      // Arrange
      const text = 'חומוס, בטחינה!';
      final normalised = TextNormaliser.normalise(text);

      // Act
      final hits = AllergenMatcher.findWith(text, _vocabulary);

      // Assert
      expect(hits, hasLength(1));
      expect(
        normalised.substring(hits.single.start, hits.single.end),
        'בטחינה',
      );
    });

    test('every occurrence is reported, left to right', () {
      // Act
      final hits = AllergenMatcher.findWith(
        'tahini, then more tahini',
        _vocabulary,
      );

      // Assert
      expect(hits.map((hit) => hit.start).toList(), <int>[0, 17]);
    });

    test('a restriction with no vocabulary entry is never reported', () {
      // Act
      final hits = AllergenMatcher.findWith(
        'sesame',
        const <RestrictionId, RestrictionVocabulary>{},
      );

      // Assert
      expect(hits, isEmpty);
    });

    test('the result is the same on every call', () {
      // Arrange
      const text = 'Noodles in soy sauce with tahini and milk';

      // Assert
      expect(
        AllergenMatcher.findWith(text, _vocabulary),
        AllergenMatcher.findWith(text, _vocabulary),
      );
    });
  });

  group('AllergenMatcher.matchText', () {
    test('is the normalised text when there is no maqaf', () {
      for (final text in <String>['Sesame-free bun', 'חומוס, בטחינה!', '']) {
        expect(AllergenMatcher.matchText(text), TextNormaliser.normalise(text));
      }
    });

    test('reads a maqaf as a space; the keto normaliser deletes it', () {
      // Arrange
      const text = 'חמאת־בוטנים';

      // Assert
      expect(TextNormaliser.normalise(text), 'חמאתבוטנימ');
      expect(AllergenMatcher.matchText(text), 'חמאת בוטנימ');
    });

    test('offsets after a maqaf index matchText', () {
      // Arrange
      const text = 'פיתה עם חמאת־בוטנים';

      // Act
      final hit = AllergenMatcher.findWith(text, _vocabulary).single;

      // Assert
      expect(
        AllergenMatcher.matchText(text).substring(hit.start, hit.end),
        'חמאת בוטנימ',
      );
    });
  });

  group('AllergenMatcher.findInDishWith', () {
    test('reads the name, the description and the option values', () {
      // Arrange
      final dish = _dish(
        'Falafel plate',
        description: 'With tahini',
        options: const <DishOption>[
          DishOption(name: 'Extras', values: <String>['Add milk']),
        ],
      );

      // Act
      final ids = AllergenMatcher.findInDishWith(
        dish,
        _vocabulary,
      ).map((hit) => hit.id).toList();

      // Assert
      expect(ids, <RestrictionId>[
        RestrictionId.sesame,
        RestrictionId.milk,
        RestrictionId.lactose,
      ]);
    });

    test('skips a removal option value, as matchDish does', () {
      // Arrange
      final dish = _dish(
        'Hummus',
        options: const <DishOption>[
          DishOption(
            name: 'Changes',
            values: <String>['No tahini', 'ללא שומשום', 'בלי חלב'],
          ),
        ],
      );

      // Act
      final hits = AllergenMatcher.findInDishWith(dish, _vocabulary);

      // Assert
      expect(hits, isEmpty);
    });

    test('reads a maqaf as a space in every field', () {
      // Arrange
      final dish = _dish(
        'טוסט',
        description: 'עם חמאת־בוטנים',
        options: const <DishOption>[
          DishOption(name: 'שינויים', values: <String>['ללא־טחינה']),
        ],
      );

      // Act
      final hits = AllergenMatcher.findInDishWith(dish, _vocabulary);

      // Assert
      expect(
        AllergenMatcher.dishMatchText(dish),
        'טוסט עמ חמאת בוטנימ שינויימ',
      );
      expect(hits.map((hit) => hit.term).toList(), <String>['חמאת בוטנים']);
    });

    test('offsets index dishRulesText', () {
      // Arrange
      final dish = _dish('סלט', description: 'עם טחינה');
      final text = TextNormaliser.dishRulesText(dish);

      // Act
      final hit = AllergenMatcher.findInDishWith(dish, _vocabulary).single;

      // Assert
      expect(text.substring(hit.start, hit.end), 'טחינה');
    });
  });

  group('AllergenMatcher over the registry', () {
    test('find is findWith over allergenVocabulary', () {
      for (final text in <String>[
        'Sesame bagel with cream cheese',
        'סלט עם טחינה ושומשום',
        'Noodles in soy sauce',
      ]) {
        expect(
          AllergenMatcher.find(text),
          AllergenMatcher.findWith(text, allergenVocabulary),
        );
      }
    });

    test('findInDish is findInDishWith over allergenVocabulary', () {
      // Arrange
      final dish = _dish(
        'Bagel',
        description: 'Sesame, cream cheese',
        options: const <DishOption>[
          DishOption(name: 'Spread', values: <String>['No butter', 'Tahini']),
        ],
      );

      // Assert
      expect(
        AllergenMatcher.findInDish(dish),
        AllergenMatcher.findInDishWith(dish, allergenVocabulary),
      );
    });
  });

  group('AllergenHit', () {
    const hit = AllergenHit(
      id: RestrictionId.sesame,
      term: 'tahini',
      certainty: TriggerCertainty.stated,
      start: 3,
      end: 9,
    );

    test('equal values are equal and hash alike', () {
      // Arrange
      const same = AllergenHit(
        id: RestrictionId.sesame,
        term: 'tahini',
        certainty: TriggerCertainty.stated,
        start: 3,
        end: 9,
      );

      // Assert
      expect(same, hit);
      expect(same.hashCode, hit.hashCode);
      expect(
        hit,
        isNot(
          const AllergenHit(
            id: RestrictionId.sesame,
            term: 'tahini',
            certainty: TriggerCertainty.stated,
            start: 4,
            end: 10,
          ),
        ),
      );
    });

    test('guarded is part of equality and defaults to false', () {
      // Arrange
      const guarded = AllergenHit(
        id: RestrictionId.sesame,
        term: 'tahini',
        certainty: TriggerCertainty.stated,
        start: 3,
        end: 9,
        guarded: true,
      );

      // Assert
      expect(hit.guarded, isFalse);
      expect(guarded, isNot(hit));
      expect(guarded.hashCode, isNot(hit.hashCode));
    });

    test('toString names the id, term, certainty and span', () {
      expect(hit.toString(), 'AllergenHit(sesame, tahini, stated, 3-9)');
    });

    test('toString marks a guarded hit', () {
      expect(
        const AllergenHit(
          id: RestrictionId.sesame,
          term: 'tahini',
          certainty: TriggerCertainty.suspected,
          start: 3,
          end: 9,
          guarded: true,
        ).toString(),
        'AllergenHit(sesame, tahini, suspected, 3-9, guarded)',
      );
    });
  });
}

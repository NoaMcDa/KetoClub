import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/utils/allergens/allergen_matcher.dart';
import 'package:ketoclub/utils/allergens/vocabulary.dart';
import 'package:ketoclub/utils/classification_rules.dart';

/// The restrictions `vocab_seeds_extra.dart` owns.
const List<RestrictionId> _ids = <RestrictionId>[
  RestrictionId.corn,
  RestrictionId.sunflower,
  RestrictionId.flax,
];

/// The hits [AllergenMatcher.find] reports for [id] in [text], each as
/// `term:certainty`, with `:guarded` when a guard lowered it. Filtered by
/// id so the other groups' vocabularies cannot change these tests.
List<String> _hits(String text, RestrictionId id) => <String>[
  for (final hit in AllergenMatcher.find(text))
    if (hit.id == id)
      '${hit.term}:${hit.certainty.name}${hit.guarded ? ':guarded' : ''}',
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
  group('the group', () {
    for (final id in _ids) {
      test('${id.name} holds a term, so the picker offers it', () {
        // Act
        final vocabulary = allergenVocabulary[id]!;

        // Assert
        expect(vocabulary.isEmpty, isFalse);
        expect(vocabulary.sources, isNotEmpty);
      });
    }
  });

  group('corn', () {
    const id = RestrictionId.corn;
    _run(<_Case>[
      _hit('Corn salad', id, <String>['corn:stated']),
      _hit('Salad with baby corn', id, <String>['corn:stated']),
      _hit('Creamy polenta', id, <String>['polenta:stated']),
      _hit('Shrimp and grits', id, <String>['grits:stated']),
      _hit('Cornbread muffin', id, <String>['cornbread:stated']),
      _hit('Elote', id, <String>['elote:stated']),
      _hit('Arepa with cheese', id, <String>[
        'arepa:likely',
      ], why: 'is corn masa by definition'),
      _hit('Chicken tamales', id, <String>['tamales:likely']),
      _hit('Loaded nachos', id, <String>['nachos:likely']),
      _hit('Tortilla chips and salsa', id, <String>['tortilla chips:likely']),
      _hit('Bamba', id, <String>['bamba:likely'], why: 'is puffed maize'),
      _hit('Fish tacos', id, <String>[
        'tacos:suspected',
      ], why: 'may be corn or flour'),
      _hit('Corn tortilla', id, <String>['corn:stated', 'tortilla:suspected']),
      _hit('Flour tortilla wrap', id, <String>[
        'tortilla:suspected:guarded',
      ], why: 'is lowered, never dropped'),
      _hit('Soup thickened with cornstarch', id, <String>[
        'cornstarch:suspected',
      ]),
      _hit('Glazed with corn syrup', id, <String>[
        'corn:suspected:guarded',
        'corn syrup:suspected',
      ], why: 'refined: guidance disagrees'),
      _hit('Fried in corn oil', id, <String>[
        'corn:suspected:guarded',
        'corn oil:suspected',
      ]),
      _hit('Popcorn', id, <String>['popcorn:stated']),
      _hit('Popcorn shrimp', id, <String>[
        'popcorn:suspected:guarded',
      ], why: 'is a size, lowered'),
      _hit('Corn-free tacos', id, <String>['corn:suspected:guarded']),
      _miss('Peppercorn steak', id, why: 'is not corn'),
      _miss('Corned beef on rye', id, why: 'is not corn'),
      _miss('Served with cornichons', id),
      _miss('Acorn squash', id),
      _miss('Halva', id),
      _hit('סלט תירס', id, <String>['תירס:stated']),
      _hit('ועם תירס', id, <String>['תירס:stated'], why: 'takes a prefix'),
      _hit('פולנטה קרמית', id, <String>['פולנטה:stated']),
      _hit('שניצל קורנפלקס', id, <String>['קורנפלקס:stated']),
      _hit('פופקורן', id, <String>['פופקורן:stated']),
      _hit("נאצ'וס", id, <String>[
        'נאצ׳וס:likely',
      ], why: 'apostrophe and geresh read alike'),
      _hit('במבה', id, <String>['במבה:likely']),
      _hit('טורטייה עוף', id, <String>['טורטייה:suspected']),
      _hit('מוסמך בקורנפלור', id, <String>['קורנפלור:suspected']),
      _hit('עמילן תירס', id, <String>[
        'תירס:suspected:guarded',
        'עמילן תירס:suspected',
      ]),
      _hit('בשמן תירס', id, <String>['תירס:suspected:guarded']),
      _hit('סלט ללא תירס', id, <String>['תירס:suspected:guarded']),
    ]);

    test('a corn flour lowers wheat and still reports corn', () {
      // Act
      final hits = AllergenMatcher.find('Corn flour flatbread');

      // Assert
      expect(
        hits.where((hit) => hit.id == RestrictionId.corn).single.certainty,
        TriggerCertainty.stated,
      );
      final wheatFlour = hits.firstWhere(
        (hit) => hit.id == RestrictionId.wheat && hit.term == 'flour',
      );
      expect(wheatFlour.guarded, isTrue);
    });

    test('a Hebrew corn flour lowers wheat and still reports corn', () {
      // Act
      final hits = AllergenMatcher.find('קמח תירס');

      // Assert
      expect(_hits('קמח תירס', RestrictionId.corn), <String>['תירס:stated']);
      final wheat = hits.where((hit) => hit.id == RestrictionId.wheat);
      expect(wheat.every((hit) => hit.guarded), isTrue);
    });

    test('changes no keto verdict: corn is still a carb trigger', () {
      // Act
      final result = ClassificationRules.match('Salad with baby corn');

      // Assert
      expect(result.instructions, isNotEmpty);
    });
  });

  group('sunflower', () {
    const id = RestrictionId.sunflower;
    _run(<_Case>[
      _hit('Toasted sunflower seeds', id, <String>[
        'sunflower:stated',
        'sunflower seeds:stated',
      ]),
      _hit('Sunflower seed butter', id, <String>[
        'sunflower seed butter:stated',
      ]),
      _hit('SunButter toast', id, <String>['sunbutter:stated']),
      _hit('Sunflower halva', id, <String>['sunflower:stated']),
      _hit('Fried in sunflower oil', id, <String>[
        'sunflower:suspected:guarded',
        'sunflower oil:suspected',
      ], why: 'refined oil is often tolerated'),
      _hit('Sunflower seed oil', id, <String>[
        'sunflower:suspected:guarded',
        'sunflower seed:suspected:guarded',
      ]),
      _hit('Multigrain toast', id, <String>['multigrain:suspected']),
      _hit('Sunflower-free', id, <String>['sunflower:suspected:guarded']),
      _miss('Halva', id, why: 'Israeli halva is tahini'),
      _miss('Sesame bagel', id),
      _hit('סלט עם גרעיני חמנייה', id, <String>['חמנייה:stated']),
      _hit('חלבת חמניות', id, <String>['חמניות:stated']),
      _hit('בשמן חמניות', id, <String>[
        'חמניות:suspected:guarded',
        'שמן חמניות:suspected',
      ]),
      _hit('שקית גרעינים', id, <String>['גרעינים:suspected']),
      _hit('גרעינים של דלעת', id, <String>['גרעינים:suspected:guarded']),
      _hit('כריך בלחם דגנים', id, <String>['לחם דגנים:suspected']),
      _hit('ללא חמניות', id, <String>['חמניות:suspected:guarded']),
      _miss('חלבה', id, why: 'Israeli halva is tahini'),
      _miss('המבורגר בלחמנייה', id, why: 'a bread roll, not sunflower'),
      _miss('לחמניה רכה', id, why: 'a bread roll, not sunflower'),
      _miss('לחמניות', id, why: 'bread rolls, not sunflower'),
      _miss('לחמנית מחמצת', id, why: 'a bread roll, not sunflower'),
      _hit('שומשום וחמנייה', id, <String>['וחמנייה:stated']),
      _miss('גרעיני רימון', id, why: 'pomegranate seeds'),
    ]);
  });

  group('flax', () {
    const id = RestrictionId.flax;
    _run(<_Case>[
      _hit('Ground flaxseed', id, <String>['flaxseed:stated']),
      _hit('Linseed bread', id, <String>['linseed:stated']),
      _hit('Flax meal', id, <String>['flax:stated', 'flax meal:stated']),
      _hit('Seeded bread roll', id, <String>['seeded bread:suspected']),
      _hit('Multi-grain bread', id, <String>['multi grain:suspected']),
      _hit('Flax-free granola', id, <String>['flax:suspected:guarded']),
      _miss('Chia pudding', id),
      _hit('זרעי פשתן', id, <String>['פשתן:stated', 'זרעי פשתן:stated']),
      _hit('קרקר פשתן', id, <String>['פשתן:stated']),
      _hit('לחם רב דגנים', id, <String>['רב דגנים:suspected']),
      _hit('ללא פשתן', id, <String>['פשתן:suspected:guarded']),
    ]);

    test('flax crackers lower wheat and still report flax', () {
      // Act
      final hits = AllergenMatcher.find('Flax crackers');

      // Assert
      expect(_hits('Flax crackers', RestrictionId.flax), <String>[
        'flax:stated',
      ]);
      final crackers = hits.firstWhere(
        (hit) => hit.id == RestrictionId.wheat && hit.term == 'crackers',
      );
      expect(crackers.guarded, isTrue);
    });
  });

  group('chestnut (tree nuts)', () {
    const id = RestrictionId.treeNuts;
    _run(<_Case>[
      _hit('Roast chestnuts', id, <String>[
        'chestnuts:suspected',
      ], why: 'a low-confidence tree nut'),
      _hit('Chestnut soup', id, <String>['chestnut:suspected']),
      _hit('Marrons glacés', id, <String>['marrons glaces:suspected']),
      _hit('Water chestnut stir-fry', id, <String>[
        'chestnut:suspected:guarded',
      ], why: 'is lowered, never dropped'),
      _miss('Butternut squash', id),
      _hit('מרק ערמונים', id, <String>['ערמונים:suspected']),
      _hit('ערמון קלוי', id, <String>['ערמון:suspected']),
      _miss('ערמוני מים', id, why: 'water chestnuts are not a term'),
    ]);

    test('a chestnut is never stated', () {
      // Act
      final hits = AllergenMatcher.find('Chestnuts, chestnut, ערמונים');

      // Assert
      final chestnuts = hits.where((hit) => hit.id == RestrictionId.treeNuts);
      expect(chestnuts, isNotEmpty);
      expect(
        chestnuts.every((hit) => hit.certainty == TriggerCertainty.suspected),
        isTrue,
      );
    });
  });
}

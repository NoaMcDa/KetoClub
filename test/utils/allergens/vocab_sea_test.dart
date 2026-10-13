import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/utils/allergens/allergen_matcher.dart';
import 'package:ketoclub/utils/allergens/vocabulary.dart';

// One expectation: `text` gives `id` a hit on `term` at certainty `c`.
typedef _Hit = (String text, RestrictionId id, String term, TriggerCertainty c);

const TriggerCertainty _stated = TriggerCertainty.stated;
const TriggerCertainty _likely = TriggerCertainty.likely;
const TriggerCertainty _suspected = TriggerCertainty.suspected;

const RestrictionId _fish = RestrictionId.fish;
const RestrictionId _crust = RestrictionId.crustaceans;
const RestrictionId _moll = RestrictionId.molluscs;

const List<RestrictionId> _ids = <RestrictionId>[_fish, _crust, _moll];

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
  group('fish and seafood vocabulary', () {
    for (final id in _ids) {
      group(id.name, () {
        final vocabulary = allergenVocabulary[id]!;

        test('is filled and cites its sources', () {
          expect(vocabulary.isEmpty, isFalse);
          expect(vocabulary.directEn, isNotEmpty);
          expect(vocabulary.directHe, isNotEmpty);
          expect(vocabulary.hiddenEn, isNotEmpty);
          expect(vocabulary.hiddenHe, isNotEmpty);
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
      });
    }

    test('seafood and shellfish name crustaceans and molluscs, not fish', () {
      for (final text in <String>[
        'Seafood platter',
        'Shellfish bisque',
        'Frutti di mare',
        'פירות ים',
        'ספגטי פירות ים',
        'בפירות הים',
      ]) {
        expect(_hits(text, _crust), isNotEmpty, reason: text);
        expect(_hits(text, _moll), isNotEmpty, reason: text);
        expect(_hits(text, _fish), isEmpty, reason: text);
      }
    });
  });

  group('direct hits', () {
    const cases = <_Hit>[
      ('Grilled salmon', _fish, 'salmon', _stated),
      ('Tuna tartare', _fish, 'tuna', _stated),
      ('Sea bass fillet', _fish, 'sea bass', _stated),
      ('Whole bream', _fish, 'bream', _stated),
      ('Smoked trout', _fish, 'trout', _stated),
      ('Cod and chips', _fish, 'cod', _stated),
      ('Anchovy toast', _fish, 'anchovy', _stated),
      ('Fresh sardines', _fish, 'sardines', _stated),
      ('Mackerel pate', _fish, 'mackerel', _stated),
      ('Pickled herring', _fish, 'herring', _stated),
      ('Grilled tilapia', _fish, 'tilapia', _stated),
      ('Grey mullet', _fish, 'mullet', _stated),
      ('Fish and chips', _fish, 'fish', _stated),
      ('Salmon caviar', _fish, 'caviar', _stated),
      ('Cured roe', _fish, 'roe', _stated),
      ('Thai nam pla dressing', _fish, 'nam pla', _stated),
      ('Bouillabaisse', _fish, 'bouillabaisse', _stated),
      ('דג ביום', _fish, 'דג', _stated),
      ('מנת דגים', _fish, 'דגים', _stated),
      ('פילה לדג', _fish, 'דג', _stated),
      ('אורז עם הדג', _fish, 'דג', _stated),
      ('סלמון בתנור', _fish, 'סלמון', _stated),
      ('טונה אדומה', _fish, 'טונה', _stated),
      ('לברק בצלייה', _fish, 'לברק', _stated),
      ('דניס על האש', _fish, 'דניס', _stated),
      ('פורל מעושן', _fish, 'פורל', _stated),
      ('אמנון בתנור', _fish, 'אמנון', _stated),
      ('בורי צלוי', _fish, 'בורי', _stated),
      ('הרינג כבוש', _fish, 'הרינג', _stated),
      ('אנשובי ברוטב', _fish, 'אנשובי', _stated),
      ('חריימה חריפה', _fish, 'חריימה', _stated),
      ("סביצ'ה דג לבן", _fish, "סביצ'ה", _stated),
      ('קוויאר שחור', _fish, 'קוויאר', _stated),
      ('Shrimp tempura', _crust, 'shrimp', _stated),
      ('Garlic prawns', _crust, 'prawns', _stated),
      ('Crab cakes', _crust, 'crab', _stated),
      ('Lobster roll', _crust, 'lobster', _stated),
      ('Crayfish salad', _crust, 'crayfish', _stated),
      ('Langoustine tails', _crust, 'langoustine', _stated),
      ('Scampi in garlic', _crust, 'scampi', _stated),
      ('Lobster bisque', _crust, 'bisque', _stated),
      ('Seafood linguine', _crust, 'seafood', _stated),
      ('Seafood linguine', _moll, 'seafood', _stated),
      ('שרימפס בשמן שום', _crust, 'שרימפס', _stated),
      ('פסטה משרימפס', _crust, 'שרימפס', _stated),
      ('סרטן ברוטב', _crust, 'סרטן', _stated),
      ('לובסטר צלוי', _crust, 'לובסטר', _stated),
      ('פירות ים בחמאה', _crust, 'פירות ים', _stated),
      ('פירות ים בחמאה', _moll, 'פירות ים', _stated),
      ('Mussels in white wine', _moll, 'mussels', _stated),
      ('Steamed clams', _moll, 'clams', _stated),
      ('Fresh oysters', _moll, 'oysters', _stated),
      ('Seared scallops', _moll, 'scallops', _stated),
      ('Grilled squid', _moll, 'squid', _stated),
      ('Fried calamari', _moll, 'calamari', _stated),
      ('Charred octopus', _moll, 'octopus', _stated),
      ('Escargot in butter', _moll, 'escargot', _stated),
      ('Spaghetti vongole', _moll, 'vongole', _stated),
      ('מולים ביין לבן', _moll, 'מולים', _stated),
      ('פסטה במולים', _moll, 'מולים', _stated),
      ('צדפות טריות', _moll, 'צדפות', _stated),
      ('קלמרי מטוגן', _moll, 'קלמרי', _stated),
      ('תמנון על הגריל', _moll, 'תמנון', _stated),
      ('דיונון ממולא', _moll, 'דיונון', _stated),
      ('סקאלופס בחמאה', _moll, 'סקאלופס', _stated),
      ('חלזונות בשום', _moll, 'חלזונות', _stated),
    ];
    for (final (text, id, term, certainty) in cases) {
      test('$text gives ${id.name} "$term" (${certainty.name})', () {
        expect(_certaintyOf(text, id, term), certainty);
      });
    }

    test('fish, shellfish and mollusc words do not cross over', () {
      expect(_hits('Grilled squid', _fish), isEmpty);
      expect(_hits('Grilled squid', _crust), isEmpty);
      expect(_hits('Shrimp tempura', _moll), isEmpty);
      expect(_hits('Shrimp tempura', _fish), isEmpty);
      expect(_hits('Crayfish salad', _fish), isEmpty);
      expect(_hits('Cuttlefish ink pasta', _fish), isEmpty);
      expect(_hits('Cuttlefish ink pasta', _crust), isEmpty);
      expect(_hits('פילה דג', _moll), isEmpty);
    });
  });

  group('hidden sources keep their certainty', () {
    const cases = <_Hit>[
      ('Worcestershire glaze', _fish, 'worcestershire', _likely),
      ('Caesar salad', _fish, 'caesar', _likely),
      ('Crab sticks with surimi', _fish, 'surimi', _likely),
      ('Fish sauce dressing', _fish, 'fish sauce', _likely),
      ('Dashi broth', _fish, 'dashi', _suspected),
      ('Miso soup', _fish, 'miso soup', _suspected),
      ('Kimchi fried rice', _fish, 'kimchi', _suspected),
      ('Spaghetti puttanesca', _fish, 'puttanesca', _suspected),
      ('Barbecue sauce ribs', _fish, 'barbecue sauce', _suspected),
      ('סלט קיסר', _fish, 'סלט קיסר', _likely),
      ('רוטב דגים', _fish, 'רוטב דגים', _likely),
      ('מרק מיסו', _fish, 'מרק מיסו', _suspected),
      ('Surimi roll', _crust, 'surimi', _suspected),
      ('Shrimp paste', _crust, 'shrimp paste', _suspected),
      ('Red curry paste', _crust, 'curry paste', _suspected),
      ('Seafood paella', _crust, 'paella', _suspected),
      ('Fish stock', _crust, 'fish stock', _suspected),
      ('חריימה', _crust, 'חריימה', _suspected),
      ('Oyster sauce stir fry', _moll, 'oyster sauce', _likely),
      ('XO sauce noodles', _moll, 'xo sauce', _likely),
      ('Fish sauce marinade', _moll, 'fish sauce', _suspected),
      ('רוטב צדפות', _moll, 'רוטב צדפות', _likely),
      ('נודלס ברוטב XO', _moll, 'רוטב xo', _likely),
    ];
    for (final (text, id, term, certainty) in cases) {
      test('$text gives ${id.name} "$term" (${certainty.name})', () {
        expect(_certaintyOf(text, id, term), certainty);
      });
    }

    test(
      'an oyster sauce is a mollusc hit twice over, at both certainties',
      () {
        expect(_certaintyOf('Oyster sauce', _moll, 'oyster'), _stated);
        expect(_certaintyOf('Oyster sauce', _moll, 'oyster sauce'), _likely);
      },
    );
  });

  group('guards', () {
    const lowered = <(String, RestrictionId, String)>[
      ('Fish-free batter', _fish, 'fish'),
      ('No fish', _fish, 'fish'),
      ('Cooked without anchovy', _fish, 'anchovy'),
      ('Vegan Caesar', _fish, 'caesar'),
      ('Vegan fish sauce', _fish, 'fish'),
      ('Vegan fish sauce', _fish, 'fish sauce'),
      ('ללא דגים', _fish, 'דגים'),
      ('בלי סלמון', _fish, 'סלמון'),
      ('רוטב דגים טבעוני', _fish, 'דגים'),
      ('Shrimp-free dressing', _crust, 'shrimp'),
      ('No shrimp', _crust, 'shrimp'),
      ('Vegan shrimp', _crust, 'shrimp'),
      ('Kosher seafood', _crust, 'seafood'),
      ('Kosher seafood', _moll, 'seafood'),
      ('Seafood, kosher', _crust, 'seafood'),
      ('מסעדת פירות ים כשרה', _crust, 'פירות ים'),
      ('מסעדת פירות ים כשרה', _moll, 'פירות ים'),
      ('כשר פירות ים', _crust, 'פירות ים'),
      ('ללא פירות ים', _moll, 'פירות ים'),
      ('ללא שרימפס', _crust, 'שרימפס'),
      ('Oyster mushroom risotto', _moll, 'oyster'),
      ('Grilled oyster mushrooms', _moll, 'oyster'),
      ('No calamari', _moll, 'calamari'),
      ('Calamari-free', _moll, 'calamari'),
      ('Crab apple jelly', _crust, 'crab'),
    ];
    for (final (text, id, term) in lowered) {
      test('$text: ${id.name} lowers "$term"', () {
        final hits = _hits(text, id).where((hit) => hit.term == term);
        expect(_lowered(hits.toList()), isTrue, reason: '$hits');
      });
    }

    test('kosher lowers shellfish but never fish', () {
      expect(_certaintyOf('Kosher salmon', _fish, 'salmon'), _stated);
      expect(_certaintyOf('סלמון כשר', _fish, 'סלמון'), _stated);
      expect(_certaintyOf('Kosher fish and chips', _fish, 'fish'), _stated);
      expect(_lowered(_hits('Kosher shrimp', _crust)), isTrue);
      expect(_lowered(_hits('שרימפס כשר', _crust)), isTrue);
      expect(_lowered(_hits('קלמרי כשר', _moll)), isTrue);
    });

    test('vegetarian is a weak guard: Worcestershire still hits', () {
      expect(
        _certaintyOf('Vegetarian Worcestershire', _fish, 'worcestershire'),
        _likely,
      );
      expect(_hits('Vegetarian and fish options', _fish), isNotEmpty);
      expect(
        _certaintyOf('Vegetarian oyster sauce', _moll, 'oyster sauce'),
        _likely,
      );
    });

    test('a guard never reaches past two words', () {
      expect(
        _certaintyOf('No sauces or sides, just fish', _fish, 'fish'),
        _stated,
      );
      expect(
        _certaintyOf('Kosher kitchen, daily special: shrimp', _crust, 'shrimp'),
        _stated,
      );
    });

    test('a mushroom beside oyster sauce does not hide the oyster sauce', () {
      expect(
        _certaintyOf('Beef in oyster sauce with mushrooms', _moll, 'oyster'),
        _stated,
      );
    });
  });

  group('confusions produce no hit', () {
    const texts = <(String, RestrictionId)>[
      ('פטריות צדפה בגריל', _moll),
      ('פטריית צדפה', _moll),
      ('Crabapple jelly', _crust),
      ('Jellyfish salad', _fish),
      ('Starfish cookie', _fish),
      ('Selfish', _fish),
      ('Crayfish bisque', _fish),
      ('Swordfish steak', _crust),
      ('Salmon fillet', _crust),
      ('Salmon fillet', _moll),
      ('סלט ירקות', _fish),
      ('חומוס עם טחינה', _fish),
      ('שניצל עוף', _crust),
    ];
    for (final (text, id) in texts) {
      test('"$text" has no ${id.name} hit', () {
        expect(_hits(text, id), isEmpty);
      });
    }

    // A compound a term guard disarms, or a guarded word, is lowered and
    // never dropped (ALG-04a).
    for (final (text, id) in const <(String, RestrictionId)>[
      ('Oyster mushroom salad', _moll),
      ('King oyster mushrooms', _moll),
      ('Crab apple chutney', _crust),
      ('Fish-free', _fish),
    ]) {
      test('"$text" has its ${id.name} hit lowered', () {
        expect(_lowered(_hits(text, id)), isTrue);
      });
    }

    test('the word fish inside a compound is not a fish hit', () {
      for (final text in <String>[
        'Jellyfish',
        'Cuttlefish',
        'Crayfish',
        'Shellfish',
        'Catfish tacos',
      ]) {
        final terms = _hits(text, _fish).map((hit) => hit.term).toList();
        expect(terms, isNot(contains('fish')), reason: text);
      }
    });
  });
}

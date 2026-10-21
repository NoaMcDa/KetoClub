// The extra diets' vocabulary (Banto, issue #342; file 11 §30, file 12
// §14): pescatarian, paleo, Whole30, AIP and Jain. Each is flexible, so a
// stated or likely hit moves the dish (the #346 rule) and a suspected one
// is only listed; the cases below pin which words are which, the guards
// that lower a look-alike, and that each diet carries the pieces it reuses.
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/utils/allergens/allergen_matcher.dart';
import 'package:ketoclub/utils/allergens/profile_evaluator.dart';
import 'package:ketoclub/utils/allergens/vocab_dairy_eggs.dart';
import 'package:ketoclub/utils/allergens/vocab_diets.dart';
import 'package:ketoclub/utils/allergens/vocab_gluten_grains.dart';
import 'package:ketoclub/utils/allergens/vocab_nuts_seeds.dart';
import 'package:ketoclub/utils/allergens/vocab_plants_additives.dart';
import 'package:ketoclub/utils/allergens/vocab_religious.dart';
import 'package:ketoclub/utils/allergens/vocabulary.dart';

const RestrictionId _pesc = RestrictionId.pescatarian;
const RestrictionId _paleo = RestrictionId.paleo;
const RestrictionId _w30 = RestrictionId.whole30;
const RestrictionId _aip = RestrictionId.aip;
const RestrictionId _jain = RestrictionId.jain;

/// The hits [AllergenMatcher.find] reports for [id] in [text], each as
/// `term:certainty`, with `:guarded` when a guard lowered it. Filtered by
/// id so other groups' vocabularies cannot change these tests.
List<String> _hits(String text, RestrictionId id) => <String>[
  for (final hit in AllergenMatcher.find(text))
    if (hit.id == id)
      '${hit.term}:${hit.certainty.name}${hit.guarded ? ':guarded' : ''}',
];

/// Expects [text] to report every one of [expected] for [id].
void _expectHits(RestrictionId id, String text, List<String> expected) {
  test('${id.name}: "$text" reports $expected', () {
    // Act
    final hits = _hits(text, id);

    // Assert
    for (final entry in expected) {
      expect(hits, contains(entry), reason: '$hits');
    }
  });
}

/// Expects [text] to report nothing at all for [id].
void _expectNone(RestrictionId id, String text) {
  test('${id.name}: "$text" reports nothing', () {
    expect(_hits(text, id), isEmpty);
  });
}

/// Every term of [id]'s vocabulary in one language, direct and hidden.
Set<String> _terms(RestrictionId id, {required bool hebrew}) {
  final vocabulary = allergenVocabulary[id]!;
  return hebrew
      ? <String>{
          ...vocabulary.directHe,
          for (final trigger in vocabulary.hiddenHe) trigger.term,
        }
      : <String>{
          ...vocabulary.directEn,
          for (final trigger in vocabulary.hiddenEn) trigger.term,
        };
}

/// [dish] evaluated as a green keto dish for a profile of [id] alone.
DishState _state(Dish dish, RestrictionId id) => ProfileEvaluator.evaluate(
  AnalysedDish(
    dishId: dish.id,
    name: dish.name,
    verdict: DishVerdict.orderAsIs,
    why: 'Fits',
  ),
  dish,
  DietaryProfile.empty.withEntry(id),
).state;

/// A dish named [name] with [description] and one removable option group.
Dish _dish(
  String name, {
  String description = '',
  List<String> options = const <String>[],
}) => Dish(
  id: 'd',
  name: name,
  description: description,
  price: 10,
  options: options.isEmpty
      ? const <DishOption>[]
      : <DishOption>[DishOption(name: 'Extras', values: options)],
);

void main() {
  group('every extra diet is offered: its vocabulary holds terms', () {
    for (final id in <RestrictionId>[_pesc, _paleo, _w30, _aip, _jain]) {
      test(id.name, () {
        expect(allergenVocabulary[id]!.isEmpty, isFalse);
      });
    }
  });

  group('the reused pieces are carried whole', () {
    test('pescatarian carries every meat and poultry word, no fish', () {
      final english = _terms(_pesc, hebrew: false);
      final hebrew = _terms(_pesc, hebrew: true);
      expect(english, containsAll(meatPoultryDirectEn));
      expect(hebrew, containsAll(meatPoultryDirectHe));
      expect(english.intersection(seaAnimalsDirectEn.toSet()), isEmpty);
      expect(hebrew.intersection(seaAnimalsDirectHe.toSet()), isEmpty);
    });

    test('paleo and AIP carry every grain, legume and milk word', () {
      for (final id in <RestrictionId>[_paleo, _aip]) {
        final english = _terms(id, hebrew: false);
        final hebrew = _terms(id, hebrew: true);
        expect(english, containsAll(wheatFoodsEn), reason: id.name);
        expect(english, containsAll(glutenGrainsEn), reason: id.name);
        expect(english, containsAll(legumesDirectEn), reason: id.name);
        expect(english, containsAll(milkWordsEn), reason: id.name);
        expect(english, containsAll(dairyFoodsEn), reason: id.name);
        expect(hebrew, containsAll(wheatFoodsHe), reason: id.name);
        expect(hebrew, containsAll(legumesDirectHe), reason: id.name);
        expect(hebrew, containsAll(milkWordsHe), reason: id.name);
      }
    });

    test('Whole30 leaves out the peas and ghee, which it allows', () {
      final english = _terms(_w30, hebrew: false);
      final hebrew = _terms(_w30, hebrew: true);
      expect(english, containsAll(pulseFoodsEn));
      expect(english, containsAll(beanFoodsEn));
      expect(english.intersection(peaFoodsEn.toSet()), isEmpty);
      expect(hebrew.intersection(peaFoodsHe.toSet()), isEmpty);
      expect(english, isNot(contains('ghee')));
      expect(hebrew, isNot(contains('סמנה')));
    });

    test('AIP carries every egg, tree-nut and sesame word', () {
      final english = _terms(_aip, hebrew: false);
      final hebrew = _terms(_aip, hebrew: true);
      expect(english, containsAll(eggsDirectEn));
      expect(english, containsAll(treeNutsDirectEn));
      expect(english, containsAll(sesameDirectEn));
      expect(hebrew, containsAll(eggsDirectHe));
      expect(hebrew, containsAll(treeNutsDirectHe));
      expect(hebrew, containsAll(sesameDirectHe));
    });

    test("Jain carries meat, fish, eggs and halal's alcohol, no dairy", () {
      final english = _terms(_jain, hebrew: false);
      final hebrew = _terms(_jain, hebrew: true);
      expect(english, containsAll(meatPoultryDirectEn));
      expect(english, containsAll(seaAnimalsDirectEn));
      expect(english, containsAll(eggsDirectEn));
      expect(english, containsAll(alcoholHiddenEn.map((t) => t.term)));
      expect(hebrew, containsAll(alcoholHiddenHe.map((t) => t.term)));
      expect(english.intersection(milkWordsEn.toSet()), isEmpty);
      expect(hebrew.intersection(milkWordsHe.toSet()), isEmpty);
    });
  });

  group('pescatarian', () {
    _expectHits(_pesc, 'Grilled chicken breast', <String>['chicken:stated']);
    _expectHits(_pesc, 'Beef shawarma', <String>[
      'beef:stated',
      'shawarma:stated',
    ]);
    _expectHits(_pesc, 'שניצל עוף', <String>['עוף:stated', 'שניצל:likely']);
    _expectHits(_pesc, 'Seared tuna steak', <String>[
      'steak:suspected:guarded',
    ]);
    _expectHits(_pesc, 'Salmon burger', <String>['burger:suspected:guarded']);
    _expectHits(_pesc, 'סטייק טונה', <String>['סטייק:suspected:guarded']);
    _expectHits(_pesc, 'קציצות דגים ברוטב', <String>[
      'קציצות:suspected:guarded',
    ]);
    _expectHits(_pesc, 'Vegetable soup with chicken stock', <String>[
      'chicken:stated',
    ]);
    _expectNone(_pesc, 'Grilled sea bass with lemon');
    _expectNone(_pesc, 'פילה סלמון על מצע ירקות');
    _expectNone(_pesc, 'Shrimp tempura');
  });

  group('paleo', () {
    _expectHits(_paleo, 'Spaghetti carbonara', <String>['spaghetti:stated']);
    _expectHits(_paleo, 'Steamed jasmine rice', <String>['rice:stated']);
    _expectHits(_paleo, 'Hummus plate', <String>['hummus:stated']);
    _expectHits(_paleo, 'Greek salad with feta', <String>['feta:stated']);
    _expectHits(_paleo, 'Chicken schnitzel', <String>['schnitzel:likely']);
    _expectHits(_paleo, 'Brown sugar glaze', <String>['sugar:suspected']);
    _expectHits(_paleo, 'Fried in canola', <String>['canola:suspected']);
    _expectHits(_paleo, 'Basmati with ghee', <String>['ghee:suspected']);
    _expectHits(_paleo, 'Cauliflower rice bowl', <String>[
      'rice:suspected:guarded',
    ]);
    _expectHits(_paleo, 'Almond flour crust', <String>[
      'flour:suspected:guarded',
    ]);
    _expectHits(_paleo, 'Curry with coconut milk', <String>[
      'milk:suspected:guarded',
    ]);
    _expectHits(_paleo, 'Grain-free granola', <String>[
      'grain:suspected:guarded',
    ]);
    _expectHits(_paleo, 'פיתה עם חומוס', <String>[
      'פיתה:stated',
      'חומוס:stated',
    ]);
    _expectHits(_paleo, 'אורז כרובית', <String>['אורז:suspected:guarded']);
    _expectHits(_paleo, 'קפה עם חלב שקדים', <String>['חלב:suspected:guarded']);
    _expectHits(_paleo, 'עוגה בלי סוכר', <String>['סוכר:suspected:guarded']);
    _expectHits(_paleo, 'Green beans with garlic', <String>[
      'beans:suspected:guarded',
    ]);
    _expectNone(_paleo, 'Honey-glazed salmon with sweet potato');
    _expectHits(_paleo, 'Steak, whole grain mustard', <String>[
      'grain:suspected:guarded',
    ]);
  });

  group('Whole30', () {
    _expectHits(_w30, 'Honey-glazed salmon', <String>['honey:stated']);
    _expectHits(_w30, 'Maple syrup', <String>['maple:stated', 'syrup:stated']);
    _expectHits(_w30, 'Beef in red wine sauce', <String>['wine:stated']);
    _expectHits(_w30, 'Corn on the cob', <String>['corn:stated']);
    _expectHits(_w30, 'Edamame', <String>['edamame:stated']);
    _expectHits(_w30, 'Lentil soup', <String>['lentil:stated']);
    _expectHits(_w30, 'Red wine vinegar dressing', <String>[
      'wine:suspected:guarded',
    ]);
    _expectHits(_w30, 'Sugar snap peas', <String>['sugar:suspected:guarded']);
    _expectHits(_w30, 'סלמון ברוטב דבש', <String>['דבש:stated']);
    _expectHits(_w30, 'רוטב ברביקיו', <String>['ברביקיו:likely']);
    _expectHits(_w30, 'בצל מקורמל', <String>['מקורמל:suspected']);
    _expectHits(_w30, 'סלט בחומץ יין', <String>['יין:suspected:guarded']);
    _expectNone(_w30, 'Split pea soup with green peas');
    _expectNone(_w30, 'Eggs fried in ghee');
    _expectNone(_w30, 'Seared in canola oil');
    _expectNone(_w30, 'מרק אפונה');
  });

  group('AIP', () {
    _expectHits(_aip, 'Tomato salad', <String>['tomato:stated']);
    _expectHits(_aip, 'Grilled eggplant', <String>['eggplant:stated']);
    _expectHits(_aip, 'Roasted peppers with paprika', <String>[
      'peppers:stated',
      'paprika:stated',
    ]);
    _expectHits(_aip, 'Poached egg', <String>['egg:stated']);
    _expectHits(_aip, 'Toasted almonds', <String>['almonds:stated']);
    _expectHits(_aip, 'Cumin-roasted carrots', <String>['cumin:stated']);
    _expectHits(_aip, 'Iced coffee', <String>['coffee:stated']);
    _expectHits(_aip, 'Dark chocolate mousse', <String>['chocolate:stated']);
    _expectHits(_aip, 'Chicken curry', <String>['curry:likely']);
    _expectHits(_aip, 'Sweet potato fries', <String>[
      'potato:suspected:guarded',
      'fries:suspected:guarded',
    ]);
    _expectHits(_aip, 'עגבניות שרי', <String>['עגבניות:stated']);
    _expectHits(_aip, 'פלפל שחור גרוס', <String>['פלפל:suspected:guarded']);
    _expectHits(_aip, 'מלח ופלפל', <String>['פלפל:suspected:guarded']);
    _expectHits(_aip, 'שקשוקה', <String>['שקשוקה:stated']);
    _expectHits(_aip, 'קפה שחור', <String>['קפה:stated']);
    _expectNone(_aip, 'Roast chicken with black pepper');
    _expectNone(_aip, 'בטטה צלויה');
  });

  group('Jain', () {
    _expectHits(_jain, 'Onion bhaji', <String>['onion:stated']);
    _expectHits(_jain, 'Garlic naan', <String>['garlic:stated']);
    _expectHits(_jain, 'Aloo gobi', <String>['aloo:stated']);
    _expectHits(_jain, 'Carrot and ginger soup', <String>[
      'carrot:stated',
      'ginger:stated',
    ]);
    _expectHits(_jain, 'Beetroot salad', <String>['beetroot:stated']);
    _expectHits(_jain, 'Masala omelette', <String>['omelette:stated']);
    _expectHits(_jain, 'Honey cake', <String>['honey:stated']);
    _expectHits(_jain, 'Fish curry', <String>['fish:stated']);
    _expectHits(_jain, 'Penne with white wine', <String>['wine:likely']);
    _expectHits(_jain, 'Mushroom risotto', <String>['mushroom:suspected']);
    _expectHits(_jain, 'Vegan sausage roll', <String>[
      'sausage:suspected:guarded',
    ]);
    _expectHits(_jain, 'סלט סלק וגזר', <String>['סלק:stated', 'גזר:stated']);
    _expectHits(_jain, 'פירה תפוחי אדמה', <String>['תפוחי אדמה:stated']);
    _expectHits(_jain, 'רוטב שום', <String>['שום:stated']);
    _expectHits(_jain, 'ברוטב יין לבן', <String>['יין:likely']);
    _expectHits(_jain, 'עוגת דבש', <String>['דבש:stated']);
    _expectHits(_jain, 'ממרח דבש תמרים', <String>['דבש:suspected:guarded']);
    _expectHits(_jain, 'אין שום תוספות', <String>['שום:suspected:guarded']);
    _expectNone(_jain, 'Paneer tikka with mint chutney');
    _expectNone(_jain, 'פסטה ברוטב שמנת וגבינה');
    _expectNone(_jain, 'משום שזה טעים');
  });

  group('the #346 rule: flexible, so stated and likely move the dish', () {
    test('a stated grain in the dish is avoid for paleo', () {
      expect(_state(_dish('Pasta al pomodoro'), _paleo), DishState.avoid);
    });

    test('a suspected refined sugar moves nothing for paleo', () {
      expect(
        _state(_dish('Grilled fish, sugar glaze'), _paleo),
        isNot(DishState.avoid),
      );
    });

    test('onion in a removable option is a change for Jain', () {
      expect(
        _state(_dish('Paneer salad', options: <String>['Add onion']), _jain),
        DishState.fitsWithChange,
      );
    });

    test('a fish dish fits a pescatarian', () {
      expect(_state(_dish('Grilled salmon'), _pesc), DishState.fits);
    });
  });
}

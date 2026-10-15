/// Trip mode's local hidden-ingredient lexicons (Banto; the Allergens epic,
/// ALG-13, issue #355).
///
/// Per [TripDestination], a small list of the dishes and ingredients that
/// hide a restriction there without naming it: soba is often part wheat,
/// dashi is fish stock, a French pastry may hold lupin flour, a German
/// roulade is spread with mustard. Each [TripLexiconEntry] cites the
/// allergen documentation section it comes from (file 11 or 12); the
/// country sections of file 12 §8 are **unreviewed desk research**, and
/// their wording must be checked in a browser before it ships.
///
/// Two readers:
///
/// - **The evaluator**, while a trip is active: [TripLexicon.withTrip]
///   adds the destination's terms to the on-device pass that already reads
///   the user's own words (`ProfileEvaluator`, ALG-17), every one a
///   [TriggerCertainty.suspected] hidden trigger. A suspected finding on a
///   strict entry makes a dish "ask"; on a flexible one it is listed and
///   moves nothing. Nothing here reaches a request, the server, the model
///   or a golden (D26 C1): the destination stays on the device like the
///   profile.
/// - **The pre-trip briefing page** (`TripBriefingScreen`), which lists the
///   entries that hide something in the profile ([TripLexicon.briefing]).
///
/// The terms are written as a menu at the destination prints them, in
/// Latin script (romanised Japanese, as tourist menus print it) or, for
/// Israel, Hebrew too: the matcher's Latin pattern uses the ASCII word
/// boundary, which never matches inside kana or kanji, so Japanese script
/// would be dead weight. Accents fold (`TextNormaliser`), so "béarnaise"
/// and "bearnaise" are one term; `ß` does not fold, so no term uses it.
///
/// The glosses are bilingual in Dart beside their citation, like the
/// taxonomy's display names, so one review covers the fact and its wording;
/// they are reference content for the briefing, not interface chrome.
library;

import 'package:flutter/foundation.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/models/trip_destination.dart';
import 'package:ketoclub/utils/allergens/allergen_matcher.dart';
import 'package:ketoclub/utils/allergens/vocabulary.dart';
import 'package:ketoclub/utils/text_normaliser.dart';

/// One dish or ingredient that hides a restriction at a destination.
@immutable
final class TripLexiconEntry {
  /// Creates the entry for [terms], hiding [hides].
  const new({
    required this.terms,
    required this.hides,
    required this.glossEn,
    required this.glossHe,
    required this.source,
  });

  /// The word as a menu there prints it, then its other spellings; the
  /// first is the one the briefing shows.
  final List<String> terms;

  /// The restrictions the sources say it may hide.
  final List<RestrictionId> hides;

  /// What it is and where the restriction hides, in English.
  final String glossEn;

  /// The same in Hebrew.
  final String glossHe;

  /// Where the entry comes from: `"12 §8.2"` is file 12, section 8.2.
  final String source;

  /// [hides] with what follows from it by definition, in taxonomy order:
  /// fish, shellfish and mammal meat are not vegetarian; those and milk and
  /// eggs are not vegan; milk may carry lactose. What the evaluator and
  /// the briefing read.
  List<RestrictionId> get restrictions {
    final ids = <RestrictionId>{...hides};
    const animal = <RestrictionId>{
      RestrictionId.fish,
      RestrictionId.crustaceans,
      RestrictionId.molluscs,
      RestrictionId.alphaGal,
    };
    if (hides.any(animal.contains)) {
      ids
        ..add(RestrictionId.vegetarian)
        ..add(RestrictionId.vegan);
    }
    if (hides.contains(RestrictionId.milk) ||
        hides.contains(RestrictionId.eggs)) {
      ids.add(RestrictionId.vegan);
    }
    if (hides.contains(RestrictionId.milk)) ids.add(RestrictionId.lactose);
    return List<RestrictionId>.unmodifiable(
      ids.toList()..sort((a, b) => a.index.compareTo(b.index)),
    );
  }

  @override
  String toString() => 'TripLexiconEntry(${terms.first})';
}

// Short names for the lists below, so each entry fits one reviewable line.
const RestrictionId _peanuts = RestrictionId.peanuts;
const RestrictionId _treeNuts = RestrictionId.treeNuts;
const RestrictionId _milk = RestrictionId.milk;
const RestrictionId _eggs = RestrictionId.eggs;
const RestrictionId _soy = RestrictionId.soy;
const RestrictionId _wheat = RestrictionId.wheat;
const RestrictionId _gluten = RestrictionId.gluten;
const RestrictionId _fish = RestrictionId.fish;
const RestrictionId _crustaceans = RestrictionId.crustaceans;
const RestrictionId _molluscs = RestrictionId.molluscs;
const RestrictionId _sesame = RestrictionId.sesame;
const RestrictionId _celery = RestrictionId.celery;
const RestrictionId _mustard = RestrictionId.mustard;
const RestrictionId _lupin = RestrictionId.lupin;
const RestrictionId _sulphites = RestrictionId.sulphites;
const RestrictionId _legumes = RestrictionId.legumes;
const RestrictionId _alphaGal = RestrictionId.alphaGal;

/// Israel: the dishes a tourist menu prints in transliteration, and a few
/// Hebrew words the base vocabulary reads otherwise (file 12 §1).
const List<TripLexiconEntry> _israel = <TripLexiconEntry>[
  TripLexiconEntry(
    terms: <String>['sabich', 'sabih', 'סביח'],
    hides: <RestrictionId>[_eggs, _sesame, _legumes],
    glossEn:
        'Fried aubergine in pita with hard-boiled egg, tahini and '
        'often hummus.',
    glossHe: 'חציל מטוגן בפיתה עם ביצה קשה, טחינה ולעיתים חומוס.',
    source: '12 §1.1',
  ),
  TripLexiconEntry(
    terms: <String>['bourekas', 'burekas', 'borekas'],
    hides: <RestrictionId>[_wheat, _gluten, _sesame, _eggs, _milk],
    glossEn:
        'Pastry brushed with egg and topped with sesame; cheese '
        'fillings are common.',
    glossHe: 'מאפה מוברש בביצה ומפוזר בשומשום; מילוי גבינה נפוץ.',
    source: '12 §1.1',
  ),
  TripLexiconEntry(
    terms: <String>['jachnun', 'jahnun'],
    hides: <RestrictionId>[_wheat, _gluten, _milk],
    glossEn:
        'Yemenite wheat pastry, made with butter, samneh or '
        'margarine — the menu seldom says which.',
    glossHe:
        'מאפה תימני מקמח חיטה, עם חמאה, סמנה או מרגרינה — התפריט '
        'כמעט אף פעם לא אומר.',
    source: '12 §1.4',
  ),
  TripLexiconEntry(
    terms: <String>['malawach', 'malawah', 'melawach'],
    hides: <RestrictionId>[_wheat, _gluten, _milk],
    glossEn: 'Yemenite fried wheat pastry, made with butter or margarine.',
    glossHe: 'מאפה תימני מטוגן מקמח חיטה, עם חמאה או מרגרינה.',
    source: '12 §1.4',
  ),
  TripLexiconEntry(
    terms: <String>['kubbeh', 'kubbe', 'kibbeh'],
    hides: <RestrictionId>[_wheat, _gluten],
    glossEn: 'Dumplings with a semolina or bulgur shell.',
    glossHe: 'כופתאות במעטפת סולת או בורגול.',
    source: '12 §1.4',
  ),
  TripLexiconEntry(
    terms: <String>['ptitim', 'Israeli couscous'],
    hides: <RestrictionId>[_wheat, _gluten],
    glossEn: 'Toasted wheat pasta (a rice version exists).',
    glossHe: 'פתיתים: פסטה קלויה מחיטה (יש גם גרסת אורז).',
    source: '12 §1.4',
  ),
  TripLexiconEntry(
    terms: <String>['halva', 'halvah', 'halawa'],
    hides: <RestrictionId>[_sesame],
    glossEn: 'A sesame sweet — not dairy, despite the Hebrew spelling.',
    glossHe: 'חלבה: ממתק שומשום — לא מוצר חלב.',
    source: '12 §1.1',
  ),
  TripLexiconEntry(
    terms: <String>['Bamba'],
    hides: <RestrictionId>[_peanuts, _soy],
    glossEn: 'Peanut puffs: classic Bamba is about half ground peanuts.',
    glossHe: 'במבה: חטיף בוטנים, כמחציתו בוטנים טחונים.',
    source: '12 §1.2',
  ),
  TripLexiconEntry(
    terms: <String>['hilbeh', 'hilbe', 'חילבה'],
    hides: <RestrictionId>[_legumes],
    glossEn:
        'Fenugreek relish served with Yemenite pastries and soup; '
        'fenugreek is a legume.',
    glossHe:
        'ממרח גרגרי חילבה שמוגש עם מאפים תימניים ומרק; חילבה היא '
        'קטנית.',
    source: '12 §1.3',
  ),
  TripLexiconEntry(
    terms: <String>['falafel'],
    hides: <RestrictionId>[_legumes, _sesame],
    glossEn: 'Chickpea or fava balls; many batters hold sesame.',
    glossHe: 'כדורי חומוס או פול; בבלילות רבות יש שומשום.',
    source: '12 §1.3',
  ),
  TripLexiconEntry(
    terms: <String>['shakshuka', 'shakshouka'],
    hides: <RestrictionId>[_eggs],
    glossEn: 'Eggs poached in tomato sauce.',
    glossHe: 'ביצים ברוטב עגבניות.',
    source: '12 §1.6',
  ),
  TripLexiconEntry(
    terms: <String>['chraime', 'חריימה'],
    hides: <RestrictionId>[_fish, _crustaceans, _molluscs],
    glossEn: 'Fish in a spicy red sauce; seafood versions exist.',
    glossHe: 'דג ברוטב אדום חריף; יש גם גרסת פירות ים.',
    source: '12 §1.7',
  ),
  TripLexiconEntry(
    terms: <String>['שקדי מרק', 'soup almonds'],
    hides: <RestrictionId>[_wheat, _gluten],
    glossEn: 'Soup croutons made of wheat, despite the "almond" name.',
    glossHe: 'קרוטונים מחיטה, למרות השם "שקדים".',
    source: '12 §1.4',
  ),
];

/// The United States: cuisine-specific hides (file 12 §5).
const List<TripLexiconEntry> _unitedStates = <TripLexiconEntry>[
  TripLexiconEntry(
    terms: <String>['mole', 'mole poblano'],
    hides: <RestrictionId>[_peanuts, _treeNuts, _sesame],
    glossEn: 'Mexican sauce often thickened with peanuts, nuts or sesame.',
    glossHe:
        'רוטב מקסיקני שמסמיכים לעיתים קרובות בבוטנים, אגוזים או '
        'שומשום.',
    source: '12 §5',
  ),
  TripLexiconEntry(
    terms: <String>['enchilada', 'enchiladas'],
    hides: <RestrictionId>[_peanuts],
    glossEn: 'Enchilada sauce is named as a peanut hider.',
    glossHe: "רוטב אנצ'ילדה מוזכר כמקום שבוטנים מסתתרים בו.",
    source: '12 §5',
  ),
  TripLexiconEntry(
    terms: <String>['egg roll', 'egg rolls'],
    hides: <RestrictionId>[_peanuts, _wheat, _gluten, _eggs],
    glossEn: 'Fried wheat rolls; peanut butter in the filling is reported.',
    glossHe: 'גלילות בצק חיטה מטוגנות; דווח על חמאת בוטנים במילוי.',
    source: '12 §5',
  ),
  TripLexiconEntry(
    terms: <String>['lo mein'],
    hides: <RestrictionId>[_peanuts, _wheat, _gluten, _eggs, _soy],
    glossEn:
        'Egg-wheat noodles in a soy-based sauce; peanuts are common '
        'in the kitchen.',
    glossHe: 'אטריות ביצים מחיטה ברוטב על בסיס סויה; בוטנים נפוצים במטבח.',
    source: '12 §5',
  ),
  TripLexiconEntry(
    terms: <String>['pad thai'],
    hides: <RestrictionId>[_peanuts, _fish, _eggs, _sesame],
    glossEn:
        'Rice noodles with peanuts, fish sauce and egg; sesame oil is '
        'reported.',
    glossHe:
        'אטריות אורז עם בוטנים, רוטב דגים וביצה; דווח גם על שמן '
        'שומשום.',
    source: '12 §5',
  ),
  TripLexiconEntry(
    terms: <String>['spicy tuna'],
    hides: <RestrictionId>[_sesame],
    glossEn: 'Sushi filling often mixed with sesame oil.',
    glossHe: 'מילוי סושי שמערבבים לעיתים קרובות בשמן שומשום.',
    source: '12 §5',
  ),
  TripLexiconEntry(
    terms: <String>['hoisin'],
    hides: <RestrictionId>[_soy, _wheat, _gluten, _sesame],
    glossEn: 'Sweet soy-based sauce with wheat and sesame.',
    glossHe: 'רוטב מתוק על בסיס סויה, עם חיטה ושומשום.',
    source: '12 §5',
  ),
  TripLexiconEntry(
    terms: <String>['refried beans'],
    hides: <RestrictionId>[_alphaGal],
    glossEn: 'Often cooked with lard (pork fat).',
    glossHe: 'מבושלות לעיתים קרובות עם שומן חזיר.',
    source: '12 §5',
  ),
  TripLexiconEntry(
    terms: <String>['flour tortilla', 'burrito', 'quesadilla', 'soft taco'],
    hides: <RestrictionId>[_wheat, _gluten],
    glossEn: 'Wheat tortillas; corn ones may share the griddle.',
    glossHe: "טורטיות חיטה; גם טורטיות תירס עשויות לחלוק את הפלנצ'ה.",
    source: '12 §5',
  ),
  TripLexiconEntry(
    terms: <String>['fried chicken', 'buttermilk'],
    hides: <RestrictionId>[_milk, _wheat, _gluten],
    glossEn: 'Chicken brined in buttermilk and coated in flour.',
    glossHe: 'עוף שהושרה בחלב חמוץ (באטרמילק) וצופה בקמח.',
    source: '12 §5',
  ),
  TripLexiconEntry(
    terms: <String>['omelet', 'omelette'],
    hides: <RestrictionId>[_wheat, _gluten],
    glossEn: 'Some diners add pancake batter to omelets.',
    glossHe: 'יש מסעדות שמוסיפות בלילת פנקייק לחביתה.',
    source: '11 §7.2',
  ),
  TripLexiconEntry(
    terms: <String>['elote'],
    hides: <RestrictionId>[_milk],
    glossEn: 'Grilled corn with crema and cheese.',
    glossHe: 'תירס צלוי עם שמנת וגבינה.',
    source: '12 §5',
  ),
  TripLexiconEntry(
    terms: <String>['Caesar'],
    hides: <RestrictionId>[_fish, _eggs, _milk, _mustard],
    glossEn: 'Caesar dressing: anchovy, egg, cheese and often mustard.',
    glossHe: 'רוטב קיסר: אנשובי, ביצה, גבינה ולעיתים קרובות חרדל.',
    source: '12 §5',
  ),
];

/// The United Kingdom (file 12 §8.7; file 11).
const List<TripLexiconEntry> _unitedKingdom = <TripLexiconEntry>[
  TripLexiconEntry(
    terms: <String>['Yorkshire pudding'],
    hides: <RestrictionId>[_wheat, _gluten, _eggs, _milk],
    glossEn: 'A baked batter of flour, egg and milk, served with roasts.',
    glossHe: 'בלילה אפויה מקמח, ביצים וחלב, שמוגשת עם צלי.',
    source: '12 §8.7',
  ),
  TripLexiconEntry(
    terms: <String>['gravy'],
    hides: <RestrictionId>[_wheat, _gluten, _celery],
    glossEn: 'Meat sauce thickened with flour; gravy granules hold celery.',
    glossHe: 'רוטב בשר שמסמיכים בקמח; באבקות רוטב יש סלרי.',
    source: '11 §12.2',
  ),
  TripLexiconEntry(
    terms: <String>['brown sauce'],
    hides: <RestrictionId>[_gluten],
    glossEn: 'A table sauce made with malt (barley) vinegar.',
    glossHe: 'רוטב שולחן עם חומץ לתת (שעורה).',
    source: '11 §7.2',
  ),
  TripLexiconEntry(
    terms: <String>['Worcester sauce', 'Worcestershire'],
    hides: <RestrictionId>[_fish],
    glossEn:
        'Contains anchovy; it goes into many sauces and cheese on '
        'toast.',
    glossHe: 'מכיל אנשובי; נכנס לרטבים רבים ולגבינה על טוסט.',
    source: '11 §8.2',
  ),
  TripLexiconEntry(
    terms: <String>['Scotch egg'],
    hides: <RestrictionId>[_eggs, _wheat, _gluten],
    glossEn: 'Egg wrapped in sausage meat and breadcrumbs.',
    glossHe: 'ביצה עטופה בבשר נקניק ובפירורי לחם.',
    source: '12 §8.7',
  ),
  TripLexiconEntry(
    terms: <String>['piccalilli'],
    hides: <RestrictionId>[_mustard],
    glossEn: 'A mustard pickle.',
    glossHe: 'חמוצים ברוטב חרדל.',
    source: '11 §13.1',
  ),
  TripLexiconEntry(
    terms: <String>['coronation chicken'],
    hides: <RestrictionId>[_eggs, _mustard],
    glossEn: 'Chicken in curried mayonnaise; curry powder may hold mustard.',
    glossHe: 'עוף במיונז קארי; באבקת קארי עשוי להיות חרדל.',
    source: '12 §8.7',
  ),
  TripLexiconEntry(
    terms: <String>['Bakewell'],
    hides: <RestrictionId>[_treeNuts, _wheat, _gluten, _eggs],
    glossEn: 'A tart with an almond frangipane filling.',
    glossHe: "טארט במילוי קרם שקדים (פרנז'יפן).",
    source: '12 §8.7',
  ),
  TripLexiconEntry(
    terms: <String>['haggis'],
    hides: <RestrictionId>[_gluten, _alphaGal],
    glossEn: 'Sheep offal with oatmeal.',
    glossHe: 'פנימיות כבש עם שיבולת שועל.',
    source: '12 §8.7',
  ),
  TripLexiconEntry(
    terms: <String>['Marmite'],
    hides: <RestrictionId>[_celery, _gluten],
    glossEn: "A yeast-extract spread made from brewer's yeast.",
    glossHe: 'ממרח תמצית שמרים, משמרי בירה.',
    source: '11 §12.2',
  ),
  TripLexiconEntry(
    terms: <String>['Welsh rarebit'],
    hides: <RestrictionId>[_milk, _wheat, _gluten, _mustard, _fish],
    glossEn:
        'Cheese sauce on toast, often with mustard and Worcestershire '
        'sauce.',
    glossHe: 'רוטב גבינה על טוסט, לרוב עם חרדל ורוטב ווסטרשייר.',
    source: '12 §8.7',
  ),
  TripLexiconEntry(
    terms: <String>['stuffing'],
    hides: <RestrictionId>[_wheat, _gluten, _celery],
    glossEn: 'Breadcrumb stuffing, often with celery or stock.',
    glossHe: 'מלית פירורי לחם, לעיתים קרובות עם סלרי או ציר.',
    source: '12 §8.7',
  ),
  TripLexiconEntry(
    terms: <String>["ploughman's"],
    hides: <RestrictionId>[_milk, _wheat, _gluten, _mustard],
    glossEn: 'Cheese, bread and pickle; the pickle may hold mustard.',
    glossHe: 'גבינה, לחם וחמוצים; בחמוצים עשוי להיות חרדל.',
    source: '12 §8.7',
  ),
];

/// France (file 12 §8.3; file 11).
const List<TripLexiconEntry> _france = <TripLexiconEntry>[
  TripLexiconEntry(
    terms: <String>['farine de lupin', 'lupin'],
    hides: <RestrictionId>[_lupin],
    glossEn: 'Lupin flour, used in breads, pastry and gluten-free baking.',
    glossHe: 'קמח תורמוס, בלחמים, במאפים ובאפייה ללא גלוטן.',
    source: '11 §14.2',
  ),
  TripLexiconEntry(
    terms: <String>['viennoiserie', 'viennoiseries', 'pain au chocolat'],
    hides: <RestrictionId>[_wheat, _gluten, _lupin, _milk, _eggs],
    glossEn:
        'Bakery pastries: butter, egg glaze, and lupin flour in some '
        'doughs.',
    glossHe: 'מאפי בוקר: חמאה, הברשת ביצה, ובחלק מהבצקים קמח תורמוס.',
    source: '12 §8.3',
  ),
  TripLexiconEntry(
    terms: <String>['moutarde', 'Dijon'],
    hides: <RestrictionId>[_mustard],
    glossEn: 'Mustard: in vinaigrettes, sauces and meat glazes.',
    glossHe: 'חרדל: בוויניגרטים, ברטבים ובזיגוג בשר.',
    source: '12 §8.3',
  ),
  TripLexiconEntry(
    terms: <String>['vinaigrette'],
    hides: <RestrictionId>[_mustard],
    glossEn: 'French dressing, usually made with Dijon mustard.',
    glossHe: "רוטב צרפתי, בדרך כלל עם חרדל דיז'ון.",
    source: '11 §13.1',
  ),
  TripLexiconEntry(
    terms: <String>['béarnaise'],
    hides: <RestrictionId>[_eggs, _milk],
    glossEn: 'Egg-yolk and butter sauce.',
    glossHe: 'רוטב חלמונים וחמאה.',
    source: '12 §8.3',
  ),
  TripLexiconEntry(
    terms: <String>['hollandaise'],
    hides: <RestrictionId>[_eggs, _milk],
    glossEn: 'Egg-yolk and butter sauce, lightly cooked.',
    glossHe: 'רוטב חלמונים וחמאה, מבושל קלות.',
    source: '11 §5.2',
  ),
  TripLexiconEntry(
    terms: <String>['beurre blanc'],
    hides: <RestrictionId>[_milk, _sulphites],
    glossEn: 'Butter sauce reduced with wine.',
    glossHe: 'רוטב חמאה מצומצם ביין.',
    source: '12 §8.3',
  ),
  TripLexiconEntry(
    terms: <String>['rémoulade'],
    hides: <RestrictionId>[_mustard, _eggs],
    glossEn: 'Mayonnaise with mustard, served with celeriac or fish.',
    glossHe: 'מיונז עם חרדל, שמוגש עם סלרי שורש או דגים.',
    source: '12 §8.3',
  ),
  TripLexiconEntry(
    terms: <String>['aïoli'],
    hides: <RestrictionId>[_eggs],
    glossEn: 'Garlic mayonnaise.',
    glossHe: 'מיונז שום.',
    source: '11 §5.1',
  ),
  TripLexiconEntry(
    terms: <String>['rouille'],
    hides: <RestrictionId>[_eggs, _wheat, _gluten, _fish],
    glossEn:
        'Garlic-saffron sauce thickened with egg or bread, served with '
        'fish soup.',
    glossHe: 'רוטב שום וזעפרן שמסמיכים בביצה או בלחם, מוגש עם מרק דגים.',
    source: '12 §8.3',
  ),
  TripLexiconEntry(
    terms: <String>['bouillabaisse'],
    hides: <RestrictionId>[_fish, _crustaceans, _molluscs, _celery],
    glossEn: 'Provençal fish stew, often with shellfish.',
    glossHe: 'תבשיל דגים פרובנסלי, לעיתים קרובות עם פירות ים.',
    source: '11 §8.1',
  ),
  TripLexiconEntry(
    terms: <String>['bouillon', 'fond de veau', 'fumet'],
    hides: <RestrictionId>[_celery],
    glossEn: 'Stocks and bouillons commonly hold celery.',
    glossHe: 'בציר ובמרק בסיס יש לעיתים קרובות סלרי.',
    source: '11 §12.2',
  ),
  TripLexiconEntry(
    terms: <String>['frangipane'],
    hides: <RestrictionId>[_treeNuts],
    glossEn: 'Almond cream, in tarts and the galette des rois.',
    glossHe: 'קרם שקדים, בטארטים ובגלט דה רואה.',
    source: '11 §2.1',
  ),
  TripLexiconEntry(
    terms: <String>['praliné'],
    hides: <RestrictionId>[_treeNuts],
    glossEn: 'Caramelised hazelnut or almond paste.',
    glossHe: 'ממרח אגוזי לוז או שקדים מקורמלים.',
    source: '11 §2.2',
  ),
  TripLexiconEntry(
    terms: <String>['financier', 'financiers'],
    hides: <RestrictionId>[_treeNuts, _milk, _eggs, _wheat, _gluten],
    glossEn: 'Small almond-flour cakes made with brown butter.',
    glossHe: 'עוגיות קמח שקדים עם חמאה חומה.',
    source: '12 §8.3',
  ),
  TripLexiconEntry(
    terms: <String>['croque monsieur', 'croque madame'],
    hides: <RestrictionId>[_wheat, _gluten, _milk, _eggs],
    glossEn: 'Toasted ham sandwich with cheese and béchamel.',
    glossHe: 'כריך חם עם נקניק, גבינה ורוטב בשמל.',
    source: '12 §8.3',
  ),
  TripLexiconEntry(
    terms: <String>['gratin', 'dauphinois'],
    hides: <RestrictionId>[_milk],
    glossEn: 'Baked in cream, milk or cheese.',
    glossHe: 'אפוי בשמנת, בחלב או בגבינה.',
    source: '12 §8.3',
  ),
  TripLexiconEntry(
    terms: <String>['au vin'],
    hides: <RestrictionId>[_sulphites],
    glossEn: 'Cooked in wine, which commonly carries sulphites.',
    glossHe: 'מבושל ביין, שבדרך כלל יש בו סולפיטים.',
    source: '11 §15.2',
  ),
];

/// Italy (file 12 §5, §8.4; file 11).
const List<TripLexiconEntry> _italy = <TripLexiconEntry>[
  TripLexiconEntry(
    terms: <String>['pesto', 'genovese'],
    hides: <RestrictionId>[_treeNuts, _milk],
    glossEn: 'Basil sauce with pine nuts and Parmesan.',
    glossHe: 'רוטב בזיליקום עם צנוברים ופרמזן.',
    source: '12 §5',
  ),
  TripLexiconEntry(
    terms: <String>['trapanese'],
    hides: <RestrictionId>[_treeNuts],
    glossEn: 'Sicilian pesto made with almonds.',
    glossHe: 'פסטו סיציליאני עם שקדים.',
    source: '12 §5',
  ),
  TripLexiconEntry(
    terms: <String>['mortadella'],
    hides: <RestrictionId>[_treeNuts],
    glossEn: 'Cold cut often studded with pistachio.',
    glossHe: 'נקניק שמשובצים בו לעיתים קרובות פיסטוקים.',
    source: '12 §5',
  ),
  TripLexiconEntry(
    terms: <String>['cannoli', 'cannolo'],
    hides: <RestrictionId>[_milk, _wheat, _gluten, _treeNuts],
    glossEn: 'Fried wheat shells with ricotta, often with pistachio.',
    glossHe: 'גלילי בצק מטוגנים עם ריקוטה, לעיתים קרובות עם פיסטוק.',
    source: '12 §5',
  ),
  TripLexiconEntry(
    terms: <String>['puttanesca'],
    hides: <RestrictionId>[_fish],
    glossEn: 'Tomato sauce with anchovies.',
    glossHe: 'רוטב עגבניות עם אנשובי.',
    source: '12 §5',
  ),
  TripLexiconEntry(
    terms: <String>['polpette'],
    hides: <RestrictionId>[_wheat, _gluten, _eggs, _milk],
    glossEn: 'Meatballs bound with breadcrumbs, egg and often cheese.',
    glossHe: 'קציצות עם פירורי לחם, ביצה ולעיתים קרובות גבינה.',
    source: '12 §5',
  ),
  TripLexiconEntry(
    terms: <String>['bagna cauda'],
    hides: <RestrictionId>[_fish, _milk],
    glossEn: 'Warm anchovy and garlic dip, often with butter.',
    glossHe: 'מטבל חם של אנשובי ושום, לעיתים קרובות עם חמאה.',
    source: '12 §8.4',
  ),
  TripLexiconEntry(
    terms: <String>['tonnato'],
    hides: <RestrictionId>[_fish, _eggs],
    glossEn: 'Tuna mayonnaise sauce, as on vitello tonnato.',
    glossHe: 'רוטב מיונז טונה, כמו בוויטלו טונאטו.',
    source: '12 §8.4',
  ),
  TripLexiconEntry(
    terms: <String>['amaretti', 'amaretto'],
    hides: <RestrictionId>[_treeNuts],
    glossEn: 'Almond or apricot-kernel biscuits and liqueur.',
    glossHe: 'עוגיות וליקר משקדים או מגלעיני משמש.',
    source: '12 §8.4',
  ),
  TripLexiconEntry(
    terms: <String>['torrone'],
    hides: <RestrictionId>[_treeNuts, _eggs],
    glossEn: 'Nougat with almonds or hazelnuts and egg white.',
    glossHe: 'נוגט עם שקדים או אגוזי לוז וחלבון ביצה.',
    source: '12 §8.4',
  ),
  TripLexiconEntry(
    terms: <String>['gianduja', 'gianduia'],
    hides: <RestrictionId>[_treeNuts, _milk],
    glossEn: 'Hazelnut chocolate.',
    glossHe: 'שוקולד אגוזי לוז.',
    source: '11 §2.1',
  ),
  TripLexiconEntry(
    terms: <String>['tiramisù'],
    hides: <RestrictionId>[_eggs, _milk, _wheat, _gluten],
    glossEn: 'Mascarpone and raw-egg cream on wheat biscuits.',
    glossHe: 'קרם מסקרפונה וביצים על עוגיות חיטה.',
    source: '12 §8.4',
  ),
  TripLexiconEntry(
    terms: <String>['carbonara'],
    hides: <RestrictionId>[_eggs, _milk],
    glossEn: 'Egg-yolk and cheese sauce.',
    glossHe: 'רוטב חלמונים וגבינה.',
    source: '11 §5.2',
  ),
  TripLexiconEntry(
    terms: <String>['fritto misto', 'frittura'],
    hides: <RestrictionId>[_wheat, _gluten, _fish, _crustaceans, _molluscs],
    glossEn: 'Floured fried seafood, often from one shared fryer.',
    glossHe: 'פירות ים מטוגנים בקמח, לעיתים קרובות מאותו סיר טיגון.',
    source: '12 §8.4',
  ),
  TripLexiconEntry(
    terms: <String>['salsa verde'],
    hides: <RestrictionId>[_fish],
    glossEn: 'Herb sauce, often with anchovies.',
    glossHe: 'רוטב עשבי תיבול, לעיתים קרובות עם אנשובי.',
    source: '12 §8.4',
  ),
  TripLexiconEntry(
    terms: <String>['bottarga'],
    hides: <RestrictionId>[_fish],
    glossEn: 'Cured fish roe, grated over pasta.',
    glossHe: 'ביצי דגים כבושות, מגוררות על פסטה.',
    source: '11 §8.1',
  ),
  TripLexiconEntry(
    terms: <String>['alla milanese', 'impanato', 'impanata'],
    hides: <RestrictionId>[_wheat, _gluten, _eggs],
    glossEn: 'Breaded with egg and breadcrumbs.',
    glossHe: 'מצופה בביצה ובפירורי לחם.',
    source: '12 §8.4',
  ),
];

/// Spain (file 12 §8.5; file 11).
const List<TripLexiconEntry> _spain = <TripLexiconEntry>[
  TripLexiconEntry(
    terms: <String>['altramuces'],
    hides: <RestrictionId>[_lupin],
    glossEn: 'Pickled lupin beans, a bar snack.',
    glossHe: 'גרגרי תורמוס כבושים, חטיף בר.',
    source: '11 §14.1',
  ),
  TripLexiconEntry(
    terms: <String>['mostaza'],
    hides: <RestrictionId>[_mustard],
    glossEn: 'Mustard.',
    glossHe: 'חרדל.',
    source: '12 §8.5',
  ),
  TripLexiconEntry(
    terms: <String>['romesco'],
    hides: <RestrictionId>[_treeNuts, _wheat, _gluten],
    glossEn: 'Pepper sauce thickened with almonds or hazelnuts and bread.',
    glossHe: 'רוטב פלפלים שמסמיכים בשקדים או אגוזי לוז ובלחם.',
    source: '12 §8.5',
  ),
  TripLexiconEntry(
    terms: <String>['alioli', 'allioli'],
    hides: <RestrictionId>[_eggs],
    glossEn: 'Garlic sauce, in restaurants usually made with egg.',
    glossHe: 'רוטב שום, במסעדות בדרך כלל עם ביצה.',
    source: '12 §8.5',
  ),
  TripLexiconEntry(
    terms: <String>['salmorejo'],
    hides: <RestrictionId>[_wheat, _gluten, _eggs],
    glossEn: 'Cold tomato soup thickened with bread, topped with egg.',
    glossHe: 'מרק עגבניות קר שמסמיכים בלחם, עם ביצה מעל.',
    source: '12 §8.5',
  ),
  TripLexiconEntry(
    terms: <String>['gazpacho'],
    hides: <RestrictionId>[_wheat, _gluten],
    glossEn: 'Cold vegetable soup, often thickened with bread.',
    glossHe: 'מרק ירקות קר, לעיתים קרובות מוסמך בלחם.',
    source: '12 §8.5',
  ),
  TripLexiconEntry(
    terms: <String>['croquetas', 'croqueta'],
    hides: <RestrictionId>[_wheat, _gluten, _milk, _eggs],
    glossEn: 'Béchamel croquettes, egg-and-breadcrumbed.',
    glossHe: 'קרוקטים של רוטב בשמל, מצופים בביצה ופירורי לחם.',
    source: '12 §8.5',
  ),
  TripLexiconEntry(
    terms: <String>['paella'],
    hides: <RestrictionId>[_crustaceans, _molluscs, _fish],
    glossEn: 'Rice cooked in stock, often seafood stock.',
    glossHe: 'אורז מבושל בציר, לעיתים קרובות ציר פירות ים.',
    source: '12 §8.5',
  ),
  TripLexiconEntry(
    terms: <String>['fideuà', 'fideos'],
    hides: <RestrictionId>[_wheat, _gluten, _crustaceans, _molluscs],
    glossEn: 'Short wheat noodles cooked like paella, usually with seafood.',
    glossHe: 'אטריות חיטה קצרות שמבושלות כמו פאייה, בדרך כלל עם פירות ים.',
    source: '12 §8.5',
  ),
  TripLexiconEntry(
    terms: <String>['ajoblanco'],
    hides: <RestrictionId>[_treeNuts, _wheat, _gluten],
    glossEn: 'Cold almond and bread soup.',
    glossHe: 'מרק קר של שקדים ולחם.',
    source: '12 §8.5',
  ),
  TripLexiconEntry(
    terms: <String>['turrón'],
    hides: <RestrictionId>[_treeNuts, _eggs],
    glossEn: 'Almond nougat with egg white.',
    glossHe: 'נוגט שקדים עם חלבון ביצה.',
    source: '12 §8.5',
  ),
  TripLexiconEntry(
    terms: <String>['rebozado', 'rebozada', 'empanado', 'empanada'],
    hides: <RestrictionId>[_wheat, _gluten, _eggs],
    glossEn: 'Battered, breaded, or a wheat pastry turnover.',
    glossHe: 'בבלילה, מצופה בפירורי לחם, או מאפה בצק חיטה ממולא.',
    source: '12 §8.5',
  ),
  TripLexiconEntry(
    terms: <String>['ensaladilla'],
    hides: <RestrictionId>[_eggs, _fish],
    glossEn: 'Potato salad in mayonnaise, often with tuna.',
    glossHe: 'סלט תפוחי אדמה במיונז, לעיתים קרובות עם טונה.',
    source: '12 §8.5',
  ),
];

/// Germany (file 12 §8.6; file 11).
const List<TripLexiconEntry> _germany = <TripLexiconEntry>[
  TripLexiconEntry(
    terms: <String>['Senf'],
    hides: <RestrictionId>[_mustard],
    glossEn:
        'Mustard: in sauces, dressings, marinades and on every '
        'sausage.',
    glossHe: 'חרדל: ברטבים, ברטבי סלט, במרינדות ועל כל נקניקייה.',
    source: '12 §8.6',
  ),
  TripLexiconEntry(
    terms: <String>['Remoulade'],
    hides: <RestrictionId>[_mustard, _eggs],
    glossEn: 'Mayonnaise sauce with mustard and pickles.',
    glossHe: 'רוטב מיונז עם חרדל וחמוצים.',
    source: '12 §8.6',
  ),
  TripLexiconEntry(
    terms: <String>['Rouladen', 'Roulade', 'Rinderroulade'],
    hides: <RestrictionId>[_mustard],
    glossEn: 'Beef rolls spread with mustard.',
    glossHe: 'גלילות בקר שמרוחות בחרדל.',
    source: '12 §8.6',
  ),
  TripLexiconEntry(
    terms: <String>['Currywurst'],
    hides: <RestrictionId>[_mustard],
    glossEn: 'Sausage with curry ketchup; curry powder may hold mustard.',
    glossHe: 'נקניקייה בקטשופ קארי; באבקת קארי עשוי להיות חרדל.',
    source: '11 §13.2',
  ),
  TripLexiconEntry(
    terms: <String>['Bratwurst', 'Wurst'],
    hides: <RestrictionId>[_mustard, _wheat, _gluten],
    glossEn: 'Sausages: some hold wheat, and they come with mustard.',
    glossHe: 'נקניקיות: בחלקן יש חיטה, והן מוגשות עם חרדל.',
    source: '12 §8.6',
  ),
  TripLexiconEntry(
    terms: <String>['Kartoffelsalat'],
    hides: <RestrictionId>[_mustard, _eggs],
    glossEn: 'Potato salad, dressed with mustard or mayonnaise.',
    glossHe: 'סלט תפוחי אדמה, ברוטב חרדל או מיונז.',
    source: '11 §13.2',
  ),
  TripLexiconEntry(
    terms: <String>['Spätzle', 'Spaetzle'],
    hides: <RestrictionId>[_eggs, _wheat, _gluten],
    glossEn: 'Egg noodles made of wheat.',
    glossHe: 'אטריות ביצים מקמח חיטה.',
    source: '12 §8.6',
  ),
  TripLexiconEntry(
    terms: <String>['Käsespätzle'],
    hides: <RestrictionId>[_eggs, _wheat, _gluten, _milk],
    glossEn: 'Egg noodles baked with cheese.',
    glossHe: 'אטריות ביצים אפויות עם גבינה.',
    source: '12 §8.6',
  ),
  TripLexiconEntry(
    terms: <String>['Knödel', 'Knoedel', 'Semmelknödel'],
    hides: <RestrictionId>[_wheat, _gluten, _eggs, _milk],
    glossEn: 'Bread dumplings bound with egg and milk.',
    glossHe: 'כופתאות לחם עם ביצה וחלב.',
    source: '12 §8.6',
  ),
  TripLexiconEntry(
    terms: <String>['Maultaschen'],
    hides: <RestrictionId>[_wheat, _gluten, _eggs],
    glossEn: 'Large filled pasta of wheat and egg.',
    glossHe: 'כיסני פסטה גדולים מחיטה וביצים.',
    source: '12 §8.6',
  ),
  TripLexiconEntry(
    terms: <String>['paniert'],
    hides: <RestrictionId>[_wheat, _gluten, _eggs],
    glossEn: 'Breaded with flour, egg and breadcrumbs.',
    glossHe: 'מצופה בקמח, ביצה ופירורי לחם.',
    source: '12 §8.6',
  ),
  TripLexiconEntry(
    terms: <String>['Sellerie', 'Knollensellerie'],
    hides: <RestrictionId>[_celery],
    glossEn: 'Celery, or celeriac.',
    glossHe: 'סלרי, או סלרי שורש.',
    source: '12 §8.6',
  ),
  TripLexiconEntry(
    terms: <String>['Suppengrün', 'Suppengemüse'],
    hides: <RestrictionId>[_celery],
    glossEn: 'Soup greens: a bundle that includes celeriac.',
    glossHe: 'ירקות למרק: צרור שכולל סלרי שורש.',
    source: '12 §8.6',
  ),
  TripLexiconEntry(
    terms: <String>['Brühe', 'Fleischbrühe', 'Gemüsebrühe'],
    hides: <RestrictionId>[_celery],
    glossEn: 'Broth; stocks commonly hold celery.',
    glossHe: 'ציר; בציר יש לעיתים קרובות סלרי.',
    source: '11 §12.2',
  ),
  TripLexiconEntry(
    terms: <String>['Marzipan'],
    hides: <RestrictionId>[_treeNuts],
    glossEn: 'Almond paste.',
    glossHe: 'ממרח שקדים (מרציפן).',
    source: '11 §2.2',
  ),
  TripLexiconEntry(
    terms: <String>['Bienenstich'],
    hides: <RestrictionId>[_treeNuts, _milk, _eggs, _wheat, _gluten],
    glossEn: 'Yeast cake with an almond topping and custard filling.',
    glossHe: 'עוגת שמרים עם ציפוי שקדים ומילוי קרם.',
    source: '12 §8.6',
  ),
  TripLexiconEntry(
    terms: <String>['Lupinenmehl', 'Lupine'],
    hides: <RestrictionId>[_lupin],
    glossEn: 'Lupin flour, in some breads and gluten-free baking.',
    glossHe: 'קמח תורמוס, בחלק מהלחמים ובאפייה ללא גלוטן.',
    source: '11 §14.1',
  ),
];

/// Japan (file 12 §8.2; file 11).
const List<TripLexiconEntry> _japan = <TripLexiconEntry>[
  TripLexiconEntry(
    terms: <String>['soba'],
    hides: <RestrictionId>[_wheat, _gluten],
    glossEn:
        'Buckwheat noodles, usually mixed with wheat flour. Buckwheat '
        "is on Japan's mandatory list; if you react to it, add it as your "
        'own word.',
    glossHe:
        'אטריות כוסמת, לרוב מעורבבות בקמח חיטה. כוסמת ברשימת החובה '
        'של יפן; אם יש לך רגישות אליה, הוסיפו אותה כמילה משלך.',
    source: '12 §8.2',
  ),
  TripLexiconEntry(
    terms: <String>['yakisoba'],
    hides: <RestrictionId>[_wheat, _gluten, _soy],
    glossEn: 'Fried wheat noodles in a soy-based sauce.',
    glossHe: 'אטריות חיטה מוקפצות ברוטב על בסיס סויה.',
    source: '12 §8.2',
  ),
  TripLexiconEntry(
    terms: <String>['udon', 'ramen'],
    hides: <RestrictionId>[_wheat, _gluten],
    glossEn: 'Wheat noodles.',
    glossHe: 'אטריות חיטה.',
    source: '12 §8.2',
  ),
  TripLexiconEntry(
    terms: <String>['shoyu', 'soy sauce'],
    hides: <RestrictionId>[_wheat, _gluten, _soy],
    glossEn: 'Soy sauce is brewed with wheat; it is in most sauces.',
    glossHe: 'רוטב סויה נרקח עם חיטה; הוא נמצא ברוב הרטבים.',
    source: '11 §7.2',
  ),
  TripLexiconEntry(
    terms: <String>['dashi'],
    hides: <RestrictionId>[_fish],
    glossEn:
        'Stock made from bonito (fish) flakes: the base of soups, '
        'sauces and broths.',
    glossHe: 'ציר מפתיתי דג בוניטו: הבסיס של מרקים, רטבים וצירים.',
    source: '11 §8.1',
  ),
  TripLexiconEntry(
    terms: <String>['katsuobushi', 'bonito'],
    hides: <RestrictionId>[_fish],
    glossEn: 'Dried fish flakes, sprinkled on many dishes.',
    glossHe: 'פתיתי דג מיובש, שמפזרים על מנות רבות.',
    source: '11 §8.1',
  ),
  TripLexiconEntry(
    terms: <String>['miso'],
    hides: <RestrictionId>[_soy, _gluten],
    glossEn: 'Fermented soy paste; barley miso holds gluten.',
    glossHe: 'ממרח סויה מותסס; מיסו שעורה מכיל גלוטן.',
    source: '12 §8.2',
  ),
  TripLexiconEntry(
    terms: <String>['tempura'],
    hides: <RestrictionId>[_wheat, _gluten, _eggs],
    glossEn: 'Fried in a wheat-flour batter, often with egg.',
    glossHe: 'מטוגן בבלילת קמח חיטה, לעיתים קרובות עם ביצה.',
    source: '12 §8.2',
  ),
  TripLexiconEntry(
    terms: <String>['ponzu'],
    hides: <RestrictionId>[_soy, _wheat, _gluten, _fish],
    glossEn: 'Citrus soy sauce, usually made with dashi.',
    glossHe: 'רוטב סויה והדרים, בדרך כלל עם דאשי.',
    source: '12 §8.2',
  ),
  TripLexiconEntry(
    terms: <String>['katsu', 'tonkatsu'],
    hides: <RestrictionId>[_wheat, _gluten, _eggs],
    glossEn: 'Breaded cutlet; the sauce holds wheat and soy.',
    glossHe: 'שניצל מצופה; ברוטב יש חיטה וסויה.',
    source: '12 §8.2',
  ),
  TripLexiconEntry(
    terms: <String>['okonomiyaki'],
    hides: <RestrictionId>[_wheat, _gluten, _eggs, _fish],
    glossEn: 'Wheat-and-egg pancake topped with bonito flakes.',
    glossHe: 'פנקייק חיטה וביצים עם פתיתי בוניטו מעל.',
    source: '12 §8.2',
  ),
  TripLexiconEntry(
    terms: <String>['takoyaki'],
    hides: <RestrictionId>[_wheat, _gluten, _eggs, _molluscs, _fish],
    glossEn: 'Octopus balls in wheat batter, topped with bonito.',
    glossHe: 'כדורי תמנון בבלילת חיטה, עם בוניטו מעל.',
    source: '12 §8.2',
  ),
  TripLexiconEntry(
    terms: <String>['furikake'],
    hides: <RestrictionId>[_sesame, _fish],
    glossEn: 'Rice seasoning of sesame, seaweed and dried fish.',
    glossHe: 'תיבול לאורז משומשום, אצות ודג מיובש.',
    source: '12 §8.2',
  ),
  TripLexiconEntry(
    terms: <String>['goma', 'gomadare'],
    hides: <RestrictionId>[_sesame],
    glossEn: 'Sesame, as in sesame sauce and goma-ae salads.',
    glossHe: 'שומשום, כמו ברוטב שומשום ובסלטי גומה-אה.',
    source: '12 §8.2',
  ),
  TripLexiconEntry(
    terms: <String>['teriyaki'],
    hides: <RestrictionId>[_wheat, _gluten, _soy],
    glossEn: 'Glaze made with soy sauce, which holds wheat.',
    glossHe: 'זיגוג עם רוטב סויה, שיש בו חיטה.',
    source: '11 §7.2',
  ),
  TripLexiconEntry(
    terms: <String>['mentaiko'],
    hides: <RestrictionId>[_fish],
    glossEn: 'Spicy pollock roe, in pasta and rice balls.',
    glossHe: 'ביצי דג פולוק חריפות, בפסטה ובכדורי אורז.',
    source: '12 §8.2',
  ),
  TripLexiconEntry(
    terms: <String>['tamagoyaki', 'tamago'],
    hides: <RestrictionId>[_eggs, _fish],
    glossEn: 'Rolled omelette, often seasoned with dashi.',
    glossHe: 'חביתה מגולגלת, לעיתים קרובות מתובלת בדאשי.',
    source: '12 §8.2',
  ),
  TripLexiconEntry(
    terms: <String>['gyoza'],
    hides: <RestrictionId>[_wheat, _gluten],
    glossEn: 'Wheat-wrapper dumplings.',
    glossHe: 'כיסונים בעטיפת בצק חיטה.',
    source: '12 §8.2',
  ),
];

/// Every destination's lexicon. Total over [TripDestination] (a test pins
/// it), and every entry cites file 11 or 12.
const Map<TripDestination, List<TripLexiconEntry>> tripLexicon =
    <TripDestination, List<TripLexiconEntry>>{
      TripDestination.israel: _israel,
      TripDestination.unitedStates: _unitedStates,
      TripDestination.unitedKingdom: _unitedKingdom,
      TripDestination.france: _france,
      TripDestination.italy: _italy,
      TripDestination.spain: _spain,
      TripDestination.germany: _germany,
      TripDestination.japan: _japan,
    };

/// Trip mode's lexicon readers.
abstract final class TripLexicon {
  /// Each destination's lexicon as a vocabulary, built once; the matcher
  /// caches compiled patterns per map instance, so the same map must come
  /// back every time.
  static final Map<TripDestination, Map<RestrictionId, RestrictionVocabulary>>
  _vocabularies =
      <TripDestination, Map<RestrictionId, RestrictionVocabulary>>{};

  /// The user's own vocabulary merged with a destination's, per own map
  /// instance and destination, for the same reason.
  static final Expando<
    Map<TripDestination, Map<RestrictionId, RestrictionVocabulary>>
  >
  _merged =
      Expando<Map<TripDestination, Map<RestrictionId, RestrictionVocabulary>>>(
        'trip vocabulary',
      );

  /// [destination]'s lexicon.
  static List<TripLexiconEntry> entriesFor(TripDestination destination) =>
      tripLexicon[destination] ?? const <TripLexiconEntry>[];

  /// The entries of [destination] that hide a restriction [profile] holds
  /// (keto aside), in the lexicon's order: what the briefing page lists.
  static List<TripLexiconEntry> briefing(
    TripDestination destination,
    DietaryProfile profile,
  ) => <TripLexiconEntry>[
    for (final entry in entriesFor(destination))
      if (entry.restrictions.any(
        (id) => id != RestrictionId.keto && profile.contains(id),
      ))
        entry,
  ];

  /// [destination]'s lexicon as a vocabulary: per restriction, every term
  /// of every entry that hides it ([TripLexiconEntry.restrictions]) as a
  /// [TriggerCertainty.suspected] hidden trigger citing the entry, Hebrew
  /// terms in the Hebrew list. Terms that normalise alike are listed once
  /// per restriction. Pure; the same map is returned every time.
  static Map<RestrictionId, RestrictionVocabulary> vocabularyFor(
    TripDestination destination,
  ) => _vocabularies[destination] ??= _build(destination);

  /// [own], the vocabulary of the user's own words, with [trip]'s lexicon
  /// added; [own] itself when [trip] is null (no trip active). The hook
  /// `ProfileEvaluator` reads: its pass over the user's own words then reads
  /// the destination's terms too, as suspected hidden sources (ALG-13). The
  /// two never share a key ([own] holds only [RestrictionId.custom]). Pure;
  /// the same map is returned for the same [own] instance and [trip].
  static Map<RestrictionId, RestrictionVocabulary> withTrip(
    Map<RestrictionId, RestrictionVocabulary> own,
    TripDestination? trip,
  ) {
    if (trip == null) return own;
    final byTrip = _merged[own] ??=
        <TripDestination, Map<RestrictionId, RestrictionVocabulary>>{};
    return byTrip[trip] ??=
        Map<RestrictionId, RestrictionVocabulary>.unmodifiable(
          <RestrictionId, RestrictionVocabulary>{
            ...vocabularyFor(trip),
            ...own,
          },
        );
  }

  /// [vocabularyFor], uncached.
  static Map<RestrictionId, RestrictionVocabulary> _build(
    TripDestination destination,
  ) {
    final english = <RestrictionId, List<HiddenTrigger>>{};
    final hebrew = <RestrictionId, List<HiddenTrigger>>{};
    final seen = <RestrictionId, Set<String>>{};
    for (final entry in entriesFor(destination)) {
      for (final id in entry.restrictions) {
        for (final term in entry.terms) {
          final normalised = AllergenMatcher.matchText(term);
          if (normalised.isEmpty ||
              !(seen[id] ??= <String>{}).add(normalised)) {
            continue;
          }
          final trigger = HiddenTrigger(
            term: term,
            certainty: TriggerCertainty.suspected,
            source: entry.source,
          );
          final target = TextNormaliser.containsHebrew(term) ? hebrew : english;
          (target[id] ??= <HiddenTrigger>[]).add(trigger);
        }
      }
    }
    return Map<RestrictionId, RestrictionVocabulary>.unmodifiable(
      <RestrictionId, RestrictionVocabulary>{
        for (final id in <RestrictionId>{...english.keys, ...hebrew.keys})
          id: RestrictionVocabulary(
            hiddenEn: List<HiddenTrigger>.unmodifiable(
              english[id] ?? const <HiddenTrigger>[],
            ),
            hiddenHe: List<HiddenTrigger>.unmodifiable(
              hebrew[id] ?? const <HiddenTrigger>[],
            ),
          ),
      },
    );
  }
}

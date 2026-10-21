/// Kosher and halal: the trigger vocabulary of the religious components
/// (Banto; related to issue #342).
///
/// **Components only, never certification** (file 03, "Kosher, halal,
/// Jain"; file 10's non-goals). A menu's words can show pork, shellfish,
/// meat served with dairy or wine in a sauce; they can never show that a
/// kitchen, its meat or its slaughter is kosher or halal, so nothing here
/// says so. The only kosher statement the app makes stays ALG-09's
/// attributed chip, "Declared kosher by the platform".
///
/// Every term comes from
/// `allergen app documentation/11_hidden_allergen_sources.md` §24 (kosher)
/// and §25 (halal), or `12_israeli_and_us_menu_lexicon.md` §9 (the Hebrew
/// terms), and its source cites the section, which
/// `test/utils/allergens/vocabulary_test.dart` checks. After a change,
/// regenerate the goldens and copy `allergens.json` to `backend/app/keto/`
/// (architecture.md D26).
///
/// The shellfish and mammal-meat words are not copied: they are the public
/// pieces of `vocab_sea.dart` and `vocab_extended.dart`, spread here, so a
/// word added there reaches kosher too.
///
/// Kosher's fifth component, meat served with dairy, is no single word: it
/// is a rule over two words of one dish
/// (`ClassificationRules.allergenFindings`), which reads the meat words
/// from [meatWithDairyMeatVocabulary] and the dairy words from the Milk
/// restriction's own vocabulary. A cheeseburger names both at once, so it
/// is a direct trigger here.
library;

import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/utils/allergens/vocab_extended.dart';
import 'package:ketoclub/utils/allergens/vocab_sea.dart';
import 'package:ketoclub/utils/allergens/vocabulary_types.dart';

/// What joins the meat words and the dairy words of a meat-with-dairy
/// concern's matched text ("Ribeye + butter").
const String meatWithDairyJoiner = ' + ';

// --- Pork (11 §24.1, §25.1; 12 §9.1) -------------------------------------

/// English words that name pork (11 §24.1).
const List<String> _porkEn = <String>[
  'pork',
  'pig',
  'piglet',
  'suckling pig',
  'boar',
  'bacon',
  'ham',
  'gammon',
  'lard',
  'lardo',
  'lardons',
  'carnitas',
  'char siu',
  'tonkatsu',
  'tonkotsu',
  'porchetta',
  'guanciale',
  'prosciutto',
  'pancetta',
  'jamon',
  'serrano ham',
];

/// Hebrew words that name pork (12 §9.1). `חזיר` takes no free prefix
/// ("מחזיר" is "returns"), so its prefixed forms are their own terms.
const List<String> _porkHe = <String>['חזיר', 'החזיר', 'וחזיר', 'בחזיר'];

/// English cured meats and sausages that are usually or sometimes pork
/// (11 §24.1).
const List<HiddenTrigger> _porkHiddenEn = <HiddenTrigger>[
  HiddenTrigger(
    term: 'chorizo',
    certainty: TriggerCertainty.likely,
    source: '11 §24.1',
  ),
  HiddenTrigger(
    term: 'mortadella',
    certainty: TriggerCertainty.likely,
    source: '11 §24.1',
  ),
  HiddenTrigger(
    term: 'speck',
    certainty: TriggerCertainty.likely,
    source: '11 §24.1',
  ),
  HiddenTrigger(
    term: 'bratwurst',
    certainty: TriggerCertainty.likely,
    source: '11 §24.1',
  ),
  HiddenTrigger(
    term: 'kielbasa',
    certainty: TriggerCertainty.likely,
    source: '11 §24.1',
  ),
  HiddenTrigger(
    term: 'chicharron',
    certainty: TriggerCertainty.likely,
    source: '11 §24.1',
  ),
  HiddenTrigger(
    term: 'chicharrones',
    certainty: TriggerCertainty.likely,
    source: '11 §24.1',
  ),
  HiddenTrigger(
    term: 'spare ribs',
    certainty: TriggerCertainty.likely,
    source: '11 §24.1',
  ),
  HiddenTrigger(
    term: 'baby back ribs',
    certainty: TriggerCertainty.likely,
    source: '11 §24.1',
  ),
  HiddenTrigger(
    term: 'salami',
    certainty: TriggerCertainty.suspected,
    source: '11 §24.1',
  ),
  HiddenTrigger(
    term: 'pepperoni',
    certainty: TriggerCertainty.suspected,
    source: '11 §24.1',
  ),
  HiddenTrigger(
    term: 'sausage',
    certainty: TriggerCertainty.suspected,
    source: '11 §24.1',
  ),
  HiddenTrigger(
    term: 'sausages',
    certainty: TriggerCertainty.suspected,
    source: '11 §24.1',
  ),
  HiddenTrigger(
    term: 'hot dog',
    certainty: TriggerCertainty.suspected,
    source: '11 §24.1',
  ),
  HiddenTrigger(
    term: 'hot dogs',
    certainty: TriggerCertainty.suspected,
    source: '11 §24.1',
  ),
];

/// Hebrew cured meats that are usually or sometimes pork (12 §9.1). "בשר
/// לבן" and "סטייק לבן" are Israel's euphemism for pork, but "white meat"
/// is also poultry, so they are likely, never stated.
const List<HiddenTrigger> _porkHiddenHe = <HiddenTrigger>[
  HiddenTrigger(
    term: 'בשר לבן',
    certainty: TriggerCertainty.likely,
    source: '12 §9.1',
  ),
  HiddenTrigger(
    term: 'סטייק לבן',
    certainty: TriggerCertainty.likely,
    source: '12 §9.1',
  ),
  HiddenTrigger(
    term: 'בייקון',
    certainty: TriggerCertainty.likely,
    source: '12 §9.1',
  ),
  HiddenTrigger(
    term: 'פרושוטו',
    certainty: TriggerCertainty.likely,
    source: '12 §9.1',
  ),
  HiddenTrigger(
    term: "פנצ'טה",
    certainty: TriggerCertainty.likely,
    source: '12 §9.1',
  ),
  HiddenTrigger(
    term: 'סלמי',
    certainty: TriggerCertainty.suspected,
    source: '12 §9.1',
  ),
  HiddenTrigger(
    term: 'פפרוני',
    certainty: TriggerCertainty.suspected,
    source: '12 §9.1',
  ),
  HiddenTrigger(
    term: "צ'וריסו",
    certainty: TriggerCertainty.suspected,
    source: '12 §9.1',
  ),
  HiddenTrigger(
    term: 'נקניק',
    certainty: TriggerCertainty.suspected,
    source: '12 §9.1',
  ),
];

/// The words beside a pork word that name another meat ("turkey bacon",
/// "בייקון בקר", "פרושוטו אווז"): Israeli kosher menus print these often.
const Map<String, AllergenGuards> _porkTermGuards = <String, AllergenGuards>{
  'bacon': AllergenGuards(
    beforeEn: <String>[
      'turkey',
      'beef',
      'veggie',
      'coconut',
      'duck',
      'lamb',
      'goose',
      'chicken',
      'salmon',
      'mushroom',
      'tempeh',
    ],
  ),
  'ham': AllergenGuards(
    beforeEn: <String>['turkey', 'chicken', 'beef', 'goose', 'duck'],
  ),
  'prosciutto': AllergenGuards(
    beforeEn: <String>['duck', 'goose', 'beef', 'turkey'],
  ),
  'char siu': AllergenGuards(beforeEn: <String>['chicken', 'tofu']),
  'tonkatsu': AllergenGuards(beforeEn: <String>['chicken']),
  'chorizo': AllergenGuards(beforeEn: <String>['chicken', 'beef', 'veggie']),
  'bratwurst': AllergenGuards(
    beforeEn: <String>['chicken', 'turkey', 'veggie'],
  ),
  'kielbasa': AllergenGuards(beforeEn: <String>['turkey', 'beef']),
  'salami': AllergenGuards(
    beforeEn: <String>['turkey', 'chicken', 'beef', 'goose'],
  ),
  'pepperoni': AllergenGuards(beforeEn: <String>['turkey', 'chicken', 'beef']),
  'sausage': AllergenGuards(
    beforeEn: <String>['chicken', 'turkey', 'beef', 'lamb', 'veggie', 'fish'],
  ),
  'sausages': AllergenGuards(
    beforeEn: <String>['chicken', 'turkey', 'beef', 'lamb', 'veggie', 'fish'],
  ),
  'hot dog': AllergenGuards(
    beforeEn: <String>['chicken', 'turkey', 'beef', 'veggie'],
  ),
  'hot dogs': AllergenGuards(
    beforeEn: <String>['chicken', 'turkey', 'beef', 'veggie'],
  ),
  'בשר לבן': AllergenGuards(
    beforeHe: <String>['עוף', 'הודו'],
    afterHe: <String>['עוף', 'הודו'],
  ),
  'בייקון': AllergenGuards(
    afterHe: <String>['בקר', 'הודו', 'עוף', 'אווז', 'ברווז', 'טלה'],
  ),
  'פרושוטו': AllergenGuards(afterHe: <String>['אווז', 'בקר', 'הודו', 'ברווז']),
  'סלמי': AllergenGuards(afterHe: <String>['הודו', 'עוף', 'בקר', 'אווז']),
  'פפרוני': AllergenGuards(afterHe: <String>['בקר', 'הודו', 'עוף']),
  "צ'וריסו": AllergenGuards(afterHe: <String>['בקר', 'עוף']),
  'נקניק': AllergenGuards(afterHe: <String>['עוף', 'הודו', 'בקר']),
};

// --- Blood and gelatin (11 §24.4, §24.6, §25.3, §25.4; 12 §9.5) -----------

/// English blood dishes (11 §24.4).
const List<String> _bloodEn = <String>[
  'black pudding',
  'blood pudding',
  'blood sausage',
  'morcilla',
  'boudin noir',
  'blutwurst',
];

/// Hebrew blood dishes (12 §9.5).
const List<String> _bloodHe = <String>['נקניק דם'];

/// English gelatin and the desserts set with it (11 §24.6): suspected,
/// because gelatin may be fish or plant-based, and only the kitchen knows.
const List<HiddenTrigger> _gelatinEn = <HiddenTrigger>[
  HiddenTrigger(
    term: 'gelatin',
    certainty: TriggerCertainty.suspected,
    source: '11 §24.6',
  ),
  HiddenTrigger(
    term: 'gelatine',
    certainty: TriggerCertainty.suspected,
    source: '11 §24.6',
  ),
  HiddenTrigger(
    term: 'panna cotta',
    certainty: TriggerCertainty.suspected,
    source: '11 §24.6',
  ),
  HiddenTrigger(
    term: 'marshmallow',
    certainty: TriggerCertainty.suspected,
    source: '11 §24.6',
  ),
  HiddenTrigger(
    term: 'marshmallows',
    certainty: TriggerCertainty.suspected,
    source: '11 §24.6',
  ),
  HiddenTrigger(
    term: 'gummies',
    certainty: TriggerCertainty.suspected,
    source: '11 §24.6',
  ),
  HiddenTrigger(
    term: 'aspic',
    certainty: TriggerCertainty.suspected,
    source: '11 §24.6',
  ),
];

/// Hebrew gelatin and gelatin desserts (12 §9.5).
const List<HiddenTrigger> _gelatinHe = <HiddenTrigger>[
  HiddenTrigger(
    term: "ג'לטין",
    certainty: TriggerCertainty.suspected,
    source: '12 §9.5',
  ),
  HiddenTrigger(
    term: 'פנקוטה',
    certainty: TriggerCertainty.suspected,
    source: '12 §9.5',
  ),
  HiddenTrigger(
    term: 'פנה קוטה',
    certainty: TriggerCertainty.suspected,
    source: '12 §9.5',
  ),
  HiddenTrigger(
    term: 'מרשמלו',
    certainty: TriggerCertainty.suspected,
    source: '12 §9.5',
  ),
  HiddenTrigger(
    term: 'סוכריות גומי',
    certainty: TriggerCertainty.suspected,
    source: '12 §9.5',
  ),
];

/// Fish gelatin is neither pork nor beef (11 §24.6).
const Map<String, AllergenGuards> _gelatinTermGuards = <String, AllergenGuards>{
  'gelatin': AllergenGuards(beforeEn: <String>['fish']),
  'gelatine': AllergenGuards(beforeEn: <String>['fish']),
  "ג'לטין": AllergenGuards(afterHe: <String>['דגים']),
};

// --- Kosher only (11 §24.2, §24.3, §24.5; 12 §9.2, §9.3) -----------------

/// English fish without fins and removable scales (11 §24.2).
const List<String> _finlessFishEn = <String>[
  'eel',
  'eels',
  'unagi',
  'catfish',
  'pangasius',
  'basa',
  'swai',
  'shark',
  'monkfish',
  'skate',
];

/// Hebrew fish without fins and scales (12 §9.2).
const List<String> _finlessFishHe = <String>[
  'צלופח',
  'אונאגי',
  'שפמנון',
  'פנגסיוס',
  'כריש',
];

/// English fish whose scales are disputed or whose roe is sturgeon's
/// (11 §24.2): sturgeon and caviar likely, swordfish suspected, since
/// some authorities accept it.
const List<HiddenTrigger> _disputedFishEn = <HiddenTrigger>[
  HiddenTrigger(
    term: 'sturgeon',
    certainty: TriggerCertainty.likely,
    source: '11 §24.2',
  ),
  HiddenTrigger(
    term: 'caviar',
    certainty: TriggerCertainty.likely,
    source: '11 §24.2',
  ),
  HiddenTrigger(
    term: 'swordfish',
    certainty: TriggerCertainty.suspected,
    source: '11 §24.2',
  ),
];

/// [_disputedFishEn] in Hebrew (12 §9.2).
const List<HiddenTrigger> _disputedFishHe = <HiddenTrigger>[
  HiddenTrigger(
    term: 'חדקן',
    certainty: TriggerCertainty.likely,
    source: '12 §9.2',
  ),
  HiddenTrigger(
    term: 'קוויאר',
    certainty: TriggerCertainty.likely,
    source: '12 §9.2',
  ),
  HiddenTrigger(
    term: 'קביאר',
    certainty: TriggerCertainty.likely,
    source: '12 §9.2',
  ),
  HiddenTrigger(
    term: 'דג חרב',
    certainty: TriggerCertainty.suspected,
    source: '12 §9.2',
  ),
];

/// "Eel sauce" is a glaze usually made without eel; "salmon caviar" and
/// "eggplant caviar" are not sturgeon roe (11 §24.2).
const Map<String, AllergenGuards> _fishTermGuards = <String, AllergenGuards>{
  'eel': AllergenGuards(afterEn: <String>['sauce']),
  'unagi': AllergenGuards(afterEn: <String>['sauce']),
  'caviar': AllergenGuards(
    beforeEn: <String>['salmon', 'trout', 'eggplant', 'aubergine', 'lentil'],
  ),
  'אונאגי': AllergenGuards(beforeHe: <String>['רוטב']),
  'קוויאר': AllergenGuards(
    afterHe: <String>['חצילים', 'סלמון', 'פורל', 'עדשים'],
  ),
  'קביאר': AllergenGuards(
    afterHe: <String>['חצילים', 'סלמון', 'פורל', 'עדשים'],
  ),
};

/// English animals that are not kosher beyond pork and seafood (11 §24.3).
const List<String> _otherAnimalsEn = <String>['rabbit', 'hare', 'frog legs'];

/// Hebrew animals that are not kosher beyond pork and seafood (12 §9.2).
const List<String> _otherAnimalsHe = <String>['ארנב', 'ארנבת'];

/// English dishes that name meat and cheese in one word (11 §24.5).
const List<String> _cheeseMeatEn = <String>[
  'cheeseburger',
  'cheeseburgers',
  'cheesesteak',
  'cheesesteaks',
];

/// Hebrew dishes that name meat and cheese in one word (12 §9.3).
const List<String> _cheeseMeatHe = <String>["צ'יזבורגר", "צ'יז בורגר"];

// --- Alcohol (halal only; 11 §25.2, 12 §9.4) -------------------------------

/// English drinks and dishes that hold alcohol (11 §25.2). Every one is
/// hidden and likely: the menu names the drink, not its alcohol, and some
/// kitchens cook it off — which most halal guidance still forbids.
/// Public because the Jain diet (`vocab_diets_extra.dart`) spreads it.
const List<HiddenTrigger> alcoholHiddenEn = <HiddenTrigger>[
  HiddenTrigger(
    term: 'wine',
    certainty: TriggerCertainty.likely,
    source: '11 §25.2',
  ),
  HiddenTrigger(
    term: 'wines',
    certainty: TriggerCertainty.likely,
    source: '11 §25.2',
  ),
  HiddenTrigger(
    term: 'beer',
    certainty: TriggerCertainty.likely,
    source: '11 §25.2',
  ),
  HiddenTrigger(
    term: 'beers',
    certainty: TriggerCertainty.likely,
    source: '11 §25.2',
  ),
  HiddenTrigger(
    term: 'lager',
    certainty: TriggerCertainty.likely,
    source: '11 §25.2',
  ),
  HiddenTrigger(
    term: 'rum',
    certainty: TriggerCertainty.likely,
    source: '11 §25.2',
  ),
  HiddenTrigger(
    term: 'vodka',
    certainty: TriggerCertainty.likely,
    source: '11 §25.2',
  ),
  HiddenTrigger(
    term: 'whisky',
    certainty: TriggerCertainty.likely,
    source: '11 §25.2',
  ),
  HiddenTrigger(
    term: 'whiskey',
    certainty: TriggerCertainty.likely,
    source: '11 §25.2',
  ),
  HiddenTrigger(
    term: 'bourbon',
    certainty: TriggerCertainty.likely,
    source: '11 §25.2',
  ),
  HiddenTrigger(
    term: 'brandy',
    certainty: TriggerCertainty.likely,
    source: '11 §25.2',
  ),
  HiddenTrigger(
    term: 'cognac',
    certainty: TriggerCertainty.likely,
    source: '11 §25.2',
  ),
  HiddenTrigger(
    term: 'liqueur',
    certainty: TriggerCertainty.likely,
    source: '11 §25.2',
  ),
  HiddenTrigger(
    term: 'liqueurs',
    certainty: TriggerCertainty.likely,
    source: '11 §25.2',
  ),
  HiddenTrigger(
    term: 'sake',
    certainty: TriggerCertainty.likely,
    source: '11 §25.2',
  ),
  HiddenTrigger(
    term: 'mirin',
    certainty: TriggerCertainty.likely,
    source: '11 §25.2',
  ),
  HiddenTrigger(
    term: 'marsala',
    certainty: TriggerCertainty.likely,
    source: '11 §25.2',
  ),
  HiddenTrigger(
    term: 'sherry',
    certainty: TriggerCertainty.likely,
    source: '11 §25.2',
  ),
  HiddenTrigger(
    term: 'gin',
    certainty: TriggerCertainty.likely,
    source: '11 §25.2',
  ),
  HiddenTrigger(
    term: 'tequila',
    certainty: TriggerCertainty.likely,
    source: '11 §25.2',
  ),
  HiddenTrigger(
    term: 'champagne',
    certainty: TriggerCertainty.likely,
    source: '11 §25.2',
  ),
  HiddenTrigger(
    term: 'prosecco',
    certainty: TriggerCertainty.likely,
    source: '11 §25.2',
  ),
  HiddenTrigger(
    term: 'arak',
    certainty: TriggerCertainty.likely,
    source: '11 §25.2',
  ),
  HiddenTrigger(
    term: 'ouzo',
    certainty: TriggerCertainty.likely,
    source: '11 §25.2',
  ),
  HiddenTrigger(
    term: 'sangria',
    certainty: TriggerCertainty.likely,
    source: '11 §25.2',
  ),
  HiddenTrigger(
    term: 'cocktail',
    certainty: TriggerCertainty.likely,
    source: '11 §25.2',
  ),
  HiddenTrigger(
    term: 'cocktails',
    certainty: TriggerCertainty.likely,
    source: '11 §25.2',
  ),
  HiddenTrigger(
    term: 'alcohol',
    certainty: TriggerCertainty.likely,
    source: '11 §25.2',
  ),
  HiddenTrigger(
    term: 'alcoholic',
    certainty: TriggerCertainty.likely,
    source: '11 §25.2',
  ),
  HiddenTrigger(
    term: 'flambe',
    certainty: TriggerCertainty.likely,
    source: '11 §25.2',
  ),
  HiddenTrigger(
    term: 'flambeed',
    certainty: TriggerCertainty.likely,
    source: '11 §25.2',
  ),
  HiddenTrigger(
    term: 'beurre blanc',
    certainty: TriggerCertainty.likely,
    source: '11 §25.2',
  ),
  HiddenTrigger(
    term: 'coq au vin',
    certainty: TriggerCertainty.likely,
    source: '11 §25.2',
  ),
  HiddenTrigger(
    term: 'bourguignon',
    certainty: TriggerCertainty.likely,
    source: '11 §25.2',
  ),
  HiddenTrigger(
    term: 'limoncello',
    certainty: TriggerCertainty.likely,
    source: '11 §25.2',
  ),
  HiddenTrigger(
    term: 'amaretto',
    certainty: TriggerCertainty.likely,
    source: '11 §25.2',
  ),
  HiddenTrigger(
    term: 'mojito',
    certainty: TriggerCertainty.likely,
    source: '11 §25.2',
  ),
  HiddenTrigger(
    term: 'martini',
    certainty: TriggerCertainty.likely,
    source: '11 §25.2',
  ),
  HiddenTrigger(
    term: 'vermouth',
    certainty: TriggerCertainty.likely,
    source: '11 §25.2',
  ),
  HiddenTrigger(
    term: 'irish coffee',
    certainty: TriggerCertainty.likely,
    source: '11 §25.2',
  ),
  HiddenTrigger(
    term: 'zabaglione',
    certainty: TriggerCertainty.likely,
    source: '11 §25.2',
  ),
  HiddenTrigger(
    term: 'tiramisu',
    certainty: TriggerCertainty.suspected,
    source: '11 §25.2',
  ),
  HiddenTrigger(
    term: 'risotto',
    certainty: TriggerCertainty.suspected,
    source: '11 §25.2',
  ),
  HiddenTrigger(
    term: 'teriyaki',
    certainty: TriggerCertainty.suspected,
    source: '11 §25.2',
  ),
  HiddenTrigger(
    term: 'fondue',
    certainty: TriggerCertainty.suspected,
    source: '11 §25.2',
  ),
];

/// Hebrew drinks and dishes that hold alcohol (12 §9.4). "שרי" is left
/// out: on an Israeli menu it is the cherry tomato (עגבניות שרי), not
/// sherry. Spread by Jain like [alcoholHiddenEn].
const List<HiddenTrigger> alcoholHiddenHe = <HiddenTrigger>[
  HiddenTrigger(
    term: 'יין',
    certainty: TriggerCertainty.likely,
    source: '12 §9.4',
  ),
  HiddenTrigger(
    term: 'בירה',
    certainty: TriggerCertainty.likely,
    source: '12 §9.4',
  ),
  HiddenTrigger(
    term: 'וודקה',
    certainty: TriggerCertainty.likely,
    source: '12 §9.4',
  ),
  HiddenTrigger(
    term: 'רום',
    certainty: TriggerCertainty.likely,
    source: '12 §9.4',
  ),
  HiddenTrigger(
    term: 'ליקר',
    certainty: TriggerCertainty.likely,
    source: '12 §9.4',
  ),
  HiddenTrigger(
    term: 'מירין',
    certainty: TriggerCertainty.likely,
    source: '12 §9.4',
  ),
  HiddenTrigger(
    term: 'ברנדי',
    certainty: TriggerCertainty.likely,
    source: '12 §9.4',
  ),
  HiddenTrigger(
    term: 'קוניאק',
    certainty: TriggerCertainty.likely,
    source: '12 §9.4',
  ),
  HiddenTrigger(
    term: 'סאקה',
    certainty: TriggerCertainty.likely,
    source: '12 §9.4',
  ),
  HiddenTrigger(
    term: 'ויסקי',
    certainty: TriggerCertainty.likely,
    source: '12 §9.4',
  ),
  HiddenTrigger(
    term: 'וויסקי',
    certainty: TriggerCertainty.likely,
    source: '12 §9.4',
  ),
  HiddenTrigger(
    term: 'ערק',
    certainty: TriggerCertainty.likely,
    source: '12 §9.4',
  ),
  HiddenTrigger(
    term: 'שמפניה',
    certainty: TriggerCertainty.likely,
    source: '12 §9.4',
  ),
  HiddenTrigger(
    term: 'מרסלה',
    certainty: TriggerCertainty.likely,
    source: '12 §9.4',
  ),
  HiddenTrigger(
    term: 'טקילה',
    certainty: TriggerCertainty.likely,
    source: '12 §9.4',
  ),
  HiddenTrigger(
    term: 'סנגריה',
    certainty: TriggerCertainty.likely,
    source: '12 §9.4',
  ),
  HiddenTrigger(
    term: 'קוקטייל',
    certainty: TriggerCertainty.likely,
    source: '12 §9.4',
  ),
  HiddenTrigger(
    term: 'אלכוהול',
    certainty: TriggerCertainty.likely,
    source: '12 §9.4',
  ),
  HiddenTrigger(
    term: 'פלמבה',
    certainty: TriggerCertainty.likely,
    source: '12 §9.4',
  ),
  HiddenTrigger(
    term: 'טירמיסו',
    certainty: TriggerCertainty.suspected,
    source: '12 §9.4',
  ),
  HiddenTrigger(
    term: 'ריזוטו',
    certainty: TriggerCertainty.suspected,
    source: '12 §9.4',
  ),
  HiddenTrigger(
    term: 'טריאקי',
    certainty: TriggerCertainty.suspected,
    source: '12 §9.4',
  ),
];

/// The words beside an alcohol word that name something else: wine
/// vinegar, root beer, a shrimp cocktail, salmon nigiri ("sake" is also
/// the Japanese word for salmon), malt beer (בירה שחורה). Public because
/// the diets that leave out alcohol (`vocab_diets_extra.dart`) spread it.
const Map<String, AllergenGuards> alcoholTermGuards = <String, AllergenGuards>{
  'wine': AllergenGuards(afterEn: <String>['vinegar']),
  'sherry': AllergenGuards(afterEn: <String>['vinegar']),
  'champagne': AllergenGuards(afterEn: <String>['vinegar']),
  'beer': AllergenGuards(beforeEn: <String>['root', 'ginger']),
  'sake': AllergenGuards(
    afterEn: <String>[
      'nigiri',
      'maki',
      'sashimi',
      'roll',
      'rolls',
      'don',
      'avocado',
    ],
  ),
  'cocktail': AllergenGuards(
    beforeEn: <String>[
      'shrimp',
      'prawn',
      'prawns',
      'fruit',
      'seafood',
      'crab',
      'virgin',
    ],
    afterEn: <String>[
      'sauce',
      'tomato',
      'tomatoes',
      'sausage',
      'sausages',
      'onions',
    ],
  ),
  'cocktails': AllergenGuards(beforeEn: <String>['virgin']),
  'יין': AllergenGuards(beforeHe: <String>['חומץ']),
  'בירה': AllergenGuards(afterHe: <String>['שחורה']),
  'קוקטייל': AllergenGuards(
    beforeHe: <String>['שרימפס', 'פירות'],
    afterHe: <String>['שרימפס', 'פירות', 'עגבניות'],
  ),
};

// --- The two vocabularies -------------------------------------------------

/// The kosher guards (11 §24.7): a negation, a plant-based or imitation
/// word, or "kosher" beside a word, which on a menu marks a substitute
/// ("kosher bacon" is beef). "Vegetarian" is not one, as for the sea
/// group: it would lower "vegetarian and shrimp options".
const AllergenGuards _kosherGuards = AllergenGuards(
  beforeEn: <String>[
    'no',
    'without',
    'free of',
    'free from',
    'vegan',
    'plant based',
    'meatless',
    'imitation',
    'faux',
    'mock',
    'kosher',
  ],
  afterEn: <String>['free', 'substitute', 'alternative', 'kosher'],
  beforeHe: <String>['ללא', 'וללא', 'בלי', 'ובלי', 'נטול', 'תחליף', 'כשר'],
  afterHe: <String>[
    'טבעוני',
    'טבעונית',
    'צמחי',
    'צמחית',
    'כשר',
    'כשרה',
    'כשרים',
  ],
);

/// The halal guards (11 §25.5): as [_kosherGuards], with "halal" for
/// "kosher", and the words that mark a drink without alcohol ("non
/// alcoholic", "alcohol-free", "ללא אלכוהול").
const AllergenGuards _halalGuards = AllergenGuards(
  beforeEn: <String>[
    'no',
    'non',
    'without',
    'free of',
    'free from',
    'vegan',
    'plant based',
    'meatless',
    'imitation',
    'faux',
    'mock',
    'halal',
    'non alcoholic',
    'alcohol free',
  ],
  afterEn: <String>['free', 'substitute', 'alternative', 'halal'],
  beforeHe: <String>[
    'ללא',
    'וללא',
    'בלי',
    'ובלי',
    'נטול',
    'נטולת',
    'תחליף',
    'חלאל',
  ],
  afterHe: <String>[
    'טבעוני',
    'טבעונית',
    'צמחי',
    'צמחית',
    'חלאל',
    'ללא אלכוהול',
    'נטול אלכוהול',
    'נטולת אלכוהול',
  ],
);

/// The kosher and halal vocabularies (11 §24, §25; 12 §9).
const Map<RestrictionId, RestrictionVocabulary> religiousVocabulary =
    <RestrictionId, RestrictionVocabulary>{
      RestrictionId.kosher: RestrictionVocabulary(
        directEn: <String>[
          ..._porkEn,
          ...crustaceanNamesEn,
          ...molluscNamesEn,
          ...shellfishNamesEn,
          ..._finlessFishEn,
          ..._otherAnimalsEn,
          ..._bloodEn,
          ..._cheeseMeatEn,
        ],
        directHe: <String>[
          ..._porkHe,
          ...crustaceanNamesHe,
          ...molluscNamesHe,
          ...shellfishNamesHe,
          ..._finlessFishHe,
          ..._otherAnimalsHe,
          ..._bloodHe,
          ..._cheeseMeatHe,
        ],
        hiddenEn: <HiddenTrigger>[
          ..._porkHiddenEn,
          ...shrimpPastesEn,
          ...molluscSaucesEn,
          ..._disputedFishEn,
          ..._gelatinEn,
        ],
        hiddenHe: <HiddenTrigger>[
          ..._porkHiddenHe,
          ...molluscSaucesHe,
          ..._disputedFishHe,
          ..._gelatinHe,
        ],
        guards: _kosherGuards,
        termGuards: <String, AllergenGuards>{
          ..._porkTermGuards,
          ...crustaceanTermGuards,
          ...molluscTermGuards,
          ..._fishTermGuards,
          ..._gelatinTermGuards,
        },
        noPrefixHe: <String>['חזיר'],
        sources: <String>[
          '11 §24.1',
          '11 §24.2',
          '11 §24.3',
          '11 §24.4',
          '11 §24.5',
          '11 §24.7',
          '12 §9.1',
          '12 §9.2',
          '12 §9.3',
          '12 §9.5',
        ],
      ),
      RestrictionId.halal: RestrictionVocabulary(
        directEn: <String>[..._porkEn, ..._bloodEn],
        directHe: <String>[..._porkHe, ..._bloodHe],
        hiddenEn: <HiddenTrigger>[
          ..._porkHiddenEn,
          ...alcoholHiddenEn,
          ..._gelatinEn,
        ],
        hiddenHe: <HiddenTrigger>[
          ..._porkHiddenHe,
          ...alcoholHiddenHe,
          ..._gelatinHe,
        ],
        guards: _halalGuards,
        termGuards: <String, AllergenGuards>{
          ..._porkTermGuards,
          ...alcoholTermGuards,
          ..._gelatinTermGuards,
        },
        noPrefixHe: <String>['חזיר', 'רום'],
        sources: <String>[
          '11 §25.1',
          '11 §25.2',
          '11 §25.3',
          '11 §25.5',
          '12 §9.1',
          '12 §9.4',
          '12 §9.5',
        ],
      ),
    };

// --- Meat with dairy (kosher; 11 §24.5, 12 §9.3) ---------------------------

/// English poultry and meat dishes (11 §24.5): poultry counts as meat for
/// this rule; fish never does, so a fish in a cream sauce is not flagged.
const List<String> _meatDishesEn = <String>[
  'meat',
  'chicken',
  'turkey',
  'duck',
  'goose',
  'quail',
  'poussin',
  'burger',
  'burgers',
  'hamburger',
  'hamburgers',
  'steak',
  'steaks',
  'schnitzel',
  'kebab',
  'kebabs',
  'kabab',
  'kofta',
  'shawarma',
  'meatball',
  'meatballs',
  'shashlik',
  'beef skewers',
  'gyro',
  'gyros',
  'merguez',
  'pastrami',
  'salami',
  'pepperoni',
  'sausage',
  'sausages',
  'hot dog',
  'hot dogs',
  'luncheon meat',
  'deli meat',
  'deli meats',
  'bacon',
  'ham',
  'prosciutto',
  'chorizo',
  'liver',
  'ribs',
  'spare ribs',
  'cholent',
];

/// English meat words that sometimes hide in a dish (11 §24.5).
const List<HiddenTrigger> _meatHiddenEn = <HiddenTrigger>[
  HiddenTrigger(
    term: 'gravy',
    certainty: TriggerCertainty.likely,
    source: '11 §24.5',
  ),
  HiddenTrigger(
    term: 'bolognese',
    certainty: TriggerCertainty.likely,
    source: '11 §24.5',
  ),
  HiddenTrigger(
    term: 'ragu',
    certainty: TriggerCertainty.likely,
    source: '11 §24.5',
  ),
  HiddenTrigger(
    term: 'carpaccio',
    certainty: TriggerCertainty.likely,
    source: '11 §24.5',
  ),
  HiddenTrigger(
    term: 'stock',
    certainty: TriggerCertainty.suspected,
    source: '11 §24.5',
  ),
  HiddenTrigger(
    term: 'broth',
    certainty: TriggerCertainty.suspected,
    source: '11 §24.5',
  ),
];

/// Hebrew poultry and meat dishes (12 §9.3). `בשר` takes no free prefix,
/// as for alpha-gal, so its prefixed forms are their own terms.
const List<String> _meatDishesHe = <String>[
  'בשר',
  'הבשר',
  'בבשר',
  'ובשר',
  'עוף',
  'עופות',
  'הודו',
  'ברווז',
  'אווז',
  'פרגית',
  'פרגיות',
  'שניצל',
  'שניצלים',
  'המבורגר',
  'קבב',
  'קציצות',
  'סטייק',
  'שווארמה',
  'שיפודים',
  'פסטרמה',
  'סלמי',
  'נקניקיה',
  'נקניקייה',
  'נקניקיות',
  'קבנוס',
  'מרגז',
  'עראייס',
  'כבד',
  'כבדים',
  'צלעות',
  "צ'ולנט",
  'חמין',
];

/// Hebrew meat words that sometimes hide in a dish (12 §9.3).
const List<HiddenTrigger> _meatHiddenHe = <HiddenTrigger>[
  HiddenTrigger(
    term: 'ציר',
    certainty: TriggerCertainty.suspected,
    source: '12 §9.3',
  ),
  HiddenTrigger(
    term: 'הציר',
    certainty: TriggerCertainty.suspected,
    source: '12 §9.3',
  ),
  HiddenTrigger(
    term: 'וציר',
    certainty: TriggerCertainty.suspected,
    source: '12 §9.3',
  ),
];

/// The words beside a meat word that name something that is not meat or
/// poultry: a fish, a vegetable, a plant burger. Poultry is never one of
/// them, since poultry is meat here.
const Map<String, AllergenGuards> _meatTermGuards = <String, AllergenGuards>{
  'goat': goatTermGuards,
  'meat': AllergenGuards(
    beforeEn: <String>['crab', 'fish', 'coconut', 'jackfruit', 'lobster'],
  ),
  'steak': AllergenGuards(
    beforeEn: <String>[
      'tuna',
      'salmon',
      'swordfish',
      'fish',
      'cauliflower',
      'portobello',
      'mushroom',
    ],
  ),
  'steaks': AllergenGuards(
    beforeEn: <String>['tuna', 'salmon', 'fish', 'cauliflower', 'mushroom'],
  ),
  'burger': AllergenGuards(
    beforeEn: <String>[
      'fish',
      'salmon',
      'tuna',
      'veggie',
      'beyond',
      'impossible',
      'mushroom',
      'bean',
      'falafel',
      'lentil',
      'quinoa',
    ],
  ),
  'burgers': AllergenGuards(
    beforeEn: <String>['fish', 'salmon', 'veggie', 'beyond', 'impossible'],
  ),
  'schnitzel': AllergenGuards(
    beforeEn: <String>['fish', 'corn', 'eggplant', 'cauliflower', 'tofu'],
  ),
  'kebab': AllergenGuards(beforeEn: <String>['fish', 'vegetable', 'veggie']),
  'meatball': AllergenGuards(beforeEn: <String>['fish']),
  'meatballs': AllergenGuards(beforeEn: <String>['fish']),
  'sausage': AllergenGuards(beforeEn: <String>['fish', 'veggie']),
  'sausages': AllergenGuards(beforeEn: <String>['fish', 'veggie']),
  'carpaccio': AllergenGuards(
    beforeEn: <String>[
      'beet',
      'beetroot',
      'salmon',
      'tuna',
      'fish',
      'zucchini',
    ],
  ),
  'liver': AllergenGuards(beforeEn: <String>['cod', 'monkfish']),
  'stock': AllergenGuards(
    beforeEn: <String>['fish', 'vegetable', 'veggie', 'mushroom', 'shrimp'],
  ),
  'broth': AllergenGuards(
    beforeEn: <String>['fish', 'vegetable', 'veggie', 'mushroom', 'miso'],
  ),
  'בשר': AllergenGuards(afterHe: <String>['דג', 'דגים', 'סויה', 'סרטן']),
  'שניצל': AllergenGuards(
    afterHe: <String>['תירס', 'חציל', 'כרובית', 'דג', 'טופו'],
  ),
  'קבב': AllergenGuards(afterHe: <String>['דגים', 'ירקות']),
  'קציצות': AllergenGuards(afterHe: <String>['דגים', 'דג', 'ירק', 'ירקות']),
  'סטייק': AllergenGuards(
    afterHe: <String>['טונה', 'סלמון', 'כרובית', 'פורטובלו', 'דג'],
  ),
  'המבורגר': AllergenGuards(afterHe: <String>['דג', 'סלמון', 'טבעוני']),
  'שיפודים': AllergenGuards(afterHe: <String>['ירקות', 'דגים', 'טופו']),
  'כבד': AllergenGuards(afterHe: <String>['דגים']),
  'ציר': AllergenGuards(afterHe: <String>['ירקות', 'דגים', 'פטריות']),
  'הציר': AllergenGuards(afterHe: <String>['ירקות', 'דגים', 'פטריות']),
  'וציר': AllergenGuards(afterHe: <String>['ירקות', 'דגים', 'פטריות']),
};

/// The meat words of the meat-with-dairy rule, keyed by
/// [RestrictionId.kosher] so the matcher reads them in taxonomy order
/// (`ClassificationRules.allergenFindings`; exported as `meatWithDairy` in
/// `allergens.json` for the Python twin). The mammal meats and cuts are
/// alpha-gal's, spread; poultry and the meat dishes are this file's.
const Map<RestrictionId, RestrictionVocabulary> meatWithDairyMeatVocabulary =
    <RestrictionId, RestrictionVocabulary>{
      RestrictionId.kosher: RestrictionVocabulary(
        directEn: <String>[
          ...mammalMeatEn,
          ...mammalOffalCutsEn,
          ..._meatDishesEn,
        ],
        directHe: <String>[...mammalMeatHe, ...mammalCutsHe, ..._meatDishesHe],
        hiddenEn: _meatHiddenEn,
        hiddenHe: _meatHiddenHe,
        guards: mammalMeatGuards,
        termGuards: _meatTermGuards,
        noPrefixHe: <String>[...mammalMeatNoPrefixHe, 'בשר', 'ציר'],
        sources: <String>['11 §24.5', '12 §9.3'],
      ),
    };

// --- Components, for the waiter questions ---------------------------------

/// One component of a religious restriction: what a waiter question names
/// ("pork", "alcohol") and the words that are it, keyed by
/// [RestrictionId.kosher] for the matcher (`WaiterQuestions` re-reads a
/// concern's matched words against each in turn).
typedef ReligiousComponent = ({
  String subjectEn,
  String subjectHe,
  Map<RestrictionId, RestrictionVocabulary> vocabulary,
});

/// The components, in the order a question looks for them: the first that
/// matches a concern's words names its subject.
const List<ReligiousComponent> religiousComponents = <ReligiousComponent>[
  (
    subjectEn: 'pork',
    subjectHe: 'חזיר',
    vocabulary: <RestrictionId, RestrictionVocabulary>{
      RestrictionId.kosher: RestrictionVocabulary(
        directEn: _porkEn,
        directHe: _porkHe,
        hiddenEn: _porkHiddenEn,
        hiddenHe: _porkHiddenHe,
        noPrefixHe: <String>['חזיר'],
      ),
    },
  ),
  (
    subjectEn: 'shellfish',
    subjectHe: 'פירות ים',
    vocabulary: <RestrictionId, RestrictionVocabulary>{
      RestrictionId.kosher: RestrictionVocabulary(
        directEn: <String>[
          ...crustaceanNamesEn,
          ...molluscNamesEn,
          ...shellfishNamesEn,
        ],
        directHe: <String>[
          ...crustaceanNamesHe,
          ...molluscNamesHe,
          ...shellfishNamesHe,
        ],
        hiddenEn: <HiddenTrigger>[...shrimpPastesEn, ...molluscSaucesEn],
        hiddenHe: molluscSaucesHe,
      ),
    },
  ),
  (
    subjectEn: 'fish without fins and scales',
    subjectHe: 'דג ללא סנפירים וקשקשים',
    vocabulary: <RestrictionId, RestrictionVocabulary>{
      RestrictionId.kosher: RestrictionVocabulary(
        directEn: _finlessFishEn,
        directHe: _finlessFishHe,
        hiddenEn: _disputedFishEn,
        hiddenHe: _disputedFishHe,
      ),
    },
  ),
  (
    subjectEn: 'rabbit, hare or frog',
    subjectHe: 'ארנב',
    vocabulary: <RestrictionId, RestrictionVocabulary>{
      RestrictionId.kosher: RestrictionVocabulary(
        directEn: _otherAnimalsEn,
        directHe: _otherAnimalsHe,
      ),
    },
  ),
  (
    subjectEn: 'blood',
    subjectHe: 'דם',
    vocabulary: <RestrictionId, RestrictionVocabulary>{
      RestrictionId.kosher: RestrictionVocabulary(
        directEn: _bloodEn,
        directHe: _bloodHe,
      ),
    },
  ),
  (
    subjectEn: 'gelatin',
    subjectHe: "ג'לטין",
    vocabulary: <RestrictionId, RestrictionVocabulary>{
      RestrictionId.kosher: RestrictionVocabulary(
        hiddenEn: _gelatinEn,
        hiddenHe: _gelatinHe,
      ),
    },
  ),
  (
    subjectEn: 'cheese',
    subjectHe: 'גבינה',
    vocabulary: <RestrictionId, RestrictionVocabulary>{
      RestrictionId.kosher: RestrictionVocabulary(
        directEn: _cheeseMeatEn,
        directHe: _cheeseMeatHe,
      ),
    },
  ),
  (
    subjectEn: 'alcohol',
    subjectHe: 'אלכוהול',
    vocabulary: <RestrictionId, RestrictionVocabulary>{
      RestrictionId.kosher: RestrictionVocabulary(
        hiddenEn: alcoholHiddenEn,
        hiddenHe: alcoholHiddenHe,
        noPrefixHe: <String>['רום'],
      ),
    },
  ),
];

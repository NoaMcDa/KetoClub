/// Nuts and seeds: the trigger vocabulary of peanuts, treeNuts and sesame
/// (Banto; ALG-01, issue #343).
///
/// Filled by ALG-01b; the other four groups are filled by their own pull
/// requests.
///
/// Every term comes from
/// `allergen app documentation/11_hidden_allergen_sources.md` or
/// `12_israeli_and_us_menu_lexicon.md` and its source cites the section
/// (`"11 §11"`, `"12 §1.1"`), which
/// `test/utils/allergens/vocabulary_test.dart` checks. After a change,
/// regenerate the goldens and copy `allergens.json` to
/// `backend/app/keto/` (architecture.md D26).
///
/// A guard lowers the hit to `suspected` and never cancels it, and counts
/// only in the slot beside its term (ALG-04a): "no" and "without" just
/// before it, a bare "free" or a "peanut free" just after it. "Nut free"
/// lowers tree nuts and not peanuts (11 §1.3), "peanut free" lowers peanuts
/// and not tree nuts, and a tahini or sesame guard lowers no other
/// restriction. Prefer a `suspected` hidden trigger to
/// silence: the wording floor is "ask the restaurant".
library;

import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/utils/allergens/vocabulary_types.dart';

/// Peanut's direct English triggers. Public because `legumes`
/// (vocab_plants_additives.dart) spreads them: a peanut is a legume.
const List<String> peanutDirectEn = <String>[
  'peanut',
  'peanuts',
  'groundnut',
  'groundnuts',
  'monkey nut',
  'monkey nuts',
  'arachis',
  'bamba',
];

/// Peanut's direct Hebrew triggers; see [peanutDirectEn].
const List<String> peanutDirectHe = <String>[
  'בוטנים',
  'בוטן',
  'אגוזי אדמה',
  'אגוז אדמה',
  'במבה',
];

/// Peanut's hidden English sources. Public because `legumes`
/// (vocab_plants_additives.dart) spreads them: a peanut is a legume.
const List<HiddenTrigger> peanutHiddenEn = <HiddenTrigger>[
  // Satay, and the Asian dishes and sauces FARE and Anaphylaxis UK name
  // as common hiding places.
  HiddenTrigger(
    term: 'satay',
    certainty: TriggerCertainty.likely,
    source: '11 §1.2',
  ),
  HiddenTrigger(
    term: 'kung pao',
    certainty: TriggerCertainty.likely,
    source: '11 §1.2',
  ),
  HiddenTrigger(
    term: 'massaman',
    certainty: TriggerCertainty.likely,
    source: '11 §1.2',
  ),
  HiddenTrigger(
    term: 'egg roll',
    certainty: TriggerCertainty.likely,
    source: '11 §1.2',
  ),
  HiddenTrigger(
    term: 'egg rolls',
    certainty: TriggerCertainty.likely,
    source: '11 §1.2',
  ),
  // Cuisines and sauces where peanut sits unannounced; a menu rarely
  // says.
  HiddenTrigger(
    term: 'pad thai',
    certainty: TriggerCertainty.suspected,
    source: '11 §1.2',
  ),
  HiddenTrigger(
    term: 'spring roll',
    certainty: TriggerCertainty.suspected,
    source: '11 §1.2',
  ),
  HiddenTrigger(
    term: 'spring rolls',
    certainty: TriggerCertainty.suspected,
    source: '11 §1.2',
  ),
  HiddenTrigger(
    term: 'lo mein',
    certainty: TriggerCertainty.suspected,
    source: '11 §1.2',
  ),
  HiddenTrigger(
    term: 'curry',
    certainty: TriggerCertainty.suspected,
    source: '11 §1.2',
  ),
  HiddenTrigger(
    term: 'curries',
    certainty: TriggerCertainty.suspected,
    source: '11 §1.2',
  ),
  HiddenTrigger(
    term: 'stir fry',
    certainty: TriggerCertainty.suspected,
    source: '11 §1.2',
  ),
  HiddenTrigger(
    term: 'asian',
    certainty: TriggerCertainty.suspected,
    source: '11 §1.2',
  ),
  HiddenTrigger(
    term: 'chili sauce',
    certainty: TriggerCertainty.suspected,
    source: '11 §1.2',
  ),
  HiddenTrigger(
    term: 'chilli sauce',
    certainty: TriggerCertainty.suspected,
    source: '11 §1.2',
  ),
  HiddenTrigger(
    term: 'hot sauce',
    certainty: TriggerCertainty.suspected,
    source: '11 §1.2',
  ),
  HiddenTrigger(
    term: 'gochujang',
    certainty: TriggerCertainty.suspected,
    source: '11 §1.2',
  ),
  HiddenTrigger(
    term: 'mole',
    certainty: TriggerCertainty.suspected,
    source: '11 §1.2',
  ),
  HiddenTrigger(
    term: 'enchilada sauce',
    certainty: TriggerCertainty.suspected,
    source: '11 §1.2',
  ),
  HiddenTrigger(
    term: 'pesto',
    certainty: TriggerCertainty.suspected,
    source: '11 §1.2',
  ),
  HiddenTrigger(
    term: 'granola',
    certainty: TriggerCertainty.suspected,
    source: '11 §1.2',
  ),
  HiddenTrigger(
    term: 'trail mix',
    certainty: TriggerCertainty.suspected,
    source: '11 §1.2',
  ),
  HiddenTrigger(
    term: 'nut butter',
    certainty: TriggerCertainty.suspected,
    source: '11 §1.2',
  ),
  // A bare "nuts" is tree nuts first and peanut when it is loose (12
  // §1.2).
  HiddenTrigger(
    term: 'nuts',
    certainty: TriggerCertainty.suspected,
    source: '12 §1.2',
  ),
  // Recall-gate additions (issue #352): chili, where peanut
  // butter is a thickener (11 §1.2).
  HiddenTrigger(
    term: 'chili con carne',
    certainty: TriggerCertainty.suspected,
    source: '11 §1.2',
  ),
  HiddenTrigger(
    term: 'chilli con carne',
    certainty: TriggerCertainty.suspected,
    source: '11 §1.2',
  ),
  HiddenTrigger(
    term: 'texas chili',
    certainty: TriggerCertainty.suspected,
    source: '11 §1.2',
  ),
  HiddenTrigger(
    term: 'chili dog',
    certainty: TriggerCertainty.suspected,
    source: '11 §1.2',
  ),
  HiddenTrigger(
    term: 'chili cheese',
    certainty: TriggerCertainty.suspected,
    source: '11 §1.2',
  ),
];

/// Peanut's hidden Hebrew sources; see [peanutHiddenEn].
const List<HiddenTrigger> peanutHiddenHe = <HiddenTrigger>[
  // Satay and the Asian dishes (11 §1.2); "אגרול" is the egg roll.
  HiddenTrigger(
    term: 'סאטה',
    certainty: TriggerCertainty.likely,
    source: '11 §1.2',
  ),
  HiddenTrigger(
    term: 'אגרול',
    certainty: TriggerCertainty.likely,
    source: '11 §1.2',
  ),
  HiddenTrigger(
    term: 'קונג פאו',
    certainty: TriggerCertainty.likely,
    source: '11 §1.2',
  ),
  // Sauces and dishes where peanut hides unannounced.
  HiddenTrigger(
    term: 'פאד תאי',
    certainty: TriggerCertainty.suspected,
    source: '11 §1.2',
  ),
  HiddenTrigger(
    term: 'פד תאי',
    certainty: TriggerCertainty.suspected,
    source: '11 §1.2',
  ),
  HiddenTrigger(
    term: 'ספרינג רול',
    certainty: TriggerCertainty.suspected,
    source: '11 §1.2',
  ),
  HiddenTrigger(
    term: 'קארי',
    certainty: TriggerCertainty.suspected,
    source: '11 §1.2',
  ),
  HiddenTrigger(
    term: 'קרי',
    certainty: TriggerCertainty.suspected,
    source: '11 §1.2',
  ),
  HiddenTrigger(
    term: 'אסייתי',
    certainty: TriggerCertainty.suspected,
    source: '11 §1.2',
  ),
  HiddenTrigger(
    term: 'רוטב צילי',
    certainty: TriggerCertainty.suspected,
    source: '11 §1.2',
  ),
  HiddenTrigger(
    term: 'פסטו',
    certainty: TriggerCertainty.suspected,
    source: '11 §1.2',
  ),
  HiddenTrigger(
    term: 'גרנולה',
    certainty: TriggerCertainty.suspected,
    source: '11 §1.2',
  ),
  // A bare "אגוזים" on an Israeli menu: tree nuts first, peanut
  // unknown, so ask.
  HiddenTrigger(
    term: 'אגוזים',
    certainty: TriggerCertainty.suspected,
    source: '12 §1.2',
  ),
  HiddenTrigger(
    term: 'צ׳ילי קון קרנה',
    certainty: TriggerCertainty.suspected,
    source: '11 §1.2',
  ),
];

/// Tree nuts' direct English triggers (11 §2.1). Public because the
/// diets that leave out nuts (`vocab_diets_extra.dart`) spread them.
const List<String> treeNutsDirectEn = <String>[
  'tree nut',
  'tree nuts',
  'almond',
  'almonds',
  'hazelnut',
  'hazelnuts',
  'filbert',
  'filberts',
  'walnut',
  'walnuts',
  'cashew',
  'cashews',
  'pecan',
  'pecans',
  'pistachio',
  'pistachios',
  'macadamia',
  'macadamias',
  'queensland nut',
  'brazil nut',
  'brazil nuts',
  'pine nut',
  'pine nuts',
  'pine kernel',
  'pine kernels',
  'pignoli',
  'pili nut',
  'pili nuts',
  'marzipan',
  'praline',
  'pralines',
  'frangipane',
  'gianduja',
];

/// [treeNutsDirectEn] in Hebrew (12 §1.2).
const List<String> treeNutsDirectHe = <String>[
  'שקדים',
  'שקד',
  'לוז',
  'אגוזי מלך',
  'אגוז מלך',
  'פקאן',
  'קשיו',
  'פיסטוק',
  'פיסטוקים',
  'אגוזי ברזיל',
  'אגוז ברזיל',
  'מקדמיה',
  'צנוברים',
  'צנובר',
  'אגוזי עץ',
  'מרציפן',
  'פרלין',
  'פראלין',
];

/// Sesame's direct English triggers (11 §11.1). Public because the diets
/// that leave out seeds (`vocab_diets_extra.dart`) spread them.
const List<String> sesameDirectEn = <String>[
  'sesame',
  'tahini',
  'tahina',
  'tehina',
  'techina',
  'halva',
  'halvah',
  'helva',
  'benne',
  'gingelly',
  'gomasio',
  'sesamol',
  'sesamum',
];

/// [sesameDirectEn] in Hebrew (12 §1.1).
const List<String> sesameDirectHe = <String>[
  'שומשום',
  'שומשומים',
  'שומשומין',
  'סומסום',
  'סומסומים',
  'סומסומין',
  'טחינה',
  'טחינא',
  'טחינת',
  'חלבה',
  'חלווה',
];

/// Nuts and seeds: one entry per restriction this group owns.
const Map<RestrictionId, RestrictionVocabulary>
nutsSeedsVocabulary = <RestrictionId, RestrictionVocabulary>{
  RestrictionId.peanuts: RestrictionVocabulary(
    directEn: peanutDirectEn,
    directHe: peanutDirectHe,
    hiddenEn: peanutHiddenEn,
    hiddenHe: peanutHiddenHe,
    guards: AllergenGuards(
      beforeEn: <String>['no', 'without', 'peanut free', 'free from'],
      afterEn: <String>['free', 'peanut free', 'no peanuts', 'without peanuts'],
      beforeHe: <String>['ללא', 'בלי', 'וללא', 'ובלי'],
      afterHe: <String>['ללא בוטנים', 'בלי בוטנים'],
    ),
    sources: <String>['11 §1.1', '11 §1.3', '11 §1.5', '12 §1.2'],
  ),
  RestrictionId.treeNuts: RestrictionVocabulary(
    directEn: treeNutsDirectEn,
    directHe: treeNutsDirectHe,
    hiddenEn: <HiddenTrigger>[
      // A bare "nuts" and the unnamed nut products 11 §2.2 lists.
      HiddenTrigger(
        term: 'nuts',
        certainty: TriggerCertainty.likely,
        source: '11 §2.2',
      ),
      HiddenTrigger(
        term: 'nut butter',
        certainty: TriggerCertainty.likely,
        source: '11 §2.2',
      ),
      HiddenTrigger(
        term: 'nut milk',
        certainty: TriggerCertainty.likely,
        source: '11 §2.2',
      ),
      HiddenTrigger(
        term: 'nut oil',
        certainty: TriggerCertainty.likely,
        source: '11 §2.2',
      ),
      HiddenTrigger(
        term: 'nut paste',
        certainty: TriggerCertainty.likely,
        source: '11 §2.2',
      ),
      HiddenTrigger(
        term: 'nut flour',
        certainty: TriggerCertainty.likely,
        source: '11 §2.2',
      ),
      HiddenTrigger(
        term: 'nut meal',
        certainty: TriggerCertainty.likely,
        source: '11 §2.2',
      ),
      HiddenTrigger(
        term: 'nut extract',
        certainty: TriggerCertainty.likely,
        source: '11 §2.2',
      ),
      // Pesto is pine nuts or walnuts.
      HiddenTrigger(
        term: 'pesto',
        certainty: TriggerCertainty.likely,
        source: '11 §2.2',
      ),
      // Sweets whose usual filling or topping is a nut.
      HiddenTrigger(
        term: 'baklava',
        certainty: TriggerCertainty.likely,
        source: '12 §1.2',
      ),
      HiddenTrigger(
        term: 'kadaif',
        certainty: TriggerCertainty.likely,
        source: '12 §1.2',
      ),
      HiddenTrigger(
        term: 'kataifi',
        certainty: TriggerCertainty.likely,
        source: '12 §1.2',
      ),
      HiddenTrigger(
        term: 'kadayif',
        certainty: TriggerCertainty.likely,
        source: '12 §1.2',
      ),
      HiddenTrigger(
        term: 'nougat',
        certainty: TriggerCertainty.likely,
        source: '12 §1.2',
      ),
      HiddenTrigger(
        term: 'nutella',
        certainty: TriggerCertainty.likely,
        source: '12 §1.2',
      ),
      HiddenTrigger(
        term: 'charoset',
        certainty: TriggerCertainty.likely,
        source: '12 §1.2',
      ),
      HiddenTrigger(
        term: 'haroset',
        certainty: TriggerCertainty.likely,
        source: '12 §1.2',
      ),
      // Almond flavourings and cookies.
      HiddenTrigger(
        term: 'amaretti',
        certainty: TriggerCertainty.likely,
        source: '11 §2.2',
      ),
      HiddenTrigger(
        term: 'orgeat',
        certainty: TriggerCertainty.likely,
        source: '11 §2.2',
      ),
      // Cuisines and sweets that often carry a nut unannounced.
      HiddenTrigger(
        term: 'amaretto',
        certainty: TriggerCertainty.suspected,
        source: '11 §2.2',
      ),
      HiddenTrigger(
        term: 'curry',
        certainty: TriggerCertainty.suspected,
        source: '11 §2.2',
      ),
      HiddenTrigger(
        term: 'curries',
        certainty: TriggerCertainty.suspected,
        source: '11 §2.2',
      ),
      HiddenTrigger(
        term: 'korma',
        certainty: TriggerCertainty.suspected,
        source: '11 §2.2',
      ),
      HiddenTrigger(
        term: 'satay',
        certainty: TriggerCertainty.suspected,
        source: '11 §2.2',
      ),
      // Cereals and snack mixes (11 §1.2).
      HiddenTrigger(
        term: 'granola',
        certainty: TriggerCertainty.suspected,
        source: '11 §1.2',
      ),
      HiddenTrigger(
        term: 'trail mix',
        certainty: TriggerCertainty.suspected,
        source: '11 §1.2',
      ),
      // Italian pastry and charcuterie with hazelnut or pistachio.
      HiddenTrigger(
        term: 'cannoli',
        certainty: TriggerCertainty.suspected,
        source: '12 §5',
      ),
      HiddenTrigger(
        term: 'mortadella',
        certainty: TriggerCertainty.suspected,
        source: '12 §5',
      ),
      // Chestnut: a tree nut for FARE, not for the EU list, Anaphylaxis UK
      // or the FDA since 2025, and allergy to it is unusual, so a
      // low-confidence trigger with a jurisdiction note (11 §2.5, §27.5).
      // A water chestnut is an aquatic vegetable, lowered by its term
      // guard.
      HiddenTrigger(
        term: 'chestnut',
        certainty: TriggerCertainty.suspected,
        source: '11 §2.5',
      ),
      HiddenTrigger(
        term: 'chestnuts',
        certainty: TriggerCertainty.suspected,
        source: '11 §2.5',
      ),
      HiddenTrigger(
        term: 'marrons glaces',
        certainty: TriggerCertainty.suspected,
        source: '11 §27.5',
      ),
      HiddenTrigger(
        term: 'marron glace',
        certainty: TriggerCertainty.suspected,
        source: '11 §27.5',
      ),
    ],
    hiddenHe: <HiddenTrigger>[
      // A bare "אגוזים" on an Israeli menu is tree nuts first (12 §1.2);
      // the peanut side is in the peanuts entry.
      HiddenTrigger(
        term: 'אגוזים',
        certainty: TriggerCertainty.likely,
        source: '12 §1.2',
      ),
      HiddenTrigger(
        term: 'במבה במילוי',
        certainty: TriggerCertainty.likely,
        source: '12 §1.2',
      ),
      // Pesto is pine nuts or walnuts.
      HiddenTrigger(
        term: 'פסטו',
        certainty: TriggerCertainty.likely,
        source: '11 §2.2',
      ),
      // Sweets whose usual filling or topping is a nut.
      HiddenTrigger(
        term: 'בקלאווה',
        certainty: TriggerCertainty.likely,
        source: '12 §1.2',
      ),
      HiddenTrigger(
        term: 'באקלאווה',
        certainty: TriggerCertainty.likely,
        source: '12 §1.2',
      ),
      HiddenTrigger(
        term: 'קדאיף',
        certainty: TriggerCertainty.likely,
        source: '12 §1.2',
      ),
      HiddenTrigger(
        term: 'חרוסת',
        certainty: TriggerCertainty.likely,
        source: '12 §1.2',
      ),
      HiddenTrigger(
        term: 'נוגט',
        certainty: TriggerCertainty.likely,
        source: '12 §1.2',
      ),
      HiddenTrigger(
        term: 'נוטלה',
        certainty: TriggerCertainty.likely,
        source: '12 §1.2',
      ),
      // Almond liqueur biscuits.
      HiddenTrigger(
        term: 'אמרטי',
        certainty: TriggerCertainty.likely,
        source: '11 §2.2',
      ),
      // Cuisines and sweets that often carry a nut unannounced.
      HiddenTrigger(
        term: 'קארי',
        certainty: TriggerCertainty.suspected,
        source: '11 §2.2',
      ),
      HiddenTrigger(
        term: 'קרי',
        certainty: TriggerCertainty.suspected,
        source: '11 §2.2',
      ),
      HiddenTrigger(
        term: 'סאטה',
        certainty: TriggerCertainty.suspected,
        source: '11 §2.2',
      ),
      HiddenTrigger(
        term: 'אמרטו',
        certainty: TriggerCertainty.suspected,
        source: '11 §2.2',
      ),
      // Cereals (11 §1.2).
      HiddenTrigger(
        term: 'גרנולה',
        certainty: TriggerCertainty.suspected,
        source: '11 §1.2',
      ),
      // Italian pastry and charcuterie with hazelnut or pistachio.
      HiddenTrigger(
        term: 'קנולי',
        certainty: TriggerCertainty.suspected,
        source: '12 §5',
      ),
      HiddenTrigger(
        term: 'מורטדלה',
        certainty: TriggerCertainty.suspected,
        source: '12 §5',
      ),
      // Chestnut (11 §2.5; 12 §11.4). The construct form ערמוני is not a
      // term, so "ערמוני מים" (water chestnuts) never reads as one.
      HiddenTrigger(
        term: 'ערמונים',
        certainty: TriggerCertainty.suspected,
        source: '12 §11.4',
      ),
      HiddenTrigger(
        term: 'ערמון',
        certainty: TriggerCertainty.suspected,
        source: '12 §11.4',
      ),
    ],
    guards: AllergenGuards(
      beforeEn: <String>[
        'no',
        'without',
        'nut free',
        'tree nut free',
        'free from',
      ],
      afterEn: <String>[
        'free',
        'nut free',
        'tree nut free',
        'no nuts',
        'without nuts',
      ],
      beforeHe: <String>['ללא', 'בלי', 'וללא', 'ובלי'],
      afterHe: <String>['ללא אגוזים', 'בלי אגוזים'],
    ),
    termGuards: <String, AllergenGuards>{
      'chestnut': AllergenGuards(beforeEn: <String>['water']),
      'chestnuts': AllergenGuards(beforeEn: <String>['water']),
      'ערמונים': AllergenGuards(afterHe: <String>['מים']),
      'ערמון': AllergenGuards(afterHe: <String>['מים']),
    },
    sources: <String>['11 §2.1', '11 §2.3', '11 §2.5', '12 §1.2'],
  ),
  RestrictionId.sesame: RestrictionVocabulary(
    directEn: sesameDirectEn,
    directHe: sesameDirectHe,
    hiddenEn: <HiddenTrigger>[
      // Hummus, baba ghanoush, bourekas, sabich and za'atar: the dishes
      // that carry sesame without saying so.
      HiddenTrigger(
        term: 'hummus',
        certainty: TriggerCertainty.likely,
        source: '11 §11.1',
      ),
      HiddenTrigger(
        term: 'houmous',
        certainty: TriggerCertainty.likely,
        source: '11 §11.1',
      ),
      HiddenTrigger(
        term: 'humus',
        certainty: TriggerCertainty.likely,
        source: '11 §11.1',
      ),
      HiddenTrigger(
        term: 'hommus',
        certainty: TriggerCertainty.likely,
        source: '11 §11.1',
      ),
      HiddenTrigger(
        term: 'hommos',
        certainty: TriggerCertainty.likely,
        source: '11 §11.1',
      ),
      HiddenTrigger(
        term: 'baba ghanoush',
        certainty: TriggerCertainty.likely,
        source: '11 §11.1',
      ),
      HiddenTrigger(
        term: 'baba ganoush',
        certainty: TriggerCertainty.likely,
        source: '11 §11.1',
      ),
      HiddenTrigger(
        term: 'baba ghanouj',
        certainty: TriggerCertainty.likely,
        source: '11 §11.1',
      ),
      HiddenTrigger(
        term: "za'atar",
        certainty: TriggerCertainty.likely,
        source: '11 §11.1',
      ),
      HiddenTrigger(
        term: 'za atar',
        certainty: TriggerCertainty.likely,
        source: '11 §11.1',
      ),
      HiddenTrigger(
        term: 'zatar',
        certainty: TriggerCertainty.likely,
        source: '11 §11.1',
      ),
      HiddenTrigger(
        term: 'zahtar',
        certainty: TriggerCertainty.likely,
        source: '11 §11.1',
      ),
      // Israeli menu items that carry sesame (12 §1.1).
      HiddenTrigger(
        term: 'bourekas',
        certainty: TriggerCertainty.likely,
        source: '12 §1.1',
      ),
      HiddenTrigger(
        term: 'burekas',
        certainty: TriggerCertainty.likely,
        source: '12 §1.1',
      ),
      HiddenTrigger(
        term: 'borekas',
        certainty: TriggerCertainty.likely,
        source: '12 §1.1',
      ),
      HiddenTrigger(
        term: 'boureka',
        certainty: TriggerCertainty.likely,
        source: '12 §1.1',
      ),
      HiddenTrigger(
        term: 'bureka',
        certainty: TriggerCertainty.likely,
        source: '12 §1.1',
      ),
      HiddenTrigger(
        term: 'sabich',
        certainty: TriggerCertainty.likely,
        source: '12 §1.1',
      ),
      HiddenTrigger(
        term: 'sabih',
        certainty: TriggerCertainty.likely,
        source: '12 §1.1',
      ),
      HiddenTrigger(
        term: 'jerusalem bagel',
        certainty: TriggerCertainty.likely,
        source: '12 §1.1',
      ),
      // Falafel (sesame in many batters), buns, pretzels and bread seeds.
      HiddenTrigger(
        term: 'falafel',
        certainty: TriggerCertainty.suspected,
        source: '12 §1.1',
      ),
      HiddenTrigger(
        term: 'felafel',
        certainty: TriggerCertainty.suspected,
        source: '12 §1.1',
      ),
      HiddenTrigger(
        term: 'pretzel',
        certainty: TriggerCertainty.suspected,
        source: '12 §1.1',
      ),
      HiddenTrigger(
        term: 'pretzels',
        certainty: TriggerCertainty.suspected,
        source: '12 §1.1',
      ),
      HiddenTrigger(
        term: 'pita',
        certainty: TriggerCertainty.suspected,
        source: '12 §1.1',
      ),
      HiddenTrigger(
        term: 'pitta',
        certainty: TriggerCertainty.suspected,
        source: '12 §1.1',
      ),
      HiddenTrigger(
        term: 'eggplant salad',
        certainty: TriggerCertainty.suspected,
        source: '12 §1.1',
      ),
      HiddenTrigger(
        term: 'aubergine salad',
        certainty: TriggerCertainty.suspected,
        source: '12 §1.1',
      ),
      // Burger buns, breadsticks, crackers, veggie burgers, seeds in dough,
      // stir-fry oils and "natural flavors" (11 §11.2).
      HiddenTrigger(
        term: 'burger bun',
        certainty: TriggerCertainty.suspected,
        source: '11 §11.2',
      ),
      HiddenTrigger(
        term: 'burger buns',
        certainty: TriggerCertainty.suspected,
        source: '11 §11.2',
      ),
      HiddenTrigger(
        term: 'hamburger bun',
        certainty: TriggerCertainty.suspected,
        source: '11 §11.2',
      ),
      HiddenTrigger(
        term: 'hamburger buns',
        certainty: TriggerCertainty.suspected,
        source: '11 §11.2',
      ),
      HiddenTrigger(
        term: 'hot dog bun',
        certainty: TriggerCertainty.suspected,
        source: '11 §11.2',
      ),
      HiddenTrigger(
        term: 'bun',
        certainty: TriggerCertainty.suspected,
        source: '11 §11.2',
      ),
      HiddenTrigger(
        term: 'buns',
        certainty: TriggerCertainty.suspected,
        source: '11 §11.2',
      ),
      HiddenTrigger(
        term: 'breadsticks',
        certainty: TriggerCertainty.suspected,
        source: '11 §11.2',
      ),
      HiddenTrigger(
        term: 'crackers',
        certainty: TriggerCertainty.suspected,
        source: '11 §11.2',
      ),
      HiddenTrigger(
        term: 'veggie burger',
        certainty: TriggerCertainty.suspected,
        source: '11 §11.2',
      ),
      HiddenTrigger(
        term: 'everything bagel',
        certainty: TriggerCertainty.suspected,
        source: '11 §11.2',
      ),
      HiddenTrigger(
        term: 'seeded',
        certainty: TriggerCertainty.suspected,
        source: '11 §11.2',
      ),
      HiddenTrigger(
        term: 'multi seed',
        certainty: TriggerCertainty.suspected,
        source: '11 §11.2',
      ),
      HiddenTrigger(
        term: 'mixed seeds',
        certainty: TriggerCertainty.suspected,
        source: '11 §11.2',
      ),
      HiddenTrigger(
        term: 'stir fry',
        certainty: TriggerCertainty.suspected,
        source: '11 §11.2',
      ),
      HiddenTrigger(
        term: 'stir fried',
        certainty: TriggerCertainty.suspected,
        source: '11 §11.2',
      ),
      HiddenTrigger(
        term: 'asian',
        certainty: TriggerCertainty.suspected,
        source: '11 §11.2',
      ),
      HiddenTrigger(
        term: 'natural flavor',
        certainty: TriggerCertainty.suspected,
        source: '11 §11.2',
      ),
      HiddenTrigger(
        term: 'natural flavors',
        certainty: TriggerCertainty.suspected,
        source: '11 §11.2',
      ),
      HiddenTrigger(
        term: 'natural flavour',
        certainty: TriggerCertainty.suspected,
        source: '11 §11.2',
      ),
      HiddenTrigger(
        term: 'natural flavours',
        certainty: TriggerCertainty.suspected,
        source: '11 §11.2',
      ),
      HiddenTrigger(
        term: 'spices',
        certainty: TriggerCertainty.suspected,
        source: '11 §11.2',
      ),
      HiddenTrigger(
        term: 'spice mix',
        certainty: TriggerCertainty.suspected,
        source: '11 §11.2',
      ),
      HiddenTrigger(
        term: 'spice blend',
        certainty: TriggerCertainty.suspected,
        source: '11 §11.2',
      ),
      // Sesame oil and paste in Asian-style dishes (12 §5).
      HiddenTrigger(
        term: 'hoisin',
        certainty: TriggerCertainty.likely,
        source: '12 §5',
      ),
      HiddenTrigger(
        term: 'spicy tuna',
        certainty: TriggerCertainty.suspected,
        source: '12 §5',
      ),
      HiddenTrigger(
        term: 'sushi',
        certainty: TriggerCertainty.suspected,
        source: '12 §5',
      ),
      HiddenTrigger(
        term: 'pad thai',
        certainty: TriggerCertainty.suspected,
        source: '12 §5',
      ),
      // Recall-gate additions (issue #352): bread classes and
      // the Asian dishes Anaphylaxis UK names (11 §11.2).
      HiddenTrigger(
        term: 'bread',
        certainty: TriggerCertainty.suspected,
        source: '11 §11.2',
      ),
      HiddenTrigger(
        term: 'roll',
        certainty: TriggerCertainty.suspected,
        source: '11 §11.2',
      ),
      HiddenTrigger(
        term: 'rolls',
        certainty: TriggerCertainty.suspected,
        source: '11 §11.2',
      ),
      HiddenTrigger(
        term: 'fried rice',
        certainty: TriggerCertainty.suspected,
        source: '11 §11.2',
      ),
      HiddenTrigger(
        term: 'fortune cookie',
        certainty: TriggerCertainty.suspected,
        source: '11 §11.2',
      ),
      HiddenTrigger(
        term: 'fortune cookies',
        certainty: TriggerCertainty.suspected,
        source: '11 §11.2',
      ),
      HiddenTrigger(
        term: 'kung pao',
        certainty: TriggerCertainty.suspected,
        source: '11 §11.2',
      ),
      HiddenTrigger(
        // Written without the apostrophe: the normaliser deletes it, so
        // "General Tso's" reads "general tsos".
        term: 'general tsos',
        certainty: TriggerCertainty.suspected,
        source: '11 §11.2',
      ),
      HiddenTrigger(
        term: 'dumpling',
        certainty: TriggerCertainty.suspected,
        source: '11 §11.2',
      ),
      HiddenTrigger(
        term: 'dumplings',
        certainty: TriggerCertainty.suspected,
        source: '11 §11.2',
      ),
      HiddenTrigger(
        term: 'cheeseburger',
        certainty: TriggerCertainty.suspected,
        source: '11 §11.2',
      ),
      HiddenTrigger(
        term: 'hamburger',
        certainty: TriggerCertainty.suspected,
        source: '11 §11.2',
      ),
      HiddenTrigger(
        term: 'focaccia',
        certainty: TriggerCertainty.suspected,
        source: '11 §11.2',
      ),
      HiddenTrigger(
        term: 'teriyaki',
        certainty: TriggerCertainty.suspected,
        source: '12 §5',
      ),
      HiddenTrigger(
        term: 'gyoza',
        certainty: TriggerCertainty.suspected,
        source: '12 §5',
      ),
      HiddenTrigger(
        term: 'udon',
        certainty: TriggerCertainty.suspected,
        source: '12 §5',
      ),
      HiddenTrigger(
        term: 'tempura roll',
        certainty: TriggerCertainty.suspected,
        source: '12 §5',
      ),
    ],
    hiddenHe: <HiddenTrigger>[
      // Hummus, bourekas, sabich, za'atar and baba ghanoush: sesame even
      // when the menu names only the chickpeas, the pastry or the eggplant.
      HiddenTrigger(
        term: 'חומוס',
        certainty: TriggerCertainty.likely,
        source: '12 §1.1',
      ),
      HiddenTrigger(
        term: 'חומס',
        certainty: TriggerCertainty.likely,
        source: '12 §1.1',
      ),
      HiddenTrigger(
        term: 'בורקס',
        certainty: TriggerCertainty.likely,
        source: '12 §1.1',
      ),
      HiddenTrigger(
        term: 'בורקסים',
        certainty: TriggerCertainty.likely,
        source: '12 §1.1',
      ),
      HiddenTrigger(
        term: 'בורקאס',
        certainty: TriggerCertainty.likely,
        source: '12 §1.1',
      ),
      HiddenTrigger(
        term: 'סביח',
        certainty: TriggerCertainty.likely,
        source: '12 §1.1',
      ),
      HiddenTrigger(
        term: 'בייגל ירושלמי',
        certainty: TriggerCertainty.likely,
        source: '12 §1.1',
      ),
      HiddenTrigger(
        term: 'באבא גנוש',
        certainty: TriggerCertainty.likely,
        source: '12 §1.1',
      ),
      // Za'atar (11 §11.1, inferred).
      HiddenTrigger(
        term: 'זעתר',
        certainty: TriggerCertainty.likely,
        source: '11 §11.1',
      ),
      // Falafel, rolls, pretzels, eggplant salad, filled Bamba and "Asian"
      // dishes (12 §1.1).
      HiddenTrigger(
        term: 'פלאפל',
        certainty: TriggerCertainty.suspected,
        source: '12 §1.1',
      ),
      HiddenTrigger(
        term: 'לחמנייה',
        certainty: TriggerCertainty.suspected,
        source: '12 §1.1',
      ),
      HiddenTrigger(
        term: 'לחמניה',
        certainty: TriggerCertainty.suspected,
        source: '12 §1.1',
      ),
      HiddenTrigger(
        term: 'לחמניות',
        certainty: TriggerCertainty.suspected,
        source: '12 §1.1',
      ),
      HiddenTrigger(
        term: 'לחמנייות',
        certainty: TriggerCertainty.suspected,
        source: '12 §1.1',
      ),
      HiddenTrigger(
        term: 'פיתה',
        certainty: TriggerCertainty.suspected,
        source: '12 §1.1',
      ),
      HiddenTrigger(
        term: 'פיתות',
        certainty: TriggerCertainty.suspected,
        source: '12 §1.1',
      ),
      HiddenTrigger(
        term: 'בייגלה',
        certainty: TriggerCertainty.suspected,
        source: '12 §1.1',
      ),
      HiddenTrigger(
        term: 'סלט חצילים',
        certainty: TriggerCertainty.suspected,
        source: '12 §1.1',
      ),
      HiddenTrigger(
        term: 'אסייתי',
        certainty: TriggerCertainty.suspected,
        source: '12 §1.1',
      ),
      HiddenTrigger(
        term: 'במבה במילוי',
        certainty: TriggerCertainty.suspected,
        source: '12 §1.1',
      ),
      // Breadsticks and crackers (11 §11.2).
      HiddenTrigger(
        term: 'קרקרים',
        certainty: TriggerCertainty.suspected,
        source: '11 §11.2',
      ),
      HiddenTrigger(
        term: 'מקלות לחם',
        certainty: TriggerCertainty.suspected,
        source: '11 §11.2',
      ),
      HiddenTrigger(
        term: 'לחם',
        certainty: TriggerCertainty.suspected,
        source: '12 §1.1',
      ),
      HiddenTrigger(
        term: 'לחמניית',
        certainty: TriggerCertainty.suspected,
        source: '12 §1.1',
      ),
      HiddenTrigger(
        term: 'פוקאצ׳ה',
        certainty: TriggerCertainty.suspected,
        source: '12 §1.1',
      ),
      HiddenTrigger(
        term: 'ג׳חנון',
        certainty: TriggerCertainty.suspected,
        source: '12 §1.1',
      ),
      HiddenTrigger(
        term: 'טריאקי',
        certainty: TriggerCertainty.suspected,
        source: '12 §5',
      ),
      HiddenTrigger(
        term: 'גיוזה',
        certainty: TriggerCertainty.suspected,
        source: '12 §5',
      ),
      HiddenTrigger(
        term: 'אודון',
        certainty: TriggerCertainty.suspected,
        source: '12 §5',
      ),
      HiddenTrigger(
        term: 'רול טמפורה',
        certainty: TriggerCertainty.suspected,
        source: '12 §5',
      ),
      HiddenTrigger(
        term: 'אורז מטוגן',
        certainty: TriggerCertainty.suspected,
        source: '12 §5',
      ),
    ],
    guards: AllergenGuards(
      beforeEn: <String>[
        'no',
        'without',
        'sesame free',
        'tahini free',
        'free from',
      ],
      afterEn: <String>[
        'free',
        'sesame free',
        'tahini free',
        'no sesame',
        'no tahini',
        'without sesame',
        'without tahini',
      ],
      beforeHe: <String>['ללא', 'בלי', 'וללא', 'ובלי'],
      afterHe: <String>['ללא טחינה', 'בלי טחינה', 'ללא שומשום', 'בלי שומשום'],
    ),
    sources: <String>['11 §11.1', '11 §11.3', '12 §1.1'],
  ),
};

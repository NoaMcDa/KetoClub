/// Diets extra: the trigger vocabulary of the pescatarian, paleo,
/// Whole30, AIP and Jain diets (Banto; issue #342; file 11 §30, file 12
/// §14).
///
/// Each is flexible (a lifestyle diet, or for Jain a religious component):
/// a hit means "the text names something this diet leaves out", never a
/// safety claim. Under the #346 rule (architecture.md D26) a `stated` or
/// `likely` hit moves the dish to "avoid" or "with a change", and a
/// `suspected` one is only listed, so the lists below keep `likely` for
/// what a source says the dish usually holds and `suspected` for the rest
/// (refined sugar, seed oils, mushrooms for Jain, stock and broth).
///
/// **Mostly reuse.** These diets are exclusion sets of things other
/// vocabularies already know, so each spreads the public pieces of those
/// files rather than copying them: the meat, poultry and sea-animal lists
/// of `vegetarian` (`vocab_diets.dart`), halal's alcohol list for Jain
/// (`vocab_religious.dart`), the wheat foods and gluten grains
/// (`vocab_gluten_grains.dart`), the legume words (`vocab_plants_additives
/// .dart`, peas apart because Whole30 allows them), the milk words without
/// clarified butter (`vocab_dairy_eggs.dart`, because Whole30 allows ghee),
/// and the egg, tree-nut and sesame direct lists. A term may be listed
/// only once per restriction (`vocabulary_test.dart`), so the hidden lists
/// of those strict allergens are **not** spread: they overlap one another
/// ("croissant" is wheat, milk, egg and legume), and their recall-first
/// certainties are written for an allergy, not a diet. The short hidden
/// lists here are this group's own.
///
/// **Duplicated for a later cleanup:** the nightshade words (AIP) and the
/// caffeine words (coffee and chocolate, AIP) are listed here because
/// `vocab_sensitivities.dart` is still empty; once its `nightshades` and
/// `caffeine` pieces exist, AIP should spread them. The alcohol words of
/// Whole30 and AIP repeat most of halal's, which they cannot spread (see
/// [_alcoholEn]).
///
/// **Out of scope:** Jain practice also limits when one eats (not after
/// sunset, fasting days) and, for many, fermented foods (vinegar, yogurt,
/// soy sauce) and green leafy vegetables on some days; a menu cannot
/// carry any of that, so nothing here does. Whole30's ban on recreating
/// baked goods with compliant ingredients and AIP's food additives and
/// gums are not menu words either.
///
/// `שום` ("garlic", but also "any": "אין שום"), `יין` (`מיין` "sorts") and
/// `רום` (`מרום` "height") are compiled without the permissive Hebrew
/// prefix, and their prefixed food forms are terms of their own; so are
/// the no-prefix terms of the spread lists (`חיטה`, `חלה`, `חלות`, `בירה`,
/// `פול`, `בשר`, `עוף`, `בקר`, `כבש`). Every term cites its section, as
/// `vocabulary_test.dart` checks; after a change, regenerate the goldens
/// and copy `allergens.json` to `backend/app/keto/` (architecture.md D26).
library;

import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/utils/allergens/vocab_dairy_eggs.dart';
import 'package:ketoclub/utils/allergens/vocab_diets.dart';
import 'package:ketoclub/utils/allergens/vocab_gluten_grains.dart';
import 'package:ketoclub/utils/allergens/vocab_nuts_seeds.dart';
import 'package:ketoclub/utils/allergens/vocab_plants_additives.dart';
import 'package:ketoclub/utils/allergens/vocab_religious.dart';
import 'package:ketoclub/utils/allergens/vocabulary_types.dart';

/// The grains and grain foods that are not wheat, barley or rye: rice,
/// corn, oats and the pseudo-cereals (11 §30.2, §30.3). Paleo, Whole30
/// and AIP leave every grain out.
const List<String> _otherGrainsEn = <String>[
  'grain',
  'grains',
  'cereal',
  'cereals',
  'rice',
  'risotto',
  'paella',
  'pilaf',
  'pilau',
  'biryani',
  'congee',
  'arancini',
  'corn',
  'maize',
  'cornmeal',
  'cornstarch',
  'polenta',
  'grits',
  'popcorn',
  'tortilla',
  'tortillas',
  'nachos',
  'arepa',
  'arepas',
  'oat',
  'oats',
  'oatmeal',
  'porridge',
  'granola',
  'muesli',
  'quinoa',
  'millet',
  'buckwheat',
  'kasha',
  'soba',
  'sorghum',
  'amaranth',
  'teff',
];

/// [_otherGrainsEn] in Hebrew (12 §14.1).
const List<String> _otherGrainsHe = <String>[
  'דגנים',
  'דגני',
  'אורז',
  'ריזוטו',
  'פאייה',
  'תירס',
  'קורנפלור',
  'פולנטה',
  'ממליגה',
  'פופקורן',
  'טורטיה',
  'טורטייה',
  'טורטיות',
  "נאצ'וס",
  'שיבולת שועל',
  'קוואקר',
  'דייסה',
  'גרנולה',
  'מוזלי',
  'קינואה',
  'כוסמת',
  'דוחן',
  'סורגום',
  'אמרנט',
  'סובה',
];

/// The dishes that usually carry a grain without naming it: flour, a
/// breaded cutlet, sushi rice, a taco shell (11 §30.2).
const List<HiddenTrigger> _grainHiddenEn = <HiddenTrigger>[
  HiddenTrigger(
    term: 'flour',
    certainty: TriggerCertainty.likely,
    source: '11 §30.2',
  ),
  HiddenTrigger(
    term: 'floured',
    certainty: TriggerCertainty.suspected,
    source: '11 §30.2',
  ),
  HiddenTrigger(
    term: 'roux',
    certainty: TriggerCertainty.suspected,
    source: '11 §30.2',
  ),
  HiddenTrigger(
    term: 'gravy',
    certainty: TriggerCertainty.suspected,
    source: '11 §30.2',
  ),
  HiddenTrigger(
    term: 'schnitzel',
    certainty: TriggerCertainty.likely,
    source: '11 §30.2',
  ),
  HiddenTrigger(
    term: 'katsu',
    certainty: TriggerCertainty.likely,
    source: '11 §30.2',
  ),
  HiddenTrigger(
    term: 'milanese',
    certainty: TriggerCertainty.likely,
    source: '11 §30.2',
  ),
  HiddenTrigger(
    term: 'nuggets',
    certainty: TriggerCertainty.likely,
    source: '11 §30.2',
  ),
  HiddenTrigger(
    term: 'pie',
    certainty: TriggerCertainty.likely,
    source: '11 §30.2',
  ),
  HiddenTrigger(
    term: 'pies',
    certainty: TriggerCertainty.likely,
    source: '11 §30.2',
  ),
  HiddenTrigger(
    term: 'tart',
    certainty: TriggerCertainty.suspected,
    source: '11 §30.2',
  ),
  HiddenTrigger(
    term: 'tarts',
    certainty: TriggerCertainty.suspected,
    source: '11 §30.2',
  ),
  HiddenTrigger(
    term: 'wrap',
    certainty: TriggerCertainty.suspected,
    source: '11 §30.2',
  ),
  HiddenTrigger(
    term: 'wraps',
    certainty: TriggerCertainty.suspected,
    source: '11 §30.2',
  ),
  HiddenTrigger(
    term: 'cracker',
    certainty: TriggerCertainty.likely,
    source: '11 §30.2',
  ),
  HiddenTrigger(
    term: 'crackers',
    certainty: TriggerCertainty.likely,
    source: '11 §30.2',
  ),
  HiddenTrigger(
    term: 'sushi',
    certainty: TriggerCertainty.likely,
    source: '11 §30.2',
  ),
  HiddenTrigger(
    term: 'nigiri',
    certainty: TriggerCertainty.likely,
    source: '11 §30.2',
  ),
  HiddenTrigger(
    term: 'maki',
    certainty: TriggerCertainty.likely,
    source: '11 §30.2',
  ),
  HiddenTrigger(
    term: 'onigiri',
    certainty: TriggerCertainty.likely,
    source: '11 §30.2',
  ),
  HiddenTrigger(
    term: 'taco',
    certainty: TriggerCertainty.likely,
    source: '11 §30.2',
  ),
  HiddenTrigger(
    term: 'tacos',
    certainty: TriggerCertainty.likely,
    source: '11 §30.2',
  ),
  HiddenTrigger(
    term: 'burrito',
    certainty: TriggerCertainty.likely,
    source: '11 §30.2',
  ),
  HiddenTrigger(
    term: 'burritos',
    certainty: TriggerCertainty.likely,
    source: '11 §30.2',
  ),
  HiddenTrigger(
    term: 'enchilada',
    certainty: TriggerCertainty.likely,
    source: '11 §30.2',
  ),
  HiddenTrigger(
    term: 'enchiladas',
    certainty: TriggerCertainty.likely,
    source: '11 §30.2',
  ),
  HiddenTrigger(
    term: 'quesadilla',
    certainty: TriggerCertainty.likely,
    source: '11 §30.2',
  ),
  HiddenTrigger(
    term: 'tabbouleh',
    certainty: TriggerCertainty.likely,
    source: '11 §30.2',
  ),
  HiddenTrigger(
    term: 'tabouli',
    certainty: TriggerCertainty.likely,
    source: '11 §30.2',
  ),
  HiddenTrigger(
    term: 'kibbeh',
    certainty: TriggerCertainty.likely,
    source: '11 §30.2',
  ),
];

/// [_grainHiddenEn] in Hebrew (12 §14.1).
const List<HiddenTrigger> _grainHiddenHe = <HiddenTrigger>[
  HiddenTrigger(
    term: 'קמח',
    certainty: TriggerCertainty.likely,
    source: '12 §14.1',
  ),
  HiddenTrigger(
    term: 'מקומח',
    certainty: TriggerCertainty.suspected,
    source: '12 §14.1',
  ),
  HiddenTrigger(
    term: 'שניצל',
    certainty: TriggerCertainty.likely,
    source: '12 §14.1',
  ),
  HiddenTrigger(
    term: 'שניצלים',
    certainty: TriggerCertainty.likely,
    source: '12 §14.1',
  ),
  HiddenTrigger(
    term: 'נאגטס',
    certainty: TriggerCertainty.likely,
    source: '12 §14.1',
  ),
  HiddenTrigger(
    term: 'פאי',
    certainty: TriggerCertainty.likely,
    source: '12 §14.1',
  ),
  HiddenTrigger(
    term: 'טארט',
    certainty: TriggerCertainty.suspected,
    source: '12 §14.1',
  ),
  HiddenTrigger(
    term: 'ראפ',
    certainty: TriggerCertainty.suspected,
    source: '12 §14.1',
  ),
  HiddenTrigger(
    term: 'סושי',
    certainty: TriggerCertainty.likely,
    source: '12 §14.1',
  ),
  HiddenTrigger(
    term: 'ניגירי',
    certainty: TriggerCertainty.likely,
    source: '12 §14.1',
  ),
  HiddenTrigger(
    term: 'טאקו',
    certainty: TriggerCertainty.likely,
    source: '12 §14.1',
  ),
  HiddenTrigger(
    term: 'בוריטו',
    certainty: TriggerCertainty.likely,
    source: '12 §14.1',
  ),
  HiddenTrigger(
    term: 'קסדייה',
    certainty: TriggerCertainty.likely,
    source: '12 §14.1',
  ),
  HiddenTrigger(
    term: 'קסדילה',
    certainty: TriggerCertainty.likely,
    source: '12 §14.1',
  ),
  HiddenTrigger(
    term: 'טאבולה',
    certainty: TriggerCertainty.likely,
    source: '12 §14.1',
  ),
  HiddenTrigger(
    term: 'קובה',
    certainty: TriggerCertainty.likely,
    source: '12 §14.1',
  ),
];

/// Soy- and peanut-based sauces that name no legume (11 §30.2, after
/// 11 §6.2 and §1.2).
const List<HiddenTrigger> _legumeHiddenEn = <HiddenTrigger>[
  HiddenTrigger(
    term: 'satay',
    certainty: TriggerCertainty.likely,
    source: '11 §30.2',
  ),
  HiddenTrigger(
    term: 'teriyaki',
    certainty: TriggerCertainty.likely,
    source: '11 §30.2',
  ),
  HiddenTrigger(
    term: 'hoisin',
    certainty: TriggerCertainty.likely,
    source: '11 §30.2',
  ),
  HiddenTrigger(
    term: 'ponzu',
    certainty: TriggerCertainty.likely,
    source: '11 §30.2',
  ),
  HiddenTrigger(
    term: 'kung pao',
    certainty: TriggerCertainty.likely,
    source: '11 §30.2',
  ),
];

/// [_legumeHiddenEn] in Hebrew (12 §14.1).
const List<HiddenTrigger> _legumeHiddenHe = <HiddenTrigger>[
  HiddenTrigger(
    term: 'סאטה',
    certainty: TriggerCertainty.likely,
    source: '12 §14.1',
  ),
  HiddenTrigger(
    term: 'טריאקי',
    certainty: TriggerCertainty.likely,
    source: '12 §14.1',
  ),
  HiddenTrigger(
    term: 'הויסין',
    certainty: TriggerCertainty.likely,
    source: '12 §14.1',
  ),
  HiddenTrigger(
    term: 'פונזו',
    certainty: TriggerCertainty.likely,
    source: '12 §14.1',
  ),
  HiddenTrigger(
    term: 'קונג פאו',
    certainty: TriggerCertainty.likely,
    source: '12 §14.1',
  ),
];

/// The cheese dishes of `milk` whose name hides the word "cheese" from
/// the word boundary (11 §3.1); "cheesecake" comes with [wheatFoodsEn].
const List<String> _cheeseDishesEn = <String>['cheeseburger', 'cheesesteak'];

/// The coffees, sauces and desserts that are made with milk (11 §30.2,
/// after 11 §3.2).
const List<HiddenTrigger> _dairyHiddenEn = <HiddenTrigger>[
  HiddenTrigger(
    term: 'dairy',
    certainty: TriggerCertainty.likely,
    source: '11 §30.2',
  ),
  HiddenTrigger(
    term: 'latte',
    certainty: TriggerCertainty.likely,
    source: '11 §30.2',
  ),
  HiddenTrigger(
    term: 'cappuccino',
    certainty: TriggerCertainty.likely,
    source: '11 §30.2',
  ),
  HiddenTrigger(
    term: 'flat white',
    certainty: TriggerCertainty.likely,
    source: '11 §30.2',
  ),
  HiddenTrigger(
    term: 'ice cream',
    certainty: TriggerCertainty.likely,
    source: '11 §30.2',
  ),
  HiddenTrigger(
    term: 'gelato',
    certainty: TriggerCertainty.likely,
    source: '11 §30.2',
  ),
  HiddenTrigger(
    term: 'tzatziki',
    certainty: TriggerCertainty.likely,
    source: '11 §30.2',
  ),
  HiddenTrigger(
    term: 'alfredo',
    certainty: TriggerCertainty.likely,
    source: '11 §30.2',
  ),
  HiddenTrigger(
    term: 'bechamel',
    certainty: TriggerCertainty.likely,
    source: '11 §30.2',
  ),
  HiddenTrigger(
    term: 'hollandaise',
    certainty: TriggerCertainty.likely,
    source: '11 §30.2',
  ),
  HiddenTrigger(
    term: 'pesto',
    certainty: TriggerCertainty.likely,
    source: '11 §30.2',
  ),
  HiddenTrigger(
    term: 'gratin',
    certainty: TriggerCertainty.likely,
    source: '11 §30.2',
  ),
  HiddenTrigger(
    term: 'tiramisu',
    certainty: TriggerCertainty.likely,
    source: '11 §30.2',
  ),
  HiddenTrigger(
    term: 'creamy',
    certainty: TriggerCertainty.suspected,
    source: '11 §30.2',
  ),
];

/// [_dairyHiddenEn] in Hebrew (12 §14.1); `חלבי` is the kosher "dairy"
/// label (12 §2.1).
const List<HiddenTrigger> _dairyHiddenHe = <HiddenTrigger>[
  HiddenTrigger(
    term: 'חלבי',
    certainty: TriggerCertainty.likely,
    source: '12 §14.1',
  ),
  HiddenTrigger(
    term: 'חלבית',
    certainty: TriggerCertainty.likely,
    source: '12 §14.1',
  ),
  HiddenTrigger(
    term: 'הפוך',
    certainty: TriggerCertainty.likely,
    source: '12 §14.1',
  ),
  HiddenTrigger(
    term: 'לאטה',
    certainty: TriggerCertainty.likely,
    source: '12 §14.1',
  ),
  HiddenTrigger(
    term: "קפוצ'ינו",
    certainty: TriggerCertainty.likely,
    source: '12 §14.1',
  ),
  HiddenTrigger(
    term: 'גלידה',
    certainty: TriggerCertainty.likely,
    source: '12 §14.1',
  ),
  HiddenTrigger(
    term: 'גלידת',
    certainty: TriggerCertainty.likely,
    source: '12 §14.1',
  ),
  HiddenTrigger(
    term: 'צזיקי',
    certainty: TriggerCertainty.likely,
    source: '12 §14.1',
  ),
  HiddenTrigger(
    term: 'אלפרדו',
    certainty: TriggerCertainty.likely,
    source: '12 §14.1',
  ),
  HiddenTrigger(
    term: 'בשמל',
    certainty: TriggerCertainty.likely,
    source: '12 §14.1',
  ),
  HiddenTrigger(
    term: 'הולנדייז',
    certainty: TriggerCertainty.likely,
    source: '12 §14.1',
  ),
  HiddenTrigger(
    term: 'פסטו',
    certainty: TriggerCertainty.likely,
    source: '12 §14.1',
  ),
  HiddenTrigger(
    term: 'טירמיסו',
    certainty: TriggerCertainty.likely,
    source: '12 §14.1',
  ),
  HiddenTrigger(
    term: 'קרמי',
    certainty: TriggerCertainty.suspected,
    source: '12 §14.1',
  ),
];

/// Ghee: dairy, but allowed by many paleo plans and by Whole30, so
/// paleo and AIP only list it (11 §30.2).
const List<HiddenTrigger> _clarifiedButterHiddenEn = <HiddenTrigger>[
  HiddenTrigger(
    term: 'ghee',
    certainty: TriggerCertainty.suspected,
    source: '11 §30.2',
  ),
];

/// [_clarifiedButterHiddenEn] in Hebrew.
const List<HiddenTrigger> _clarifiedButterHiddenHe = <HiddenTrigger>[
  HiddenTrigger(
    term: 'גהי',
    certainty: TriggerCertainty.suspected,
    source: '12 §14.1',
  ),
  HiddenTrigger(
    term: 'סמנה',
    certainty: TriggerCertainty.suspected,
    source: '12 §14.1',
  ),
  HiddenTrigger(
    term: 'סאמנה',
    certainty: TriggerCertainty.suspected,
    source: '12 §14.1',
  ),
];

/// Refined sugar, which paleo and AIP leave out while allowing honey and
/// maple syrup: `suspected`, because a menu rarely says which sugar it
/// used (11 §30.2).
const List<HiddenTrigger> _refinedSugarHiddenEn = <HiddenTrigger>[
  HiddenTrigger(
    term: 'sugar',
    certainty: TriggerCertainty.suspected,
    source: '11 §30.2',
  ),
  HiddenTrigger(
    term: 'sugars',
    certainty: TriggerCertainty.suspected,
    source: '11 §30.2',
  ),
  HiddenTrigger(
    term: 'sugared',
    certainty: TriggerCertainty.suspected,
    source: '11 §30.2',
  ),
  HiddenTrigger(
    term: 'sugary',
    certainty: TriggerCertainty.suspected,
    source: '11 §30.2',
  ),
  HiddenTrigger(
    term: 'corn syrup',
    certainty: TriggerCertainty.suspected,
    source: '11 §30.2',
  ),
  HiddenTrigger(
    term: 'glucose syrup',
    certainty: TriggerCertainty.suspected,
    source: '11 §30.2',
  ),
  HiddenTrigger(
    term: 'caramel',
    certainty: TriggerCertainty.suspected,
    source: '11 §30.2',
  ),
  HiddenTrigger(
    term: 'candied',
    certainty: TriggerCertainty.suspected,
    source: '11 §30.2',
  ),
  HiddenTrigger(
    term: 'frosting',
    certainty: TriggerCertainty.suspected,
    source: '11 §30.2',
  ),
  HiddenTrigger(
    term: 'icing',
    certainty: TriggerCertainty.suspected,
    source: '11 §30.2',
  ),
  HiddenTrigger(
    term: 'toffee',
    certainty: TriggerCertainty.suspected,
    source: '11 §30.2',
  ),
  HiddenTrigger(
    term: 'fudge',
    certainty: TriggerCertainty.suspected,
    source: '11 §30.2',
  ),
  HiddenTrigger(
    term: 'candy',
    certainty: TriggerCertainty.suspected,
    source: '11 §30.2',
  ),
];

/// [_refinedSugarHiddenEn] in Hebrew.
const List<HiddenTrigger> _refinedSugarHiddenHe = <HiddenTrigger>[
  HiddenTrigger(
    term: 'סוכר',
    certainty: TriggerCertainty.suspected,
    source: '12 §14.2',
  ),
  HiddenTrigger(
    term: 'מסוכר',
    certainty: TriggerCertainty.suspected,
    source: '12 §14.2',
  ),
  HiddenTrigger(
    term: 'מסוכרים',
    certainty: TriggerCertainty.suspected,
    source: '12 §14.2',
  ),
  HiddenTrigger(
    term: 'מסוכרת',
    certainty: TriggerCertainty.suspected,
    source: '12 §14.2',
  ),
  HiddenTrigger(
    term: 'קרמל',
    certainty: TriggerCertainty.suspected,
    source: '12 §14.2',
  ),
  HiddenTrigger(
    term: 'מקורמל',
    certainty: TriggerCertainty.suspected,
    source: '12 §14.2',
  ),
  HiddenTrigger(
    term: 'מקורמלים',
    certainty: TriggerCertainty.suspected,
    source: '12 §14.2',
  ),
  HiddenTrigger(
    term: 'סירופ גלוקוזה',
    certainty: TriggerCertainty.suspected,
    source: '12 §14.2',
  ),
  HiddenTrigger(
    term: 'פונדנט',
    certainty: TriggerCertainty.suspected,
    source: '12 §14.2',
  ),
  HiddenTrigger(
    term: 'טופי',
    certainty: TriggerCertainty.suspected,
    source: '12 §14.2',
  ),
  HiddenTrigger(
    term: 'סוכריות',
    certainty: TriggerCertainty.suspected,
    source: '12 §14.2',
  ),
];

/// Whole30's "no added sugar, real or artificial": every sugar and
/// sweetener a menu names, honey and maple syrup included (11 §30.3).
const List<String> _sugarWordsEn = <String>[
  'sugar',
  'sugars',
  'sugared',
  'sugary',
  'syrup',
  'glucose',
  'caramel',
  'candied',
  'frosting',
  'icing',
  'toffee',
  'fudge',
  'candy',
  'honey',
  'maple',
  'agave',
  'molasses',
  'silan',
  'stevia',
  'sucralose',
  'splenda',
  'xylitol',
  'monk fruit',
  'sweetener',
  'sweetened',
];

/// [_sugarWordsEn] in Hebrew (12 §14.2).
const List<String> _sugarWordsHe = <String>[
  'סוכר',
  'מסוכר',
  'מסוכרים',
  'מסוכרת',
  'סירופ',
  'קרמל',
  'פונדנט',
  'טופי',
  'סוכריות',
  'דבש',
  'מייפל',
  'אגבה',
  'סילאן',
  'מולסה',
  'סטיביה',
  'ממתיק',
  'ממתיקים',
];

/// Sauces that are usually sweetened, and a glaze (11 §30.3).
const List<HiddenTrigger> _sugarHiddenEn = <HiddenTrigger>[
  HiddenTrigger(
    term: 'glazed',
    certainty: TriggerCertainty.suspected,
    source: '11 §30.3',
  ),
  HiddenTrigger(
    term: 'bbq sauce',
    certainty: TriggerCertainty.likely,
    source: '11 §30.3',
  ),
  HiddenTrigger(
    term: 'barbecue sauce',
    certainty: TriggerCertainty.likely,
    source: '11 §30.3',
  ),
  HiddenTrigger(
    term: 'ketchup',
    certainty: TriggerCertainty.likely,
    source: '11 §30.3',
  ),
  HiddenTrigger(
    term: 'sweet and sour',
    certainty: TriggerCertainty.likely,
    source: '11 §30.3',
  ),
  HiddenTrigger(
    term: 'sweet chili',
    certainty: TriggerCertainty.likely,
    source: '11 §30.3',
  ),
];

/// [_sugarHiddenEn] in Hebrew (12 §14.2), and caramelised onion, which
/// may or may not be sugared (suspected).
const List<HiddenTrigger> _sugarHiddenHe = <HiddenTrigger>[
  HiddenTrigger(
    term: 'מזוגג',
    certainty: TriggerCertainty.suspected,
    source: '12 §14.2',
  ),
  HiddenTrigger(
    term: 'מקורמל',
    certainty: TriggerCertainty.suspected,
    source: '12 §14.2',
  ),
  HiddenTrigger(
    term: 'מקורמלים',
    certainty: TriggerCertainty.suspected,
    source: '12 §14.2',
  ),
  HiddenTrigger(
    term: 'ברביקיו',
    certainty: TriggerCertainty.likely,
    source: '12 §14.2',
  ),
  HiddenTrigger(
    term: 'קטשופ',
    certainty: TriggerCertainty.likely,
    source: '12 §14.2',
  ),
  HiddenTrigger(
    term: 'חמוץ מתוק',
    certainty: TriggerCertainty.likely,
    source: '12 §14.2',
  ),
  HiddenTrigger(
    term: "צ'ילי מתוק",
    certainty: TriggerCertainty.likely,
    source: '12 §14.2',
  ),
];

/// The refined seed oils paleo and AIP leave out (11 §30.2): `suspected`
/// everywhere, since a menu seldom names its frying oil.
const List<HiddenTrigger> _seedOilsHiddenEn = <HiddenTrigger>[
  HiddenTrigger(
    term: 'canola',
    certainty: TriggerCertainty.suspected,
    source: '11 §30.2',
  ),
  HiddenTrigger(
    term: 'rapeseed oil',
    certainty: TriggerCertainty.suspected,
    source: '11 §30.2',
  ),
  HiddenTrigger(
    term: 'vegetable oil',
    certainty: TriggerCertainty.suspected,
    source: '11 §30.2',
  ),
  HiddenTrigger(
    term: 'soybean oil',
    certainty: TriggerCertainty.suspected,
    source: '11 §30.2',
  ),
  HiddenTrigger(
    term: 'sunflower oil',
    certainty: TriggerCertainty.suspected,
    source: '11 §30.2',
  ),
  HiddenTrigger(
    term: 'safflower oil',
    certainty: TriggerCertainty.suspected,
    source: '11 §30.2',
  ),
  HiddenTrigger(
    term: 'cottonseed oil',
    certainty: TriggerCertainty.suspected,
    source: '11 §30.2',
  ),
  HiddenTrigger(
    term: 'margarine',
    certainty: TriggerCertainty.suspected,
    source: '11 §30.2',
  ),
  HiddenTrigger(
    term: 'shortening',
    certainty: TriggerCertainty.suspected,
    source: '11 §30.2',
  ),
  HiddenTrigger(
    term: 'deep fried',
    certainty: TriggerCertainty.suspected,
    source: '11 §30.2',
  ),
];

/// [_seedOilsHiddenEn] in Hebrew.
const List<HiddenTrigger> _seedOilsHiddenHe = <HiddenTrigger>[
  HiddenTrigger(
    term: 'קנולה',
    certainty: TriggerCertainty.suspected,
    source: '12 §14.2',
  ),
  HiddenTrigger(
    term: 'שמן צמחי',
    certainty: TriggerCertainty.suspected,
    source: '12 §14.2',
  ),
  HiddenTrigger(
    term: 'שמן חמניות',
    certainty: TriggerCertainty.suspected,
    source: '12 §14.2',
  ),
  HiddenTrigger(
    term: 'מרגרינה',
    certainty: TriggerCertainty.suspected,
    source: '12 §14.2',
  ),
  HiddenTrigger(
    term: 'טיגון עמוק',
    certainty: TriggerCertainty.suspected,
    source: '12 §14.2',
  ),
];

/// Alcohol, which Whole30 (cooking included) and AIP leave out (11 §30.3,
/// §30.4). Beer is in [glutenGrainsEn]. Halal's `alcoholHiddenEn` is not
/// spread here: it also holds beer, risotto, tiramisu and teriyaki, which
/// the grain, dairy and legume pieces already list. Jain spreads it.
const List<String> _alcoholEn = <String>[
  'alcohol',
  'alcoholic',
  'wine',
  'wines',
  'vodka',
  'rum',
  'whisky',
  'whiskey',
  'bourbon',
  'gin',
  'tequila',
  'mezcal',
  'brandy',
  'cognac',
  'liqueur',
  'liquor',
  'sake',
  'champagne',
  'prosecco',
  'sangria',
  'cocktail',
  'cocktails',
  'mojito',
  'spritz',
  'aperol',
  'campari',
  'vermouth',
  'sherry',
  'arak',
  'ouzo',
  'limoncello',
  'martini',
];

/// [_alcoholEn] in Hebrew (12 §14.2). `יין` and `רום` have no permissive
/// prefix, so the prefixed wine forms are terms of their own.
const List<String> _alcoholHe = <String>[
  'אלכוהול',
  'יין',
  'היין',
  'ביין',
  'ויין',
  'יינות',
  'וודקה',
  'רום',
  'ויסקי',
  'וויסקי',
  "ג'ין",
  'טקילה',
  'ברנדי',
  'קוניאק',
  'ליקר',
  'סאקה',
  'שמפניה',
  'פרוסקו',
  'סנגריה',
  'קוקטייל',
  'קוקטיילים',
  'מוחיטו',
  'ספריץ',
  'אפרול',
  'קמפרי',
  'ורמוט',
  'ערק',
  'עראק',
  'אוזו',
  "לימונצ'לו",
];

/// Wine and spirits in cooking: mirin and marsala are wines, a flambé is
/// lit spirit; "margarita" is also a pizza, so it is only suspected
/// (11 §30.3).
const List<HiddenTrigger> _alcoholHiddenEn = <HiddenTrigger>[
  HiddenTrigger(
    term: 'mirin',
    certainty: TriggerCertainty.likely,
    source: '11 §30.3',
  ),
  HiddenTrigger(
    term: 'marsala',
    certainty: TriggerCertainty.likely,
    source: '11 §30.3',
  ),
  HiddenTrigger(
    term: 'flambe',
    certainty: TriggerCertainty.likely,
    source: '11 §30.3',
  ),
  HiddenTrigger(
    term: 'flambeed',
    certainty: TriggerCertainty.likely,
    source: '11 §30.3',
  ),
  HiddenTrigger(
    term: 'margarita',
    certainty: TriggerCertainty.suspected,
    source: '11 §30.3',
  ),
];

/// [_alcoholHiddenEn] in Hebrew (12 §14.2).
const List<HiddenTrigger> _alcoholHiddenHe = <HiddenTrigger>[
  HiddenTrigger(
    term: 'מירין',
    certainty: TriggerCertainty.likely,
    source: '12 §14.2',
  ),
  HiddenTrigger(
    term: 'מרסלה',
    certainty: TriggerCertainty.likely,
    source: '12 §14.2',
  ),
  HiddenTrigger(
    term: 'פלמבה',
    certainty: TriggerCertainty.likely,
    source: '12 §14.2',
  ),
  HiddenTrigger(
    term: 'מרגריטה',
    certainty: TriggerCertainty.suspected,
    source: '12 §14.2',
  ),
];

/// Seeds and nuts beyond the tree-nut and sesame lists (11 §30.4).
const List<String> _seedsEn = <String>[
  'nut',
  'nuts',
  'seed',
  'seeds',
  'seeded',
  'chia',
  'flax',
  'flaxseed',
  'linseed',
  'sunflower',
  'pepitas',
  'hemp',
  'poppy',
];

/// [_seedsEn] in Hebrew (12 §14.3).
const List<String> _seedsHe = <String>[
  'אגוזים',
  'זרעים',
  'זרעי',
  'גרעינים',
  'גרעיני',
  "צ'יה",
  'פשתן',
  'פרג',
];

/// The seed spices AIP leaves out (11 §30.4): cumin, coriander seed,
/// fennel seed, anise, caraway, nutmeg, cardamom, allspice, mustard.
const List<String> _seedSpicesEn = <String>[
  'cumin',
  'coriander seed',
  'coriander seeds',
  'fennel seed',
  'fennel seeds',
  'anise',
  'aniseed',
  'caraway',
  'nutmeg',
  'cardamom',
  'allspice',
  'mustard',
  'dijon',
];

/// [_seedSpicesEn] in Hebrew (12 §14.3).
const List<String> _seedSpicesHe = <String>[
  'כמון',
  'קימל',
  'אניס',
  'חרדל',
  'מוסקט',
];

/// Spice blends built on seed spices (11 §30.4).
const List<HiddenTrigger> _seedSpicesHiddenEn = <HiddenTrigger>[
  HiddenTrigger(
    term: 'curry',
    certainty: TriggerCertainty.likely,
    source: '11 §30.4',
  ),
  HiddenTrigger(
    term: 'curries',
    certainty: TriggerCertainty.likely,
    source: '11 §30.4',
  ),
  HiddenTrigger(
    term: 'garam masala',
    certainty: TriggerCertainty.likely,
    source: '11 §30.4',
  ),
  HiddenTrigger(
    term: "za'atar",
    certainty: TriggerCertainty.likely,
    source: '11 §30.4',
  ),
  HiddenTrigger(
    term: 'zaatar',
    certainty: TriggerCertainty.likely,
    source: '11 §30.4',
  ),
  HiddenTrigger(
    term: 'dukkah',
    certainty: TriggerCertainty.likely,
    source: '11 §30.4',
  ),
  HiddenTrigger(
    term: 'baharat',
    certainty: TriggerCertainty.likely,
    source: '11 §30.4',
  ),
  HiddenTrigger(
    term: 'ras el hanout',
    certainty: TriggerCertainty.likely,
    source: '11 §30.4',
  ),
  HiddenTrigger(
    term: 'five spice',
    certainty: TriggerCertainty.likely,
    source: '11 §30.4',
  ),
  HiddenTrigger(
    term: 'hawaij',
    certainty: TriggerCertainty.likely,
    source: '11 §30.4',
  ),
];

/// [_seedSpicesHiddenEn] in Hebrew.
const List<HiddenTrigger> _seedSpicesHiddenHe = <HiddenTrigger>[
  HiddenTrigger(
    term: 'קארי',
    certainty: TriggerCertainty.likely,
    source: '12 §14.3',
  ),
  HiddenTrigger(
    term: 'קרי',
    certainty: TriggerCertainty.likely,
    source: '12 §14.3',
  ),
  HiddenTrigger(
    term: 'זעתר',
    certainty: TriggerCertainty.likely,
    source: '12 §14.3',
  ),
  HiddenTrigger(
    term: 'דוקה',
    certainty: TriggerCertainty.likely,
    source: '12 §14.3',
  ),
  HiddenTrigger(
    term: 'בהרט',
    certainty: TriggerCertainty.likely,
    source: '12 §14.3',
  ),
  HiddenTrigger(
    term: "חוואייג'",
    certainty: TriggerCertainty.likely,
    source: '12 §14.3',
  ),
  HiddenTrigger(
    term: 'ראס אל חנות',
    certainty: TriggerCertainty.likely,
    source: '12 §14.3',
  ),
  HiddenTrigger(
    term: 'גרם מסאלה',
    certainty: TriggerCertainty.likely,
    source: '12 §14.3',
  ),
];

/// Nightshades (11 §30.4): tomato, potato, eggplant, sweet and hot
/// peppers and their spices. Bare "pepper" is left out (black pepper is
/// not a nightshade). Duplicated for a later cleanup (see the library
/// comment).
const List<String> _nightshadesEn = <String>[
  'tomato',
  'tomatoes',
  'potato',
  'potatoes',
  'eggplant',
  'eggplants',
  'aubergine',
  'aubergines',
  'peppers',
  'bell pepper',
  'bell peppers',
  'red pepper',
  'green pepper',
  'sweet pepper',
  'chili',
  'chilli',
  'chile',
  'chilies',
  'chillies',
  'jalapeno',
  'jalapenos',
  'cayenne',
  'paprika',
  'chipotle',
  'pimento',
  'pimiento',
  'goji',
  'tomatillo',
  'fries',
  'hash brown',
  'hash browns',
];

/// [_nightshadesEn] in Hebrew (12 §14.3). `פלפל` is listed with term
/// guards for black and white pepper.
const List<String> _nightshadesHe = <String>[
  'עגבנייה',
  'עגבניה',
  'עגבניות',
  'תפוח אדמה',
  'תפוחי אדמה',
  "צ'יפס",
  'חציל',
  'חצילים',
  'פלפל',
  'פלפלים',
  'גמבה',
  "צ'ילי",
  'פפריקה',
  'חלפיניו',
  "ג'לפניו",
  'קאיין',
];

/// Sauces and dishes that are usually tomato, pepper or eggplant
/// (11 §30.4).
const List<HiddenTrigger> _nightshadesHiddenEn = <HiddenTrigger>[
  HiddenTrigger(
    term: 'salsa',
    certainty: TriggerCertainty.likely,
    source: '11 §30.4',
  ),
  HiddenTrigger(
    term: 'ketchup',
    certainty: TriggerCertainty.likely,
    source: '11 §30.4',
  ),
  HiddenTrigger(
    term: 'marinara',
    certainty: TriggerCertainty.likely,
    source: '11 §30.4',
  ),
  HiddenTrigger(
    term: 'pomodoro',
    certainty: TriggerCertainty.likely,
    source: '11 §30.4',
  ),
  HiddenTrigger(
    term: 'arrabbiata',
    certainty: TriggerCertainty.likely,
    source: '11 §30.4',
  ),
  HiddenTrigger(
    term: 'bolognese',
    certainty: TriggerCertainty.likely,
    source: '11 §30.4',
  ),
  HiddenTrigger(
    term: 'harissa',
    certainty: TriggerCertainty.likely,
    source: '11 §30.4',
  ),
  HiddenTrigger(
    term: 'sriracha',
    certainty: TriggerCertainty.likely,
    source: '11 §30.4',
  ),
  HiddenTrigger(
    term: 'hot sauce',
    certainty: TriggerCertainty.likely,
    source: '11 §30.4',
  ),
  HiddenTrigger(
    term: 'gazpacho',
    certainty: TriggerCertainty.likely,
    source: '11 §30.4',
  ),
  HiddenTrigger(
    term: 'ratatouille',
    certainty: TriggerCertainty.likely,
    source: '11 §30.4',
  ),
  HiddenTrigger(
    term: 'moussaka',
    certainty: TriggerCertainty.likely,
    source: '11 §30.4',
  ),
  HiddenTrigger(
    term: 'baba ghanoush',
    certainty: TriggerCertainty.likely,
    source: '11 §30.4',
  ),
];

/// [_nightshadesHiddenEn] in Hebrew.
const List<HiddenTrigger> _nightshadesHiddenHe = <HiddenTrigger>[
  HiddenTrigger(
    term: 'פירה',
    certainty: TriggerCertainty.likely,
    source: '12 §14.3',
  ),
  HiddenTrigger(
    term: 'סלסה',
    certainty: TriggerCertainty.likely,
    source: '12 §14.3',
  ),
  HiddenTrigger(
    term: 'קטשופ',
    certainty: TriggerCertainty.likely,
    source: '12 §14.3',
  ),
  HiddenTrigger(
    term: 'מרינרה',
    certainty: TriggerCertainty.likely,
    source: '12 §14.3',
  ),
  HiddenTrigger(
    term: 'פומודורו',
    certainty: TriggerCertainty.likely,
    source: '12 §14.3',
  ),
  HiddenTrigger(
    term: 'ארביאטה',
    certainty: TriggerCertainty.likely,
    source: '12 §14.3',
  ),
  HiddenTrigger(
    term: 'בולונז',
    certainty: TriggerCertainty.likely,
    source: '12 §14.3',
  ),
  HiddenTrigger(
    term: 'הריסה',
    certainty: TriggerCertainty.likely,
    source: '12 §14.3',
  ),
  HiddenTrigger(
    term: 'סחוג',
    certainty: TriggerCertainty.likely,
    source: '12 §14.3',
  ),
  HiddenTrigger(
    term: 'מטבוחה',
    certainty: TriggerCertainty.likely,
    source: '12 §14.3',
  ),
  HiddenTrigger(
    term: "סרירצ'ה",
    certainty: TriggerCertainty.likely,
    source: '12 §14.3',
  ),
  HiddenTrigger(
    term: 'רטטוי',
    certainty: TriggerCertainty.likely,
    source: '12 §14.3',
  ),
  HiddenTrigger(
    term: 'מוסקה',
    certainty: TriggerCertainty.likely,
    source: '12 §14.3',
  ),
  HiddenTrigger(
    term: 'באבא גנוש',
    certainty: TriggerCertainty.likely,
    source: '12 §14.3',
  ),
];

/// Coffee and chocolate, seeds that the AIP elimination phase leaves out
/// (11 §30.4). Duplicated for a later cleanup with `caffeine`.
const List<String> _coffeeChocolateEn = <String>[
  'coffee',
  'espresso',
  'americano',
  'mocha',
  'macchiato',
  'cold brew',
  'chocolate',
  'cocoa',
  'cacao',
];

/// [_coffeeChocolateEn] in Hebrew (12 §14.3).
const List<String> _coffeeChocolateHe = <String>[
  'קפה',
  'אספרסו',
  'אמריקנו',
  'מוקה',
  'מקיאטו',
  'שוקולד',
  'קקאו',
];

/// Desserts built on them (11 §30.4).
const List<HiddenTrigger> _coffeeChocolateHiddenEn = <HiddenTrigger>[
  HiddenTrigger(
    term: 'affogato',
    certainty: TriggerCertainty.likely,
    source: '11 §30.4',
  ),
  HiddenTrigger(
    term: 'nutella',
    certainty: TriggerCertainty.likely,
    source: '11 §30.4',
  ),
  HiddenTrigger(
    term: 'mole',
    certainty: TriggerCertainty.suspected,
    source: '11 §30.4',
  ),
];

/// [_coffeeChocolateHiddenEn] in Hebrew.
const List<HiddenTrigger> _coffeeChocolateHiddenHe = <HiddenTrigger>[
  HiddenTrigger(
    term: 'נוטלה',
    certainty: TriggerCertainty.likely,
    source: '12 §14.3',
  ),
];

/// Root and underground vegetables, which most Jains do not eat
/// (11 §30.5): the onion family, garlic, potato, carrot, beet, radish,
/// turnip, ginger and the tubers.
const List<String> _rootsEn = <String>[
  'onion',
  'onions',
  'shallot',
  'shallots',
  'scallion',
  'scallions',
  'leek',
  'leeks',
  'garlic',
  'potato',
  'potatoes',
  'fries',
  'carrot',
  'carrots',
  'beet',
  'beets',
  'beetroot',
  'radish',
  'radishes',
  'turnip',
  'turnips',
  'parsnip',
  'parsnips',
  'yam',
  'yams',
  'cassava',
  'yuca',
  'taro',
  'celeriac',
  'horseradish',
  'ginger',
  'aloo',
  'lotus root',
];

/// [_rootsEn] in Hebrew (12 §14.4). `שום` has no permissive prefix
/// ("משום" is "because"); its prefixed forms are terms of their own.
const List<String> _rootsHe = <String>[
  'בצל',
  'בצלים',
  'שאלוט',
  'כרישה',
  'כרישות',
  'שום',
  'השום',
  'ושום',
  'בשום',
  'ובשום',
  'והשום',
  'תפוח אדמה',
  'תפוחי אדמה',
  "צ'יפס",
  'גזר',
  'סלק',
  'צנון',
  'צנונית',
  'לפת',
  'בטטה',
  'בטטות',
  "ג'ינג'ר",
  'זנגביל',
  'חזרת',
];

/// Dishes that are usually a root, and the fungi many Jains also avoid
/// (suspected: practice varies) (11 §30.5).
const List<HiddenTrigger> _rootsHiddenEn = <HiddenTrigger>[
  HiddenTrigger(
    term: 'hash brown',
    certainty: TriggerCertainty.likely,
    source: '11 §30.5',
  ),
  HiddenTrigger(
    term: 'hash browns',
    certainty: TriggerCertainty.likely,
    source: '11 §30.5',
  ),
  HiddenTrigger(
    term: 'latkes',
    certainty: TriggerCertainty.likely,
    source: '11 §30.5',
  ),
  HiddenTrigger(
    term: 'gnocchi',
    certainty: TriggerCertainty.likely,
    source: '11 §30.5',
  ),
  HiddenTrigger(
    term: 'chips',
    certainty: TriggerCertainty.likely,
    source: '11 §30.5',
  ),
  HiddenTrigger(
    term: 'wasabi',
    certainty: TriggerCertainty.likely,
    source: '11 §30.5',
  ),
  HiddenTrigger(
    term: 'tzatziki',
    certainty: TriggerCertainty.likely,
    source: '11 §30.5',
  ),
  HiddenTrigger(
    term: 'pesto',
    certainty: TriggerCertainty.likely,
    source: '11 §30.5',
  ),
  HiddenTrigger(
    term: 'salsa',
    certainty: TriggerCertainty.likely,
    source: '11 §30.5',
  ),
  HiddenTrigger(
    term: 'chimichurri',
    certainty: TriggerCertainty.likely,
    source: '11 §30.5',
  ),
  HiddenTrigger(
    term: 'gazpacho',
    certainty: TriggerCertainty.likely,
    source: '11 §30.5',
  ),
  HiddenTrigger(
    term: 'mushroom',
    certainty: TriggerCertainty.suspected,
    source: '11 §30.5',
  ),
  HiddenTrigger(
    term: 'mushrooms',
    certainty: TriggerCertainty.suspected,
    source: '11 §30.5',
  ),
  HiddenTrigger(
    term: 'truffle',
    certainty: TriggerCertainty.suspected,
    source: '11 §30.5',
  ),
  HiddenTrigger(
    term: 'truffles',
    certainty: TriggerCertainty.suspected,
    source: '11 §30.5',
  ),
  HiddenTrigger(
    term: 'stock',
    certainty: TriggerCertainty.suspected,
    source: '11 §30.5',
  ),
  HiddenTrigger(
    term: 'broth',
    certainty: TriggerCertainty.suspected,
    source: '11 §30.5',
  ),
];

/// [_rootsHiddenEn] in Hebrew (12 §14.4).
const List<HiddenTrigger> _rootsHiddenHe = <HiddenTrigger>[
  HiddenTrigger(
    term: 'פירה',
    certainty: TriggerCertainty.likely,
    source: '12 §14.4',
  ),
  HiddenTrigger(
    term: 'לביבות',
    certainty: TriggerCertainty.likely,
    source: '12 §14.4',
  ),
  HiddenTrigger(
    term: 'ניוקי',
    certainty: TriggerCertainty.likely,
    source: '12 §14.4',
  ),
  HiddenTrigger(
    term: 'וואסאבי',
    certainty: TriggerCertainty.likely,
    source: '12 §14.4',
  ),
  HiddenTrigger(
    term: 'צזיקי',
    certainty: TriggerCertainty.likely,
    source: '12 §14.4',
  ),
  HiddenTrigger(
    term: 'פסטו',
    certainty: TriggerCertainty.likely,
    source: '12 §14.4',
  ),
  HiddenTrigger(
    term: 'סלסה',
    certainty: TriggerCertainty.likely,
    source: '12 §14.4',
  ),
  HiddenTrigger(
    term: "צ'ימיצ'ורי",
    certainty: TriggerCertainty.likely,
    source: '12 §14.4',
  ),
  HiddenTrigger(
    term: 'פטריות',
    certainty: TriggerCertainty.suspected,
    source: '12 §14.4',
  ),
  HiddenTrigger(
    term: 'פטרייה',
    certainty: TriggerCertainty.suspected,
    source: '12 §14.4',
  ),
  HiddenTrigger(
    term: 'פטריה',
    certainty: TriggerCertainty.suspected,
    source: '12 §14.4',
  ),
  HiddenTrigger(
    term: 'כמהין',
    certainty: TriggerCertainty.suspected,
    source: '12 §14.4',
  ),
  HiddenTrigger(
    term: 'ציר',
    certainty: TriggerCertainty.suspected,
    source: '12 §14.4',
  ),
  HiddenTrigger(
    term: 'מרק',
    certainty: TriggerCertainty.suspected,
    source: '12 §14.4',
  ),
];

/// Meat words that `vegetarian` does not list as direct triggers, for
/// pescatarian (11 §30.1, after 11 §17.1).
const List<String> _meatExtraEn = <String>[
  'kebab',
  'kebabs',
  'shawarma',
  'chorizo',
  'pastrami',
  'meatloaf',
  'liver',
  'gyro',
  'gyros',
  'merguez',
  'bone broth',
];

/// Dishes that are usually meat or poultry, and the stocks that often
/// are (11 §30.1).
const List<HiddenTrigger> _meatExtraHiddenEn = <HiddenTrigger>[
  HiddenTrigger(
    term: 'schnitzel',
    certainty: TriggerCertainty.likely,
    source: '11 §30.1',
  ),
  HiddenTrigger(
    term: 'nuggets',
    certainty: TriggerCertainty.likely,
    source: '11 §30.1',
  ),
  HiddenTrigger(
    term: 'wings',
    certainty: TriggerCertainty.likely,
    source: '11 §30.1',
  ),
  HiddenTrigger(
    term: 'hot dog',
    certainty: TriggerCertainty.likely,
    source: '11 §30.1',
  ),
  HiddenTrigger(
    term: 'hot dogs',
    certainty: TriggerCertainty.likely,
    source: '11 §30.1',
  ),
  HiddenTrigger(
    term: 'kofta',
    certainty: TriggerCertainty.likely,
    source: '11 §30.1',
  ),
  HiddenTrigger(
    term: 'carpaccio',
    certainty: TriggerCertainty.likely,
    source: '11 §30.1',
  ),
  HiddenTrigger(
    term: 'gravy',
    certainty: TriggerCertainty.suspected,
    source: '11 §30.1',
  ),
  HiddenTrigger(
    term: 'stock',
    certainty: TriggerCertainty.suspected,
    source: '11 §30.1',
  ),
  HiddenTrigger(
    term: 'broth',
    certainty: TriggerCertainty.suspected,
    source: '11 §30.1',
  ),
  HiddenTrigger(
    term: 'pate',
    certainty: TriggerCertainty.suspected,
    source: '11 §30.1',
  ),
];

/// Hebrew meat words beyond `vegetarian` (12 §14.5).
const List<String> _meatExtraHe = <String>[
  'מרגז',
  'קבנוס',
  "צ'וריסו",
  'מעורב ירושלמי',
];

/// [_meatExtraHiddenEn] in Hebrew (12 §14.5).
const List<HiddenTrigger> _meatExtraHiddenHe = <HiddenTrigger>[
  HiddenTrigger(
    term: 'כבד',
    certainty: TriggerCertainty.likely,
    source: '12 §14.5',
  ),
  HiddenTrigger(
    term: 'כבדים',
    certainty: TriggerCertainty.likely,
    source: '12 §14.5',
  ),
  HiddenTrigger(
    term: 'קציצות',
    certainty: TriggerCertainty.likely,
    source: '12 §14.5',
  ),
  HiddenTrigger(
    term: 'עראייס',
    certainty: TriggerCertainty.likely,
    source: '12 §14.5',
  ),
  HiddenTrigger(
    term: "קרפצ'יו",
    certainty: TriggerCertainty.likely,
    source: '12 §14.5',
  ),
  HiddenTrigger(
    term: 'נקניקיה',
    certainty: TriggerCertainty.likely,
    source: '12 §14.5',
  ),
  HiddenTrigger(
    term: 'נקניקייה',
    certainty: TriggerCertainty.likely,
    source: '12 §14.5',
  ),
  HiddenTrigger(
    term: 'ציר',
    certainty: TriggerCertainty.suspected,
    source: '12 §14.5',
  ),
];

/// The guards of paleo, Whole30 and AIP: a removal, a "free" claim, a
/// plant-based substitute or the diet's own name lowers a hit beside it.
const AllergenGuards _dietGuards = AllergenGuards(
  beforeEn: <String>[
    'no',
    'without',
    'free from',
    'no added',
    'unsweetened',
    'paleo',
    'whole30',
    'aip',
    'grain free',
    'dairy free',
    'vegan',
    'plant based',
  ],
  afterEn: <String>['free', 'substitute', 'alternative'],
  beforeHe: <String>['ללא', 'וללא', 'בלי', 'ובלי', 'נטול', 'נטולת', 'תחליף'],
  afterHe: <String>['פליאו', 'טבעוני', 'טבעונית', 'צמחי', 'צמחית'],
);

/// The guards of Jain: a removal, a "free" claim or the restaurant's
/// "Jain" label ("Jain pav bhaji" is made without roots). The plant-based
/// words are term guards on the meat and egg words only ([_jainTermGuards]),
/// so "vegetarian onion soup" keeps its onion.
const AllergenGuards _jainGuards = AllergenGuards(
  beforeEn: <String>['no', 'without', 'free from', 'jain'],
  afterEn: <String>['free'],
  beforeHe: <String>['ללא', 'וללא', 'בלי', 'ובלי', 'נטול', 'נטולת'],
);

/// The guards of pescatarian: `vegetarian`'s, and the diet's own name.
const AllergenGuards _pescatarianGuards = AllergenGuards(
  beforeEn: <String>[
    'pescatarian',
    'vegetarian',
    'vegan',
    'plant based',
    'plant',
    'no',
    'without',
    'imitation',
    'faux',
    'mock',
    'fake',
    'veggie',
    'meatless',
  ],
  afterEn: <String>['alternative', 'substitute', 'analogue'],
  beforeHe: <String>['ללא', 'וללא', 'בלי', 'ובלי', 'נטול', 'נטולת', 'תחליף'],
  afterHe: <String>[
    'צמחוני',
    'צמחונית',
    'צמחוניים',
    'צמחוניות',
    'טבעוני',
    'טבעונית',
    'טבעוניים',
    'טבעוניות',
    'צמחי',
    'צמחית',
    'צמחיים',
    'צמחיות',
    'על בסיס',
  ],
);

/// The fish and plant words that make a meat word another food ("tuna
/// steak", "salmon burger", "veggie sausage"; 11 §30.1, §30.6).
const List<String> _notMeatEn = <String>[
  'fish',
  'salmon',
  'tuna',
  'cod',
  'trout',
  'sea bass',
  'seafood',
  'shrimp',
  'prawn',
  'crab',
  'lobster',
  'swordfish',
  'halibut',
  'tilapia',
  'sardine',
  'mackerel',
  'vegetable',
  'veggie',
  'mushroom',
  'cauliflower',
  'tofu',
  'seitan',
  'bean',
  'lentil',
  'chickpea',
  'beet',
];

/// [_notMeatEn] in Hebrew, after the meat word ("סטייק טונה").
const List<String> _notMeatHe = <String>[
  'דג',
  'דגים',
  'טונה',
  'סלמון',
  'לברק',
  'דניס',
  'בקלה',
  'אמנון',
  'מוסר',
  'פירות ים',
  'שרימפס',
  'ירקות',
  'כרובית',
  'פטריות',
  'עדשים',
  'חומוס',
  'סלק',
  'טופו',
];

/// The pescatarian term guard on a meat word: a fish or plant word just
/// before it.
const AllergenGuards _notMeatBeforeEn = AllergenGuards(beforeEn: _notMeatEn);

/// [_notMeatBeforeEn] in Hebrew: the fish or plant word just after it.
const AllergenGuards _notMeatAfterHe = AllergenGuards(afterHe: _notMeatHe);

/// Pescatarian's fish compounds (11 §30.6): "tuna steak", "salmon
/// burger", "fish sausage", "סטייק טונה", "קציצות דגים".
const Map<String, AllergenGuards> _pescatarianTermGuards =
    <String, AllergenGuards>{
      'steak': _notMeatBeforeEn,
      'burger': _notMeatBeforeEn,
      'burgers': _notMeatBeforeEn,
      'patty': _notMeatBeforeEn,
      'meatball': _notMeatBeforeEn,
      'meatballs': _notMeatBeforeEn,
      'sausage': _notMeatBeforeEn,
      'sausages': _notMeatBeforeEn,
      'kebab': _notMeatBeforeEn,
      'kebabs': _notMeatBeforeEn,
      'nuggets': _notMeatBeforeEn,
      'schnitzel': _notMeatBeforeEn,
      'hot dog': _notMeatBeforeEn,
      'carpaccio': _notMeatBeforeEn,
      'liver': _notMeatBeforeEn,
      'stock': _notMeatBeforeEn,
      'broth': _notMeatBeforeEn,
      'gravy': _notMeatBeforeEn,
      'סטייק': _notMeatAfterHe,
      'המבורגר': _notMeatAfterHe,
      'בורגר': _notMeatAfterHe,
      'קבב': _notMeatAfterHe,
      'קציצות': _notMeatAfterHe,
      'שניצל': _notMeatAfterHe,
      'נקניק': _notMeatAfterHe,
      'נקניקיות': _notMeatAfterHe,
      'נקניקיה': _notMeatAfterHe,
      "קרפצ'יו": _notMeatAfterHe,
      'ציר': _notMeatAfterHe,
    };

/// The Jain term guard on a meat or egg word: a plant-based word just
/// before it ("vegan sausage", "eggless mayo").
const AllergenGuards _plantBasedBeforeEn = AllergenGuards(
  beforeEn: <String>[
    'vegan',
    'vegetarian',
    'veggie',
    'plant based',
    'plant',
    'meatless',
    'mock',
    'faux',
    'imitation',
    'fake',
    'eggless',
  ],
);

/// [_plantBasedBeforeEn] in Hebrew: the word just after it ("נקניק
/// טבעוני").
const AllergenGuards _plantBasedAfterHe = AllergenGuards(
  afterHe: <String>['צמחוני', 'צמחונית', 'טבעוני', 'טבעונית', 'צמחי', 'צמחית'],
);

/// Jain's term guards (11 §30.6): plant-based meat and egg substitutes,
/// date honey (silan, no bees) and the "any" of `שום` ("אין שום", "שום
/// דבר"). The alcohol compounds come with `alcoholTermGuards`.
const Map<String, AllergenGuards> _jainTermGuards = <String, AllergenGuards>{
  'meat': _plantBasedBeforeEn,
  'meats': _plantBasedBeforeEn,
  'chicken': _plantBasedBeforeEn,
  'sausage': _plantBasedBeforeEn,
  'sausages': _plantBasedBeforeEn,
  'meatball': _plantBasedBeforeEn,
  'meatballs': _plantBasedBeforeEn,
  'bacon': _plantBasedBeforeEn,
  'hamburger': _plantBasedBeforeEn,
  'burger': _plantBasedBeforeEn,
  'burgers': _plantBasedBeforeEn,
  'patty': _plantBasedBeforeEn,
  'egg': _plantBasedBeforeEn,
  'eggs': _plantBasedBeforeEn,
  'mayonnaise': _plantBasedBeforeEn,
  'mayo': _plantBasedBeforeEn,
  'בשר': _plantBasedAfterHe,
  'נקניק': _plantBasedAfterHe,
  'נקניקיות': _plantBasedAfterHe,
  'המבורגר': _plantBasedAfterHe,
  'בורגר': _plantBasedAfterHe,
  'שניצל': _plantBasedAfterHe,
  'ביצה': _plantBasedAfterHe,
  'ביצים': _plantBasedAfterHe,
  'מיונז': _plantBasedAfterHe,
  'honey': AllergenGuards(afterEn: <String>['date']),
  'דבש': AllergenGuards(afterHe: <String>['תמרים']),
  'שום': AllergenGuards(beforeHe: <String>['אין'], afterHe: <String>['דבר']),
  'בשום': AllergenGuards(afterHe: <String>['אופן']),
};

/// The compounds that make a grain or dairy word another food (11 §30.6):
/// almond flour, cauliflower rice, zucchini noodles, a Spanish tortilla,
/// coconut milk, nut butter, green beans, whole-grain mustard, rice
/// vinegar. An oat, soy or rice milk keeps its oat, soy or rice.
const Map<String, AllergenGuards> _grainDairyTermGuards =
    <String, AllergenGuards>{
      'grain': AllergenGuards(afterEn: <String>['mustard']),
      'flour': AllergenGuards(
        beforeEn: <String>[
          'almond',
          'coconut',
          'cassava',
          'tapioca',
          'arrowroot',
          'tiger nut',
          'plantain',
          'nut',
          'banana',
        ],
      ),
      'rice': AllergenGuards(
        beforeEn: <String>[
          'cauliflower',
          'cauli',
          'broccoli',
          'konjac',
          'shirataki',
        ],
        afterEn: <String>['vinegar'],
      ),
      'noodle': AllergenGuards(
        beforeEn: <String>[
          'zucchini',
          'courgette',
          'kelp',
          'konjac',
          'shirataki',
          'vegetable',
          'cucumber',
        ],
      ),
      'noodles': AllergenGuards(
        beforeEn: <String>[
          'zucchini',
          'courgette',
          'kelp',
          'konjac',
          'shirataki',
          'vegetable',
          'cucumber',
        ],
      ),
      'spaghetti': AllergenGuards(
        beforeEn: <String>['zucchini', 'vegetable'],
        afterEn: <String>['squash'],
      ),
      'pasta': AllergenGuards(
        beforeEn: <String>['zucchini', 'vegetable', 'veggie'],
      ),
      'pizza': AllergenGuards(beforeEn: <String>['cauliflower']),
      'bread': AllergenGuards(
        beforeEn: <String>['cloud', 'almond', 'coconut', 'cauliflower'],
      ),
      'tortilla': AllergenGuards(
        beforeEn: <String>['spanish', 'cassava', 'coconut', 'almond'],
        afterEn: <String>['espanola', 'de patatas'],
      ),
      'tortillas': AllergenGuards(
        beforeEn: <String>['cassava', 'coconut', 'almond'],
      ),
      'cracker': AllergenGuards(
        beforeEn: <String>['seed', 'flax', 'almond', 'cassava'],
      ),
      'crackers': AllergenGuards(
        beforeEn: <String>['seed', 'flax', 'almond', 'cassava'],
      ),
      'milk': AllergenGuards(
        beforeEn: <String>[
          'almond',
          'coconut',
          'cashew',
          'hazelnut',
          'macadamia',
          'oat',
          'soy',
          'soya',
          'rice',
          'hemp',
          'nut',
        ],
      ),
      'butter': AllergenGuards(
        beforeEn: <String>[
          'almond',
          'cashew',
          'nut',
          'peanut',
          'cocoa',
          'cacao',
          'shea',
          'apple',
          'coconut',
          'sunflower',
          'seed',
          'pistachio',
          'hazelnut',
        ],
      ),
      'cream': AllergenGuards(
        beforeEn: <String>['coconut', 'cashew', 'oat', 'soy'],
      ),
      'cheese': AllergenGuards(beforeEn: <String>['cashew', 'nut']),
      'yogurt': AllergenGuards(
        beforeEn: <String>['coconut', 'almond', 'soy', 'oat', 'cashew'],
      ),
      'yoghurt': AllergenGuards(
        beforeEn: <String>['coconut', 'almond', 'soy', 'oat', 'cashew'],
      ),
      'bean': AllergenGuards(
        beforeEn: <String>[
          'green',
          'string',
          'coffee',
          'vanilla',
          'cocoa',
          'cacao',
          'jelly',
        ],
      ),
      'beans': AllergenGuards(
        beforeEn: <String>[
          'green',
          'string',
          'coffee',
          'vanilla',
          'cocoa',
          'cacao',
          'jelly',
        ],
      ),
      'קמח': AllergenGuards(
        afterHe: <String>['שקדים', 'קוקוס', 'טפיוקה', 'קסאווה', 'אגוזים'],
      ),
      'אורז': AllergenGuards(
        beforeHe: <String>['חומץ'],
        afterHe: <String>['כרובית', 'ברוקולי'],
      ),
      'חלב': AllergenGuards(
        afterHe: <String>[
          'שקדים',
          'סויה',
          'קוקוס',
          'שיבולת שועל',
          'קשיו',
          'אורז',
          'אגוזים',
        ],
      ),
      'חמאת': AllergenGuards(
        afterHe: <String>['בוטנים', 'שקדים', 'קקאו', 'שיאה', 'אגוזים', 'קשיו'],
      ),
      'שמנת': AllergenGuards(afterHe: <String>['קוקוס', 'צמחית']),
      'גבינת': AllergenGuards(afterHe: <String>['קשיו', 'שקדים']),
      'שעועית': AllergenGuards(afterHe: <String>['ירוקה']),
      'ספגטי': AllergenGuards(afterHe: <String>['דלעת', 'קישואים']),
    };

/// Sugar snap peas are no sugar (11 §30.6).
const Map<String, AllergenGuards> _sugarTermGuards = <String, AllergenGuards>{
  'sugar': AllergenGuards(afterEn: <String>['snap']),
};

/// A margherita is a pizza (11 §30.6); the other alcohol compounds (wine
/// vinegar, which Whole30 allows, and a shrimp cocktail) come with
/// `alcoholTermGuards`.
const Map<String, AllergenGuards> _margaritaTermGuards =
    <String, AllergenGuards>{
      'margarita': AllergenGuards(afterEn: <String>['pizza']),
      'מרגריטה': AllergenGuards(beforeHe: <String>['פיצה']),
    };

/// Sweet potato is no nightshade, and black or white pepper is no
/// pepper plant (11 §30.6).
const Map<String, AllergenGuards> _nightshadeTermGuards =
    <String, AllergenGuards>{
      'potato': AllergenGuards(beforeEn: <String>['sweet']),
      'potatoes': AllergenGuards(beforeEn: <String>['sweet']),
      'fries': AllergenGuards(
        beforeEn: <String>[
          'sweet potato',
          'zucchini',
          'carrot',
          'cassava',
          'yuca',
          'plantain',
        ],
      ),
      'פלפל': AllergenGuards(
        beforeHe: <String>['מלח'],
        afterHe: <String>['שחור', 'לבן', 'אנגלי'],
      ),
      "צ'יפס": AllergenGuards(afterHe: <String>['בטטה', 'קישואים']),
      'פירה': AllergenGuards(
        afterHe: <String>['בטטה', 'כרובית', 'סלרי', 'דלעת'],
      ),
    };

/// Diets extra: one entry per restriction this group owns.
const Map<RestrictionId, RestrictionVocabulary> dietsExtraVocabulary =
    <RestrictionId, RestrictionVocabulary>{
      // No meat or poultry; fish and seafood allowed (11 §30.1).
      RestrictionId.pescatarian: RestrictionVocabulary(
        directEn: <String>[...meatPoultryDirectEn, ..._meatExtraEn],
        directHe: <String>[...meatPoultryDirectHe, ..._meatExtraHe],
        hiddenEn: <HiddenTrigger>[
          ...gelatinSweetsHiddenEn,
          ...meatPattyHiddenEn,
          ..._meatExtraHiddenEn,
        ],
        hiddenHe: <HiddenTrigger>[...meatHiddenHe, ..._meatExtraHiddenHe],
        guards: _pescatarianGuards,
        termGuards: _pescatarianTermGuards,
        noPrefixHe: <String>['בשר', 'עוף', 'בקר', 'כבש', 'ציר'],
        sources: <String>['11 §30.1', '11 §30.6', '12 §14.5', '12 §2.2'],
      ),
      // No grains, legumes, dairy, refined sugar or seed oils (11 §30.2).
      RestrictionId.paleo: RestrictionVocabulary(
        directEn: <String>[
          ...wheatFoodsEn,
          ...glutenGrainsEn,
          ..._otherGrainsEn,
          ...legumesDirectEn,
          ...milkWordsEn,
          ...yogurtWordsEn,
          ...curdWordsEn,
          ...dairyFoodsEn,
          ..._cheeseDishesEn,
          'custard',
        ],
        directHe: <String>[
          ...wheatFoodsHe,
          ...glutenGrainsHe,
          ..._otherGrainsHe,
          ...legumesDirectHe,
          ...milkWordsHe,
          ...dairyFoodsHe,
        ],
        hiddenEn: <HiddenTrigger>[
          ..._grainHiddenEn,
          ..._legumeHiddenEn,
          ..._dairyHiddenEn,
          ..._clarifiedButterHiddenEn,
          ..._refinedSugarHiddenEn,
          ..._seedOilsHiddenEn,
        ],
        hiddenHe: <HiddenTrigger>[
          ..._grainHiddenHe,
          ..._legumeHiddenHe,
          ..._dairyHiddenHe,
          ..._clarifiedButterHiddenHe,
          ..._refinedSugarHiddenHe,
          ..._seedOilsHiddenHe,
        ],
        guards: _dietGuards,
        termGuards: <String, AllergenGuards>{
          ..._grainDairyTermGuards,
          ..._sugarTermGuards,
        },
        noPrefixHe: <String>['חיטה', 'חלה', 'חלות', 'בירה', 'פול', 'הפוך'],
        sources: <String>[
          '11 §30.2',
          '11 §30.6',
          '12 §14.1',
          '12 §14.2',
          '11 §7.1',
          '11 §16.1',
          '11 §3.1',
        ],
      ),
      // Paleo's groups plus every added sugar and alcohol; peas, green
      // beans, ghee and cooking oils allowed (11 §30.3).
      RestrictionId.whole30: RestrictionVocabulary(
        directEn: <String>[
          ...wheatFoodsEn,
          ...glutenGrainsEn,
          ..._otherGrainsEn,
          ...soyDirectEn,
          ...peanutDirectEn,
          ...lupinDirectEn,
          ...peanutLupinExtraEn,
          ...pulseFoodsEn,
          ...beanFoodsEn,
          ...milkWordsEn,
          ...yogurtWordsEn,
          ...curdWordsEn,
          ...dairyFoodsEn,
          ..._cheeseDishesEn,
          'custard',
          ..._sugarWordsEn,
          ..._alcoholEn,
        ],
        directHe: <String>[
          ...wheatFoodsHe,
          ...glutenGrainsHe,
          ..._otherGrainsHe,
          ...soyDirectHe,
          ...peanutDirectHe,
          ...lupinDirectHe,
          ...pulseFoodsHe,
          ...beanFoodsHe,
          ...milkWordsHe,
          ...dairyFoodsHe,
          ..._sugarWordsHe,
          ..._alcoholHe,
        ],
        hiddenEn: <HiddenTrigger>[
          ..._grainHiddenEn,
          ..._legumeHiddenEn,
          ..._dairyHiddenEn,
          ..._sugarHiddenEn,
          ..._alcoholHiddenEn,
        ],
        hiddenHe: <HiddenTrigger>[
          ..._grainHiddenHe,
          ..._legumeHiddenHe,
          ..._dairyHiddenHe,
          ..._sugarHiddenHe,
          ..._alcoholHiddenHe,
        ],
        guards: _dietGuards,
        termGuards: <String, AllergenGuards>{
          ..._grainDairyTermGuards,
          ..._sugarTermGuards,
          ...alcoholTermGuards,
          ..._margaritaTermGuards,
        },
        noPrefixHe: <String>[
          'חיטה',
          'חלה',
          'חלות',
          'בירה',
          'פול',
          'הפוך',
          'יין',
          'רום',
        ],
        sources: <String>[
          '11 §30.3',
          '11 §30.6',
          '12 §14.1',
          '12 §14.2',
          '11 §7.1',
          '11 §16.1',
          '11 §3.1',
        ],
      ),
      // Paleo plus eggs, nuts, seeds and seed spices, nightshades, coffee,
      // chocolate and alcohol (11 §30.4).
      RestrictionId.aip: RestrictionVocabulary(
        directEn: <String>[
          ...wheatFoodsEn,
          ...glutenGrainsEn,
          ..._otherGrainsEn,
          ...legumesDirectEn,
          ...milkWordsEn,
          ...yogurtWordsEn,
          ...curdWordsEn,
          ...dairyFoodsEn,
          ..._cheeseDishesEn,
          ...eggsDirectEn,
          ...treeNutsDirectEn,
          ...sesameDirectEn,
          ..._seedsEn,
          ..._seedSpicesEn,
          ..._nightshadesEn,
          ..._coffeeChocolateEn,
          ..._alcoholEn,
        ],
        directHe: <String>[
          ...wheatFoodsHe,
          ...glutenGrainsHe,
          ..._otherGrainsHe,
          ...legumesDirectHe,
          ...milkWordsHe,
          ...dairyFoodsHe,
          ...eggsDirectHe,
          ...treeNutsDirectHe,
          ...sesameDirectHe,
          ..._seedsHe,
          ..._seedSpicesHe,
          ..._nightshadesHe,
          ..._coffeeChocolateHe,
          ..._alcoholHe,
        ],
        hiddenEn: <HiddenTrigger>[
          ..._grainHiddenEn,
          ..._legumeHiddenEn,
          ..._dairyHiddenEn,
          ..._clarifiedButterHiddenEn,
          ..._refinedSugarHiddenEn,
          ..._seedOilsHiddenEn,
          ..._seedSpicesHiddenEn,
          ..._nightshadesHiddenEn,
          ..._coffeeChocolateHiddenEn,
          ..._alcoholHiddenEn,
        ],
        hiddenHe: <HiddenTrigger>[
          ..._grainHiddenHe,
          ..._legumeHiddenHe,
          ..._dairyHiddenHe,
          ..._clarifiedButterHiddenHe,
          ..._refinedSugarHiddenHe,
          ..._seedOilsHiddenHe,
          ..._seedSpicesHiddenHe,
          ..._nightshadesHiddenHe,
          ..._coffeeChocolateHiddenHe,
          ..._alcoholHiddenHe,
        ],
        guards: _dietGuards,
        termGuards: <String, AllergenGuards>{
          ..._grainDairyTermGuards,
          ..._sugarTermGuards,
          ...alcoholTermGuards,
          ..._margaritaTermGuards,
          ..._nightshadeTermGuards,
        },
        noPrefixHe: <String>[
          'חיטה',
          'חלה',
          'חלות',
          'בירה',
          'פול',
          'הפוך',
          'יין',
          'רום',
        ],
        sources: <String>[
          '11 §30.4',
          '11 §30.6',
          '12 §14.1',
          '12 §14.2',
          '12 §14.3',
          '11 §7.1',
          '11 §16.1',
          '11 §3.1',
          '11 §5.1',
          '11 §2.1',
          '11 §11.1',
        ],
      ),
      // No meat, fish, eggs, honey, alcohol or roots (11 §30.5).
      RestrictionId.jain: RestrictionVocabulary(
        directEn: <String>[
          ...meatPoultryDirectEn,
          ...seaAnimalsDirectEn,
          ...eggsDirectEn,
          'honey',
          'honeycomb',
          ..._rootsEn,
        ],
        directHe: <String>[
          ...meatPoultryDirectHe,
          ...seaAnimalsDirectHe,
          ...eggsDirectHe,
          'דבש',
          ..._rootsHe,
        ],
        hiddenEn: <HiddenTrigger>[
          ...gelatinSweetsHiddenEn,
          ...anchovySaucesHiddenEn,
          ...meatPattyHiddenEn,
          ...alcoholHiddenEn,
          ..._rootsHiddenEn,
        ],
        hiddenHe: <HiddenTrigger>[
          ...meatHiddenHe,
          ...alcoholHiddenHe,
          ..._rootsHiddenHe,
        ],
        guards: _jainGuards,
        termGuards: <String, AllergenGuards>{
          ..._jainTermGuards,
          ...alcoholTermGuards,
        },
        noPrefixHe: <String>['בשר', 'עוף', 'בקר', 'כבש', 'רום', 'שום', 'ציר'],
        sources: <String>[
          '11 §30.5',
          '11 §30.6',
          '12 §14.2',
          '12 §14.4',
          '12 §2.2',
          '11 §5.1',
        ],
      ),
    };

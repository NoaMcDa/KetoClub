/// Foods extra: the trigger vocabulary of buckwheat and of the foods on
/// Japan's recommended allergen list that no other id covers — kiwi,
/// peach, apple, banana, orange, beef, pork, chicken, gelatin and yam
/// (Banto; issue #342).
///
/// Every term comes from
/// `allergen app documentation/11_hidden_allergen_sources.md` §26 (one
/// subsection per food, the English menu words and their sources) or
/// `12_israeli_and_us_menu_lexicon.md` §10 (the Hebrew menu words, with
/// the same numbering), and its source cites the subsection, which
/// `test/utils/allergens/vocabulary_test.dart` checks. After a change,
/// regenerate the goldens and copy `allergens.json` to `backend/app/keto/`
/// (architecture.md D26).
///
/// Desk research, not clinical review: the sections are unreviewed, and so
/// is every certainty below; a term the research could not source is
/// `suspected` or left out. Every restriction here is strict (an allergy),
/// so the file favours recall: a dish that names the food is stated, one
/// that usually holds it ("panna cotta", "שניצל") likely, one that may
/// hold it suspected. A guard lowers a hit to suspected, never clears it
/// (ALG-04a).
///
/// The traps the lists are written around (`allergen_matcher.dart`):
///
/// - **Buckwheat is not wheat** (11 §7.5). It stays a guard of wheat's
///   and gluten's triggers in `vocab_gluten_grains.dart` ("buckwheat
///   flour" lowers wheat's "flour"); a guard belongs to one restriction,
///   so it never lowers a buckwheat hit. "yakisoba" (wheat noodles) is one
///   word and never matches "soba"; "yaki soba" is lowered.
/// - **"תפוח אדמה" is a potato**: `תפוח` is lowered before `אדמה`, and the
///   usual plural `תפוחי אדמה` never matches, because `תפוחי` alone is not
///   a term and the Hebrew boundary allows no suffix. "pineapple" is one
///   word and never matches "apple".
/// - **Yam is Japan's yamaimo**, the Japanese mountain yam, **not sweet
///   potato**: a US menu's "yams" are sweet potatoes (11 §26.11), so the
///   bare word is not a term, and `בטטה` never is.
/// - **Real false positives are lowered**: orange roughy (a fish), orange
///   wine, banana peppers, chicken-fried steak (beef), chicken of the
///   woods (a mushroom), turkey bacon.
/// - `בקר`, `עגל`, `חזיר`, `בשר` and `ציר` take no free prefix (`מבקר` is a
///   visitor, `מעגל` a circle, `מחזיר` "returns", `מבשר` "heralds",
///   `בציר` a vintage), so their real prefixed forms are terms of their own
///   — as in alpha-gal's entry (`vocab_extended.dart`).
///
/// Milk is not listed under beef, though some beef-allergic people react
/// to it (bovine serum albumin, 11 §26.7): the Milk restriction carries
/// it, as for alpha-gal. Eggs are not chicken meat; the Eggs restriction
/// carries them. The kosher and halal follow-up builds a pork list of its
/// own (`vocab_religious.dart`); the two may later share one.
library;

import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/utils/allergens/vocabulary_types.dart';

/// The English phrases that lower a trigger of any food here from the
/// word before it ("no kiwi", "without bacon").
const List<String> _negativeBeforeEn = <String>['no', 'without'];

/// The English phrases that lower a trigger from the word after it
/// ("kiwi-free" normalises to "kiwi free").
const List<String> _negativeAfterEn = <String>['free'];

/// The Hebrew phrases that lower a trigger from the words before it
/// ("ללא תפוז", "בלי בייקון").
const List<String> _negativeBeforeHe = <String>['ללא', 'וללא', 'בלי', 'ובלי'];

/// The guards of a fruit, a grain or yam: "no", "without", "-free",
/// "ללא", "בלי".
const AllergenGuards _plainGuards = AllergenGuards(
  beforeEn: _negativeBeforeEn,
  afterEn: _negativeAfterEn,
  beforeHe: _negativeBeforeHe,
);

/// The guards of a meat or of gelatin: the plain ones plus a vegan,
/// vegetarian or imitation version ("vegan bacon", "שניצל טבעוני",
/// "תחליף בשר"), as alpha-gal's entry has them.
const AllergenGuards _meatGuards = AllergenGuards(
  beforeEn: <String>[
    ..._negativeBeforeEn,
    'vegan',
    'vegetarian',
    'plant based',
    'meatless',
    'imitation',
    'faux',
    'mock',
  ],
  afterEn: <String>[..._negativeAfterEn, 'substitute', 'alternative'],
  beforeHe: <String>[..._negativeBeforeHe, 'תחליף'],
  afterHe: <String>['טבעוני', 'טבעונית', 'צמחוני', 'צמחונית', 'צמחי', 'צמחית'],
);

/// Foods extra: one entry per restriction this group owns.
const Map<RestrictionId, RestrictionVocabulary>
foodsExtraVocabulary = <RestrictionId, RestrictionVocabulary>{
  // Buckwheat (11 §26.1, 12 §10.1): on Japan's mandatory list.
  RestrictionId.buckwheat: RestrictionVocabulary(
    directEn: <String>[
      'buckwheat',
      'kasha',
      'soba',
      'sarrasin',
      'blé noir',
      'grano saraceno',
    ],
    directHe: <String>['כוסמת', 'סובה'],
    hiddenEn: <HiddenTrigger>[
      HiddenTrigger(
        term: 'pizzoccheri',
        certainty: TriggerCertainty.likely,
        source: '11 §26.1',
      ),
      HiddenTrigger(
        term: 'polenta taragna',
        certainty: TriggerCertainty.likely,
        source: '11 §26.1',
      ),
      HiddenTrigger(
        term: 'galette',
        certainty: TriggerCertainty.suspected,
        source: '11 §26.1',
      ),
      HiddenTrigger(
        term: 'galettes',
        certainty: TriggerCertainty.suspected,
        source: '11 §26.1',
      ),
      HiddenTrigger(
        term: 'blini',
        certainty: TriggerCertainty.suspected,
        source: '11 §26.1',
      ),
      HiddenTrigger(
        term: 'blinis',
        certainty: TriggerCertainty.suspected,
        source: '11 §26.1',
      ),
      HiddenTrigger(
        term: 'poffertjes',
        certainty: TriggerCertainty.suspected,
        source: '11 §26.1',
      ),
      HiddenTrigger(
        term: 'gluten-free',
        certainty: TriggerCertainty.suspected,
        source: '11 §26.1',
      ),
    ],
    hiddenHe: <HiddenTrigger>[
      HiddenTrigger(
        term: 'בליני',
        certainty: TriggerCertainty.suspected,
        source: '12 §10.1',
      ),
      HiddenTrigger(
        term: 'ללא גלוטן',
        certainty: TriggerCertainty.suspected,
        source: '12 §10.1',
      ),
    ],
    guards: _plainGuards,
    termGuards: <String, AllergenGuards>{
      // Buckwheat honey is a honey, not the grain (11 §26.1).
      'buckwheat': AllergenGuards(afterEn: <String>['honey']),
      // Yakisoba and Okinawa soba are wheat noodles (12 §8.2).
      'soba': AllergenGuards(beforeEn: <String>['yaki', 'okinawa']),
      'סובה': AllergenGuards(beforeHe: <String>['יאקי']),
    },
    sources: <String>['11 §26.1', '12 §10.1'],
  ),
  // Kiwi (11 §26.2, 12 §10.2).
  RestrictionId.kiwi: RestrictionVocabulary(
    directEn: <String>['kiwi', 'kiwis', 'kiwifruit'],
    directHe: <String>['קיווי', 'קיוי'],
    hiddenEn: <HiddenTrigger>[
      HiddenTrigger(
        term: 'fruit salad',
        certainty: TriggerCertainty.suspected,
        source: '11 §26.2',
      ),
      HiddenTrigger(
        term: 'smoothie',
        certainty: TriggerCertainty.suspected,
        source: '11 §26.2',
      ),
      HiddenTrigger(
        term: 'smoothies',
        certainty: TriggerCertainty.suspected,
        source: '11 §26.2',
      ),
      HiddenTrigger(
        term: 'pavlova',
        certainty: TriggerCertainty.suspected,
        source: '11 §26.2',
      ),
    ],
    hiddenHe: <HiddenTrigger>[
      HiddenTrigger(
        term: 'סלט פירות',
        certainty: TriggerCertainty.suspected,
        source: '12 §10.2',
      ),
      HiddenTrigger(
        term: 'שייק פירות',
        certainty: TriggerCertainty.suspected,
        source: '12 §10.2',
      ),
      HiddenTrigger(
        term: 'סמוטי',
        certainty: TriggerCertainty.suspected,
        source: '12 §10.2',
      ),
      HiddenTrigger(
        term: 'פבלובה',
        certainty: TriggerCertainty.suspected,
        source: '12 §10.2',
      ),
    ],
    guards: _plainGuards,
    sources: <String>['11 §26.2', '12 §10.2'],
  ),
  // Peach (11 §26.3, 12 §10.3): a nectarine is the same species.
  RestrictionId.peach: RestrictionVocabulary(
    directEn: <String>['peach', 'peaches'],
    directHe: <String>['אפרסק', 'אפרסקים'],
    hiddenEn: <HiddenTrigger>[
      HiddenTrigger(
        term: 'nectarine',
        certainty: TriggerCertainty.likely,
        source: '11 §26.3',
      ),
      HiddenTrigger(
        term: 'nectarines',
        certainty: TriggerCertainty.likely,
        source: '11 §26.3',
      ),
      HiddenTrigger(
        term: 'bellini',
        certainty: TriggerCertainty.suspected,
        source: '11 §26.3',
      ),
    ],
    hiddenHe: <HiddenTrigger>[
      HiddenTrigger(
        term: 'נקטרינה',
        certainty: TriggerCertainty.likely,
        source: '12 §10.3',
      ),
      HiddenTrigger(
        term: 'נקטרינות',
        certainty: TriggerCertainty.likely,
        source: '12 §10.3',
      ),
    ],
    guards: _plainGuards,
    sources: <String>['11 §26.3', '12 §10.3'],
  ),
  // Apple (11 §26.4, 12 §10.4): "תפוח אדמה" is a potato.
  RestrictionId.apple: RestrictionVocabulary(
    directEn: <String>['apple', 'apples', 'applesauce'],
    directHe: <String>['תפוח', 'תפוחים', 'תפוחי עץ'],
    hiddenEn: <HiddenTrigger>[
      HiddenTrigger(
        term: 'cider',
        certainty: TriggerCertainty.suspected,
        source: '11 §26.4',
      ),
      HiddenTrigger(
        term: 'calvados',
        certainty: TriggerCertainty.suspected,
        source: '11 §26.4',
      ),
      HiddenTrigger(
        term: 'tarte tatin',
        certainty: TriggerCertainty.suspected,
        source: '11 §26.4',
      ),
      HiddenTrigger(
        term: 'waldorf',
        certainty: TriggerCertainty.suspected,
        source: '11 §26.4',
      ),
    ],
    hiddenHe: <HiddenTrigger>[
      HiddenTrigger(
        term: 'סיידר',
        certainty: TriggerCertainty.suspected,
        source: '12 §10.4',
      ),
      HiddenTrigger(
        term: 'קלבדוס',
        certainty: TriggerCertainty.suspected,
        source: '12 §10.4',
      ),
    ],
    guards: _plainGuards,
    termGuards: <String, AllergenGuards>{
      // Custard, sugar, star, rose and wax apples are other fruits.
      'apple': AllergenGuards(
        beforeEn: <String>['custard', 'sugar', 'star', 'rose', 'wax'],
      ),
      'apples': AllergenGuards(
        beforeEn: <String>['custard', 'sugar', 'star', 'rose', 'wax'],
      ),
      // Pear cider (perry) is not apple.
      'cider': AllergenGuards(beforeEn: <String>['pear']),
      'תפוח': AllergenGuards(afterHe: <String>['אדמה']),
    },
    sources: <String>['11 §26.4', '12 §10.4'],
  ),
  // Banana (11 §26.5, 12 §10.5).
  RestrictionId.banana: RestrictionVocabulary(
    directEn: <String>['banana', 'bananas'],
    directHe: <String>['בננה', 'בננות'],
    hiddenEn: <HiddenTrigger>[
      HiddenTrigger(
        term: 'banoffee',
        certainty: TriggerCertainty.likely,
        source: '11 §26.5',
      ),
      HiddenTrigger(
        term: 'plantain',
        certainty: TriggerCertainty.suspected,
        source: '11 §26.5',
      ),
      HiddenTrigger(
        term: 'plantains',
        certainty: TriggerCertainty.suspected,
        source: '11 §26.5',
      ),
      HiddenTrigger(
        term: 'smoothie',
        certainty: TriggerCertainty.suspected,
        source: '11 §26.5',
      ),
      HiddenTrigger(
        term: 'smoothies',
        certainty: TriggerCertainty.suspected,
        source: '11 §26.5',
      ),
    ],
    guards: _plainGuards,
    termGuards: <String, AllergenGuards>{
      // A banana pepper is a chilli, a banana shallot a shallot; a
      // banana leaf is a wrapper (lowered, not cleared).
      'banana': AllergenGuards(
        afterEn: <String>[
          'pepper',
          'peppers',
          'shallot',
          'shallots',
          'leaf',
          'leaves',
        ],
      ),
    },
    sources: <String>['11 §26.5', '12 §10.5'],
  ),
  // Orange (11 §26.6, 12 §10.6): Japan's item is orange alone.
  RestrictionId.orange: RestrictionVocabulary(
    directEn: <String>['orange', 'oranges', "l'orange"],
    directHe: <String>['תפוז', 'תפוזים'],
    hiddenEn: <HiddenTrigger>[
      HiddenTrigger(
        term: 'marmalade',
        certainty: TriggerCertainty.suspected,
        source: '11 §26.6',
      ),
      HiddenTrigger(
        term: 'Grand Marnier',
        certainty: TriggerCertainty.suspected,
        source: '11 §26.6',
      ),
      HiddenTrigger(
        term: 'Cointreau',
        certainty: TriggerCertainty.suspected,
        source: '11 §26.6',
      ),
      HiddenTrigger(
        term: 'triple sec',
        certainty: TriggerCertainty.suspected,
        source: '11 §26.6',
      ),
      HiddenTrigger(
        term: 'curaçao',
        certainty: TriggerCertainty.suspected,
        source: '11 §26.6',
      ),
    ],
    hiddenHe: <HiddenTrigger>[
      HiddenTrigger(
        term: 'מרמלדה',
        certainty: TriggerCertainty.suspected,
        source: '12 §10.6',
      ),
      HiddenTrigger(
        term: 'גרנד מרנייה',
        certainty: TriggerCertainty.suspected,
        source: '12 §10.6',
      ),
      HiddenTrigger(
        term: 'קואנטרו',
        certainty: TriggerCertainty.suspected,
        source: '12 §10.6',
      ),
      HiddenTrigger(
        term: 'טריפל סק',
        certainty: TriggerCertainty.suspected,
        source: '12 §10.6',
      ),
    ],
    guards: _plainGuards,
    termGuards: <String, AllergenGuards>{
      // Orange roughy is a fish; orange wine a skin-contact white
      // wine (11 §26.6). A colour alone is not guarded.
      'orange': AllergenGuards(afterEn: <String>['roughy', 'wine']),
    },
    sources: <String>['11 §26.6', '12 §10.6'],
  ),
  // Beef (11 §26.7, 12 §10.7): veal is a young beef animal.
  RestrictionId.beef: RestrictionVocabulary(
    directEn: <String>[
      'beef',
      'veal',
      'ribeye',
      'rib eye',
      'sirloin',
      'entrecôte',
      'filet mignon',
      'chateaubriand',
      'brisket',
      'oxtail',
      'osso buco',
      'wagyu',
      'angus',
      'bresaola',
    ],
    directHe: <String>[
      'בקר',
      'הבקר',
      'ובקר',
      'עגל',
      'העגל',
      'ועגל',
      'אנטריקוט',
      'סינטה',
      'שייטל',
      'פיקניה',
      'אסאדו',
      'אוסובוקו',
      'רוסטביף',
      'ברזאולה',
    ],
    hiddenEn: <HiddenTrigger>[
      HiddenTrigger(
        term: 'steak',
        certainty: TriggerCertainty.likely,
        source: '11 §26.7',
      ),
      HiddenTrigger(
        term: 'burger',
        certainty: TriggerCertainty.likely,
        source: '11 §26.7',
      ),
      HiddenTrigger(
        term: 'burgers',
        certainty: TriggerCertainty.likely,
        source: '11 §26.7',
      ),
      HiddenTrigger(
        term: 'hamburger',
        certainty: TriggerCertainty.likely,
        source: '11 §26.7',
      ),
      HiddenTrigger(
        term: 'cheeseburger',
        certainty: TriggerCertainty.likely,
        source: '11 §26.7',
      ),
      HiddenTrigger(
        term: 'carpaccio',
        certainty: TriggerCertainty.likely,
        source: '11 §26.7',
      ),
      HiddenTrigger(
        term: 'pastrami',
        certainty: TriggerCertainty.likely,
        source: '11 §26.7',
      ),
      HiddenTrigger(
        term: 'bolognese',
        certainty: TriggerCertainty.likely,
        source: '11 §26.7',
      ),
      HiddenTrigger(
        term: 'ragù',
        certainty: TriggerCertainty.likely,
        source: '11 §26.7',
      ),
      HiddenTrigger(
        term: 'meatball',
        certainty: TriggerCertainty.suspected,
        source: '11 §26.7',
      ),
      HiddenTrigger(
        term: 'meatballs',
        certainty: TriggerCertainty.suspected,
        source: '11 §26.7',
      ),
      HiddenTrigger(
        term: 'kebab',
        certainty: TriggerCertainty.suspected,
        source: '11 §26.7',
      ),
      HiddenTrigger(
        term: 'kofta',
        certainty: TriggerCertainty.suspected,
        source: '11 §26.7',
      ),
      HiddenTrigger(
        term: 'gyro',
        certainty: TriggerCertainty.suspected,
        source: '11 §26.7',
      ),
      HiddenTrigger(
        term: 'gyros',
        certainty: TriggerCertainty.suspected,
        source: '11 §26.7',
      ),
      HiddenTrigger(
        term: 'meat',
        certainty: TriggerCertainty.suspected,
        source: '11 §26.7',
      ),
      HiddenTrigger(
        term: 'stock',
        certainty: TriggerCertainty.suspected,
        source: '11 §26.7',
      ),
      HiddenTrigger(
        term: 'broth',
        certainty: TriggerCertainty.suspected,
        source: '11 §26.7',
      ),
      HiddenTrigger(
        term: 'gravy',
        certainty: TriggerCertainty.suspected,
        source: '11 §26.7',
      ),
      HiddenTrigger(
        term: 'demi-glace',
        certainty: TriggerCertainty.suspected,
        source: '11 §26.7',
      ),
      HiddenTrigger(
        term: 'bone marrow',
        certainty: TriggerCertainty.suspected,
        source: '11 §26.7',
      ),
      HiddenTrigger(
        term: 'tallow',
        certainty: TriggerCertainty.suspected,
        source: '11 §26.7',
      ),
      HiddenTrigger(
        term: 'gelatin',
        certainty: TriggerCertainty.suspected,
        source: '11 §26.7',
      ),
      HiddenTrigger(
        term: 'gelatine',
        certainty: TriggerCertainty.suspected,
        source: '11 §26.7',
      ),
    ],
    hiddenHe: <HiddenTrigger>[
      HiddenTrigger(
        term: 'המבורגר',
        certainty: TriggerCertainty.likely,
        source: '12 §10.7',
      ),
      HiddenTrigger(
        term: 'סטייק',
        certainty: TriggerCertainty.likely,
        source: '12 §10.7',
      ),
      HiddenTrigger(
        term: "קרפצ'יו",
        certainty: TriggerCertainty.likely,
        source: '12 §10.7',
      ),
      HiddenTrigger(
        term: 'בולונז',
        certainty: TriggerCertainty.likely,
        source: '12 §10.7',
      ),
      HiddenTrigger(
        term: 'פסטרמה',
        certainty: TriggerCertainty.suspected,
        source: '12 §10.7',
      ),
      HiddenTrigger(
        term: 'קבב',
        certainty: TriggerCertainty.suspected,
        source: '12 §10.7',
      ),
      HiddenTrigger(
        term: 'קציצות',
        certainty: TriggerCertainty.suspected,
        source: '12 §10.7',
      ),
      HiddenTrigger(
        term: 'בשר',
        certainty: TriggerCertainty.suspected,
        source: '12 §10.7',
      ),
      HiddenTrigger(
        term: 'הבשר',
        certainty: TriggerCertainty.suspected,
        source: '12 §10.7',
      ),
      HiddenTrigger(
        term: 'בבשר',
        certainty: TriggerCertainty.suspected,
        source: '12 §10.7',
      ),
      HiddenTrigger(
        term: 'ובשר',
        certainty: TriggerCertainty.suspected,
        source: '12 §10.7',
      ),
      HiddenTrigger(
        term: "צ'ולנט",
        certainty: TriggerCertainty.suspected,
        source: '12 §10.7',
      ),
      HiddenTrigger(
        term: 'חמין',
        certainty: TriggerCertainty.suspected,
        source: '12 §10.7',
      ),
      HiddenTrigger(
        term: 'מח עצם',
        certainty: TriggerCertainty.suspected,
        source: '12 §10.7',
      ),
      HiddenTrigger(
        term: 'ציר',
        certainty: TriggerCertainty.suspected,
        source: '12 §10.7',
      ),
      HiddenTrigger(
        term: 'הציר',
        certainty: TriggerCertainty.suspected,
        source: '12 §10.7',
      ),
      HiddenTrigger(
        term: 'וציר',
        certainty: TriggerCertainty.suspected,
        source: '12 §10.7',
      ),
      HiddenTrigger(
        term: "ג'לטין",
        certainty: TriggerCertainty.suspected,
        source: '12 §10.7',
      ),
    ],
    guards: _meatGuards,
    termGuards: <String, AllergenGuards>{
      'steak': AllergenGuards(
        beforeEn: <String>[
          'tuna',
          'salmon',
          'swordfish',
          'fish',
          'cauliflower',
          'portobello',
          'mushroom',
          'chicken',
          'turkey',
          'pork',
        ],
      ),
      'burger': AllergenGuards(
        beforeEn: <String>[
          'chicken',
          'turkey',
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
          'lamb',
        ],
      ),
      'burgers': AllergenGuards(
        beforeEn: <String>[
          'chicken',
          'turkey',
          'fish',
          'veggie',
          'beyond',
          'impossible',
          'lamb',
        ],
      ),
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
      'pastrami': AllergenGuards(beforeEn: <String>['turkey', 'chicken']),
      'bolognese': AllergenGuards(
        beforeEn: <String>['chicken', 'turkey', 'tuna', 'lentil'],
      ),
      'ragù': AllergenGuards(
        beforeEn: <String>['chicken', 'duck', 'lamb', 'boar', 'mushroom'],
      ),
      'meat': AllergenGuards(
        beforeEn: <String>[
          'crab',
          'chicken',
          'turkey',
          'duck',
          'fish',
          'coconut',
          'jackfruit',
        ],
      ),
      'המבורגר': AllergenGuards(
        afterHe: <String>['עוף', 'הודו', 'דג', 'סלמון', 'טלה'],
      ),
      'סטייק': AllergenGuards(
        afterHe: <String>[
          'טונה',
          'סלמון',
          'כרובית',
          'פורטובלו',
          'עוף',
          'הודו',
          'דג',
          'לבן',
        ],
      ),
      "קרפצ'יו": AllergenGuards(
        afterHe: <String>['סלק', 'דג', 'סלמון', 'טונה', 'לברק'],
      ),
      'בולונז': AllergenGuards(afterHe: <String>['עוף', 'הודו', 'עדשים']),
      'בשר': AllergenGuards(
        afterHe: <String>['עוף', 'הודו', 'דג', 'דגים', 'סויה', 'לבן'],
      ),
    },
    noPrefixHe: <String>['בקר', 'עגל', 'בשר', 'ציר'],
    sources: <String>['11 §26.7', '12 §10.7'],
  ),
  // Pork (11 §26.8, 12 §10.8).
  RestrictionId.pork: RestrictionVocabulary(
    directEn: <String>[
      'pork',
      'pig',
      'piglet',
      'boar',
      'bacon',
      'ham',
      'gammon',
      'lard',
      'lardo',
      'lardons',
      'pancetta',
      'guanciale',
      'prosciutto',
      'jamón',
      'porchetta',
      'carnitas',
      'char siu',
      'tonkatsu',
      'tonkotsu',
    ],
    directHe: <String>['חזיר', 'החזיר', 'וחזיר', 'בחזיר'],
    hiddenEn: <HiddenTrigger>[
      HiddenTrigger(
        term: 'chorizo',
        certainty: TriggerCertainty.likely,
        source: '11 §26.8',
      ),
      HiddenTrigger(
        term: 'mortadella',
        certainty: TriggerCertainty.likely,
        source: '11 §26.8',
      ),
      HiddenTrigger(
        term: 'speck',
        certainty: TriggerCertainty.likely,
        source: '11 §26.8',
      ),
      HiddenTrigger(
        term: 'bratwurst',
        certainty: TriggerCertainty.likely,
        source: '11 §26.8',
      ),
      HiddenTrigger(
        term: 'kielbasa',
        certainty: TriggerCertainty.likely,
        source: '11 §26.8',
      ),
      HiddenTrigger(
        term: 'chicharrón',
        certainty: TriggerCertainty.likely,
        source: '11 §26.8',
      ),
      HiddenTrigger(
        term: 'chicharrones',
        certainty: TriggerCertainty.likely,
        source: '11 §26.8',
      ),
      HiddenTrigger(
        term: 'spare ribs',
        certainty: TriggerCertainty.likely,
        source: '11 §26.8',
      ),
      HiddenTrigger(
        term: 'baby back ribs',
        certainty: TriggerCertainty.likely,
        source: '11 §26.8',
      ),
      HiddenTrigger(
        term: 'salami',
        certainty: TriggerCertainty.suspected,
        source: '11 §26.8',
      ),
      HiddenTrigger(
        term: 'pepperoni',
        certainty: TriggerCertainty.suspected,
        source: '11 §26.8',
      ),
      HiddenTrigger(
        term: 'sausage',
        certainty: TriggerCertainty.suspected,
        source: '11 §26.8',
      ),
      HiddenTrigger(
        term: 'sausages',
        certainty: TriggerCertainty.suspected,
        source: '11 §26.8',
      ),
      HiddenTrigger(
        term: 'hot dog',
        certainty: TriggerCertainty.suspected,
        source: '11 §26.8',
      ),
      HiddenTrigger(
        term: 'hot dogs',
        certainty: TriggerCertainty.suspected,
        source: '11 §26.8',
      ),
      HiddenTrigger(
        term: 'carbonara',
        certainty: TriggerCertainty.suspected,
        source: '11 §26.8',
      ),
      HiddenTrigger(
        term: 'amatriciana',
        certainty: TriggerCertainty.suspected,
        source: '11 §26.8',
      ),
      HiddenTrigger(
        term: 'gelatin',
        certainty: TriggerCertainty.suspected,
        source: '11 §26.8',
      ),
      HiddenTrigger(
        term: 'gelatine',
        certainty: TriggerCertainty.suspected,
        source: '11 §26.8',
      ),
    ],
    hiddenHe: <HiddenTrigger>[
      HiddenTrigger(
        term: 'בשר לבן',
        certainty: TriggerCertainty.likely,
        source: '12 §10.8',
      ),
      HiddenTrigger(
        term: 'ירך לבן',
        certainty: TriggerCertainty.likely,
        source: '12 §10.8',
      ),
      HiddenTrigger(
        term: 'בייקון',
        certainty: TriggerCertainty.likely,
        source: '12 §10.8',
      ),
      HiddenTrigger(
        term: 'פרושוטו',
        certainty: TriggerCertainty.likely,
        source: '12 §10.8',
      ),
      HiddenTrigger(
        term: "פנצ'טה",
        certainty: TriggerCertainty.likely,
        source: '12 §10.8',
      ),
      HiddenTrigger(
        term: 'סטייק לבן',
        certainty: TriggerCertainty.suspected,
        source: '12 §10.8',
      ),
      HiddenTrigger(
        term: 'סלמי',
        certainty: TriggerCertainty.suspected,
        source: '12 §10.8',
      ),
      HiddenTrigger(
        term: 'פפרוני',
        certainty: TriggerCertainty.suspected,
        source: '12 §10.8',
      ),
      HiddenTrigger(
        term: "צ'וריסו",
        certainty: TriggerCertainty.suspected,
        source: '12 §10.8',
      ),
      HiddenTrigger(
        term: 'נקניק',
        certainty: TriggerCertainty.suspected,
        source: '12 §10.8',
      ),
      HiddenTrigger(
        term: "ג'לטין",
        certainty: TriggerCertainty.suspected,
        source: '12 §10.8',
      ),
    ],
    guards: _meatGuards,
    termGuards: <String, AllergenGuards>{
      // The words beside a pork word that name another meat: kosher
      // menus print "turkey bacon", "בייקון בקר" and "פרושוטו אווז".
      'pig': AllergenGuards(beforeEn: <String>['guinea']),
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
      'chorizo': AllergenGuards(
        beforeEn: <String>['chicken', 'beef', 'veggie'],
      ),
      'bratwurst': AllergenGuards(
        beforeEn: <String>['chicken', 'turkey', 'veggie'],
      ),
      'kielbasa': AllergenGuards(beforeEn: <String>['turkey', 'beef']),
      'salami': AllergenGuards(
        beforeEn: <String>['turkey', 'chicken', 'beef', 'goose'],
      ),
      'pepperoni': AllergenGuards(
        beforeEn: <String>['turkey', 'chicken', 'beef'],
      ),
      'sausage': AllergenGuards(
        beforeEn: <String>[
          'chicken',
          'turkey',
          'beef',
          'lamb',
          'veggie',
          'fish',
        ],
      ),
      'sausages': AllergenGuards(
        beforeEn: <String>[
          'chicken',
          'turkey',
          'beef',
          'lamb',
          'veggie',
          'fish',
        ],
      ),
      'hot dog': AllergenGuards(
        beforeEn: <String>['chicken', 'turkey', 'beef'],
      ),
      'hot dogs': AllergenGuards(
        beforeEn: <String>['chicken', 'turkey', 'beef'],
      ),
      'בייקון': AllergenGuards(
        afterHe: <String>['בקר', 'הודו', 'אווז', 'טלה', 'עוף'],
      ),
      'פרושוטו': AllergenGuards(
        afterHe: <String>['אווז', 'ברווז', 'בקר', 'הודו'],
      ),
      'סלמי': AllergenGuards(afterHe: <String>['הודו', 'עוף', 'בקר', 'אווז']),
      'פפרוני': AllergenGuards(afterHe: <String>['הודו', 'עוף', 'בקר']),
      "צ'וריסו": AllergenGuards(afterHe: <String>['עוף', 'בקר']),
      'נקניק': AllergenGuards(afterHe: <String>['עוף', 'הודו', 'בקר']),
    },
    noPrefixHe: <String>['חזיר'],
    sources: <String>['11 §26.8', '12 §10.8'],
  ),
  // Chicken (11 §26.9, 12 §10.9): eggs are not chicken meat.
  RestrictionId.chicken: RestrictionVocabulary(
    directEn: <String>[
      'chicken',
      'poussin',
      'capon',
      'cornish hen',
      'coq au vin',
      'pollo',
    ],
    directHe: <String>['עוף', 'עופות', 'פרגית', 'פרגיות'],
    hiddenEn: <HiddenTrigger>[
      HiddenTrigger(
        term: 'wings',
        certainty: TriggerCertainty.likely,
        source: '11 §26.9',
      ),
      HiddenTrigger(
        term: 'nuggets',
        certainty: TriggerCertainty.likely,
        source: '11 §26.9',
      ),
      HiddenTrigger(
        term: 'tenders',
        certainty: TriggerCertainty.likely,
        source: '11 §26.9',
      ),
      HiddenTrigger(
        term: 'schnitzel',
        certainty: TriggerCertainty.suspected,
        source: '11 §26.9',
      ),
      HiddenTrigger(
        term: 'shawarma',
        certainty: TriggerCertainty.suspected,
        source: '11 §26.9',
      ),
      HiddenTrigger(
        term: 'poultry',
        certainty: TriggerCertainty.suspected,
        source: '11 §26.9',
      ),
      HiddenTrigger(
        term: 'stock',
        certainty: TriggerCertainty.suspected,
        source: '11 §26.9',
      ),
      HiddenTrigger(
        term: 'broth',
        certainty: TriggerCertainty.suspected,
        source: '11 §26.9',
      ),
      HiddenTrigger(
        term: 'bouillon',
        certainty: TriggerCertainty.suspected,
        source: '11 §26.9',
      ),
    ],
    hiddenHe: <HiddenTrigger>[
      HiddenTrigger(
        term: 'שניצל',
        certainty: TriggerCertainty.likely,
        source: '12 §10.9',
      ),
      HiddenTrigger(
        term: 'שניצלונים',
        certainty: TriggerCertainty.likely,
        source: '12 §10.9',
      ),
      HiddenTrigger(
        term: 'נאגטס',
        certainty: TriggerCertainty.likely,
        source: '12 §10.9',
      ),
      HiddenTrigger(
        term: 'כנפיים',
        certainty: TriggerCertainty.suspected,
        source: '12 §10.9',
      ),
      HiddenTrigger(
        term: 'שוקיים',
        certainty: TriggerCertainty.suspected,
        source: '12 §10.9',
      ),
      HiddenTrigger(
        term: 'קורקבנים',
        certainty: TriggerCertainty.suspected,
        source: '12 §10.9',
      ),
      HiddenTrigger(
        term: 'שווארמה',
        certainty: TriggerCertainty.suspected,
        source: '12 §10.9',
      ),
      HiddenTrigger(
        term: 'ציר',
        certainty: TriggerCertainty.suspected,
        source: '12 §10.9',
      ),
      HiddenTrigger(
        term: 'הציר',
        certainty: TriggerCertainty.suspected,
        source: '12 §10.9',
      ),
      HiddenTrigger(
        term: 'וציר',
        certainty: TriggerCertainty.suspected,
        source: '12 §10.9',
      ),
    ],
    guards: _meatGuards,
    termGuards: <String, AllergenGuards>{
      // Chicken-fried steak is beef; chicken of the woods a mushroom;
      // chicken eggs are the Eggs restriction's (11 §26.9).
      'chicken': AllergenGuards(
        afterEn: <String>['fried steak', 'of the woods', 'egg', 'eggs'],
      ),
      'wings': AllergenGuards(
        beforeEn: <String>[
          'cauliflower',
          'tofu',
          'seitan',
          'duck',
          'turkey',
          'angel',
        ],
      ),
      'nuggets': AllergenGuards(
        beforeEn: <String>['veggie', 'tofu', 'fish', 'cauliflower'],
      ),
      'tenders': AllergenGuards(
        beforeEn: <String>['veggie', 'tofu', 'fish', 'turkey'],
      ),
      'schnitzel': AllergenGuards(
        beforeEn: <String>['veal', 'pork', 'turkey', 'eggplant', 'cauliflower'],
      ),
      'shawarma': AllergenGuards(
        beforeEn: <String>['lamb', 'beef', 'turkey', 'veal'],
      ),
      'שניצל': AllergenGuards(
        afterHe: <String>[
          'הודו',
          'תירס',
          'חציל',
          'חצילים',
          'כרובית',
          'דג',
          'סויה',
          'עגל',
          'חזיר',
        ],
      ),
      'שניצלונים': AllergenGuards(afterHe: <String>['הודו', 'תירס', 'דגים']),
      'נאגטס': AllergenGuards(afterHe: <String>['דגים', 'תירס']),
      'שווארמה': AllergenGuards(
        afterHe: <String>['הודו', 'טלה', 'כבש', 'עגל', 'בקר'],
      ),
    },
    noPrefixHe: <String>['ציר'],
    sources: <String>['11 §26.9', '12 §10.9'],
  ),
  // Gelatin (11 §26.10, 12 §10.10): fish gelatin is still gelatin.
  RestrictionId.gelatin: RestrictionVocabulary(
    directEn: <String>['gelatin', 'gelatine', 'aspic', 'Jell-O', 'jello'],
    directHe: <String>["ג'לטין"],
    hiddenEn: <HiddenTrigger>[
      HiddenTrigger(
        term: 'gummy',
        certainty: TriggerCertainty.likely,
        source: '11 §26.10',
      ),
      HiddenTrigger(
        term: 'gummies',
        certainty: TriggerCertainty.likely,
        source: '11 §26.10',
      ),
      HiddenTrigger(
        term: 'marshmallow',
        certainty: TriggerCertainty.likely,
        source: '11 §26.10',
      ),
      HiddenTrigger(
        term: 'marshmallows',
        certainty: TriggerCertainty.likely,
        source: '11 §26.10',
      ),
      HiddenTrigger(
        term: 'panna cotta',
        certainty: TriggerCertainty.likely,
        source: '11 §26.10',
      ),
      HiddenTrigger(
        term: 'jelly',
        certainty: TriggerCertainty.suspected,
        source: '11 §26.10',
      ),
      HiddenTrigger(
        term: 'mousse',
        certainty: TriggerCertainty.suspected,
        source: '11 §26.10',
      ),
      HiddenTrigger(
        term: 'no-bake cheesecake',
        certainty: TriggerCertainty.suspected,
        source: '11 §26.10',
      ),
      HiddenTrigger(
        term: 'trifle',
        certainty: TriggerCertainty.suspected,
        source: '11 §26.10',
      ),
      HiddenTrigger(
        term: 'bavarois',
        certainty: TriggerCertainty.suspected,
        source: '11 §26.10',
      ),
      HiddenTrigger(
        term: 'terrine',
        certainty: TriggerCertainty.suspected,
        source: '11 §26.10',
      ),
      HiddenTrigger(
        term: 'mirror glaze',
        certainty: TriggerCertainty.suspected,
        source: '11 §26.10',
      ),
    ],
    hiddenHe: <HiddenTrigger>[
      HiddenTrigger(
        term: 'פנקוטה',
        certainty: TriggerCertainty.likely,
        source: '12 §10.10',
      ),
      HiddenTrigger(
        term: 'פנה קוטה',
        certainty: TriggerCertainty.likely,
        source: '12 §10.10',
      ),
      HiddenTrigger(
        term: 'מרשמלו',
        certainty: TriggerCertainty.likely,
        source: '12 §10.10',
      ),
      HiddenTrigger(
        term: 'סוכריות גומי',
        certainty: TriggerCertainty.likely,
        source: '12 §10.10',
      ),
      HiddenTrigger(
        term: 'דובוני גומי',
        certainty: TriggerCertainty.likely,
        source: '12 §10.10',
      ),
      HiddenTrigger(
        term: "ג'לי",
        certainty: TriggerCertainty.suspected,
        source: '12 §10.10',
      ),
      HiddenTrigger(
        term: 'מוס',
        certainty: TriggerCertainty.suspected,
        source: '12 §10.10',
      ),
      HiddenTrigger(
        term: 'עוגת גבינה קרה',
        certainty: TriggerCertainty.suspected,
        source: '12 §10.10',
      ),
    ],
    guards: AllergenGuards(
      beforeEn: <String>[..._negativeBeforeEn, 'vegan', 'vegetarian', 'agar'],
      afterEn: _negativeAfterEn,
      beforeHe: _negativeBeforeHe,
      afterHe: <String>['טבעוני', 'טבעונית', 'צמחי', 'צמחית'],
    ),
    sources: <String>['11 §26.10', '12 §10.10'],
  ),
  // Yam (11 §26.11, 12 §10.11): Japan's yamaimo, not sweet potato.
  RestrictionId.yam: RestrictionVocabulary(
    directEn: <String>[
      'yamaimo',
      'nagaimo',
      'jinenjo',
      'tororo',
      'japanese yam',
      'chinese yam',
      'mountain yam',
    ],
    directHe: <String>['יאמאימו', 'נאגאימו', 'טורורו'],
    hiddenEn: <HiddenTrigger>[
      HiddenTrigger(
        term: 'yamakake',
        certainty: TriggerCertainty.likely,
        source: '11 §26.11',
      ),
      HiddenTrigger(
        term: 'okonomiyaki',
        certainty: TriggerCertainty.suspected,
        source: '11 §26.11',
      ),
      HiddenTrigger(
        term: 'hanpen',
        certainty: TriggerCertainty.suspected,
        source: '11 §26.11',
      ),
      HiddenTrigger(
        term: 'purple yam',
        certainty: TriggerCertainty.suspected,
        source: '11 §26.11',
      ),
      HiddenTrigger(
        term: 'ube',
        certainty: TriggerCertainty.suspected,
        source: '11 §26.11',
      ),
    ],
    hiddenHe: <HiddenTrigger>[
      HiddenTrigger(
        term: 'אוקונומיאקי',
        certainty: TriggerCertainty.suspected,
        source: '12 §10.11',
      ),
    ],
    guards: _plainGuards,
    sources: <String>['11 §26.11', '12 §10.11'],
  ),
};

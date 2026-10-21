/// Seeds extra: the trigger vocabulary of corn, sunflower seeds and
/// flaxseed (Banto; issue #342; file 02, "Less common allergens worth
/// supporting").
///
/// Every term comes from
/// `allergen app documentation/11_hidden_allergen_sources.md` §27 or
/// `12_israeli_and_us_menu_lexicon.md` §11 and its source cites the
/// section, which `test/utils/allergens/vocabulary_test.dart` checks. After
/// a change, regenerate the goldens and copy `allergens.json` to
/// `backend/app/keto/` (architecture.md D26).
///
/// Desk research, not clinical review: the sections are unreviewed, and so
/// is every certainty below. None of the three is a regulated allergen in
/// the US, the EU or Israel (11 §27), so no label law makes a kitchen name
/// them; this file favours recall and lets a certainty say how often.
///
/// Matcher facts the lists are written around (`allergen_matcher.dart`):
/// a guard lowers a hit to `suspected` and never cancels it, and counts
/// only in the slot beside its term (ALG-04a). So a refined oil, a syrup
/// or a starch is a term guard on the food it is made from ("corn oil",
/// "שמן חמניות"): guidance differs on whether those carry enough protein
/// to matter (11 §27.1, §27.3), so the hit stays, lowered. A "popcorn
/// shrimp" is a size, not a corn coating, and is lowered the same way.
///
/// Corn and flax are also words of the wheat vocabulary
/// (`vocab_gluten_grains.dart`): term guards that lower wheat's `flour`
/// in "corn flour" and its `crackers` in "flax crackers". A term guard
/// belongs to one restriction only, so those roles lower wheat and never
/// corn or flax. Corn is a keto carb trigger too (`constants.dart`); this
/// file is allergen vocabulary only and changes no keto verdict.
library;

import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/utils/allergens/vocabulary_types.dart';

/// The words after "corn" or "maize" that make it a refined product the
/// corn-allergy guidance disagrees about (11 §27.1): lowered, never
/// dropped.
const List<String> _cornRefinedEn = <String>['oil', 'syrup', 'starch', 'sugar'];

/// [_cornRefinedEn] before the Hebrew `תירס` ("שמן תירס", "עמילן תירס").
const List<String> _cornRefinedHe = <String>['שמן', 'סירופ', 'עמילן'];

/// The words after "popcorn" that name a size of fried morsel, not corn
/// (11 §27.5).
const List<String> _popcornMorselsEn = <String>[
  'shrimp',
  'chicken',
  'prawns',
  'prawn',
];

/// The seeded breads and seed mixes that usually hold flax, sunflower seed
/// or both (11 §27.4), in English.
const List<HiddenTrigger> _seededBreadsEn = <HiddenTrigger>[
  HiddenTrigger(
    term: 'multigrain',
    certainty: TriggerCertainty.suspected,
    source: '11 §27.4',
  ),
  HiddenTrigger(
    term: 'multi grain',
    certainty: TriggerCertainty.suspected,
    source: '11 §27.4',
  ),
  HiddenTrigger(
    term: 'multiseed',
    certainty: TriggerCertainty.suspected,
    source: '11 §27.4',
  ),
  HiddenTrigger(
    term: 'seeded bread',
    certainty: TriggerCertainty.suspected,
    source: '11 §27.4',
  ),
  HiddenTrigger(
    term: 'seeded roll',
    certainty: TriggerCertainty.suspected,
    source: '11 §27.4',
  ),
  HiddenTrigger(
    term: 'mixed seeds',
    certainty: TriggerCertainty.suspected,
    source: '11 §27.4',
  ),
  HiddenTrigger(
    term: 'seed mix',
    certainty: TriggerCertainty.suspected,
    source: '11 §27.4',
  ),
  HiddenTrigger(
    term: 'seed crackers',
    certainty: TriggerCertainty.suspected,
    source: '11 §27.4',
  ),
];

/// [_seededBreadsEn] as an Israeli menu writes them (12 §11.3).
const List<HiddenTrigger> _seededBreadsHe = <HiddenTrigger>[
  HiddenTrigger(
    term: 'לחם דגנים',
    certainty: TriggerCertainty.suspected,
    source: '12 §11.3',
  ),
  HiddenTrigger(
    term: 'לחמניית דגנים',
    certainty: TriggerCertainty.suspected,
    source: '12 §11.3',
  ),
  HiddenTrigger(
    term: 'רב דגנים',
    certainty: TriggerCertainty.suspected,
    source: '12 §11.3',
  ),
  HiddenTrigger(
    term: 'לחם זרעים',
    certainty: TriggerCertainty.suspected,
    source: '12 §11.3',
  ),
  HiddenTrigger(
    term: 'תערובת זרעים',
    certainty: TriggerCertainty.suspected,
    source: '12 §11.3',
  ),
  HiddenTrigger(
    term: 'קרקר זרעים',
    certainty: TriggerCertainty.suspected,
    source: '12 §11.3',
  ),
];

/// Sunflower's direct Hebrew triggers. Every one takes no free prefix,
/// because the prefix ל turns them into a bread roll (לחמנייה, לחמניה,
/// לחמניות, לחמנית); the "and" forms are terms of their own.
const List<String> _sunflowerHe = <String>[
  'חמנייה',
  'חמניה',
  'חמניות',
  'חמנית',
  'וחמנייה',
  'וחמניה',
  'וחמניות',
  'וחמנית',
];

/// Seeds extra: one entry per restriction this group owns.
///
/// The restriction-wide guards are the negations and the "-free" family
/// only (`no`, `without`, `corn free`, `ללא`). Everything that names
/// another food is a term guard.
const Map<RestrictionId, RestrictionVocabulary> seedsExtraVocabulary =
    <RestrictionId, RestrictionVocabulary>{
      RestrictionId.corn: RestrictionVocabulary(
        directEn: <String>[
          'corn',
          'maize',
          'sweetcorn',
          'cornmeal',
          'cornbread',
          'cornflakes',
          'popcorn',
          'polenta',
          'grits',
          'hominy',
          'masa',
          'elote',
          'esquites',
        ],
        directHe: <String>['תירס', 'פולנטה', 'פופקורן', 'קורנפלקס'],
        hiddenEn: <HiddenTrigger>[
          // Dishes made of corn masa or cornmeal by definition.
          HiddenTrigger(
            term: 'arepa',
            certainty: TriggerCertainty.likely,
            source: '11 §27.2',
          ),
          HiddenTrigger(
            term: 'arepas',
            certainty: TriggerCertainty.likely,
            source: '11 §27.2',
          ),
          HiddenTrigger(
            term: 'tamale',
            certainty: TriggerCertainty.likely,
            source: '11 §27.2',
          ),
          HiddenTrigger(
            term: 'tamales',
            certainty: TriggerCertainty.likely,
            source: '11 §27.2',
          ),
          HiddenTrigger(
            term: 'pupusa',
            certainty: TriggerCertainty.likely,
            source: '11 §27.2',
          ),
          HiddenTrigger(
            term: 'pupusas',
            certainty: TriggerCertainty.likely,
            source: '11 §27.2',
          ),
          HiddenTrigger(
            term: 'pozole',
            certainty: TriggerCertainty.likely,
            source: '11 §27.2',
          ),
          HiddenTrigger(
            term: 'succotash',
            certainty: TriggerCertainty.likely,
            source: '11 §27.2',
          ),
          // Tortilla chips are corn; Bamba is puffed maize (11 §27.2).
          HiddenTrigger(
            term: 'nachos',
            certainty: TriggerCertainty.likely,
            source: '11 §27.2',
          ),
          HiddenTrigger(
            term: 'tortilla chips',
            certainty: TriggerCertainty.likely,
            source: '11 §27.2',
          ),
          HiddenTrigger(
            term: 'tostada',
            certainty: TriggerCertainty.likely,
            source: '11 §27.2',
          ),
          HiddenTrigger(
            term: 'tostadas',
            certainty: TriggerCertainty.likely,
            source: '11 §27.2',
          ),
          HiddenTrigger(
            term: 'bamba',
            certainty: TriggerCertainty.likely,
            source: '11 §27.2',
          ),
          // A tortilla is corn or wheat: suspected unless "corn" is
          // named, which the direct `corn` then reports (11 §27.2).
          HiddenTrigger(
            term: 'tortilla',
            certainty: TriggerCertainty.suspected,
            source: '11 §27.2',
          ),
          HiddenTrigger(
            term: 'tortillas',
            certainty: TriggerCertainty.suspected,
            source: '11 §27.2',
          ),
          HiddenTrigger(
            term: 'taco',
            certainty: TriggerCertainty.suspected,
            source: '11 §27.2',
          ),
          HiddenTrigger(
            term: 'tacos',
            certainty: TriggerCertainty.suspected,
            source: '11 §27.2',
          ),
          HiddenTrigger(
            term: 'enchilada',
            certainty: TriggerCertainty.suspected,
            source: '11 §27.2',
          ),
          HiddenTrigger(
            term: 'enchiladas',
            certainty: TriggerCertainty.suspected,
            source: '11 §27.2',
          ),
          // Refined corn products: guidance disagrees (11 §27.1).
          HiddenTrigger(
            term: 'cornstarch',
            certainty: TriggerCertainty.suspected,
            source: '11 §27.1',
          ),
          HiddenTrigger(
            term: 'cornflour',
            certainty: TriggerCertainty.suspected,
            source: '11 §27.1',
          ),
          HiddenTrigger(
            term: 'corn syrup',
            certainty: TriggerCertainty.suspected,
            source: '11 §27.1',
          ),
          HiddenTrigger(
            term: 'high fructose corn syrup',
            certainty: TriggerCertainty.suspected,
            source: '11 §27.1',
          ),
          HiddenTrigger(
            term: 'hfcs',
            certainty: TriggerCertainty.suspected,
            source: '11 §27.1',
          ),
          HiddenTrigger(
            term: 'corn oil',
            certainty: TriggerCertainty.suspected,
            source: '11 §27.1',
          ),
        ],
        hiddenHe: <HiddenTrigger>[
          HiddenTrigger(
            term: 'נאצ׳וס',
            certainty: TriggerCertainty.likely,
            source: '12 §11.1',
          ),
          HiddenTrigger(
            term: 'במבה',
            certainty: TriggerCertainty.likely,
            source: '12 §11.1',
          ),
          HiddenTrigger(
            term: 'ארפה',
            certainty: TriggerCertainty.likely,
            source: '12 §11.1',
          ),
          HiddenTrigger(
            term: 'טורטייה',
            certainty: TriggerCertainty.suspected,
            source: '12 §11.1',
          ),
          HiddenTrigger(
            term: 'טורטיה',
            certainty: TriggerCertainty.suspected,
            source: '12 §11.1',
          ),
          HiddenTrigger(
            term: 'טורטיות',
            certainty: TriggerCertainty.suspected,
            source: '12 §11.1',
          ),
          HiddenTrigger(
            term: 'טורטיית',
            certainty: TriggerCertainty.suspected,
            source: '12 §11.1',
          ),
          HiddenTrigger(
            term: 'טאקו',
            certainty: TriggerCertainty.suspected,
            source: '12 §11.1',
          ),
          HiddenTrigger(
            term: 'קורנפלור',
            certainty: TriggerCertainty.suspected,
            source: '12 §11.1',
          ),
          HiddenTrigger(
            term: 'עמילן תירס',
            certainty: TriggerCertainty.suspected,
            source: '12 §11.1',
          ),
          HiddenTrigger(
            term: 'שמן תירס',
            certainty: TriggerCertainty.suspected,
            source: '12 §11.1',
          ),
          HiddenTrigger(
            term: 'סירופ תירס',
            certainty: TriggerCertainty.suspected,
            source: '12 §11.1',
          ),
        ],
        guards: AllergenGuards(
          beforeEn: <String>['no', 'without', 'free of', 'free from'],
          afterEn: <String>['free'],
          beforeHe: <String>['ללא', 'בלי'],
        ),
        termGuards: <String, AllergenGuards>{
          'corn': AllergenGuards(afterEn: _cornRefinedEn),
          'maize': AllergenGuards(afterEn: _cornRefinedEn),
          'popcorn': AllergenGuards(afterEn: _popcornMorselsEn),
          'תירס': AllergenGuards(beforeHe: _cornRefinedHe),
          'tortilla': AllergenGuards(beforeEn: <String>['flour', 'wheat']),
          'tortillas': AllergenGuards(beforeEn: <String>['flour', 'wheat']),
        },
        sources: <String>['11 §27.1', '11 §27.5', '12 §11.1'],
      ),
      RestrictionId.sunflower: RestrictionVocabulary(
        directEn: <String>[
          'sunflower',
          'sunflower seed',
          'sunflower seeds',
          'sunflower kernels',
          'sunflower butter',
          'sunflower seed butter',
          'sunbutter',
        ],
        // No free prefix: ל + חמנייה is לחמנייה, a bread roll (12 §11.2).
        // The "and" forms are listed on their own.
        directHe: _sunflowerHe,
        hiddenEn: <HiddenTrigger>[
          // Refined oil is often tolerated (11 §27.3): suspected, and the
          // direct "sunflower" beside it is lowered by its term guard.
          HiddenTrigger(
            term: 'sunflower oil',
            certainty: TriggerCertainty.suspected,
            source: '11 §27.3',
          ),
          HiddenTrigger(
            term: 'sunflower lecithin',
            certainty: TriggerCertainty.suspected,
            source: '11 §27.3',
          ),
          ..._seededBreadsEn,
        ],
        hiddenHe: <HiddenTrigger>[
          // A bare "גרעינים" on an Israeli menu is usually the sunflower
          // snack (12 §11.2).
          HiddenTrigger(
            term: 'גרעינים',
            certainty: TriggerCertainty.suspected,
            source: '12 §11.2',
          ),
          HiddenTrigger(
            term: 'שמן חמניות',
            certainty: TriggerCertainty.suspected,
            source: '12 §11.2',
          ),
          ..._seededBreadsHe,
        ],
        guards: AllergenGuards(
          beforeEn: <String>['no', 'without', 'free of', 'free from'],
          afterEn: <String>['free'],
          beforeHe: <String>['ללא', 'בלי'],
        ),
        termGuards: <String, AllergenGuards>{
          'sunflower': AllergenGuards(
            afterEn: <String>['oil', 'seed oil', 'lecithin'],
          ),
          'sunflower seed': AllergenGuards(afterEn: <String>['oil']),
          'חמנייה': AllergenGuards(beforeHe: <String>['שמן']),
          'חמניה': AllergenGuards(beforeHe: <String>['שמן']),
          'חמניות': AllergenGuards(beforeHe: <String>['שמן']),
          'חמנית': AllergenGuards(beforeHe: <String>['שמן']),
          'גרעינים': AllergenGuards(
            afterHe: <String>['דלעת', 'של דלעת', 'אבטיח', 'רימון'],
          ),
        },
        noPrefixHe: _sunflowerHe,
        sources: <String>['11 §27.3', '11 §27.5', '12 §11.2'],
      ),
      RestrictionId.flax: RestrictionVocabulary(
        directEn: <String>[
          'flax',
          'flaxseed',
          'flaxseeds',
          'flax seed',
          'flax seeds',
          'linseed',
          'linseeds',
          'flax meal',
          'flaxseed meal',
          'linum',
        ],
        directHe: <String>['פשתן', 'זרעי פשתן'],
        hiddenEn: _seededBreadsEn,
        hiddenHe: _seededBreadsHe,
        guards: AllergenGuards(
          beforeEn: <String>['no', 'without', 'free of', 'free from'],
          afterEn: <String>['free'],
          beforeHe: <String>['ללא', 'בלי'],
        ),
        sources: <String>['11 §27.4', '11 §27.5', '12 §11.3'],
      ),
    };

/// The inputs of the allergen golden, `allergens.json` (Banto; ALG-01,
/// issue #343).
///
/// Data only, like `golden_corpus.dart`, which the allergen work never
/// edits: hand-written menu lines and dishes the matcher runs over, the
/// sentence frames the exporter wraps every vocabulary term in, and a
/// small fixture vocabulary that exercises every matcher rule (prefixes,
/// guards on each side, hidden certainties, the no-prefix list, taxonomy
/// order) before the vocabulary groups are filled, so the Python port is
/// pinned to the algorithm from the first commit.
library;

import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/utils/allergens/vocabulary.dart';

/// An English frame for one term; `{t}` is replaced by the term. Chosen to
/// name no allergen itself, so a frame never adds a hit of its own.
const String allergenContextEn = 'Served with {t} on the side';

/// [allergenContextEn] in Hebrew.
const String allergenContextHe = 'מוגש עם {t} בצד';

/// Words put between a guard and a term to push the guard out of the
/// keto engine's two-word window.
const String allergenGuardFillerEn = 'big fat';

/// [allergenGuardFillerEn] in Hebrew.
const String allergenGuardFillerHe = 'גדול שמן';

/// One word put between a guard and a term: inside the keto engine's
/// two-word window, but not in the slot adjacent to the term, so the
/// allergen guard does not reach it (ALG-04a).
const String allergenGuardGapEn = 'big';

/// [allergenGuardGapEn] in Hebrew.
const String allergenGuardGapHe = 'גדול';

/// Hand-written menu lines in English and Hebrew, over every restriction
/// group, the way Israeli and US menus write them.
const List<String> allergenMatcherTexts = <String>[
  'Sesame bagel with cream cheese',
  'Hummus with tahini, olive oil and paprika',
  'Satay chicken skewers with peanut sauce',
  'Pad thai with crushed peanuts',
  'Basil pesto pasta with pine nuts',
  'Almond croissant',
  'Caesar salad with anchovies and parmesan',
  'Shrimp tempura with soy sauce',
  'Grilled squid with lemon',
  'Mussels in white wine and garlic',
  'Tuna tartare with sesame oil',
  'Scrambled eggs on sourdough toast',
  'Lactose-free latte with oat milk',
  'Gluten-free bun with honey mustard',
  'Celery soup on vegetable stock',
  'Lupin flour flatbread',
  'Dried apricots (contains sulphites)',
  'Falafel with chickpeas and fava beans',
  'Vegan burger, dairy-free cheese',
  'Vegetarian lasagne with ricotta',
  'סלט ירקות עם טחינה',
  'חומוס עם טחינה וגרגירים',
  'בורקס גבינה עם שומשום',
  "ג'חנון עם ביצה קשה ורסק עגבניות",
  'שניצל עוף בפירורי לחם',
  'סלמון ברוטב סויה ודבש',
  'פסטה ברוטב שמנת ופטריות',
  'חלבה עם פיסטוקים',
  'פלאפל בפיתה עם עמבה',
  'שקשוקה עם גבינת פטה',
  'מרק עדשים כתומות',
  'קפה הפוך על חלב שקדים',
  'לחמניה ללא גלוטן',
  'חומוס ללא טחינה',
  // ALG-04a: a guard lowers, never cancels; only the adjacent slot counts;
  // a term's own guards; the maqaf joins words.
  'Hummus, no sesame or tahini',
  'Sesame-free tahini',
  'Bun made with rice flour',
  'Toast with rice flour and wheat flour',
  'Flat white with almond milk',
  'Coconut milk curry',
  'Oyster mushroom risotto',
  'Crab apple jelly',
  'Crab cakes',
  'חמאת־בוטנים',
  'פיתה עם חמאת־בוטנים',
  'קפה עם חלב־שקדים',
  'קפה עם חלב השקדים',
  'קפה עם חלב ושקדים',
  'חומוס וללא טחינה',
  'ללא גלוטן ועם טחינה',
];

/// A dish named [name] with [description] and [options], built the way a
/// mapper builds one (the price is irrelevant to the matcher).
Dish allergenDish(
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

/// Hand-written dishes: options that add a trigger, removal values that
/// must be skipped, and a trigger only in an option group's name.
final List<Dish> allergenMatcherDishes = <Dish>[
  allergenDish(
    'Bagel',
    description: 'Toasted, with cream cheese',
    options: const <DishOption>[
      DishOption(name: 'Topping', values: <String>['Sesame', 'Poppy seed']),
      DishOption(name: 'Changes', values: <String>['No cream cheese']),
    ],
  ),
  allergenDish(
    'Falafel plate',
    description: 'Falafel, hummus and salad',
    options: const <DishOption>[
      DishOption(name: 'Sauce', values: <String>['Tahini', 'Amba']),
      DishOption(name: 'Remove', values: <String>['Without tahini']),
    ],
  ),
  allergenDish(
    'סביח',
    description: 'חציל מטוגן, ביצה קשה, טחינה ועמבה',
    options: const <DishOption>[
      DishOption(name: 'בחירת לחם', values: <String>['פיתה', 'לאפה']),
      DishOption(name: 'שינויים', values: <String>['ללא טחינה', 'בלי ביצה']),
    ],
  ),
  allergenDish(
    'סלט קיסר',
    description: 'חסה, קרוטונים ורוטב קיסר',
    options: const <DishOption>[
      DishOption(name: 'תוספת', values: <String>['פרמזן', 'אנשובי']),
    ],
  ),
  allergenDish(
    'טוסט',
    description: 'עם חמאת־בוטנים',
    options: const <DishOption>[
      DishOption(name: 'שינויים', values: <String>['ללא־שומשום']),
    ],
  ),
];

/// A test-only vocabulary that exercises every matcher rule, so the
/// golden pins the algorithm (and the Python port replays it) before the
/// real vocabulary is filled. Not a safety claim and never shipped: only
/// the exporter reads it.
const Map<RestrictionId, RestrictionVocabulary> allergenFixtureVocabulary =
    <RestrictionId, RestrictionVocabulary>{
      RestrictionId.sesame: RestrictionVocabulary(
        directEn: <String>['sesame', 'tahini'],
        directHe: <String>['שומשום', 'טחינה'],
        guards: AllergenGuards(
          beforeEn: <String>['no', 'without'],
          afterEn: <String>['free'],
          beforeHe: <String>['ללא', 'בלי'],
        ),
        sources: <String>['11 §11', '12 §1.1'],
      ),
      RestrictionId.milk: RestrictionVocabulary(
        directEn: <String>['milk', 'cream cheese', 'crème fraîche'],
        directHe: <String>['חלב', 'גבינה'],
        guards: AllergenGuards(
          beforeEn: <String>['oat', 'almond', 'dairy free'],
          afterHe: <String>['שקדים', 'סויה'],
        ),
        termGuards: <String, AllergenGuards>{
          'milk': AllergenGuards(beforeEn: <String>['coconut']),
          'חלב': AllergenGuards(afterHe: <String>['קוקוס']),
        },
        sources: <String>['11 §3'],
      ),
      RestrictionId.lactose: RestrictionVocabulary(
        directEn: <String>['milk'],
        directHe: <String>['חלב'],
        guards: AllergenGuards(
          beforeEn: <String>['lactose free'],
          afterHe: <String>['ללא לקטוז'],
        ),
        sources: <String>['11 §4'],
      ),
      RestrictionId.eggs: RestrictionVocabulary(
        directEn: <String>['eggs'],
        directHe: <String>['ביצה'],
        guards: AllergenGuards(afterEn: <String>['free']),
        sources: <String>['11 §5'],
      ),
      RestrictionId.soy: RestrictionVocabulary(
        directEn: <String>['soy'],
        directHe: <String>['סויה'],
        sources: <String>['11 §6'],
      ),
      RestrictionId.wheat: RestrictionVocabulary(
        directEn: <String>['bun', 'toast', 'flour'],
        directHe: <String>['חיטה', 'פיתה'],
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
          HiddenTrigger(
            term: 'פירורי לחם',
            certainty: TriggerCertainty.likely,
            source: '12 §1.4',
          ),
        ],
        guards: AllergenGuards(
          beforeEn: <String>['gluten free'],
          afterHe: <String>['ללא גלוטן'],
        ),
        termGuards: <String, AllergenGuards>{
          'flour': AllergenGuards(beforeEn: <String>['rice']),
        },
        noPrefixHe: <String>['חיטה'],
        sources: <String>['11 §7'],
      ),
      RestrictionId.fish: RestrictionVocabulary(
        directEn: <String>['anchovies', 'tuna'],
        directHe: <String>['סלמון', 'אנשובי'],
        hiddenEn: <HiddenTrigger>[
          HiddenTrigger(
            term: 'Caesar',
            certainty: TriggerCertainty.likely,
            source: '11 §8.2',
          ),
        ],
        hiddenHe: <HiddenTrigger>[
          HiddenTrigger(
            term: 'רוטב קיסר',
            certainty: TriggerCertainty.likely,
            source: '11 §8.2',
          ),
        ],
        sources: <String>['11 §8'],
      ),
      RestrictionId.celery: RestrictionVocabulary(
        directEn: <String>['celery'],
        hiddenEn: <HiddenTrigger>[
          HiddenTrigger(
            term: 'vegetable stock',
            certainty: TriggerCertainty.suspected,
            source: '11 §12.2',
          ),
        ],
        sources: <String>['11 §12'],
      ),
      RestrictionId.peanuts: RestrictionVocabulary(
        directEn: <String>['peanut', 'peanut butter'],
        directHe: <String>['בוטנים', 'חמאת בוטנים'],
        guards: AllergenGuards(afterEn: <String>['free']),
        sources: <String>['11 §1'],
      ),
      RestrictionId.treeNuts: RestrictionVocabulary(
        directEn: <String>['almond milk', 'coconut milk'],
        directHe: <String>['שקדים'],
        sources: <String>['11 §2'],
      ),
      RestrictionId.crustaceans: RestrictionVocabulary(
        directEn: <String>['crab'],
        termGuards: <String, AllergenGuards>{
          'crab': AllergenGuards(afterEn: <String>['apple']),
        },
        sources: <String>['11 §9'],
      ),
      RestrictionId.molluscs: RestrictionVocabulary(
        directEn: <String>['oyster'],
        termGuards: <String, AllergenGuards>{
          'oyster': AllergenGuards(afterEn: <String>['mushroom']),
        },
        sources: <String>['11 §10'],
      ),
      RestrictionId.sulphites: RestrictionVocabulary(
        hiddenEn: <HiddenTrigger>[
          HiddenTrigger(
            term: 'white wine',
            certainty: TriggerCertainty.suspected,
            source: '11 §15.2',
          ),
        ],
        sources: <String>['11 §15'],
      ),
      RestrictionId.legumes: RestrictionVocabulary(
        directEn: <String>['chickpeas', 'fava beans'],
        directHe: <String>['חומוס', 'עדשים', 'פלאפל'],
        sources: <String>['11 §16', '12 §1.3'],
      ),
    };

/// The labelled corpus menus (`test/fixtures/allergens/menus/`) whose
/// every dish `allergen_concerns.json` runs through
/// `ClassificationRules.allergenConcerns` (ALG-04b): a sample across
/// English, Hebrew and mixed menus, hidden sources and options.
const List<String> allergenConcernMenuFiles = <String>[
  'asian_takeaway_soy_peanut.json',
  'golden_mixed.json',
  'il_cafe_pastries.json',
  'il_hummus_falafel.json',
  'il_sushi_bar.json',
  'us_diner_shared_fryer.json',
];

/// Hand-written dishes for `allergen_concerns.json` (ALG-04b): the
/// matched text kept as printed (case, points, a prefix letter, a quote
/// mark, a maqaf, a character outside the BMP before the term), a hidden
/// trigger in an option, a guarded and a stated finding of one
/// restriction in different parts, a removal value with a maqaf, and a
/// dish with nothing in it.
final List<Dish> allergenConcernDishes = <Dish>[
  allergenDish(
    'TAHINI Bowl',
    description: 'Sesame-free dressing, with peanuts',
    options: const <DishOption>[
      DishOption(name: 'Extras', values: <String>['Soy sauce', 'No egg']),
    ],
  ),
  allergenDish(
    'סָלָט בַּטְּחִינָה',
    description: 'עם חמאת־בוטנים',
    options: const <DishOption>[
      DishOption(name: 'שינויים', values: <String>['ללא־שומשום', 'ביצה']),
    ],
  ),
  allergenDish('🥜 Peanut "satay" skewers', description: "Chef's milk-free"),
  allergenDish(
    'Grilled fish',
    description: 'Lemon and olive oil',
    options: const <DishOption>[
      DishOption(name: 'Side', values: <String>['Salad', 'Bread']),
    ],
  ),
  allergenDish('Water'),
  // Kosher's meat with dairy (issue #342): both stated, a likely dairy
  // sauce, dairy only in an option, fish with cream (nothing), guarded
  // words on either side (nothing), and a Hebrew pair.
  allergenDish('Ribeye steak', description: 'Blue cheese butter'),
  allergenDish('Chicken alfredo'),
  allergenDish(
    'Beef burger',
    options: const <DishOption>[
      DishOption(name: 'Extras', values: <String>['Cheddar', 'No cheese']),
    ],
  ),
  allergenDish('Salmon in cream sauce'),
  allergenDish('Veggie burger', description: 'With goat cheese'),
  allergenDish('Chicken curry', description: 'Coconut milk'),
  allergenDish('שניצל עוף', description: 'ברוטב שמנת ופטריות'),
  allergenDish('פילה לברק', description: 'ברוטב חמאה ולימון'),
  allergenDish('Cheeseburger', description: 'Pork belly bacon'),
  allergenDish('Penne alla vodka', description: 'Red wine, no alcohol'),
];

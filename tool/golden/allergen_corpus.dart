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
/// two-word window.
const String allergenGuardFillerEn = 'big fat';

/// [allergenGuardFillerEn] in Hebrew.
const String allergenGuardFillerHe = 'גדול שמן';

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
        directEn: <String>['bun', 'toast'],
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

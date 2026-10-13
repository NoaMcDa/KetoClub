/// The inputs of the kitchen-signals golden, `kitchen_signals.json` (Banto;
/// ALG-07, issue #349).
///
/// Data only, like `golden_corpus.dart`: a small vocabulary of nuts, sesame
/// and seafood that the exporter runs `KitchenSignals.ofWith` under (so the
/// golden pins this pass, not the group vocabulary files, and does not move
/// when those are filled), and menus built to hit each rule: the fried and
/// grill guards, a heading that makes a signal, the evidence cap, option
/// text and removals, Hebrew prefixes and the no-prefix word.
library;

import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/utils/allergens/vocabulary.dart';

import 'golden_corpus.dart';

/// The vocabulary the kitchen-signals golden runs under. Not a safety claim
/// and never shipped: only the exporter and the tests read it.
const Map<RestrictionId, RestrictionVocabulary> kitchenFixtureVocabulary =
    <RestrictionId, RestrictionVocabulary>{
      RestrictionId.peanuts: RestrictionVocabulary(
        directEn: <String>['peanut', 'peanuts'],
        directHe: <String>['בוטנים', 'בוטן'],
        guards: AllergenGuards(
          beforeEn: <String>['no', 'without'],
          afterEn: <String>['free'],
          beforeHe: <String>['ללא', 'בלי'],
        ),
      ),
      RestrictionId.treeNuts: RestrictionVocabulary(
        directEn: <String>['almond', 'almonds', 'walnut', 'cashew', 'pecan'],
        directHe: <String>['שקדים', 'אגוזים', 'קשיו'],
        hiddenEn: <HiddenTrigger>[
          HiddenTrigger(
            term: 'baklava',
            certainty: TriggerCertainty.likely,
            source: '12',
          ),
        ],
        guards: AllergenGuards(
          beforeEn: <String>['no', 'without'],
          afterEn: <String>['free'],
          beforeHe: <String>['ללא', 'בלי'],
        ),
      ),
      RestrictionId.fish: RestrictionVocabulary(
        directEn: <String>['fish', 'salmon', 'sea bass', 'tuna'],
        directHe: <String>['דג', 'דגים', 'סלמון', 'לוקוס', 'טונה'],
      ),
      RestrictionId.crustaceans: RestrictionVocabulary(
        directEn: <String>['shrimp', 'prawns'],
        directHe: <String>['שרימפס'],
      ),
      RestrictionId.molluscs: RestrictionVocabulary(
        directEn: <String>['calamari', 'squid'],
        directHe: <String>['קלמרי'],
      ),
      RestrictionId.sesame: RestrictionVocabulary(
        directEn: <String>['sesame', 'tahini'],
        directHe: <String>['שומשום', 'טחינה'],
        hiddenEn: <HiddenTrigger>[
          HiddenTrigger(
            term: 'hummus',
            certainty: TriggerCertainty.likely,
            source: '12 §1.1',
          ),
        ],
        guards: AllergenGuards(
          beforeEn: <String>['no', 'without'],
          afterEn: <String>['free'],
          beforeHe: <String>['ללא', 'בלי'],
        ),
      ),
    };

/// A menu of [categories], each a heading and its dishes.
Menu _menu(String id, List<(String, List<Dish>)> categories) => Menu(
  venueRef: VenueRef(source: MenuSource.scan, platformId: id),
  currency: 'ILS',
  fetchedAt: goldenNow,
  categories: <MenuCategory>[
    for (final (index, (name, dishes)) in categories.indexed)
      MenuCategory(id: '$id-$index', name: name, dishes: dishes),
  ],
);

/// A dish of these menus.
Dish _dish(
  String id,
  String name, {
  String description = '',
  List<DishOption> options = const <DishOption>[],
}) => menuDish(id, name, description: description, options: options);

/// The purpose-built menus, by name, in the order the golden lists them.
final Map<String, Menu> kitchenSignalMenus = <String, Menu>{
  'empty': _menu('empty', const <(String, List<Dish>)>[]),
  'no_signals': _menu('none', <(String, List<Dish>)>[
    (
      'Salads',
      <Dish>[
        _dish('n1', 'Garden salad', description: 'Cucumber, tomato, olive oil'),
        _dish('n2', 'Boiled eggs', description: 'Two, with herbs'),
        _dish('n3', 'סלט ירקות', description: 'עגבניה, מלפפון'),
      ],
    ),
  ]),
  'fried_guards': _menu('fried', <(String, List<Dish>)>[
    (
      'Mains',
      <Dish>[
        _dish('f1', 'Stir fried vegetables', description: 'Garlic, ginger'),
        _dish('f2', 'Pan fried sea bass', description: 'Lemon butter'),
        _dish('f3', 'Air fried wings', description: 'Hot sauce'),
        _dish('f4', 'Chocolate chips cookie'),
        _dish('f5', 'Egg fried rice'),
        _dish('f6', 'אורז מטוגן', description: 'עם ירקות'),
        _dish('f7', "צ'יפס מוקפץ בשמן כמהין"),
      ],
    ),
  ]),
  'fried_cap_and_seafood': _menu('cap', <(String, List<Dish>)>[
    (
      'Fried',
      <Dish>[
        _dish('c1', 'French fries'),
        _dish('c2', 'Fish and chips', description: 'Salmon, battered'),
        _dish('c3', 'Calamari', description: 'Deep fried, lemon'),
        _dish('c4', 'Onion rings'),
        _dish('c5', 'French fries'),
        _dish('c6', 'Shrimp tempura'),
      ],
    ),
  ]),
  'grill_by_heading': _menu('grill', <(String, List<Dish>)>[
    (
      'On the Grill',
      <Dish>[
        _dish('g1', 'Rib eye 300g'),
        _dish('g2', 'Salmon fillet'),
        _dish('g3', 'Lamb chops'),
        _dish('g4', 'Sea bass'),
      ],
    ),
    ('Starters', <Dish>[_dish('g5', 'Beetroot salad')]),
  ]),
  'grill_meat_only': _menu('meat', <(String, List<Dish>)>[
    (
      'Mains',
      <Dish>[
        _dish('m1', 'Grilled chicken'),
        _dish('m2', 'Chargrilled lamb'),
        _dish('m3', 'Salmon', description: 'Baked, with lemon'),
      ],
    ),
  ]),
  'grill_vegan_burger': _menu('vegan', <(String, List<Dish>)>[
    (
      'Mains',
      <Dish>[
        _dish('v1', 'Grilled vegan burger'),
        _dish('v2', 'Grilled salmon'),
        _dish('v3', 'המבורגר טבעוני על האש'),
        _dish('v4', 'סלמון בגריל'),
        _dish('v5', 'פסטה ללא בשר בגריל'),
      ],
    ),
  ]),
  'grill_hebrew': _menu('grillhe', <(String, List<Dish>)>[
    (
      'מהמנגל',
      <Dish>[
        _dish('h1', 'סטייק אנטריקוט'),
        _dish('h2', 'פילה לוקוס'),
        _dish('h3', 'כנפיים'),
      ],
    ),
  ]),
  'wok_and_heading': _menu('wok', <(String, List<Dish>)>[
    (
      'Wok',
      <Dish>[
        _dish('w1', 'Chicken teriyaki'),
        _dish('w2', 'Pad Thai', description: 'Peanuts, lime'),
      ],
    ),
    (
      'מוקפצים',
      <Dish>[_dish('w3', 'נודלס עם ירקות'), _dish('w4', "צ'או מיין")],
    ),
  ]),
  'bakery_and_prefixes': _menu('bakery', <(String, List<Dish>)>[
    (
      'Pizza & Pastries',
      <Dish>[_dish('b1', 'Margherita'), _dish('b2', 'Calzone')],
    ),
    (
      'ראשונות',
      <Dish>[
        _dish('b3', 'חומוס', description: 'בלחם קלוי'),
        _dish('b4', 'החלה הגדולה'),
        _dish('b5', 'חלה טרייה'),
        _dish('b6', 'לחמניה'),
      ],
    ),
  ]),
  'no_prefix_challah': _menu('challah', <(String, List<Dish>)>[
    ('ראשונות', <Dish>[_dish('p1', 'החלה הגדולה'), _dish('p2', 'עוף בתנור')]),
  ]),
  'nuts_and_sesame': _menu('nuts', <(String, List<Dish>)>[
    (
      'Salads',
      <Dish>[
        _dish('s1', 'Green salad', description: 'No sesame, almond-free'),
        _dish('s2', 'Peanut noodles'),
        _dish('s3', 'Baklava'),
        _dish('s4', 'Hummus plate', description: 'Olive oil'),
        _dish('s5', 'חלווה', description: 'עם טחינה'),
      ],
    ),
  ]),
  'options_and_removals': _menu('removal', <(String, List<Dish>)>[
    (
      'Bowls',
      <Dish>[
        _dish(
          'r1',
          'Grain bowl',
          options: const <DishOption>[
            DishOption(name: 'Changes', values: <String>['No sesame']),
          ],
        ),
        _dish(
          'r2',
          'Burger',
          options: const <DishOption>[
            DishOption(name: 'Side', values: <String>['Fries', 'Salad']),
          ],
        ),
        _dish(
          'r3',
          'Wrap',
          options: const <DishOption>[
            DishOption(name: 'Changes', values: <String>['No fries']),
          ],
        ),
      ],
    ),
  ]),
  'nuts_heading': _menu('nutsheading', <(String, List<Dish>)>[
    (
      'Almonds & Walnuts',
      <Dish>[_dish('t1', 'Trail mix'), _dish('t2', 'Granola')],
    ),
  ]),
};

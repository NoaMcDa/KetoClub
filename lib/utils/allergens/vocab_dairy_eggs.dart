/// Dairy and eggs: the trigger vocabulary of milk, lactose and eggs
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
/// Milk and lactose share most triggers and differ in their guards (11 §4.3,
/// 12 §2.1): "lactose free", a hard aged cheese and "פרווה" clear lactose and
/// never milk. A vegan substitute is a `suspected` milk trigger of its own
/// (12 §2.1), so the guard that lowers its dairy word never leaves it
/// alone. A guard lowers the hit to `suspected`, never cancels it, and only
/// from the slot adjacent to its term (ALG-04a): "almond croissant" keeps
/// its croissant. The plant bases that turn a dairy word into another food
/// ("coconut milk", "peanut butter", "חלב שקדים") are term guards on the
/// dairy words, not restriction-wide guards.
library;

import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/utils/allergens/vocabulary_types.dart';

/// The plant bases that make a dairy word another food when they name it
/// ("coconut milk", "oat cream", "cashew cheese"): term guards on the dairy
/// words, never restriction-wide, so "cocoa milk" stays milk (ALG-04a).
const List<String> _plantBasesEn = <String>[
  'coconut',
  'almond',
  'oat',
  'soy',
  'soya',
  'cashew',
  'nut',
];

/// [_plantBasesEn] plus the nut and plant fats that make "butter" another
/// food ("peanut butter", "cocoa butter", "shea butter").
const List<String> _otherButtersEn = <String>[
  ..._plantBasesEn,
  'peanut',
  'cocoa',
  'cacao',
  'shea',
];

/// The Hebrew plant bases, after the dairy word in a construct phrase
/// ("חלב שקדים", "שמנת קוקוס", "גבינת קשיו").
const List<String> _plantBasesHe = <String>[
  'שקדים',
  'סויה',
  'קוקוס',
  'שיבולת שועל',
  'קשיו',
];

/// [_plantBasesHe] plus the nut and plant fats after "חמאת" ("חמאת
/// בוטנים", "חמאת קקאו", "חמאת שיאה").
const List<String> _otherButtersHe = <String>[
  ..._plantBasesHe,
  'בוטנים',
  'קקאו',
  'שיאה',
];

/// Dairy and eggs: one entry per restriction this group owns.
const Map<RestrictionId, RestrictionVocabulary>
dairyEggsVocabulary = <RestrictionId, RestrictionVocabulary>{
  RestrictionId.milk: RestrictionVocabulary(
    directEn: <String>[
      // The milk itself and what is made of it (11 §3.1).
      'milk',
      'milkshake',
      'milkshakes',
      'buttermilk',
      'butter',
      'buttered',
      'butterfat',
      'butter fat',
      'cream',
      'cheese',
      'cheeses',
      'cheesy',
      'cheesecake',
      'cheeseburger',
      'cheesesteak',
      'yogurt',
      'yoghurt',
      'ghee',
      'curd',
      'curds',
      'custard',
      'kefir',
      'skyr',
      // Milk proteins and sugar.
      'casein',
      'caseinate',
      'caseinates',
      'whey',
      'lactalbumin',
      'lactoglobulin',
      'lactose',
      // Named cheeses.
      'parmesan',
      'parmigiano',
      'pecorino',
      'grana padano',
      'gruyere',
      'emmental',
      'emmenthal',
      'manchego',
      'cheddar',
      'gouda',
      'edam',
      'jarlsberg',
      'provolone',
      'asiago',
      'mozzarella',
      'feta',
      'halloumi',
      'haloumi',
      'brie',
      'camembert',
      'gorgonzola',
      'roquefort',
      'stilton',
      'ricotta',
      'mascarpone',
      'burrata',
      'taleggio',
      'fontina',
      'cotija',
      'paneer',
      'labneh',
      'labaneh',
      'quark',
      'queso',
      'creme fraiche',
    ],
    directHe: <String>[
      // The milk itself and what is made of it (12 §1.5).
      'חלב',
      'גבינה',
      'גבינת',
      'גבינות',
      'שמנת',
      'חמאה',
      'חמאת',
      'יוגורט',
      'יוגרט',
      'קצפת',
      'שוקו',
      'קרם פרש',
      'גהי',
      'סמנה',
      'סאמנה',
      'קזאין',
      'לקטוז',
      'קשקבל',
      // Named cheeses.
      'פרמזן',
      "פרמיג'אנו",
      'פקורינו',
      'גרויר',
      'אמנטל',
      "צ'דר",
      'גאודה',
      'חלומי',
      'הלומי',
      'ריקוטה',
      'מסקרפונה',
      'קממבר',
      'פטה',
      'בולגרית',
      'צפתית',
      'גורגונזולה',
      'רוקפור',
      "קוטג'",
      'מוצרלה',
      'לאבנה',
    ],
    hiddenEn: <HiddenTrigger>[
      // "Dairy" says a dish has dairy (11 §3.3 guards its absence).
      HiddenTrigger(
        term: 'dairy',
        certainty: TriggerCertainty.likely,
        source: '11 §3.3',
      ),
      // Butter- and cream-finished sauces, gratins, enriched breads and
      // coffee drinks made with milk (11 §3.2).
      HiddenTrigger(
        term: 'beurre',
        certainty: TriggerCertainty.likely,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'beurre blanc',
        certainty: TriggerCertainty.likely,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'beurre noisette',
        certainty: TriggerCertainty.likely,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'hollandaise',
        certainty: TriggerCertainty.likely,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'bearnaise',
        certainty: TriggerCertainty.likely,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'bechamel',
        certainty: TriggerCertainty.likely,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'mornay',
        certainty: TriggerCertainty.likely,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'alfredo',
        certainty: TriggerCertainty.likely,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'gratin',
        certainty: TriggerCertainty.likely,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'dauphinoise',
        certainty: TriggerCertainty.likely,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'buttercream',
        certainty: TriggerCertainty.likely,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'brioche',
        certainty: TriggerCertainty.likely,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'pesto',
        certainty: TriggerCertainty.likely,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'caesar',
        certainty: TriggerCertainty.likely,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'latte',
        certainty: TriggerCertainty.likely,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'cappuccino',
        certainty: TriggerCertainty.likely,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'flat white',
        certainty: TriggerCertainty.likely,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'cortado',
        certainty: TriggerCertainty.likely,
        source: '11 §3.2',
      ),
      // Hidden butter and cream: the FARE steak finding, mashed potato,
      // risotto, baked goods, caramel and chocolate (11 §3.2).
      HiddenTrigger(
        term: 'carbonara',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'risotto',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'mashed potato',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'mashed potatoes',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'potato puree',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'pommes puree',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'scalloped potatoes',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'creamy',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'creamed',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'butterscotch',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'macchiato',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'mocha',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'hot chocolate',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'croissant',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'croissants',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'danish',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'pastry',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'pastries',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'cake',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'cakes',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'muffin',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'muffins',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'scone',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'scones',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'pancake',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'pancakes',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'waffle',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'waffles',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'brownie',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'brownies',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'cookie',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'cookies',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'caramel',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'chocolate',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'toffee',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'sundae',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'almond croissant',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'almond croissants',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'almond cake',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'coconut cake',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'peanut butter cookie',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'peanut butter cookies',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'margarine',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'buffalo sauce',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'buffalo wings',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      // Puddings, custards and cultured dairy dishes (11 §3.1).
      HiddenTrigger(
        term: 'pudding',
        certainty: TriggerCertainty.likely,
        source: '11 §3.1',
      ),
      HiddenTrigger(
        term: 'tiramisu',
        certainty: TriggerCertainty.likely,
        source: '11 §3.1',
      ),
      HiddenTrigger(
        term: 'panna cotta',
        certainty: TriggerCertainty.likely,
        source: '11 §3.1',
      ),
      HiddenTrigger(
        term: 'creme brulee',
        certainty: TriggerCertainty.likely,
        source: '11 §3.1',
      ),
      HiddenTrigger(
        term: 'dulce de leche',
        certainty: TriggerCertainty.likely,
        source: '11 §3.1',
      ),
      HiddenTrigger(
        term: 'gelato',
        certainty: TriggerCertainty.likely,
        source: '11 §3.1',
      ),
      HiddenTrigger(
        term: 'a la mode',
        certainty: TriggerCertainty.likely,
        source: '11 §3.1',
      ),
      HiddenTrigger(
        term: 'fondue',
        certainty: TriggerCertainty.likely,
        source: '11 §3.1',
      ),
      HiddenTrigger(
        term: 'raclette',
        certainty: TriggerCertainty.likely,
        source: '11 §3.1',
      ),
      HiddenTrigger(
        term: 'quesadilla',
        certainty: TriggerCertainty.likely,
        source: '11 §3.1',
      ),
      HiddenTrigger(
        term: 'tzatziki',
        certainty: TriggerCertainty.likely,
        source: '11 §3.1',
      ),
      HiddenTrigger(
        term: 'raita',
        certainty: TriggerCertainty.likely,
        source: '11 §3.1',
      ),
      HiddenTrigger(
        term: 'lassi',
        certainty: TriggerCertainty.likely,
        source: '11 §3.1',
      ),
      // Butter on a grilled steak melts out of sight (11 §3.2, FARE).
      HiddenTrigger(
        term: 'steak',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'steaks',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'entrecote',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      // Leftover recall misses (issue #352): grilled beef on a skewer is
      // the same grilled steak (11 §3.2).
      HiddenTrigger(
        term: 'shashlik',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'beef skewers',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'ribeye',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'rib eye',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'sirloin',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'filet mignon',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      // Casein as a binder and "non-dairy" products that can carry casein
      // (11 §3.2).
      HiddenTrigger(
        term: 'non dairy',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'nondairy',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'creamer',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'hot dog',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'hot dogs',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'sausage',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'sausages',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'luncheon meat',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'deli meat',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'deli meats',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'canned tuna',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'breadcrumbs',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'bread crumbs',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      // Vegan and plant-based substitutes: the Ministry of Health warns
      // they may carry milk protein, so they stay a question (12 §2.1).
      HiddenTrigger(
        term: 'vegan cheese',
        certainty: TriggerCertainty.suspected,
        source: '12 §2.1',
      ),
      HiddenTrigger(
        term: 'vegan butter',
        certainty: TriggerCertainty.suspected,
        source: '12 §2.1',
      ),
      HiddenTrigger(
        term: 'vegan cream',
        certainty: TriggerCertainty.suspected,
        source: '12 §2.1',
      ),
      HiddenTrigger(
        term: 'plant based cheese',
        certainty: TriggerCertainty.suspected,
        source: '12 §2.1',
      ),
      HiddenTrigger(
        term: 'plant based butter',
        certainty: TriggerCertainty.suspected,
        source: '12 §2.1',
      ),
      HiddenTrigger(
        term: 'plant based cream',
        certainty: TriggerCertainty.suspected,
        source: '12 §2.1',
      ),
      HiddenTrigger(
        term: 'dairy alternative',
        certainty: TriggerCertainty.suspected,
        source: '12 §2.1',
      ),
      HiddenTrigger(
        term: 'dairy substitute',
        certainty: TriggerCertainty.suspected,
        source: '12 §2.1',
      ),
      // Recall-gate additions (issue #352): enriched dough and
      // substitute products (11 §3.2, 12 §2.1).
      HiddenTrigger(
        term: 'hot cross bun',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'hot cross buns',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'vegan mayo',
        certainty: TriggerCertainty.suspected,
        source: '12 §2.1',
      ),
      HiddenTrigger(
        term: 'vegan mayonnaise',
        certainty: TriggerCertainty.suspected,
        source: '12 §2.1',
      ),
    ],
    hiddenHe: <HiddenTrigger>[
      // "חלבי" is the dairy kosher category: it raises a milk flag (12
      // §2.1).
      HiddenTrigger(
        term: 'חלבי',
        certainty: TriggerCertainty.likely,
        source: '12 §2.1',
      ),
      HiddenTrigger(
        term: 'חלבית',
        certainty: TriggerCertainty.likely,
        source: '12 §2.1',
      ),
      // Coffee drinks made with milk and ice cream (11 §3.2, 12 §1.5).
      HiddenTrigger(
        term: 'הפוך',
        certainty: TriggerCertainty.likely,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'לאטה',
        certainty: TriggerCertainty.likely,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'לטה',
        certainty: TriggerCertainty.likely,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: "קפוצ'ינו",
        certainty: TriggerCertainty.likely,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'פלאט וייט',
        certainty: TriggerCertainty.likely,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'קורטדו',
        certainty: TriggerCertainty.likely,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'מילקשייק',
        certainty: TriggerCertainty.likely,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'מילקשק',
        certainty: TriggerCertainty.likely,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'גלידה',
        certainty: TriggerCertainty.likely,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'גלידת',
        certainty: TriggerCertainty.likely,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'גלידות',
        certainty: TriggerCertainty.likely,
        source: '11 §3.2',
      ),
      // Butter- and cream-finished sauces and dishes (11 §3.2).
      HiddenTrigger(
        term: 'בריוש',
        certainty: TriggerCertainty.likely,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'פסטו',
        certainty: TriggerCertainty.likely,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'סלט קיסר',
        certainty: TriggerCertainty.likely,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'רוטב קיסר',
        certainty: TriggerCertainty.likely,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'אלפרדו',
        certainty: TriggerCertainty.likely,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'בשמל',
        certainty: TriggerCertainty.likely,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'הולנדייז',
        certainty: TriggerCertainty.likely,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'גראטן',
        certainty: TriggerCertainty.likely,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'גרטן',
        certainty: TriggerCertainty.likely,
        source: '11 §3.2',
      ),
      // Puddings and cultured dairy dishes (11 §3.1).
      HiddenTrigger(
        term: 'פודינג',
        certainty: TriggerCertainty.likely,
        source: '11 §3.1',
      ),
      HiddenTrigger(
        term: 'טירמיסו',
        certainty: TriggerCertainty.likely,
        source: '11 §3.1',
      ),
      HiddenTrigger(
        term: 'פנה קוטה',
        certainty: TriggerCertainty.likely,
        source: '11 §3.1',
      ),
      HiddenTrigger(
        term: 'פנקוטה',
        certainty: TriggerCertainty.likely,
        source: '11 §3.1',
      ),
      HiddenTrigger(
        term: 'קרם ברולה',
        certainty: TriggerCertainty.likely,
        source: '11 §3.1',
      ),
      HiddenTrigger(
        term: "ג'לטו",
        certainty: TriggerCertainty.likely,
        source: '11 §3.1',
      ),
      HiddenTrigger(
        term: 'פונדו',
        certainty: TriggerCertainty.likely,
        source: '11 §3.1',
      ),
      HiddenTrigger(
        term: 'קסדילה',
        certainty: TriggerCertainty.likely,
        source: '11 §3.1',
      ),
      HiddenTrigger(
        term: 'צזיקי',
        certainty: TriggerCertainty.likely,
        source: '11 §3.1',
      ),
      // Hidden butter and cream (11 §3.2).
      HiddenTrigger(
        term: 'פירה',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'ריזוטו',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'קרמי',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'קרבונרה',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'מקיאטו',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'מוקה',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'קרואסון',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'דניש',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'מאפה',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'מאפים',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'עוגה',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'עוגת',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'עוגות',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'עוגיות',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'עוגייה',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'פנקייק',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'פנקייקים',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'וופל',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'וופלים',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'בראוני',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'מאפין',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'מאפינס',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'סקונס',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'שוקולד',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'קרמל',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'קרם שקדים',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'קרואסון שקדים',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'עוגת שקדים',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'עוגת קוקוס',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'מרגרינה',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'נקניקיות',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'נקניק',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'פירורי לחם',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      // Pastries made with butter or margarine; the menu seldom says which
      // (12 §1.5).
      HiddenTrigger(
        term: "ג'חנון",
        certainty: TriggerCertainty.suspected,
        source: '12 §1.5',
      ),
      HiddenTrigger(
        term: 'מלאווח',
        certainty: TriggerCertainty.suspected,
        source: '12 §1.5',
      ),
      HiddenTrigger(
        term: 'מלווח',
        certainty: TriggerCertainty.suspected,
        source: '12 §1.5',
      ),
      HiddenTrigger(
        term: 'כובאנה',
        certainty: TriggerCertainty.suspected,
        source: '12 §1.5',
      ),
      HiddenTrigger(
        term: 'קובנה',
        certainty: TriggerCertainty.suspected,
        source: '12 §1.5',
      ),
      HiddenTrigger(
        term: 'בורקס',
        certainty: TriggerCertainty.suspected,
        source: '12 §1.5',
      ),
      HiddenTrigger(
        term: 'בורקסים',
        certainty: TriggerCertainty.suspected,
        source: '12 §1.5',
      ),
      // Butter on a grilled steak melts out of sight (11 §3.2, FARE).
      HiddenTrigger(
        term: 'סטייק',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'סטייקים',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'אנטריקוט',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'אנטרקוט',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      // Leftover recall misses (issue #352); see the English skewers.
      HiddenTrigger(
        term: 'שישליק',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'שיפודי בקר',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      // Buffalo sauce is butter and hot sauce (11 §3.2).
      HiddenTrigger(
        term: 'באפלו',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      // Vegan and pareve substitutes can carry milk protein (12 §2.1).
      HiddenTrigger(
        term: 'גבינה טבעונית',
        certainty: TriggerCertainty.suspected,
        source: '12 §2.1',
      ),
      HiddenTrigger(
        term: 'גבינה צמחית',
        certainty: TriggerCertainty.suspected,
        source: '12 §2.1',
      ),
      HiddenTrigger(
        term: 'חמאה טבעונית',
        certainty: TriggerCertainty.suspected,
        source: '12 §2.1',
      ),
      HiddenTrigger(
        term: 'שמנת צמחית',
        certainty: TriggerCertainty.suspected,
        source: '12 §2.1',
      ),
      HiddenTrigger(
        term: 'תחליף חלב',
        certainty: TriggerCertainty.suspected,
        source: '12 §2.1',
      ),
      HiddenTrigger(
        term: 'תחליף גבינה',
        certainty: TriggerCertainty.suspected,
        source: '12 §2.1',
      ),
      HiddenTrigger(
        term: 'רוגלך',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'לוביאני',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'כריך טונה',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'סלט טונה',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'טונה משומרת',
        certainty: TriggerCertainty.suspected,
        source: '11 §3.2',
      ),
      HiddenTrigger(
        term: 'מיונז טבעוני',
        certainty: TriggerCertainty.suspected,
        source: '12 §2.1',
      ),
    ],
    guards: AllergenGuards(
      beforeEn: <String>[
        'no',
        'without',
        'vegan',
        'plant based',
        'dairy free',
        'milk free',
        'free from',
      ],
      afterEn: <String>['free', 'dairy free', 'milk free'],
      beforeHe: <String>[
        'ללא',
        'בלי',
        'וללא',
        'ובלי',
        'ללא מוצרי',
        'בלי מוצרי',
      ],
      afterHe: <String>[
        'טבעוני',
        'טבעונית',
        'צמחי',
        'צמחית',
        'ללא חלב',
        'בלי חלב',
        'ללא מוצרי',
        'בלי מוצרי',
      ],
    ),
    termGuards: <String, AllergenGuards>{
      'milk': AllergenGuards(
        beforeEn: _plantBasesEn,
        afterEn: <String>['thistle'],
      ),
      'milkshake': AllergenGuards(beforeEn: _plantBasesEn),
      'milkshakes': AllergenGuards(beforeEn: _plantBasesEn),
      'cream': AllergenGuards(
        beforeEn: <String>[..._plantBasesEn, 'free ice', 'free whipped'],
        afterEn: <String>['of tartar'],
      ),
      'creamer': AllergenGuards(beforeEn: _plantBasesEn),
      'cheese': AllergenGuards(beforeEn: _plantBasesEn),
      'cheeses': AllergenGuards(beforeEn: _plantBasesEn),
      'yogurt': AllergenGuards(beforeEn: _plantBasesEn),
      'yoghurt': AllergenGuards(beforeEn: _plantBasesEn),
      'butter': AllergenGuards(beforeEn: _otherButtersEn),
      'חלב': AllergenGuards(afterHe: _plantBasesHe),
      'שמנת': AllergenGuards(afterHe: _plantBasesHe),
      'גבינת': AllergenGuards(afterHe: _plantBasesHe),
      'יוגורט': AllergenGuards(afterHe: _plantBasesHe),
      'חמאת': AllergenGuards(afterHe: _otherButtersHe),
    },
    noPrefixHe: <String>['הפוך'],
    sources: <String>['11 §3.1', '11 §3.3', '11 §3.5', '12 §1.5', '12 §2.1'],
  ),
  RestrictionId.lactose: RestrictionVocabulary(
    directEn: <String>[
      // The milk sugar and the foods that are mostly milk (11 §4.1).
      'milk',
      'milkshake',
      'milkshakes',
      'buttermilk',
      'cream',
      'cheese',
      'cheeses',
      'cheesy',
      'cheesecake',
      'cheeseburger',
      'cheesesteak',
      'custard',
      'curd',
      'curds',
      'whey',
      'lactose',
      // Soft and fresh cheeses.
      'ricotta',
      'mascarpone',
      'mozzarella',
      'burrata',
      'labneh',
      'labaneh',
      'quark',
      'paneer',
      'queso',
      'creme fraiche',
    ],
    directHe: <String>[
      // The milk sugar and the foods that are mostly milk (11 §4.1).
      'חלב',
      'גבינה',
      'גבינת',
      'גבינות',
      'שמנת',
      'קצפת',
      'שוקו',
      'קרם פרש',
      'לקטוז',
      // Soft and fresh cheeses.
      'ריקוטה',
      'מסקרפונה',
      "קוטג'",
      'מוצרלה',
      'לאבנה',
    ],
    hiddenEn: <HiddenTrigger>[
      // "Dairy" says a dish has dairy.
      HiddenTrigger(
        term: 'dairy',
        certainty: TriggerCertainty.likely,
        source: '11 §4.1',
      ),
      // Brioche and milk loaf are the enriched breads 11 §4.1 names, with
      // the milk sauces, puddings and milk coffees.
      HiddenTrigger(
        term: 'brioche',
        certainty: TriggerCertainty.likely,
        source: '11 §4.1',
      ),
      HiddenTrigger(
        term: 'bechamel',
        certainty: TriggerCertainty.likely,
        source: '11 §4.1',
      ),
      HiddenTrigger(
        term: 'mornay',
        certainty: TriggerCertainty.likely,
        source: '11 §4.1',
      ),
      HiddenTrigger(
        term: 'alfredo',
        certainty: TriggerCertainty.likely,
        source: '11 §4.1',
      ),
      HiddenTrigger(
        term: 'gratin',
        certainty: TriggerCertainty.likely,
        source: '11 §4.1',
      ),
      HiddenTrigger(
        term: 'dauphinoise',
        certainty: TriggerCertainty.likely,
        source: '11 §4.1',
      ),
      HiddenTrigger(
        term: 'buttercream',
        certainty: TriggerCertainty.likely,
        source: '11 §4.1',
      ),
      HiddenTrigger(
        term: 'latte',
        certainty: TriggerCertainty.likely,
        source: '11 §4.1',
      ),
      HiddenTrigger(
        term: 'cappuccino',
        certainty: TriggerCertainty.likely,
        source: '11 §4.1',
      ),
      HiddenTrigger(
        term: 'flat white',
        certainty: TriggerCertainty.likely,
        source: '11 §4.1',
      ),
      HiddenTrigger(
        term: 'cortado',
        certainty: TriggerCertainty.likely,
        source: '11 §4.1',
      ),
      HiddenTrigger(
        term: 'pudding',
        certainty: TriggerCertainty.likely,
        source: '11 §4.1',
      ),
      HiddenTrigger(
        term: 'tiramisu',
        certainty: TriggerCertainty.likely,
        source: '11 §4.1',
      ),
      HiddenTrigger(
        term: 'panna cotta',
        certainty: TriggerCertainty.likely,
        source: '11 §4.1',
      ),
      HiddenTrigger(
        term: 'creme brulee',
        certainty: TriggerCertainty.likely,
        source: '11 §4.1',
      ),
      HiddenTrigger(
        term: 'dulce de leche',
        certainty: TriggerCertainty.likely,
        source: '11 §4.1',
      ),
      HiddenTrigger(
        term: 'gelato',
        certainty: TriggerCertainty.likely,
        source: '11 §4.1',
      ),
      HiddenTrigger(
        term: 'a la mode',
        certainty: TriggerCertainty.likely,
        source: '11 §4.1',
      ),
      HiddenTrigger(
        term: 'fondue',
        certainty: TriggerCertainty.likely,
        source: '11 §4.1',
      ),
      HiddenTrigger(
        term: 'raclette',
        certainty: TriggerCertainty.likely,
        source: '11 §4.1',
      ),
      HiddenTrigger(
        term: 'quesadilla',
        certainty: TriggerCertainty.likely,
        source: '11 §4.1',
      ),
      HiddenTrigger(
        term: 'tzatziki',
        certainty: TriggerCertainty.likely,
        source: '11 §4.1',
      ),
      HiddenTrigger(
        term: 'raita',
        certainty: TriggerCertainty.likely,
        source: '11 §4.1',
      ),
      HiddenTrigger(
        term: 'lassi',
        certainty: TriggerCertainty.likely,
        source: '11 §4.1',
      ),
      // Sauces and drinks that are usually, not always, milky.
      HiddenTrigger(
        term: 'pesto',
        certainty: TriggerCertainty.likely,
        source: '11 §4.2',
      ),
      HiddenTrigger(
        term: 'caesar',
        certainty: TriggerCertainty.likely,
        source: '11 §4.2',
      ),
      // Hard, aged cheeses hold only traces of lactose, so lactose is a
      // question, not a certainty (11 §4.3).
      HiddenTrigger(
        term: 'parmesan',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.3',
      ),
      HiddenTrigger(
        term: 'parmigiano',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.3',
      ),
      HiddenTrigger(
        term: 'pecorino',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.3',
      ),
      HiddenTrigger(
        term: 'grana padano',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.3',
      ),
      HiddenTrigger(
        term: 'gruyere',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.3',
      ),
      HiddenTrigger(
        term: 'emmental',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.3',
      ),
      HiddenTrigger(
        term: 'emmenthal',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.3',
      ),
      HiddenTrigger(
        term: 'manchego',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.3',
      ),
      HiddenTrigger(
        term: 'cheddar',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.3',
      ),
      HiddenTrigger(
        term: 'gouda',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.3',
      ),
      HiddenTrigger(
        term: 'edam',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.3',
      ),
      HiddenTrigger(
        term: 'jarlsberg',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.3',
      ),
      HiddenTrigger(
        term: 'provolone',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.3',
      ),
      HiddenTrigger(
        term: 'asiago',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.3',
      ),
      HiddenTrigger(
        term: 'hard cheese',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.3',
      ),
      HiddenTrigger(
        term: 'aged cheese',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.3',
      ),
      HiddenTrigger(
        term: 'hard aged cheese',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.3',
      ),
      // Other cheeses, butter, ghee and cultured milk: dose-dependent (11
      // §4.3).
      HiddenTrigger(
        term: 'feta',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.3',
      ),
      HiddenTrigger(
        term: 'halloumi',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.3',
      ),
      HiddenTrigger(
        term: 'haloumi',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.3',
      ),
      HiddenTrigger(
        term: 'brie',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.3',
      ),
      HiddenTrigger(
        term: 'camembert',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.3',
      ),
      HiddenTrigger(
        term: 'gorgonzola',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.3',
      ),
      HiddenTrigger(
        term: 'roquefort',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.3',
      ),
      HiddenTrigger(
        term: 'stilton',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.3',
      ),
      HiddenTrigger(
        term: 'taleggio',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.3',
      ),
      HiddenTrigger(
        term: 'fontina',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.3',
      ),
      HiddenTrigger(
        term: 'cotija',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.3',
      ),
      HiddenTrigger(
        term: 'butter',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.3',
      ),
      HiddenTrigger(
        term: 'buttered',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.3',
      ),
      HiddenTrigger(
        term: 'ghee',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.3',
      ),
      HiddenTrigger(
        term: 'yogurt',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.3',
      ),
      HiddenTrigger(
        term: 'yoghurt',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.3',
      ),
      HiddenTrigger(
        term: 'kefir',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.3',
      ),
      HiddenTrigger(
        term: 'skyr',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.3',
      ),
      // Cream-finished dishes, baked goods and chocolate (11 §4.2).
      HiddenTrigger(
        term: 'carbonara',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.2',
      ),
      HiddenTrigger(
        term: 'risotto',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.2',
      ),
      HiddenTrigger(
        term: 'mashed potato',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.2',
      ),
      HiddenTrigger(
        term: 'mashed potatoes',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.2',
      ),
      HiddenTrigger(
        term: 'potato puree',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.2',
      ),
      HiddenTrigger(
        term: 'pommes puree',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.2',
      ),
      HiddenTrigger(
        term: 'scalloped potatoes',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.2',
      ),
      HiddenTrigger(
        term: 'creamy',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.2',
      ),
      HiddenTrigger(
        term: 'creamed',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.2',
      ),
      HiddenTrigger(
        term: 'butterscotch',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.2',
      ),
      HiddenTrigger(
        term: 'macchiato',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.2',
      ),
      HiddenTrigger(
        term: 'mocha',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.2',
      ),
      HiddenTrigger(
        term: 'hot chocolate',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.2',
      ),
      HiddenTrigger(
        term: 'croissant',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.2',
      ),
      HiddenTrigger(
        term: 'croissants',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.2',
      ),
      HiddenTrigger(
        term: 'danish',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.2',
      ),
      HiddenTrigger(
        term: 'pastry',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.2',
      ),
      HiddenTrigger(
        term: 'pastries',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.2',
      ),
      HiddenTrigger(
        term: 'cake',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.2',
      ),
      HiddenTrigger(
        term: 'cakes',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.2',
      ),
      HiddenTrigger(
        term: 'muffin',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.2',
      ),
      HiddenTrigger(
        term: 'muffins',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.2',
      ),
      HiddenTrigger(
        term: 'scone',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.2',
      ),
      HiddenTrigger(
        term: 'scones',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.2',
      ),
      HiddenTrigger(
        term: 'pancake',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.2',
      ),
      HiddenTrigger(
        term: 'pancakes',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.2',
      ),
      HiddenTrigger(
        term: 'waffle',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.2',
      ),
      HiddenTrigger(
        term: 'waffles',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.2',
      ),
      HiddenTrigger(
        term: 'brownie',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.2',
      ),
      HiddenTrigger(
        term: 'brownies',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.2',
      ),
      HiddenTrigger(
        term: 'cookie',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.2',
      ),
      HiddenTrigger(
        term: 'cookies',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.2',
      ),
      HiddenTrigger(
        term: 'caramel',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.2',
      ),
      HiddenTrigger(
        term: 'chocolate',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.2',
      ),
      HiddenTrigger(
        term: 'toffee',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.2',
      ),
      HiddenTrigger(
        term: 'sundae',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.2',
      ),
      HiddenTrigger(
        term: 'almond croissant',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.2',
      ),
      HiddenTrigger(
        term: 'almond croissants',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.2',
      ),
      HiddenTrigger(
        term: 'almond cake',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.2',
      ),
      HiddenTrigger(
        term: 'coconut cake',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.2',
      ),
      HiddenTrigger(
        term: 'peanut butter cookie',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.2',
      ),
      HiddenTrigger(
        term: 'peanut butter cookies',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.2',
      ),
      HiddenTrigger(
        term: 'hollandaise',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.2',
      ),
      HiddenTrigger(
        term: 'bearnaise',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.2',
      ),
    ],
    hiddenHe: <HiddenTrigger>[
      // "חלבי" is the dairy kosher category (12 §2.1).
      HiddenTrigger(
        term: 'חלבי',
        certainty: TriggerCertainty.likely,
        source: '12 §2.1',
      ),
      HiddenTrigger(
        term: 'חלבית',
        certainty: TriggerCertainty.likely,
        source: '12 §2.1',
      ),
      // Coffee drinks made with milk and ice cream (11 §4.1).
      HiddenTrigger(
        term: 'הפוך',
        certainty: TriggerCertainty.likely,
        source: '11 §4.1',
      ),
      HiddenTrigger(
        term: 'לאטה',
        certainty: TriggerCertainty.likely,
        source: '11 §4.1',
      ),
      HiddenTrigger(
        term: 'לטה',
        certainty: TriggerCertainty.likely,
        source: '11 §4.1',
      ),
      HiddenTrigger(
        term: "קפוצ'ינו",
        certainty: TriggerCertainty.likely,
        source: '11 §4.1',
      ),
      HiddenTrigger(
        term: 'פלאט וייט',
        certainty: TriggerCertainty.likely,
        source: '11 §4.1',
      ),
      HiddenTrigger(
        term: 'קורטדו',
        certainty: TriggerCertainty.likely,
        source: '11 §4.1',
      ),
      HiddenTrigger(
        term: 'מילקשייק',
        certainty: TriggerCertainty.likely,
        source: '11 §4.1',
      ),
      HiddenTrigger(
        term: 'מילקשק',
        certainty: TriggerCertainty.likely,
        source: '11 §4.1',
      ),
      HiddenTrigger(
        term: 'גלידה',
        certainty: TriggerCertainty.likely,
        source: '11 §4.1',
      ),
      HiddenTrigger(
        term: 'גלידת',
        certainty: TriggerCertainty.likely,
        source: '11 §4.1',
      ),
      HiddenTrigger(
        term: 'גלידות',
        certainty: TriggerCertainty.likely,
        source: '11 §4.1',
      ),
      // Sauces and dishes made with milk or cream (11 §4.1).
      HiddenTrigger(
        term: 'בריוש',
        certainty: TriggerCertainty.likely,
        source: '11 §4.1',
      ),
      HiddenTrigger(
        term: 'פסטו',
        certainty: TriggerCertainty.likely,
        source: '11 §4.1',
      ),
      HiddenTrigger(
        term: 'סלט קיסר',
        certainty: TriggerCertainty.likely,
        source: '11 §4.1',
      ),
      HiddenTrigger(
        term: 'רוטב קיסר',
        certainty: TriggerCertainty.likely,
        source: '11 §4.1',
      ),
      HiddenTrigger(
        term: 'אלפרדו',
        certainty: TriggerCertainty.likely,
        source: '11 §4.1',
      ),
      HiddenTrigger(
        term: 'בשמל',
        certainty: TriggerCertainty.likely,
        source: '11 §4.1',
      ),
      HiddenTrigger(
        term: 'הולנדייז',
        certainty: TriggerCertainty.likely,
        source: '11 §4.1',
      ),
      HiddenTrigger(
        term: 'גראטן',
        certainty: TriggerCertainty.likely,
        source: '11 §4.1',
      ),
      HiddenTrigger(
        term: 'גרטן',
        certainty: TriggerCertainty.likely,
        source: '11 §4.1',
      ),
      HiddenTrigger(
        term: 'פודינג',
        certainty: TriggerCertainty.likely,
        source: '11 §4.1',
      ),
      HiddenTrigger(
        term: 'טירמיסו',
        certainty: TriggerCertainty.likely,
        source: '11 §4.1',
      ),
      HiddenTrigger(
        term: 'פנה קוטה',
        certainty: TriggerCertainty.likely,
        source: '11 §4.1',
      ),
      HiddenTrigger(
        term: 'פנקוטה',
        certainty: TriggerCertainty.likely,
        source: '11 §4.1',
      ),
      HiddenTrigger(
        term: 'קרם ברולה',
        certainty: TriggerCertainty.likely,
        source: '11 §4.1',
      ),
      HiddenTrigger(
        term: "ג'לטו",
        certainty: TriggerCertainty.likely,
        source: '11 §4.1',
      ),
      HiddenTrigger(
        term: 'פונדו',
        certainty: TriggerCertainty.likely,
        source: '11 §4.1',
      ),
      HiddenTrigger(
        term: 'קסדילה',
        certainty: TriggerCertainty.likely,
        source: '11 §4.1',
      ),
      HiddenTrigger(
        term: 'צזיקי',
        certainty: TriggerCertainty.likely,
        source: '11 §4.1',
      ),
      // Hard cheeses hold only traces of lactose (11 §4.3).
      HiddenTrigger(
        term: 'פרמזן',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.3',
      ),
      HiddenTrigger(
        term: "פרמיג'אנו",
        certainty: TriggerCertainty.suspected,
        source: '11 §4.3',
      ),
      HiddenTrigger(
        term: 'פקורינו',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.3',
      ),
      HiddenTrigger(
        term: 'גרויר',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.3',
      ),
      HiddenTrigger(
        term: 'אמנטל',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.3',
      ),
      HiddenTrigger(
        term: "צ'דר",
        certainty: TriggerCertainty.suspected,
        source: '11 §4.3',
      ),
      HiddenTrigger(
        term: 'גאודה',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.3',
      ),
      // Other cheeses, butter, ghee and cultured milk: dose-dependent (11
      // §4.3).
      HiddenTrigger(
        term: 'חלומי',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.3',
      ),
      HiddenTrigger(
        term: 'הלומי',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.3',
      ),
      HiddenTrigger(
        term: 'קממבר',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.3',
      ),
      HiddenTrigger(
        term: 'פטה',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.3',
      ),
      HiddenTrigger(
        term: 'בולגרית',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.3',
      ),
      HiddenTrigger(
        term: 'צפתית',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.3',
      ),
      HiddenTrigger(
        term: 'גורגונזולה',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.3',
      ),
      HiddenTrigger(
        term: 'רוקפור',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.3',
      ),
      HiddenTrigger(
        term: 'קשקבל',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.3',
      ),
      HiddenTrigger(
        term: 'חמאה',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.3',
      ),
      HiddenTrigger(
        term: 'חמאת',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.3',
      ),
      HiddenTrigger(
        term: 'גהי',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.3',
      ),
      HiddenTrigger(
        term: 'סמנה',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.3',
      ),
      HiddenTrigger(
        term: 'סאמנה',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.3',
      ),
      HiddenTrigger(
        term: 'יוגורט',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.3',
      ),
      HiddenTrigger(
        term: 'יוגרט',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.3',
      ),
      // Cream-finished dishes and baked goods (11 §4.2).
      HiddenTrigger(
        term: 'פירה',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.2',
      ),
      HiddenTrigger(
        term: 'ריזוטו',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.2',
      ),
      HiddenTrigger(
        term: 'קרמי',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.2',
      ),
      HiddenTrigger(
        term: 'קרבונרה',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.2',
      ),
      HiddenTrigger(
        term: 'מקיאטו',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.2',
      ),
      HiddenTrigger(
        term: 'מוקה',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.2',
      ),
      HiddenTrigger(
        term: 'קרואסון',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.2',
      ),
      HiddenTrigger(
        term: 'דניש',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.2',
      ),
      HiddenTrigger(
        term: 'מאפה',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.2',
      ),
      HiddenTrigger(
        term: 'מאפים',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.2',
      ),
      HiddenTrigger(
        term: 'עוגה',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.2',
      ),
      HiddenTrigger(
        term: 'עוגת',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.2',
      ),
      HiddenTrigger(
        term: 'עוגות',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.2',
      ),
      HiddenTrigger(
        term: 'עוגיות',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.2',
      ),
      HiddenTrigger(
        term: 'עוגייה',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.2',
      ),
      HiddenTrigger(
        term: 'פנקייק',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.2',
      ),
      HiddenTrigger(
        term: 'פנקייקים',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.2',
      ),
      HiddenTrigger(
        term: 'וופל',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.2',
      ),
      HiddenTrigger(
        term: 'וופלים',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.2',
      ),
      HiddenTrigger(
        term: 'בראוני',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.2',
      ),
      HiddenTrigger(
        term: 'מאפין',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.2',
      ),
      HiddenTrigger(
        term: 'מאפינס',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.2',
      ),
      HiddenTrigger(
        term: 'סקונס',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.2',
      ),
      HiddenTrigger(
        term: 'שוקולד',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.2',
      ),
      HiddenTrigger(
        term: 'קרמל',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.2',
      ),
      HiddenTrigger(
        term: 'קרם שקדים',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.2',
      ),
      HiddenTrigger(
        term: 'קרואסון שקדים',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.2',
      ),
      HiddenTrigger(
        term: 'עוגת שקדים',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.2',
      ),
      HiddenTrigger(
        term: 'עוגת קוקוס',
        certainty: TriggerCertainty.suspected,
        source: '11 §4.2',
      ),
      // Pastries made with butter or margarine (12 §1.5).
      HiddenTrigger(
        term: "ג'חנון",
        certainty: TriggerCertainty.suspected,
        source: '12 §1.5',
      ),
      HiddenTrigger(
        term: 'מלאווח',
        certainty: TriggerCertainty.suspected,
        source: '12 §1.5',
      ),
      HiddenTrigger(
        term: 'מלווח',
        certainty: TriggerCertainty.suspected,
        source: '12 §1.5',
      ),
      HiddenTrigger(
        term: 'כובאנה',
        certainty: TriggerCertainty.suspected,
        source: '12 §1.5',
      ),
      HiddenTrigger(
        term: 'קובנה',
        certainty: TriggerCertainty.suspected,
        source: '12 §1.5',
      ),
      HiddenTrigger(
        term: 'בורקס',
        certainty: TriggerCertainty.suspected,
        source: '12 §1.5',
      ),
      HiddenTrigger(
        term: 'בורקסים',
        certainty: TriggerCertainty.suspected,
        source: '12 §1.5',
      ),
    ],
    guards: AllergenGuards(
      beforeEn: <String>[
        'no',
        'without',
        'lactose free',
        'hard',
        'aged',
        'mature',
        'parmesan',
        'parmigiano',
        'pecorino',
        'grana padano',
        'gruyere',
        'emmental',
        'emmenthal',
        'manchego',
        'vegan',
        'plant based',
        'dairy free',
        'free from',
      ],
      afterEn: <String>['free', 'aged', 'lactose free', 'dairy free'],
      beforeHe: <String>[
        'ללא',
        'בלי',
        'וללא',
        'ובלי',
        'דל',
        'ללא מוצרי',
        'בלי מוצרי',
      ],
      afterHe: <String>[
        'טבעוני',
        'טבעונית',
        'צמחי',
        'צמחית',
        'פרווה',
        'ללא לקטוז',
        'בלי לקטוז',
        'דל לקטוז',
        'ללא חלב',
        'בלי חלב',
        'פרמזן',
        'פקורינו',
        'גרויר',
        'אמנטל',
        'ללא מוצרי',
        'בלי מוצרי',
      ],
    ),
    termGuards: <String, AllergenGuards>{
      'milk': AllergenGuards(
        beforeEn: _plantBasesEn,
        afterEn: <String>['thistle'],
      ),
      'milkshake': AllergenGuards(beforeEn: _plantBasesEn),
      'milkshakes': AllergenGuards(beforeEn: _plantBasesEn),
      'cream': AllergenGuards(
        beforeEn: <String>[..._plantBasesEn, 'free ice', 'free whipped'],
        afterEn: <String>['of tartar'],
      ),
      'cheese': AllergenGuards(beforeEn: _plantBasesEn),
      'cheeses': AllergenGuards(beforeEn: _plantBasesEn),
      'yogurt': AllergenGuards(beforeEn: _plantBasesEn),
      'yoghurt': AllergenGuards(beforeEn: _plantBasesEn),
      'butter': AllergenGuards(beforeEn: _otherButtersEn),
      'חלב': AllergenGuards(afterHe: _plantBasesHe),
      'שמנת': AllergenGuards(afterHe: _plantBasesHe),
      'גבינת': AllergenGuards(afterHe: _plantBasesHe),
      'יוגורט': AllergenGuards(afterHe: _plantBasesHe),
      'חמאת': AllergenGuards(afterHe: _otherButtersHe),
    },
    noPrefixHe: <String>['הפוך'],
    sources: <String>['11 §4.1', '11 §4.3', '11 §4.5', '12 §1.5', '12 §2.2'],
  ),
  RestrictionId.eggs: RestrictionVocabulary(
    directEn: <String>[
      // The egg and its derivatives (11 §5.1).
      'egg',
      'eggs',
      'yolk',
      'yolks',
      'albumin',
      'albumen',
      'ovalbumin',
      'ovomucoid',
      'ovomucin',
      'lysozyme',
      'livetin',
      'vitellin',
      // Dishes that are egg by definition (11 §5.1).
      'meringue',
      'meringues',
      'mayonnaise',
      'mayo',
      'aioli',
      'eggnog',
      'omelette',
      'omelettes',
      'omelet',
      'omelets',
      'frittata',
      'shakshuka',
      'shakshouka',
      'custard',
    ],
    directHe: <String>[
      // The egg and its derivatives (12 §1.6).
      'ביצה',
      'ביצים',
      'ביצת',
      'ביצי',
      'חלמון',
      'חלמונים',
      'אלבומין',
      'ליזוזים',
      // Dishes that are egg by definition (12 §1.6).
      'חביתה',
      'חביתת',
      'חביתות',
      'אומלט',
      'פריטטה',
      'שקשוקה',
      'מיונז',
      'איולי',
      'מרנג',
    ],
    hiddenEn: <HiddenTrigger>[
      // Egg sauces, enriched bread and breaded or battered food (11 §5.2).
      HiddenTrigger(
        term: 'brioche',
        certainty: TriggerCertainty.likely,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'hollandaise',
        certainty: TriggerCertainty.likely,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'bearnaise',
        certainty: TriggerCertainty.likely,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'caesar',
        certainty: TriggerCertainty.likely,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'carbonara',
        certainty: TriggerCertainty.likely,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'tartar sauce',
        certainty: TriggerCertainty.likely,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'tartare sauce',
        certainty: TriggerCertainty.likely,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'remoulade',
        certainty: TriggerCertainty.likely,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'thousand island',
        certainty: TriggerCertainty.likely,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'schnitzel',
        certainty: TriggerCertainty.likely,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'katsu',
        certainty: TriggerCertainty.likely,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'cordon bleu',
        certainty: TriggerCertainty.likely,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'breaded',
        certainty: TriggerCertainty.likely,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'crumbed',
        certainty: TriggerCertainty.likely,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'breadcrumbs',
        certainty: TriggerCertainty.likely,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'bread crumbs',
        certainty: TriggerCertainty.likely,
        source: '11 §5.2',
      ),
      // Egg custards and baked egg dishes (11 §5.1).
      HiddenTrigger(
        term: 'quiche',
        certainty: TriggerCertainty.likely,
        source: '11 §5.1',
      ),
      HiddenTrigger(
        term: 'souffle',
        certainty: TriggerCertainty.likely,
        source: '11 §5.1',
      ),
      HiddenTrigger(
        term: 'pavlova',
        certainty: TriggerCertainty.likely,
        source: '11 §5.1',
      ),
      HiddenTrigger(
        term: 'tiramisu',
        certainty: TriggerCertainty.likely,
        source: '11 §5.1',
      ),
      HiddenTrigger(
        term: 'creme brulee',
        certainty: TriggerCertainty.likely,
        source: '11 §5.1',
      ),
      HiddenTrigger(
        term: 'french toast',
        certainty: TriggerCertainty.likely,
        source: '11 §5.1',
      ),
      // Sabich carries a hard-boiled egg (12 §1.6).
      HiddenTrigger(
        term: 'sabich',
        certainty: TriggerCertainty.likely,
        source: '12 §1.6',
      ),
      HiddenTrigger(
        term: 'sabih',
        certainty: TriggerCertainty.likely,
        source: '12 §1.6',
      ),
      // Fresh pasta, surimi and imitation crab (11 §5.2).
      HiddenTrigger(
        term: 'fresh pasta',
        certainty: TriggerCertainty.suspected,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'surimi',
        certainty: TriggerCertainty.suspected,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'imitation crab',
        certainty: TriggerCertainty.suspected,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'crab sticks',
        certainty: TriggerCertainty.suspected,
        source: '11 §5.2',
      ),
      // Coatings, batters and baked goods that carry egg wash or egg (11
      // §5.2).
      HiddenTrigger(
        term: 'battered',
        certainty: TriggerCertainty.suspected,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'tempura',
        certainty: TriggerCertainty.suspected,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'panko',
        certainty: TriggerCertainty.suspected,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'nuggets',
        certainty: TriggerCertainty.suspected,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'fish and chips',
        certainty: TriggerCertainty.suspected,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'onion rings',
        certainty: TriggerCertainty.suspected,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'pastry',
        certainty: TriggerCertainty.suspected,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'pastries',
        certainty: TriggerCertainty.suspected,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'pie',
        certainty: TriggerCertainty.suspected,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'pies',
        certainty: TriggerCertainty.suspected,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'sausage roll',
        certainty: TriggerCertainty.suspected,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'sausage rolls',
        certainty: TriggerCertainty.suspected,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'cake',
        certainty: TriggerCertainty.suspected,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'cakes',
        certainty: TriggerCertainty.suspected,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'pancake',
        certainty: TriggerCertainty.suspected,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'pancakes',
        certainty: TriggerCertainty.suspected,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'waffle',
        certainty: TriggerCertainty.suspected,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'waffles',
        certainty: TriggerCertainty.suspected,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'crepe',
        certainty: TriggerCertainty.suspected,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'crepes',
        certainty: TriggerCertainty.suspected,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'muffin',
        certainty: TriggerCertainty.suspected,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'muffins',
        certainty: TriggerCertainty.suspected,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'brownie',
        certainty: TriggerCertainty.suspected,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'brownies',
        certainty: TriggerCertainty.suspected,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'cookie',
        certainty: TriggerCertainty.suspected,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'cookies',
        certainty: TriggerCertainty.suspected,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'marshmallow',
        certainty: TriggerCertainty.suspected,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'marshmallows',
        certainty: TriggerCertainty.suspected,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'frosting',
        certainty: TriggerCertainty.suspected,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'pretzel',
        certainty: TriggerCertainty.suspected,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'pretzels',
        certainty: TriggerCertainty.suspected,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'marzipan',
        certainty: TriggerCertainty.suspected,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'pudding',
        certainty: TriggerCertainty.suspected,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'frangipane',
        certainty: TriggerCertainty.suspected,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'challah',
        certainty: TriggerCertainty.suspected,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'lasagne',
        certainty: TriggerCertainty.suspected,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'lasagna',
        certainty: TriggerCertainty.suspected,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'meatball',
        certainty: TriggerCertainty.suspected,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'meatballs',
        certainty: TriggerCertainty.suspected,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'meatloaf',
        certainty: TriggerCertainty.suspected,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'tartare',
        certainty: TriggerCertainty.likely,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'lecithin',
        certainty: TriggerCertainty.suspected,
        source: '11 §5.2',
      ),
      // Egg noodles and fried rice (12 §5).
      HiddenTrigger(
        term: 'fried rice',
        certainty: TriggerCertainty.suspected,
        source: '12 §5',
      ),
      HiddenTrigger(
        term: 'chow mein',
        certainty: TriggerCertainty.suspected,
        source: '12 §5',
      ),
      HiddenTrigger(
        term: 'lo mein',
        certainty: TriggerCertainty.suspected,
        source: '12 §5',
      ),
      // Pastry glazed with egg wash (11 §5.2).
      HiddenTrigger(
        term: 'croissant',
        certainty: TriggerCertainty.suspected,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'croissants',
        certainty: TriggerCertainty.suspected,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'danish',
        certainty: TriggerCertainty.suspected,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'scone',
        certainty: TriggerCertainty.suspected,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'scones',
        certainty: TriggerCertainty.suspected,
        source: '11 §5.2',
      ),
      // Recall-gate additions (issue #352): egg-bound doughs,
      // wrappers and creamy dressings (11 §5.2).
      HiddenTrigger(
        term: 'coleslaw',
        certainty: TriggerCertainty.suspected,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'spring roll',
        certainty: TriggerCertainty.suspected,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'spring rolls',
        certainty: TriggerCertainty.suspected,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'hot cross bun',
        certainty: TriggerCertainty.suspected,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'hot cross buns',
        certainty: TriggerCertainty.suspected,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'fettuccine',
        certainty: TriggerCertainty.suspected,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'fettucine',
        certainty: TriggerCertainty.suspected,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'tagliatelle',
        certainty: TriggerCertainty.suspected,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'pappardelle',
        certainty: TriggerCertainty.suspected,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'khachapuri',
        certainty: TriggerCertainty.suspected,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'ranch',
        certainty: TriggerCertainty.suspected,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'ranch dressing',
        certainty: TriggerCertainty.suspected,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'blue cheese dressing',
        certainty: TriggerCertainty.suspected,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'creamy dressing',
        certainty: TriggerCertainty.suspected,
        source: '11 §5.2',
      ),
    ],
    hiddenHe: <HiddenTrigger>[
      // Sabich, schnitzel and Israeli sauces and breads (12 §1.6).
      HiddenTrigger(
        term: 'סביח',
        certainty: TriggerCertainty.likely,
        source: '12 §1.6',
      ),
      HiddenTrigger(
        term: 'שניצל',
        certainty: TriggerCertainty.likely,
        source: '12 §1.6',
      ),
      HiddenTrigger(
        term: 'שניצלים',
        certainty: TriggerCertainty.likely,
        source: '12 §1.6',
      ),
      HiddenTrigger(
        term: 'פירורי לחם',
        certainty: TriggerCertainty.likely,
        source: '12 §1.6',
      ),
      HiddenTrigger(
        term: 'אלף האיים',
        certainty: TriggerCertainty.likely,
        source: '12 §1.6',
      ),
      HiddenTrigger(
        term: 'רוטב טרטר',
        certainty: TriggerCertainty.likely,
        source: '12 §1.6',
      ),
      HiddenTrigger(
        term: 'בריוש',
        certainty: TriggerCertainty.likely,
        source: '12 §1.6',
      ),
      // Caesar, hollandaise, carbonara and egg custards (11 §5.2).
      HiddenTrigger(
        term: 'סלט קיסר',
        certainty: TriggerCertainty.likely,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'רוטב קיסר',
        certainty: TriggerCertainty.likely,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'הולנדייז',
        certainty: TriggerCertainty.likely,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'קרבונרה',
        certainty: TriggerCertainty.likely,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'קרם ברולה',
        certainty: TriggerCertainty.likely,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'טירמיסו',
        certainty: TriggerCertainty.likely,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'קיש',
        certainty: TriggerCertainty.likely,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'סופלה',
        certainty: TriggerCertainty.likely,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'פבלובה',
        certainty: TriggerCertainty.likely,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'פרנץ טוסט',
        certainty: TriggerCertainty.likely,
        source: '11 §5.2',
      ),
      // Fresh pasta, surimi, bourekas egg wash, cakes, meatballs and
      // challah (12 §1.6).
      HiddenTrigger(
        term: 'פסטה טרייה',
        certainty: TriggerCertainty.suspected,
        source: '12 §1.6',
      ),
      // Leftover recall misses (issue #352): a spread of salads usually
      // holds the mayonnaise ones, eggplant and cabbage (12 §1.6).
      HiddenTrigger(
        term: 'מבחר סלטים',
        certainty: TriggerCertainty.suspected,
        source: '12 §1.6',
      ),
      HiddenTrigger(
        term: 'סורימי',
        certainty: TriggerCertainty.suspected,
        source: '12 §1.6',
      ),
      HiddenTrigger(
        term: 'בורקס',
        certainty: TriggerCertainty.suspected,
        source: '12 §1.6',
      ),
      HiddenTrigger(
        term: 'בורקסים',
        certainty: TriggerCertainty.suspected,
        source: '12 §1.6',
      ),
      HiddenTrigger(
        term: 'עוגה',
        certainty: TriggerCertainty.suspected,
        source: '12 §1.6',
      ),
      HiddenTrigger(
        term: 'עוגת',
        certainty: TriggerCertainty.suspected,
        source: '12 §1.6',
      ),
      HiddenTrigger(
        term: 'עוגות',
        certainty: TriggerCertainty.suspected,
        source: '12 §1.6',
      ),
      HiddenTrigger(
        term: 'חלה',
        certainty: TriggerCertainty.suspected,
        source: '12 §1.6',
      ),
      HiddenTrigger(
        term: 'חלות',
        certainty: TriggerCertainty.suspected,
        source: '12 §1.6',
      ),
      HiddenTrigger(
        term: 'קציצה',
        certainty: TriggerCertainty.suspected,
        source: '12 §1.6',
      ),
      HiddenTrigger(
        term: 'קציצות',
        certainty: TriggerCertainty.suspected,
        source: '12 §1.6',
      ),
      // Coatings, batters and baked goods that carry egg (11 §5.2).
      HiddenTrigger(
        term: 'נאגטס',
        certainty: TriggerCertainty.suspected,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'נגטס',
        certainty: TriggerCertainty.suspected,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'פנקו',
        certainty: TriggerCertainty.suspected,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'טמפורה',
        certainty: TriggerCertainty.suspected,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'טרטר',
        certainty: TriggerCertainty.likely,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'פנקייק',
        certainty: TriggerCertainty.suspected,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'פנקייקים',
        certainty: TriggerCertainty.suspected,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'וופל',
        certainty: TriggerCertainty.suspected,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'וופלים',
        certainty: TriggerCertainty.suspected,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'קרפ',
        certainty: TriggerCertainty.suspected,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'קרפים',
        certainty: TriggerCertainty.suspected,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'עוגיות',
        certainty: TriggerCertainty.suspected,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'עוגייה',
        certainty: TriggerCertainty.suspected,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'בראוני',
        certainty: TriggerCertainty.suspected,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'מאפין',
        certainty: TriggerCertainty.suspected,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'מרשמלו',
        certainty: TriggerCertainty.suspected,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'לזניה',
        certainty: TriggerCertainty.suspected,
        source: '11 §5.2',
      ),
      // Lecithin is soy or egg (11 §5.3).
      HiddenTrigger(
        term: 'לציטין',
        certainty: TriggerCertainty.suspected,
        source: '11 §5.3',
      ),
      // Pastry glazed with egg wash (11 §5.2).
      HiddenTrigger(
        term: 'קרואסון',
        certainty: TriggerCertainty.suspected,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'דניש',
        certainty: TriggerCertainty.suspected,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'מאפה',
        certainty: TriggerCertainty.suspected,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'מאפים',
        certainty: TriggerCertainty.suspected,
        source: '11 §5.2',
      ),
      // Egg noodles and fried rice (12 §5).
      HiddenTrigger(
        term: "צ'או מיין",
        certainty: TriggerCertainty.suspected,
        source: '12 §5',
      ),
      HiddenTrigger(
        term: 'אורז מטוגן',
        certainty: TriggerCertainty.suspected,
        source: '12 §5',
      ),
      HiddenTrigger(
        term: 'גפילטע פיש',
        certainty: TriggerCertainty.suspected,
        source: '12 §1.6',
      ),
      HiddenTrigger(
        term: 'קולסלו',
        certainty: TriggerCertainty.suspected,
        source: '12 §1.6',
      ),
      HiddenTrigger(
        term: 'רוגלך',
        certainty: TriggerCertainty.suspected,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'פטוצ׳יני',
        certainty: TriggerCertainty.suspected,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'טליאטלה',
        certainty: TriggerCertainty.suspected,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'חצ׳פורי',
        certainty: TriggerCertainty.suspected,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'חינקלי',
        certainty: TriggerCertainty.suspected,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'סמבוסק',
        certainty: TriggerCertainty.suspected,
        source: '11 §5.2',
      ),
      HiddenTrigger(
        term: 'עוגיית',
        certainty: TriggerCertainty.suspected,
        source: '11 §5.2',
      ),
    ],
    guards: AllergenGuards(
      beforeEn: <String>[
        'no',
        'without',
        'vegan',
        'plant based',
        'eggless',
        'egg free',
        'free from',
      ],
      afterEn: <String>['free', 'egg free'],
      beforeHe: <String>['ללא', 'בלי', 'וללא', 'ובלי'],
      afterHe: <String>[
        'טבעוני',
        'טבעונית',
        'צמחי',
        'צמחית',
        'ללא ביצים',
        'בלי ביצים',
        'ללא ביצה',
        'בלי ביצה',
      ],
    ),
    noPrefixHe: <String>['חלה'],
    sources: <String>['11 §5.1', '11 §5.3', '11 §5.5', '12 §1.6'],
  ),
};

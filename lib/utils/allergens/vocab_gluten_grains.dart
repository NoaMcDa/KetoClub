/// Gluten and grains: the trigger vocabulary of wheat, gluten and lupin
/// (Banto; ALG-01, issue #343).
///
/// Every term comes from
/// `allergen app documentation/11_hidden_allergen_sources.md` or
/// `12_israeli_and_us_menu_lexicon.md` and its source cites the section
/// (`"11 §7.1"`, `"12 §1.4"`), which
/// `test/utils/allergens/vocabulary_test.dart` checks. After a change,
/// regenerate the goldens and copy `allergens.json` to
/// `backend/app/keto/` (architecture.md D26).
library;

import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/utils/allergens/vocabulary_types.dart';

/// English wheat-containing foods: the grain itself and the dishes
/// made of it (11 §7.1). Shared by wheat and gluten, because everything
/// with wheat in it has gluten in it.
const List<String> _wheatFoodsEn = <String>[
  'wheat',
  'durum',
  'einkorn',
  'emmer',
  'farro',
  'farina',
  'semolina',
  'spelt',
  'kamut',
  'khorasan',
  'triticale',
  'couscous',
  'cous cous',
  'bulgur',
  'bulghur',
  'bulgar',
  'burghul',
  'freekeh',
  'seitan',
  'bread',
  'breads',
  'flatbread',
  'flatbreads',
  'cornbread',
  'shortbread',
  'gingerbread',
  'breadsticks',
  'breadstick',
  'bruschetta',
  'crostini',
  'bun',
  'buns',
  'pita',
  'pitas',
  'pitta',
  'laffa',
  'lafa',
  'naan',
  'chapati',
  'roti',
  'paratha',
  'baguette',
  'baguettes',
  'bagel',
  'bagels',
  'brioche',
  'ciabatta',
  'focaccia',
  'khachapuri',
  'hoagie',
  'hoagies',
  'sourdough',
  'challah',
  'toast',
  'toastie',
  'croutons',
  'crouton',
  'breadcrumbs',
  'breadcrumb',
  'panko',
  'pretzel',
  'pretzels',
  'sandwich',
  'sandwiches',
  'panini',
  'pasta',
  'pastas',
  'spaghetti',
  'penne',
  'fettuccine',
  'linguine',
  'tagliatelle',
  'pappardelle',
  'fusilli',
  'farfalle',
  'rigatoni',
  'macaroni',
  'lasagna',
  'lasagne',
  'cannelloni',
  'ravioli',
  'tortellini',
  'gnocchi',
  'orzo',
  'noodle',
  'noodles',
  'ramen',
  'udon',
  'lo mein',
  'chow mein',
  'dumpling',
  'dumplings',
  'gyoza',
  'wonton',
  'wontons',
  'pizza',
  'pizzas',
  'calzone',
  'calzones',
  'croissant',
  'croissants',
  'danish',
  'pastry',
  'pastries',
  'phyllo',
  'filo',
  'strudel',
  'baklava',
  'cake',
  'cakes',
  'cupcake',
  'cupcakes',
  'cheesecake',
  'cheesecakes',
  'cookie',
  'cookies',
  'biscuit',
  'biscuits',
  'brownie',
  'brownies',
  'muffin',
  'muffins',
  'scone',
  'scones',
  'donut',
  'donuts',
  'doughnut',
  'doughnuts',
  'waffle',
  'waffles',
  'pancake',
  'pancakes',
  'crepe',
  'crepes',
  'dough',
  'batter',
  'battered',
  'breaded',
  'crumbed',
  'tempura',
  'matzo',
  'matzah',
  'matza',
  'jachnun',
  'malawach',
  'kubaneh',
  'burekas',
  'bourekas',
  'borekas',
  'sambusak',
  'lahmajun',
  'ptitim',
];

/// Hebrew wheat-containing foods, with the Israeli bakery words
/// (12 §1.4). `חיטה`, `חלה` and `חלות` are compiled with no permissive
/// prefix (a prefix letter turns them into שחיטה, מחלה, מחלות), so
/// their prefixed forms are listed as their own terms. Shared by wheat
/// and gluten.
const List<String> _wheatFoodsHe = <String>[
  'חיטה',
  'החיטה',
  'בחיטה',
  'וחיטה',
  'לחיטה',
  'מחיטה',
  'כוסמין',
  'סולת',
  'קוסקוס',
  'בורגול',
  'פריקה',
  'פריקי',
  'סייטן',
  'סיטן',
  'קאמוט',
  'פתיתים',
  'פיתה',
  'פיתות',
  'לאפה',
  'לאפות',
  'לחם',
  'לחמים',
  'לחמנייה',
  'לחמניה',
  'לחמניות',
  'לחמניית',
  'לחמנית',
  'באגט',
  'בגט',
  'חלה',
  'החלה',
  'בחלה',
  'וחלה',
  'לחלה',
  'חלות',
  'החלות',
  'בחלות',
  'וחלות',
  'בייגל',
  'בייגלה',
  'טוסט',
  'טוסטים',
  'כריך',
  'כריכים',
  "סנדוויץ'",
  "סנדוויצ'ים",
  'סנדביץ',
  'פסטה',
  'פסטות',
  'ספגטי',
  'ספאגטי',
  "פטוצ'יני",
  'פטוצייני',
  'ניוקי',
  'גנוקי',
  'ראמן',
  'נודלס',
  'נודל',
  'אטריות',
  'אטריה',
  'לזניה',
  'רביולי',
  'טורטליני',
  'קנלוני',
  'טליאטלה',
  'לינגוויני',
  'ריגטוני',
  'אורזו',
  'מקרוני',
  'פיצה',
  'פיצות',
  'קלצונה',
  'קלזונה',
  'בורקס',
  'בורקסים',
  'מלאווח',
  'מלווח',
  'מלוואח',
  "ג'חנון",
  'כובאנה',
  'קובנה',
  'סמבוסק',
  'סמבוסקים',
  "לחמג'ון",
  "פוקצ'ה",
  'פוקאצ׳ה',
  'חצ׳פורי',
  'בצק',
  'בצק עלים',
  'פילו',
  'קרואסון',
  'קרואסונים',
  'בריוש',
  'דניש',
  'מאפה',
  'מאפים',
  'מאפי',
  'עוגה',
  'עוגות',
  'עוגת',
  'עוגיה',
  'עוגיות',
  'עוגיית',
  'מאפין',
  'מאפינס',
  'סקון',
  'רוגלך',
  'בקלאווה',
  'וופל',
  'וופלים',
  'פנקייק',
  'פנקייקים',
  'קרפ',
  "בלינצ'ס",
  'סופגנייה',
  'סופגניות',
  'דונאט',
  'קרקר',
  'קרקרים',
  'ביסקוויט',
  'ביסקוויטים',
  'פירורי לחם',
  'פאנקו',
  'בלילה',
  'טמפורה',
  'שקדי מרק',
  'קרוטונים',
  'מצה',
  'מצות',
];

/// English hidden sources of wheat (11 §7.1, §7.2, 12 §1.4, §5). Shared
/// by wheat and gluten.
const List<HiddenTrigger> _wheatHiddenEn = <HiddenTrigger>[
  HiddenTrigger(
    term: 'soy sauce',
    certainty: TriggerCertainty.likely,
    source: '11 §7.2',
  ),
  HiddenTrigger(
    term: 'teriyaki',
    certainty: TriggerCertainty.likely,
    source: '11 §7.2',
  ),
  HiddenTrigger(
    term: 'hoisin',
    certainty: TriggerCertainty.likely,
    source: '12 §5',
  ),
  HiddenTrigger(
    term: 'beer batter',
    certainty: TriggerCertainty.likely,
    source: '11 §7.2',
  ),
  HiddenTrigger(
    term: 'schnitzel',
    certainty: TriggerCertainty.likely,
    source: '12 §1.4',
  ),
  HiddenTrigger(
    term: 'katsu',
    certainty: TriggerCertainty.likely,
    source: '12 §1.4',
  ),
  HiddenTrigger(
    term: 'milanese',
    certainty: TriggerCertainty.likely,
    source: '12 §1.4',
  ),
  HiddenTrigger(
    term: 'nuggets',
    certainty: TriggerCertainty.likely,
    source: '12 §1.4',
  ),
  HiddenTrigger(
    term: 'fish and chips',
    certainty: TriggerCertainty.likely,
    source: '12 §1.4',
  ),
  HiddenTrigger(
    term: 'fish chips',
    certainty: TriggerCertainty.likely,
    source: '12 §1.4',
  ),
  HiddenTrigger(
    term: 'flour',
    certainty: TriggerCertainty.likely,
    source: '12 §1.4',
  ),
  HiddenTrigger(
    term: 'egg roll',
    certainty: TriggerCertainty.likely,
    source: '11 §7.1',
  ),
  HiddenTrigger(
    term: 'egg rolls',
    certainty: TriggerCertainty.likely,
    source: '11 §7.1',
  ),
  HiddenTrigger(
    term: 'roll',
    certainty: TriggerCertainty.likely,
    source: '11 §7.1',
  ),
  HiddenTrigger(
    term: 'rolls',
    certainty: TriggerCertainty.likely,
    source: '11 §7.1',
  ),
  HiddenTrigger(
    term: 'loaf',
    certainty: TriggerCertainty.likely,
    source: '11 §7.1',
  ),
  HiddenTrigger(
    term: 'loaves',
    certainty: TriggerCertainty.likely,
    source: '11 §7.1',
  ),
  HiddenTrigger(
    term: 'wholemeal',
    certainty: TriggerCertainty.likely,
    source: '11 §7.1',
  ),
  HiddenTrigger(
    term: 'cracker',
    certainty: TriggerCertainty.likely,
    source: '11 §7.1',
  ),
  HiddenTrigger(
    term: 'crackers',
    certainty: TriggerCertainty.likely,
    source: '11 §7.1',
  ),
  HiddenTrigger(
    term: 'floured',
    certainty: TriggerCertainty.suspected,
    source: '11 §7.2',
  ),
  HiddenTrigger(
    term: 'gravy',
    certainty: TriggerCertainty.suspected,
    source: '11 §7.2',
  ),
  HiddenTrigger(
    term: 'roux',
    certainty: TriggerCertainty.suspected,
    source: '11 §7.2',
  ),
  HiddenTrigger(
    term: 'bechamel',
    certainty: TriggerCertainty.suspected,
    source: '11 §7.2',
  ),
  HiddenTrigger(
    term: 'stock cube',
    certainty: TriggerCertainty.suspected,
    source: '11 §7.2',
  ),
  HiddenTrigger(
    term: 'stock cubes',
    certainty: TriggerCertainty.suspected,
    source: '11 §7.2',
  ),
  HiddenTrigger(
    term: 'bouillon cube',
    certainty: TriggerCertainty.suspected,
    source: '11 §7.2',
  ),
  HiddenTrigger(
    term: 'bouillon cubes',
    certainty: TriggerCertainty.suspected,
    source: '11 §7.2',
  ),
  HiddenTrigger(
    term: 'surimi',
    certainty: TriggerCertainty.suspected,
    source: '11 §7.2',
  ),
  HiddenTrigger(
    term: 'imitation crab',
    certainty: TriggerCertainty.suspected,
    source: '11 §7.2',
  ),
  HiddenTrigger(
    term: 'sausage',
    certainty: TriggerCertainty.suspected,
    source: '11 §7.2',
  ),
  HiddenTrigger(
    term: 'sausages',
    certainty: TriggerCertainty.suspected,
    source: '11 §7.2',
  ),
  HiddenTrigger(
    term: 'hot dog',
    certainty: TriggerCertainty.suspected,
    source: '11 §7.2',
  ),
  HiddenTrigger(
    term: 'hot dogs',
    certainty: TriggerCertainty.suspected,
    source: '11 §7.2',
  ),
  HiddenTrigger(
    term: 'plant based meat',
    certainty: TriggerCertainty.suspected,
    source: '11 §7.2',
  ),
  HiddenTrigger(
    term: 'meatball',
    certainty: TriggerCertainty.suspected,
    source: '12 §1.4',
  ),
  HiddenTrigger(
    term: 'meatballs',
    certainty: TriggerCertainty.suspected,
    source: '12 §1.4',
  ),
  HiddenTrigger(
    term: 'tortilla',
    certainty: TriggerCertainty.suspected,
    source: '12 §5',
  ),
  HiddenTrigger(
    term: 'tortillas',
    certainty: TriggerCertainty.suspected,
    source: '12 §5',
  ),
  HiddenTrigger(
    term: 'wrap',
    certainty: TriggerCertainty.suspected,
    source: '12 §5',
  ),
  HiddenTrigger(
    term: 'wraps',
    certainty: TriggerCertainty.suspected,
    source: '12 §5',
  ),
  HiddenTrigger(
    term: 'burger',
    certainty: TriggerCertainty.suspected,
    source: '11 §7.1',
  ),
  HiddenTrigger(
    term: 'burgers',
    certainty: TriggerCertainty.suspected,
    source: '11 §7.1',
  ),
  HiddenTrigger(
    term: 'hamburger',
    certainty: TriggerCertainty.suspected,
    source: '11 §7.1',
  ),
  HiddenTrigger(
    term: 'cheeseburger',
    certainty: TriggerCertainty.suspected,
    source: '11 §7.1',
  ),
  HiddenTrigger(
    term: 'soba',
    certainty: TriggerCertainty.suspected,
    source: '11 §7.1',
  ),
  HiddenTrigger(
    term: 'quiche',
    certainty: TriggerCertainty.suspected,
    source: '11 §7.1',
  ),
  HiddenTrigger(
    term: 'pie',
    certainty: TriggerCertainty.likely,
    source: '11 §7.1',
  ),
  HiddenTrigger(
    term: 'pies',
    certainty: TriggerCertainty.likely,
    source: '11 §7.1',
  ),
  HiddenTrigger(
    term: 'tart',
    certainty: TriggerCertainty.suspected,
    source: '11 §7.1',
  ),
  HiddenTrigger(
    term: 'tarts',
    certainty: TriggerCertainty.suspected,
    source: '11 §7.1',
  ),
];

/// Hebrew hidden sources of wheat (11 §7.1, §7.2, 12 §1.4). Shared by
/// wheat and gluten.
const List<HiddenTrigger> _wheatHiddenHe = <HiddenTrigger>[
  HiddenTrigger(
    term: 'רוטב סויה',
    certainty: TriggerCertainty.likely,
    source: '12 §1.4',
  ),
  HiddenTrigger(
    term: 'טריאקי',
    certainty: TriggerCertainty.likely,
    source: '12 §1.4',
  ),
  HiddenTrigger(
    term: 'טריקי',
    certainty: TriggerCertainty.likely,
    source: '12 §1.4',
  ),
  HiddenTrigger(
    term: 'הויסין',
    certainty: TriggerCertainty.likely,
    source: '12 §1.4',
  ),
  HiddenTrigger(
    term: 'בלילת בירה',
    certainty: TriggerCertainty.likely,
    source: '11 §7.2',
  ),
  HiddenTrigger(
    term: 'שניצל',
    certainty: TriggerCertainty.likely,
    source: '12 §1.4',
  ),
  HiddenTrigger(
    term: 'שניצלים',
    certainty: TriggerCertainty.likely,
    source: '12 §1.4',
  ),
  HiddenTrigger(
    term: 'נאגטס',
    certainty: TriggerCertainty.likely,
    source: '12 §1.4',
  ),
  HiddenTrigger(
    term: 'קטסו',
    certainty: TriggerCertainty.likely,
    source: '12 §1.4',
  ),
  HiddenTrigger(
    term: 'מילנז',
    certainty: TriggerCertainty.likely,
    source: '12 §1.4',
  ),
  HiddenTrigger(
    term: "פיש אנד צ'יפס",
    certainty: TriggerCertainty.likely,
    source: '12 §1.4',
  ),
  HiddenTrigger(
    term: "דג וצ'יפס",
    certainty: TriggerCertainty.likely,
    source: '12 §1.4',
  ),
  HiddenTrigger(
    term: 'קמח',
    certainty: TriggerCertainty.likely,
    source: '12 §1.4',
  ),
  HiddenTrigger(
    term: 'גלייז סויה',
    certainty: TriggerCertainty.likely,
    source: '12 §1.4',
  ),
  HiddenTrigger(
    term: 'פנה',
    certainty: TriggerCertainty.likely,
    source: '12 §1.4',
  ),
  HiddenTrigger(
    term: 'מקומח',
    certainty: TriggerCertainty.suspected,
    source: '11 §7.2',
  ),
  HiddenTrigger(
    term: 'מקומחים',
    certainty: TriggerCertainty.suspected,
    source: '11 §7.2',
  ),
  HiddenTrigger(
    term: 'ציר',
    certainty: TriggerCertainty.suspected,
    source: '11 §7.2',
  ),
  HiddenTrigger(
    term: 'קוביות מרק',
    certainty: TriggerCertainty.suspected,
    source: '11 §7.2',
  ),
  HiddenTrigger(
    term: 'אבקת מרק',
    certainty: TriggerCertainty.suspected,
    source: '11 §7.2',
  ),
  HiddenTrigger(
    term: 'בשמל',
    certainty: TriggerCertainty.suspected,
    source: '11 §7.2',
  ),
  HiddenTrigger(
    term: 'קציצה',
    certainty: TriggerCertainty.suspected,
    source: '12 §1.4',
  ),
  HiddenTrigger(
    term: 'קציצות',
    certainty: TriggerCertainty.suspected,
    source: '12 §1.4',
  ),
  HiddenTrigger(
    term: 'נקניק',
    certainty: TriggerCertainty.suspected,
    source: '12 §1.4',
  ),
  HiddenTrigger(
    term: 'נקניקים',
    certainty: TriggerCertainty.suspected,
    source: '12 §1.4',
  ),
  HiddenTrigger(
    term: 'נקניקיה',
    certainty: TriggerCertainty.suspected,
    source: '12 §1.4',
  ),
  HiddenTrigger(
    term: 'נקניקיות',
    certainty: TriggerCertainty.suspected,
    source: '12 §1.4',
  ),
  HiddenTrigger(
    term: 'תחליפי בשר',
    certainty: TriggerCertainty.suspected,
    source: '12 §1.4',
  ),
  HiddenTrigger(
    term: 'פריכיות',
    certainty: TriggerCertainty.suspected,
    source: '12 §1.4',
  ),
  HiddenTrigger(
    term: 'סורימי',
    certainty: TriggerCertainty.suspected,
    source: '12 §1.4',
  ),
  HiddenTrigger(
    term: 'המבורגר',
    certainty: TriggerCertainty.suspected,
    source: '11 §7.1',
  ),
  HiddenTrigger(
    term: 'בורגר',
    certainty: TriggerCertainty.suspected,
    source: '11 §7.1',
  ),
  HiddenTrigger(
    term: "צ'יזבורגר",
    certainty: TriggerCertainty.suspected,
    source: '11 §7.1',
  ),
  HiddenTrigger(
    term: 'ראפ',
    certainty: TriggerCertainty.suspected,
    source: '11 §7.1',
  ),
  HiddenTrigger(
    term: 'טורטייה',
    certainty: TriggerCertainty.suspected,
    source: '11 §7.1',
  ),
  HiddenTrigger(
    term: 'טורטיה',
    certainty: TriggerCertainty.suspected,
    source: '11 §7.1',
  ),
  HiddenTrigger(
    term: 'קיש',
    certainty: TriggerCertainty.suspected,
    source: '11 §7.1',
  ),
  HiddenTrigger(
    term: 'פאי',
    certainty: TriggerCertainty.likely,
    source: '11 §7.1',
  ),
  HiddenTrigger(
    term: 'טארט',
    certainty: TriggerCertainty.suspected,
    source: '11 §7.1',
  ),
  HiddenTrigger(
    term: 'מצופה',
    certainty: TriggerCertainty.suspected,
    source: '11 §7.1',
  ),
  HiddenTrigger(
    term: 'קריספי',
    certainty: TriggerCertainty.suspected,
    source: '11 §7.1',
  ),
  HiddenTrigger(
    term: 'סובה',
    certainty: TriggerCertainty.suspected,
    source: '11 §7.1',
  ),
];

/// English gluten cereals beyond wheat, and what is made of them
/// (11 §7.1): barley, rye, malt and beer.
const List<String> _glutenGrainsEn = <String>[
  'gluten',
  'barley',
  'rye',
  'malt',
  'malted',
  "brewer's yeast",
  'beer',
  'beers',
  'lager',
  'ale',
  'stout',
];

/// Hebrew gluten cereals beyond wheat (12 §1.4). `בירה` is compiled with
/// no permissive prefix (כבירה is "vast"), so its prefixed forms are
/// listed as their own terms; `בירות` (beers, but also Beirut) keeps the
/// prefix.
const List<String> _glutenGrainsHe = <String>[
  'גלוטן',
  'שעורה',
  'גריסי פנינה',
  'שיפון',
  'מאלט',
  'בירה',
  'הבירה',
  'בבירה',
  'ובירה',
  'לבירה',
  'מבירה',
  'בירות',
];

/// English hidden sources of gluten that are not wheat: oats (cross-
/// contact unless certified, 11 §7.2) and "wheat free", which is not
/// "gluten free" (11 §7.5).
const List<HiddenTrigger> _glutenHiddenEn = <HiddenTrigger>[
  HiddenTrigger(
    term: 'goldstar',
    certainty: TriggerCertainty.likely,
    source: '11 §7.1',
  ),
  HiddenTrigger(
    term: 'san miguel',
    certainty: TriggerCertainty.likely,
    source: '11 §7.1',
  ),
  HiddenTrigger(
    term: 'wheat free',
    certainty: TriggerCertainty.suspected,
    source: '11 §7.5',
  ),
  HiddenTrigger(
    term: 'oats',
    certainty: TriggerCertainty.suspected,
    source: '11 §7.2',
  ),
  HiddenTrigger(
    term: 'oat',
    certainty: TriggerCertainty.suspected,
    source: '11 §7.2',
  ),
  HiddenTrigger(
    term: 'oatmeal',
    certainty: TriggerCertainty.suspected,
    source: '11 §7.2',
  ),
  HiddenTrigger(
    term: 'porridge',
    certainty: TriggerCertainty.suspected,
    source: '11 §7.2',
  ),
  HiddenTrigger(
    term: 'granola',
    certainty: TriggerCertainty.suspected,
    source: '11 §7.2',
  ),
  HiddenTrigger(
    term: 'muesli',
    certainty: TriggerCertainty.suspected,
    source: '11 §7.2',
  ),
];

/// Hebrew hidden sources of gluten that are not wheat.
const List<HiddenTrigger> _glutenHiddenHe = <HiddenTrigger>[
  HiddenTrigger(
    term: 'גולדסטאר',
    certainty: TriggerCertainty.likely,
    source: '11 §7.1',
  ),
  HiddenTrigger(
    term: 'סאן מיגל',
    certainty: TriggerCertainty.likely,
    source: '11 §7.1',
  ),
  HiddenTrigger(
    term: 'ללא חיטה',
    certainty: TriggerCertainty.suspected,
    source: '11 §7.5',
  ),
  HiddenTrigger(
    term: 'נטול חיטה',
    certainty: TriggerCertainty.suspected,
    source: '11 §7.5',
  ),
  HiddenTrigger(
    term: 'בלי חיטה',
    certainty: TriggerCertainty.suspected,
    source: '11 §7.5',
  ),
  HiddenTrigger(
    term: 'שיבולת שועל',
    certainty: TriggerCertainty.suspected,
    source: '11 §7.2',
  ),
  HiddenTrigger(
    term: 'גרנולה',
    certainty: TriggerCertainty.suspected,
    source: '11 §7.2',
  ),
  HiddenTrigger(
    term: 'מוזלי',
    certainty: TriggerCertainty.suspected,
    source: '11 §7.2',
  ),
];

/// English lupin triggers (11 §14.1). Public because `legumes`
/// (vocab_plants_additives.dart) spreads them: lupin is a legume.
const List<String> lupinDirectEn = <String>[
  'lupin',
  'lupine',
  'lupins',
  'lupini',
  'tremoços',
  'altramuces',
];

/// Hebrew lupin triggers (11 §14.1, 12 §1.3); see [lupinDirectEn].
const List<String> lupinDirectHe = <String>['תורמוס', 'לופין'];

/// Gluten-free bakery, where lupin flour is a common substitute
/// (11 §14.2, §14.5).
const List<HiddenTrigger> _lupinHiddenEn = <HiddenTrigger>[
  HiddenTrigger(
    term: 'gluten free bread',
    certainty: TriggerCertainty.suspected,
    source: '11 §14.2',
  ),
  HiddenTrigger(
    term: 'gluten free pasta',
    certainty: TriggerCertainty.suspected,
    source: '11 §14.2',
  ),
  HiddenTrigger(
    term: 'gluten free pizza',
    certainty: TriggerCertainty.suspected,
    source: '11 §14.2',
  ),
  HiddenTrigger(
    term: 'gluten free bun',
    certainty: TriggerCertainty.suspected,
    source: '11 §14.2',
  ),
  HiddenTrigger(
    term: 'gluten free cake',
    certainty: TriggerCertainty.suspected,
    source: '11 §14.2',
  ),
  HiddenTrigger(
    term: 'gluten free cookies',
    certainty: TriggerCertainty.suspected,
    source: '11 §14.2',
  ),
  HiddenTrigger(
    term: 'gluten free pastry',
    certainty: TriggerCertainty.suspected,
    source: '11 §14.2',
  ),
  HiddenTrigger(
    term: 'gluten free pastries',
    certainty: TriggerCertainty.suspected,
    source: '11 §14.2',
  ),
  HiddenTrigger(
    term: 'gluten free bakery',
    certainty: TriggerCertainty.suspected,
    source: '11 §14.2',
  ),
  HiddenTrigger(
    term: 'gluten free flour',
    certainty: TriggerCertainty.suspected,
    source: '11 §14.2',
  ),
  HiddenTrigger(
    term: 'gluten free wrap',
    certainty: TriggerCertainty.suspected,
    source: '11 §14.2',
  ),
  HiddenTrigger(
    term: 'gluten free pancakes',
    certainty: TriggerCertainty.suspected,
    source: '11 §14.2',
  ),
  HiddenTrigger(
    term: 'gluten free waffles',
    certainty: TriggerCertainty.suspected,
    source: '11 §14.2',
  ),
  HiddenTrigger(
    term: 'gluten free muffins',
    certainty: TriggerCertainty.suspected,
    source: '11 §14.2',
  ),
];

/// Hebrew gluten-free bakery (11 §14.2).
const List<HiddenTrigger> _lupinHiddenHe = <HiddenTrigger>[
  HiddenTrigger(
    term: 'לחם ללא גלוטן',
    certainty: TriggerCertainty.suspected,
    source: '11 §14.2',
  ),
  HiddenTrigger(
    term: 'לחמנייה ללא גלוטן',
    certainty: TriggerCertainty.suspected,
    source: '11 §14.2',
  ),
  HiddenTrigger(
    term: 'פיתה ללא גלוטן',
    certainty: TriggerCertainty.suspected,
    source: '11 §14.2',
  ),
  HiddenTrigger(
    term: 'פסטה ללא גלוטן',
    certainty: TriggerCertainty.suspected,
    source: '11 §14.2',
  ),
  HiddenTrigger(
    term: 'פיצה ללא גלוטן',
    certainty: TriggerCertainty.suspected,
    source: '11 §14.2',
  ),
  HiddenTrigger(
    term: 'עוגה ללא גלוטן',
    certainty: TriggerCertainty.suspected,
    source: '11 §14.2',
  ),
  HiddenTrigger(
    term: 'עוגיות ללא גלוטן',
    certainty: TriggerCertainty.suspected,
    source: '11 §14.2',
  ),
  HiddenTrigger(
    term: 'מאפה ללא גלוטן',
    certainty: TriggerCertainty.suspected,
    source: '11 §14.2',
  ),
  HiddenTrigger(
    term: 'מאפים ללא גלוטן',
    certainty: TriggerCertainty.suspected,
    source: '11 §14.2',
  ),
  HiddenTrigger(
    term: 'בצק ללא גלוטן',
    certainty: TriggerCertainty.suspected,
    source: '11 §14.2',
  ),
  HiddenTrigger(
    term: 'קמח ללא גלוטן',
    certainty: TriggerCertainty.suspected,
    source: '11 §14.2',
  ),
  HiddenTrigger(
    term: 'לחם נטול גלוטן',
    certainty: TriggerCertainty.suspected,
    source: '11 §14.2',
  ),
  HiddenTrigger(
    term: 'פסטה נטולת גלוטן',
    certainty: TriggerCertainty.suspected,
    source: '11 §14.2',
  ),
  HiddenTrigger(
    term: 'פיצה נטולת גלוטן',
    certainty: TriggerCertainty.suspected,
    source: '11 §14.2',
  ),
  HiddenTrigger(
    term: 'עוגה נטולת גלוטן',
    certainty: TriggerCertainty.suspected,
    source: '11 §14.2',
  ),
  HiddenTrigger(
    term: 'מאפים נטולי גלוטן',
    certainty: TriggerCertainty.suspected,
    source: '11 §14.2',
  ),
];

/// Gluten and grains: one entry per restriction this group owns.
///
/// The grains a flour can be milled from that are not wheat, before the
/// English `flour` (ALG-04a term guards): a mill or a bakery may still
/// share it with wheat, so the hit is lowered, never dropped.
const List<String> _otherFloursEn = <String>[
  'rice',
  'corn',
  'chickpea',
  'almond',
  'coconut',
  'buckwheat',
  'tapioca',
  'potato',
];

/// [_otherFloursEn] after the Hebrew `קמח` ("קמח אורז").
const List<String> _otherFloursHe = <String>[
  'אורז',
  'תירס',
  'חומוס',
  'שקדים',
  'קוקוס',
  'כוסמת',
  'טפיוקה',
  'תפוחי אדמה',
];

/// The words before `roll` that make it another food: a sushi or rice-paper
/// roll, a lettuce or cabbage roll, a nori roll (ALG-04a). `spring` is here
/// deliberately: a spring roll is wrapped in wheat, but a rice-paper one is
/// not, so it is lowered to `suspected`, never dropped. `egg roll` is a
/// trigger of its own and stays `likely`.
const List<String> _notBreadRollsEn = <String>[
  'sushi',
  'maki',
  'hand',
  'summer',
  'fresh',
  'vietnamese',
  'rice paper',
  'spring',
  'lettuce',
  'cabbage',
  'nori',
  'california',
  'philly',
  'dragon',
  'rainbow',
  'spider',
  'salmon',
  'tuna',
  'avocado',
  'cucumber',
  'shrimp',
  'eel',
  'crab',
  'veggie',
  'vegetable',
];

/// The words before `cracker(s)` that make them another food: rice, seaweed,
/// cassava, almond or seed crackers are not wheat (ALG-04a).
const List<String> _notWheatCrackersEn = <String>[
  'rice',
  'seaweed',
  'cassava',
  'almond',
  'seed',
  'seeds',
  'flax',
];

/// The term guards of wheat and gluten: the flours that are not wheat, the
/// rolls that are not bread and the crackers that are not wheat.
const Map<String, AllergenGuards> _wheatTermGuards = <String, AllergenGuards>{
  'flour': AllergenGuards(beforeEn: _otherFloursEn),
  'קמח': AllergenGuards(afterHe: _otherFloursHe),
  'roll': AllergenGuards(beforeEn: _notBreadRollsEn),
  'rolls': AllergenGuards(beforeEn: _notBreadRollsEn),
  'cracker': AllergenGuards(beforeEn: _notWheatCrackersEn),
  'crackers': AllergenGuards(beforeEn: _notWheatCrackersEn),
};

/// The restriction-wide guards are only the negations and the gluten-free
/// family (`no`, `without`, `gluten free`, `GF`, `ללא`). A guard lowers a
/// hit to `suspected` from the slot beside its term and never cancels it
/// (ALG-04a). The flours that are not wheat ("rice flour", "קמח אורז") are
/// term guards on `flour` and `קמח` alone, so a rice beside a pita ("rice,
/// pita and salad") still leaves the pita stated.
const Map<RestrictionId, RestrictionVocabulary> glutenGrainsVocabulary =
    <RestrictionId, RestrictionVocabulary>{
      RestrictionId.wheat: RestrictionVocabulary(
        directEn: _wheatFoodsEn,
        directHe: _wheatFoodsHe,
        hiddenEn: _wheatHiddenEn,
        hiddenHe: _wheatHiddenHe,
        guards: AllergenGuards(
          beforeEn: <String>[
            'no',
            'without',
            'free of',
            'free from',
            'gluten free',
            'wheat free',
            'gf',
          ],
          afterEn: <String>['free', 'gf', 'gluten free', 'wheat free'],
          beforeHe: <String>[
            'ללא',
            'בלי',
            'נטול',
            'ללא גלוטן',
            'בלי גלוטן',
            'נטול גלוטן',
            'ללא חיטה',
            'בלי חיטה',
            'נטול חיטה',
          ],
          afterHe: <String>[
            'ללא גלוטן',
            'נטול גלוטן',
            'בלי גלוטן',
            'ללא חיטה',
            'נטול חיטה',
            'בלי חיטה',
            'gf',
          ],
        ),
        termGuards: _wheatTermGuards,
        noPrefixHe: <String>['חיטה', 'חלה', 'חלות', 'פנה'],
        sources: <String>['11 §7.1', '11 §7.3', '12 §1.4'],
      ),
      RestrictionId.gluten: RestrictionVocabulary(
        directEn: <String>[..._wheatFoodsEn, ..._glutenGrainsEn],
        directHe: <String>[..._wheatFoodsHe, ..._glutenGrainsHe],
        hiddenEn: <HiddenTrigger>[..._wheatHiddenEn, ..._glutenHiddenEn],
        hiddenHe: <HiddenTrigger>[..._wheatHiddenHe, ..._glutenHiddenHe],
        guards: AllergenGuards(
          beforeEn: <String>[
            'no',
            'without',
            'free of',
            'free from',
            'gluten free',
            'gf',
          ],
          afterEn: <String>['free', 'gf', 'gluten free'],
          beforeHe: <String>[
            'ללא',
            'בלי',
            'נטול',
            'ללא גלוטן',
            'בלי גלוטן',
            'נטול גלוטן',
          ],
          afterHe: <String>['ללא גלוטן', 'נטול גלוטן', 'בלי גלוטן', 'gf'],
        ),
        termGuards: _wheatTermGuards,
        noPrefixHe: <String>['חיטה', 'חלה', 'חלות', 'בירה', 'פנה'],
        sources: <String>['11 §7.1', '11 §7.3', '11 §7.5', '12 §1.4'],
      ),
      RestrictionId.lupin: RestrictionVocabulary(
        directEn: lupinDirectEn,
        directHe: lupinDirectHe,
        hiddenEn: _lupinHiddenEn,
        hiddenHe: _lupinHiddenHe,
        guards: AllergenGuards(
          beforeEn: <String>['no', 'without', 'free of', 'free from'],
          afterEn: <String>['free', 'lupin free'],
          beforeHe: <String>['ללא', 'בלי', 'נטול'],
        ),
        sources: <String>['11 §14.1', '11 §14.2', '12 §1.3'],
      ),
    };

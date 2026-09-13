/// Project-wide constants (architecture.md §5, §18.3).
///
/// Every number and string with meaning lives here or in an enum, with a
/// name and a note on where it came from. The keto vocabulary below is
/// the authoritative dataset from `vocabulary_spec.md` (the four D-V1..D-V4
/// product decisions that deliberately depart from README.md); where this
/// file and README.md disagree, this file wins.
library;

// ---------------------------------------------------------------------------
// App identity
// ---------------------------------------------------------------------------

/// The product name as shown in the app bar and the browser tab.
const String appName = 'KetoClub';

// ---------------------------------------------------------------------------
// Networking
// ---------------------------------------------------------------------------

/// The `User-Agent` sent with every restaurant-platform request, matching
/// README.md lines 206-214's reverse-engineered `KetoMenuIngestionService`
/// default header (a real Chrome/120 desktop UA; several platform APIs
/// reject requests with no browser-shaped UA).
const String browserUserAgent =
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
    'AppleWebKit/537.36 (KHTML, like Gecko) '
    'Chrome/120.0.0.0 Safari/537.36';

// ---------------------------------------------------------------------------
// Cache and LLM request tuning (architecture.md §6.4, §9.3, §9.4)
// ---------------------------------------------------------------------------

/// How long a cached menu is considered fresh before it is refetched
/// (architecture.md §6.4, §17.5).
const Duration menuCacheTtl = Duration(hours: 24);

/// Per-request timeout for the LLM classifier (architecture.md §9.3). A
/// slow model is not an offline device, so this maps to `timeout`, never
/// to `offline`.
const Duration llmRequestTimeout = Duration(seconds: 120);

/// `max_tokens` sent with every LLM request (architecture.md §9.3). A
/// 60-dish menu is several thousand output tokens; a truncated array is
/// an unrecoverable `badResponse`, so this is set generously and
/// explicitly rather than left to the provider's default.
const int llmMaxOutputTokens = 6000;

/// The response-time budget, in seconds, for the pre-release check that
/// runs the real system prompt against the pinned model id before every
/// release (architecture.md §9.3). Not a request timeout — a slower
/// answer here is a signal to re-pin the model, not a runtime failure.
const int llmReleaseCheckSeconds = 20;

/// The parser rejects a response naming more than this many dishes as
/// `badResponse` (architecture.md §9.4 rule 6).
const int maxAnalysedDishes = 150;

/// `why` is truncated at this many characters, never rejected for length
/// alone (architecture.md §9.4 rule 6, §9.1).
const int maxWhyLength = 300;

/// `modification` is truncated at this many characters, never rejected
/// for length alone (architecture.md §9.4 rule 6, §9.1).
const int maxModificationLength = 300;

/// The minimum word length counted when the parser checks whether an
/// LLM-returned dish name shares a word with a source dish name
/// (architecture.md §9.4 rule 3).
const int minOverlapWordLength = 3;

// ---------------------------------------------------------------------------
// LLM prompt text (architecture.md §9.1)
// ---------------------------------------------------------------------------

/// The three verdicts and their definitions, in the model-facing English
/// the system prompt sends verbatim (architecture.md §9.1) — so the model
/// and the UI legend describe the same three verdicts the same way.
/// Sourced from README.md lines 64-69 (the Traffic-Light Classification
/// table).
const String promptVerdictDefinitions = '''
orderAsIs — net carbohydrates 6g or less, a healthy fat-and-protein base, and no starchy side, sugary sauce, or flour coating: order it exactly as printed.
modifiable — the core protein, fish, egg, or salad is keto-compliant, but the dish arrives with a starchy side (fries, mash, rice, bread), a root vegetable (carrot, beet, corn), or a sugary sauce or glaze (teriyaki, honey, barbecue): order it with the stated substitution or removal.
nonKeto — the dish is built on a high-carbohydrate foundation no substitution can fix, such as pasta, pizza crust, a rice bowl, noodles, a breaded or battered protein, or a pastry or dessert base: skip it.''';

/// The keto rules the system prompt states alongside
/// [promptVerdictDefinitions] (architecture.md §9.1): net-carb threshold,
/// what makes a dish yellow, and what makes a dish red, plus the output
/// rules the parser (architecture.md §9.4) depends on.
const String promptKetoRules = '''
Net carbs of 6g or less per dish make it green (orderAsIs).
Starchy sides, root vegetables, sugary sauces and glazes, breading, and bread that only carries the dish (a bun, pita, toast) make an otherwise-compliant dish yellow (modifiable): name the exact component to remove and the exact substitute to ask for.
Pasta, pizza, rice bowls, noodles, breaded or battered proteins, and pastry make a dish red (nonKeto), even with modifications, and get no modification text.
Write "why" and "modification" in the language the menu is written in, each under 300 characters. Return only dishes present in the input, using their given id and exact printed name.''';

// ---------------------------------------------------------------------------
// Verdict explanation strings (`vocabulary_spec.md` "why strings")
// ---------------------------------------------------------------------------

/// Shown for a `DishVerdict.orderAsIs` (green) dish, English.
const String greenWhyEn =
    'Nothing starchy, sweet or breaded turned up in this dish. Order it as '
    'printed.';

/// Shown for a `DishVerdict.orderAsIs` (green) dish, Hebrew.
const String greenWhyHe =
    'לא נמצאו במנה פחמימות, סוכר או ציפוי קמח. אפשר '
    'להזמין אותה כמו שהיא.';

/// Shown for a `DishVerdict.modifiable` (yellow) dish, English.
const String yellowWhyEn =
    'The core of this dish is keto, but it arrives with a carb component. '
    'Ask for the change below.';

/// Shown for a `DishVerdict.modifiable` (yellow) dish, Hebrew.
const String yellowWhyHe =
    'בסיס המנה מתאים לקטו, אבל מוגש איתה רכיב עתיר '
    'פחמימות. בקשו את השינוי שמופיע כאן.';

/// Shown for a `DishVerdict.nonKeto` (red) dish, English. `{base}` is
/// replaced by the matched trigger's display label (see
/// [nonKetoBaseLabelsEn]) by whichever service renders this string.
const String redWhyEn = 'Built on {base}, which cannot be made keto.';

/// Shown for a `DishVerdict.nonKeto` (red) dish, Hebrew. `{base}` is
/// replaced by the matched trigger's display label (see
/// [nonKetoBaseLabelsHe]). Grammatical for every label with no gender or
/// number agreement needed: do not prefix the label with `ה`.
const String redWhyHe = 'המנה מבוססת על {base}, ואי אפשר להפוך אותה לקטוגנית.';

// ---------------------------------------------------------------------------
// Guard and suppression relation shapes (`vocabulary_spec.md`)
// ---------------------------------------------------------------------------

/// Words that cancel a trigger's match when they sit near it (D-V1 keto-
/// substitute guards): `before` looks up to two words to the left of the
/// trigger, `after` up to two words to the right. Most guards are
/// `before`-only; `spaghetti`'s is `after`-only (`spaghetti squash`).
typedef GuardWords = ({List<String> before, List<String> after});

// ---------------------------------------------------------------------------
// carbModifiers — English (58 triggers → waiter sentence)
// ---------------------------------------------------------------------------

const String _sSwapPotato =
    'Please swap the potatoes for a green salad or steamed vegetables.';
const String _sSwapMash = 'Swap the mash for leafy greens';
const String _sOmitBeetroot = 'Omit the beetroot from the dish';
const String _sBbq = 'Ask for barbecue glaze to be omitted (high in sugar)';

/// Carb-modifier triggers (waiter-script templates) in English, from
/// README's 13 verbatim, plus the false-green-gap additions, the D-V3
/// bread-carrier triggers, and the D-V4 additions (`vocabulary_spec.md`
/// "carbModifiers — English"). 58 entries.
const Map<String, String> carbModifiersEn = <String, String>{
  // README's 13, verbatim.
  'puree': 'Swap potato purée for green salad or steamed vegetables',
  'mashed potatoes': 'Swap mashed potatoes for leafy greens',
  'fries': 'Replace French fries with a fresh green salad or a fried egg',
  'chips': 'Replace chips with fresh vegetables or salad',
  'rice': 'Omit rice and request double vegetables or salad',
  'carrot': 'Ask to leave out carrots from the dish/salad',
  'carrots': 'Ask to leave out carrots from the dish/salad',
  'corn': 'Ask to leave out sweet corn',
  'beets': 'Omit beets from the dish',
  'sweet potato': 'Omit sweet potato or substitute with zucchini/broccoli',
  'teriyaki': 'Request without teriyaki sauce (contains sugar/mirin)',
  'honey': 'Ask for the dish to be prepared without honey',
  'bbq': _sBbq,

  // False-green-gap additions: verified to classify GREEN today without
  // these.
  'potato': _sSwapPotato,
  'potatoes': _sSwapPotato,
  'mash': _sSwapMash,
  'mashed potato': _sSwapMash,
  'potato mash': _sSwapMash,
  'beet': _sOmitBeetroot,
  'beetroot': _sOmitBeetroot,
  'sweet potatoes': 'Omit sweet potato or substitute with zucchini/broccoli',
  'barbecue': _sBbq,
  'barbeque': _sBbq,
  'bbqed': _sBbq,
  'maple': 'Please prepare it without the maple syrup.',
  'balsamic glaze':
      'Please leave out the balsamic glaze; it is reduced with sugar.',

  // D-V3: bread that only carries the dish is removable, so it is a
  // yellow carb modifier, not a red non-keto base.
  'bun':
      'Please serve the burger without the bun, wrapped in lettuce, and '
      'swap the fries for a green salad or a fried egg.',
  'buns':
      'Please serve the burger without the bun, wrapped in lettuce, and '
      'swap the fries for a green salad or a fried egg.',
  'burger bun':
      'Please serve the burger without the bun, wrapped in lettuce, and '
      'swap the fries for a green salad or a fried egg.',
  'sandwich': 'Please serve the filling on a plate, without the bread.',
  'sandwiches': 'Please serve the filling on a plate, without the bread.',
  'toast':
      'Please serve it without the bread, with salad or vegetables '
      'instead.',
  'toasts':
      'Please serve it without the bread, with salad or vegetables '
      'instead.',
  'bread':
      'Please leave out the bread and bring salad or vegetables '
      'instead.',
  'pita': 'Please serve it on a plate, without the pita.',
  'laffa': 'Please serve it on a plate, without the laffa.',
  'tortilla': 'Please serve the filling in a bowl, without the tortilla.',
  'wrap': 'Please serve the filling in a bowl, without the tortilla.',
  'baguette': 'Please serve the filling on a plate, without the baguette.',

  // D-V4 additions.
  'hummus':
      'Please leave out the hummus and add tahini or a green salad instead.',
  'bulgur': 'Please leave out the bulgur and add double vegetables instead.',
  'quinoa': 'Please leave out the quinoa and add leafy greens instead.',
  'lentils': 'Please leave out the lentils and add steamed vegetables instead.',
  'silan':
      'Please prepare it without the date syrup — it is almost pure '
      'sugar.',
  // Mirrors the Hebrew "דבש תמרים → דבש" suppression relation
  // (vocabulary_spec.md "triggerSuppresses"): see the English
  // triggerSuppresses entry below for why.
  'date honey':
      'Please prepare it without the date honey — it is almost '
      'pure sugar.',
  'sweet tahini': 'Please use plain tahini instead of the sweet tahini.',
  'sweet chili': 'Please leave out the sweet chili sauce; it is high in sugar.',
  'ketchup':
      'Please leave out the ketchup; mayonnaise or tahini instead is '
      'perfect.',
  'croutons': 'Please prepare the salad without croutons.',
  'cranberries': 'Please leave out the dried cranberries.',
  'dates': 'Please leave out the dates.',
  'thousand island':
      'Please bring olive oil and lemon on the side instead of the '
      'thousand island.',
  'house dressing':
      'Please bring olive oil and lemon on the side instead of the house '
      'dressing.',
  'vinaigrette':
      'Please bring olive oil and lemon on the side instead of the '
      'vinaigrette.',
  'peas': 'Please leave out the peas.',
  'crispy onion':
      'Please leave out the crispy onions — they are coated in flour.',
  'tamarind': 'Please leave out the tamarind sauce; it contains sugar.',
  'hoisin': 'Please leave out the hoisin sauce; it contains sugar.',
};

// ---------------------------------------------------------------------------
// carbModifiers — Hebrew (72 triggers → waiter sentence)
// ---------------------------------------------------------------------------

const String _sPirePotato =
    'אפשר בבקשה להחליף את הפירה בסלט ירוק או בירקות '
    'מאודים?';
const String _sMechitPotato =
    'אפשר בבקשה להחליף את המחית בסלט ירוק או '
    'בירקות מאודים?';
const String _sPireTapuachAdama =
    'אפשר בבקשה להחליף את פירה תפוחי האדמה '
    'בעלים ירוקים או בסלט?';
const String _sChipsHe = "אפשר בבקשה להחליף את הצ'יפס בסלט ירוק או בביצת עין?";
const String _sTapuchimMetuganim =
    'אפשר בבקשה להחליף את תפוחי האדמה '
    'המטוגנים בסלט ירוק או בביצת עין?';
const String _sOrez = 'אפשר בבקשה בלי האורז, ועם כפול ירקות או סלט במקום?';
const String _sGezer = 'אפשר בבקשה להכין את המנה בלי גזר?';
const String _sTiras = 'אפשר בבקשה בלי התירס?';
const String _sSelek = 'אפשר בבקשה להוציא את הסלק מהמנה?';
const String _sBatata =
    'אפשר בבקשה בלי הבטטה, או להחליף אותה בקישואים או בברוקולי?';
const String _sTeriyakiHe = 'אפשר בבקשה בלי רוטב הטריאקי? יש בו סוכר.';
const String _sDvash = 'אפשר בבקשה להכין את המנה בלי דבש?';
const String _sBarbecueHe = 'אפשר בבקשה בלי זיגוג הברביקיו? יש בו הרבה סוכר.';
const String _sTapuchAdama =
    'אפשר בבקשה להחליף את תפוחי האדמה בסלט ירוק או '
    'בירקות מאודים?';
const String _sLachmaniya =
    'אפשר בבקשה את ההמבורגר בלי לחמנייה, עטוף '
    "בחסה, ובמקום הצ'יפס סלט ירוק או ביצת עין?";
const String _sKarich = 'אפשר בבקשה את המילוי בצלחת, בלי הלחם?';
const String _sToastHe = 'אפשר בבקשה בלי הלחם, ועם סלט או ירקות במקום?';
const String _sTortiyaHe = 'אפשר בבקשה לקבל את המנה בקערה, בלי הטורטייה?';

/// Carb-modifier triggers (waiter-script templates) in Hebrew
/// (`vocabulary_spec.md` "carbModifiers — Hebrew"). 72 entries: the
/// "/"-separated variants in the spec are flattened here into one map
/// entry per variant, sharing the same sentence.
const Map<String, String> carbModifiersHe = <String, String>{
  'פירה': _sPirePotato,
  'מחית תפוחי אדמה': _sMechitPotato,
  'מחית תפו"א': _sMechitPotato,
  'פירה תפוחי אדמה': _sPireTapuachAdama,
  'פירה תפו"א': _sPireTapuachAdama,
  "צ'יפס": _sChipsHe,
  'תפוחי אדמה מטוגנים': _sTapuchimMetuganim,
  'קריספס': 'אפשר בבקשה להחליף את הקריספס בירקות טריים או בסלט?',
  'אורז': _sOrez,
  'אורז יסמין': _sOrez,
  'אורז מלא': _sOrez,
  'גזר': _sGezer,
  'גזרים': _sGezer,
  'גזר גמדי': _sGezer,
  'תירס': _sTiras,
  'גרעיני תירס': _sTiras,
  'תירס גמדי': _sTiras,
  'סלק': _sSelek,
  'סלקים': _sSelek,
  'סלק צלוי': _sSelek,
  'בטטה': _sBatata,
  'בטטות': _sBatata,
  'תפוח אדמה מתוק': _sBatata,
  'טריאקי': _sTeriyakiHe,
  'טריקי': _sTeriyakiHe,
  'דבש': _sDvash,
  'זיגוג דבש': 'אפשר בבקשה להכין את המנה בלי זיגוג הדבש?',
  'חרדל דבש': 'אפשר בבקשה בלי רוטב חרדל־דבש? אפשר שמן זית ולימון בצד במקום.',
  'ברביקיו': _sBarbecueHe,
  'בבקיו': _sBarbecueHe,
  'רוטב ברביקיו': 'אפשר בבקשה בלי רוטב הברביקיו? יש בו הרבה סוכר.',
  'תפוח אדמה': _sTapuchAdama,
  'תפוחי אדמה': _sTapuchAdama,
  'תפו"א': _sTapuchAdama,
  'תפוד': _sTapuchAdama,
  'תפודים': _sTapuchAdama,

  // D-V3 bread carriers.
  'לחמנייה': _sLachmaniya,
  'לחמניה': _sLachmaniya,
  'לחמניות': _sLachmaniya,
  'כריך': _sKarich,
  'כריכים': _sKarich,
  "סנדוויץ'": _sKarich,
  "סנדוויצ'ים": _sKarich,
  'סנדביץ': _sKarich,
  'טוסט': _sToastHe,
  'טוסטים': _sToastHe,
  'לחם': _sToastHe,
  'פיתה': 'אפשר בבקשה לקבל את זה בצלחת, בלי הפיתה?',
  'לאפה': 'אפשר בבקשה לקבל את זה בצלחת, בלי הלאפה?',
  'טורטייה': _sTortiyaHe,
  'טורטיה': _sTortiyaHe,
  'באגט': 'אפשר בבקשה את המילוי בצלחת, בלי הבאגט?',

  // D-V4 additions.
  'חומוס': 'אפשר בבקשה בלי החומוס, ועם טחינה או סלט ירוק במקום?',
  'בורגול': 'אפשר בבקשה בלי הבורגול, ועם כפול ירקות במקום?',
  'קינואה': 'אפשר בבקשה בלי הקינואה, ועם עלים ירוקים במקום?',
  'עדשים': 'אפשר בבקשה בלי העדשים, ועם ירקות מאודים במקום?',
  'סילן': 'אפשר בבקשה בלי הסילן? הוא סוכר כמעט לגמרי.',
  // Suppresses bare "דבש" — see triggerSuppresses below.
  'דבש תמרים': 'אפשר בבקשה בלי דבש התמרים? הוא סוכר כמעט לגמרי.',
  'טחינה מתוקה': 'אפשר בבקשה טחינה רגילה במקום הטחינה המתוקה?',
  "צ'ילי מתוק": "אפשר בבקשה בלי רוטב הצ'ילי המתוק? יש בו הרבה סוכר.",
  'קטשופ': 'אפשר בבקשה בלי קטשופ? אפשר מיונז או טחינה במקום.',
  'קרוטונים': 'אפשר בבקשה סלט בלי קרוטונים?',
  'צנוברים מסוכרים': 'אפשר בבקשה בלי הפיצוחים המסוכרים?',
  'חמוציות': 'אפשר בבקשה בלי החמוציות המיובשות?',
  'תמרים': 'אפשר בבקשה בלי התמרים?',
  'אלף האיים': 'אפשר בבקשה שמן זית ולימון בצד במקום רוטב אלף האיים?',
  'רוטב הבית': 'אפשר בבקשה שמן זית ולימון בצד במקום רוטב הבית?',
  'ויניגרט': 'אפשר בבקשה שמן זית ולימון בצד במקום הוויניגרט?',
  'אפונה': 'אפשר בבקשה בלי האפונה?',
  'בצל מטוגן': 'אפשר בבקשה בלי הבצל המטוגן? הוא מקומח.',
  'תמרינד': 'אפשר בבקשה בלי רוטב התמרינד? יש בו סוכר.',
  'הויסין': 'אפשר בבקשה בלי רוטב ההויסין? יש בו סוכר.',
};

// ---------------------------------------------------------------------------
// nonKetoBases — English (91 triggers)
// ---------------------------------------------------------------------------

/// Non-keto-base triggers in English: any match makes a dish red with no
/// waiter script (`vocabulary_spec.md` "nonKetoBases — English"). 91
/// entries: README's 16, minus the three D-V3 moves (`sandwich`,
/// `brioche bun`, `toast`, now [carbModifiersEn]), plus verified plural
/// and spelling variants, D-V2 breading, and D-V4 families.
///
/// Bare `brioche` is deliberately NOT here. It reads like a red pastry, but
/// on a real menu it almost always qualifies a bun ("beef burger on a brioche
/// bun"), and as a red base it overrode D-V3 and turned every such burger red
/// and hidden — the exact outcome D-V3 exists to prevent. Brioche as an actual
/// pastry is caught by the dessert cluster (`cake`, `tart`, `puff pastry`).
const List<String> nonKetoBasesEn = <String>[
  // Battered-fish dishes name no breading word, so D-V2's `battered` and
  // `breaded` triggers miss them. Without these two phrases the dish returns
  // YELLOW "replace the chips" and leaves the batter, which is an instruction
  // that cannot make it keto. `fish & chips` normalises to `fish chips`.
  'fish and chips',
  'fish chips',
  // README's 16, minus sandwich / brioche bun / toast (D-V3).
  'pasta', 'spaghetti', 'penne', 'fettuccine', 'gnocchi',
  'pizza', 'calzone', 'risotto', 'noodle', 'noodles', 'ramen',
  'pancake', 'waffle',

  // Plurals and spelling variants, verified GREEN today without them.
  'pastas', 'pizzas', 'calzones', 'pancakes', 'waffles',

  // D-V2: breading cannot be made keto by removing a side.
  'breaded', 'battered', 'crumbed', 'panko', 'tempura', 'beer batter',
  'schnitzel', 'nuggets', 'crispy coating', 'breadcrumbs', 'katsu',
  'milanese',

  // D-V4 families.
  'lasagna', 'lasagne', 'ravioli', 'tortellini', 'cannelloni',
  'tagliatelle', 'linguine', 'rigatoni', 'orzo', 'macaroni',
  'mac and cheese',
  'udon', 'soba', 'pad thai', 'lo mein', 'vermicelli',
  'couscous', 'mujadara', 'tabbouleh', 'freekeh', 'moghrabieh', 'polenta',
  'grits',
  'burekas', 'malawach', 'jachnun', 'sambusak', 'lahmajun', 'focaccia',
  'phyllo', 'filo',
  'puff pastry', 'empanada', 'dumpling', 'gyoza', 'bao', 'arancini',
  'croquette',
  'crepe', 'blintz', 'cake', 'cookie', 'brownie', 'tart', 'pie', 'baklava',
  'knafeh', 'malabi',
  'souffle', 'ice cream', 'milkshake',
  'challah', 'bagel', 'croissant', 'doughnut', 'donut', 'latkes',
  'burrito', 'quesadilla', 'taco shell',

  // See the doc comment above: required by D-V3's decision record and by
  // nonKetoBaseLabelsEn, missing from the spec's own enumeration.
];

// ---------------------------------------------------------------------------
// nonKetoBases — Hebrew (87 triggers)
// ---------------------------------------------------------------------------

/// Non-keto-base triggers in Hebrew (`vocabulary_spec.md` "nonKetoBases —
/// Hebrew"). 87 entries. `penne`'s transliteration (`פנה`) is
/// deliberately absent: it is an ordinary Hebrew word ("turned"), so a
/// bare trigger would redden unrelated dishes; Israeli menus print
/// *Penne* in Latin and `פסטה` catches the rest.
const List<String> nonKetoBasesHe = <String>[
  'פסטה', 'פסטות', 'ספגטי', 'ספאגטי', "פטוצ'יני", 'פטוצייני', 'ניוקי',
  'גנוקי',
  'פיצה', 'פיצות', 'קלצונה', 'קלזונה', 'ריזוטו', 'רזוטו',
  'נודלס', 'נודל', 'אטריות', 'אטריה', 'ראמן', 'רמן', 'בריוש',

  // D-V2 breading.
  'שניצל', 'שניצלים', 'פאנקו', 'טמפורה', 'בציפוי פריך', 'פירורי לחם',
  'בלילה', 'נאגטס', 'קריספי', 'בבלילת בירה', 'מטוגן בפירורים',

  // D-V4 families.
  'בורקס', 'בורקסים', 'מלווח', 'מלאווח', "ג'חנון", 'סמבוסק', "לחמג'ון",
  'פוקצה', "פוקצ'ה",
  'קובה', 'סיגרים', 'פילו', 'בצק עלים',
  'קוסקוס', 'פתיתים', "מג'דרה", 'מגדרה', 'טאבולה', 'פריקה', 'מוגרבייה',
  'לזניה', 'רביולי', 'טורטליני', 'קנלוני', 'טליאטלה', 'לינגוויני',
  'ריגטוני', 'אורזו',
  'אודון', 'סובה', 'פאד תאי', 'לו מיין', 'ורמישלי',
  'קרפ', 'קראפ', "בלינצ'ס", 'מלבי', 'קנאפה', 'בקלאווה', 'סופלה', 'בראוניז',
  'עוגה', 'עוגיות', 'טארט', 'קרם ברולה', 'חלבה', 'גלידה', 'מילקשייק',
  'חלה', 'בייגל', 'ראפ', 'קרואסון', 'דונאט', 'לביבות', 'ניוקי בטטה',
];

// ---------------------------------------------------------------------------
// nonKetoBaseLabels — for rendering {base} in redWhy
// ---------------------------------------------------------------------------

/// Display labels for [nonKetoBasesEn] triggers, for rendering `{base}`
/// in [redWhyEn]. Every trigger not listed here defaults to itself
/// (`vocabulary_spec.md`: "English: identity, except..."); looking a
/// trigger up should fall back to the trigger's own (already
/// correctly-spelled, non-normalised) text, e.g.
/// `nonKetoBaseLabelsEn[trigger] ?? trigger`.
const Map<String, String> nonKetoBaseLabelsEn = <String, String>{
  'fish and chips': 'battered fish',
  'fish chips': 'battered fish',
  'noodle': 'noodles',
};

/// Display labels for [nonKetoBasesHe] triggers, for rendering `{base}`
/// in [redWhyHe]. Every trigger not listed here defaults to itself, same
/// fallback rule as [nonKetoBaseLabelsEn].
///
/// `לחמניות → לחמנייה` is *not* included here even though the spec's
/// "e.g." label list names it: `לחמניות` is a [carbModifiersHe] trigger
/// (a bun, D-V3, which is yellow, never red), so it is never the
/// `baseLabel` of a red `RuleMatch` and a label for it here would be
/// dead code.
const Map<String, String> nonKetoBaseLabelsHe = <String, String>{
  'ספאגטי': 'ספגטי',
  'רזוטו': 'ריזוטו',
  'רמן': 'ראמן',
  'פיצות': 'פיצה',
};

// ---------------------------------------------------------------------------
// Guards (D-V1)
// ---------------------------------------------------------------------------

/// Keto-substitute guards, English (`vocabulary_spec.md` "Guards
/// (D-V1)"). `corn` is deliberately absent: `baby corn` is a genuine
/// trap, not a rescue, so `corn` is never guarded.
const Map<String, GuardWords> ketoQualifierGuardsEn = <String, GuardWords>{
  'rice': (
    before: [
      'cauliflower',
      'broccoli',
      'konjac',
      'shirataki',
      'keto',
      'cabbage',
    ],
    after: [],
  ),
  'noodles': (
    before: [
      'zucchini',
      'courgette',
      'cauliflower',
      'konjac',
      'shirataki',
      'palmini',
      'keto',
      'cabbage',
      'kelp',
    ],
    after: [],
  ),
  'noodle': (
    before: ['zucchini', 'courgette', 'konjac', 'shirataki', 'palmini', 'keto'],
    after: [],
  ),
  'spaghetti': (before: [], after: ['squash']),
  'pizza': (
    before: ['cauliflower', 'keto', 'almond', 'fathead', 'low carb', 'lowcarb'],
    after: [],
  ),
  'risotto': (before: ['cauliflower', 'konjac', 'keto'], after: []),
  'chips': (
    before: [
      'kale',
      'parmesan',
      'cheese',
      'zucchini',
      'courgette',
      'cabbage',
      'coconut',
      'keto',
    ],
    after: [],
  ),
  'toast': (before: ['keto', 'cloud', 'almond'], after: []),
  'pancake': (before: ['keto', 'almond', 'coconut'], after: []),
  'waffle': (before: ['keto', 'chaffle', 'almond'], after: []),
  'bread': (before: ['keto', 'cloud', 'almond'], after: []),
};

/// Builds a Hebrew guard's [GuardWords] from one word list, applied on
/// **both** sides. Unlike the English table, no Hebrew guard is
/// `before`-only or `after`-only: Hebrew adjectives conventionally
/// follow the noun they qualify ("פיצה כרובית", pizza cauliflower-ish,
/// not "כרובית פיצה"), the mirror image of the English word order these
/// guards were modelled on, so checking one side only would leave that
/// ordinary phrasing unguarded — which the required guard test (`פיצה
/// כרובית` must not come back red) rules out.
GuardWords _heGuard(List<String> words) => (before: words, after: words);

/// See [ketoQualifierGuardsHe] — shared by `אורז`.
final GuardWords _heCauliflowerLikeGuard = _heGuard(const [
  'כרובית',
  'קונגאק',
  'שיראטקי',
  'קטו',
  'כרוב',
]);

/// See [ketoQualifierGuardsHe] — shared by `נודלס` and `אטריות`.
final GuardWords _heNoodleGuard = _heGuard(const [
  'קישואים',
  'קישוא',
  'כרובית',
  'קונגאק',
  'שיראטקי',
  'קטו',
]);

/// See [ketoQualifierGuardsHe] — `פיצה`.
final GuardWords _hePizzaGuard = _heGuard(const [
  'כרובית',
  'קטו',
  'שקדים',
  'דלת פחמימות',
]);

/// See [ketoQualifierGuardsHe] — `ריזוטו`.
final GuardWords _heRisottoGuard = _heGuard(const ['כרובית', 'קטו']);

/// See [ketoQualifierGuardsHe] — `צ'יפס`.
final GuardWords _heChipsGuard = _heGuard(const [
  'קישואים',
  'כרוב',
  'פרמזן',
  'גבינה',
  'קייל',
  'קטו',
]);

/// See [ketoQualifierGuardsHe] — shared by `לחמנייה` and `לחם`.
final GuardWords _heBreadGuard = _heGuard(const [
  'קטו',
  'ענן',
  'שקדים',
  'דלת פחמימות',
]);

/// See [ketoQualifierGuardsHe] — `טוסט`.
final GuardWords _heToastGuard = _heGuard(const ['קטו', 'ענן', 'שקדים']);

/// Keto-substitute guards, Hebrew (`vocabulary_spec.md` "Guards
/// (D-V1)"). See [_heGuard] for why every entry is bidirectional here,
/// unlike [ketoQualifierGuardsEn].
final Map<String, GuardWords> ketoQualifierGuardsHe = <String, GuardWords>{
  'אורז': _heCauliflowerLikeGuard,
  'נודלס': _heNoodleGuard,
  'אטריות': _heNoodleGuard,
  'פיצה': _hePizzaGuard,
  'ריזוטו': _heRisottoGuard,
  "צ'יפס": _heChipsGuard,
  'לחמנייה': _heBreadGuard,
  'לחם': _heBreadGuard,
  'טוסט': _heToastGuard,
};

// ---------------------------------------------------------------------------
// triggerSuppresses
// ---------------------------------------------------------------------------

/// When the key trigger matches, drop these triggers' sentences too — the
/// more specific phrase wins, so `sweet potato` does not also emit the
/// bare `potato` sentence (`vocabulary_spec.md` "triggerSuppresses").
///
/// `mashed potato` and `potato mash` (variant spellings of the same
/// `mash`-cluster trigger the spec lists as one line) and `בטטות` /
/// `תפוח אדמה מתוק` (variants of the `בטטה` cluster) each get their own
/// entry here, mirroring how the spec itself gives `sweet potato` and
/// `sweet potatoes` separate entries rather than one.
///
/// `date honey → honey` is not in the spec's English table, but its
/// Hebrew mirror (`דבש תמרים → דבש`) is: leaving it out would have an
/// English "date honey" dish emit both "no date honey" and "no honey"
/// for the same word, which the Hebrew side explicitly avoids.
const Map<String, List<String>> triggerSuppresses = <String, List<String>>{
  'sweet potato': ['potato', 'potatoes'],
  'sweet potatoes': ['potato', 'potatoes'],
  'mashed potatoes': ['potato', 'potatoes', 'puree', 'mash'],
  'mash': ['potato', 'potatoes'],
  // "potato puree" matches both `puree` and `potato`; the puree sentence
  // already names the swap, so the generic potato one is noise.
  'puree': ['potato', 'potatoes'],
  'mashed potato': ['potato', 'potatoes'],
  'potato mash': ['potato', 'potatoes'],
  'date honey': ['honey'],
  'בטטה': ['תפוח אדמה', 'תפוחי אדמה'],
  'בטטות': ['תפוח אדמה', 'תפוחי אדמה'],
  'תפוח אדמה מתוק': ['תפוח אדמה', 'תפוחי אדמה'],
  'פירה תפוחי אדמה': ['פירה', 'תפוח אדמה', 'תפוחי אדמה'],
  'פירה תפו"א': ['פירה', 'תפוח אדמה', 'תפוחי אדמה'],
  "צ'יפס": ['תפוח אדמה', 'תפוחי אדמה'],
  'דבש תמרים': ['דבש'],
};

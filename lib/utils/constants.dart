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

/// The web-client version sent as both `client-version` and
/// `clientversionnumber` on Wolt's discovery endpoints
/// (`phase2_discovery_research.md` §2.2). Values seen in 2026 run from
/// `1.16.75` to `1.16.125`; Wolt answers an outdated one with HTTP 430 or
/// a 410, which the venue search reports as `platformChanged`. Pinned in
/// one place so bumping it is a one-line change; the backend's
/// `WOLT_CLIENT_VERSION` setting is its counterpart for the proxy.
const String woltClientVersion = '1.16.125';

/// The value of the `w-wolt-session-id` header on Wolt's discovery
/// endpoints (`phase2_discovery_research.md` §2.2): what wolt.com itself
/// sends for a visitor who declined analytics.
const String woltSessionIdNoConsent = 'no-analytics-consent';

/// The longest venue-search query sent, in characters. The backend's
/// search proxy rejects anything longer (`phase2_discovery_research.md`
/// §3), so a longer query is cut rather than failing the whole search.
const int venueSearchMaxQueryLength = 80;

/// How long the Discovery search field waits after the last keystroke
/// before searching by name (`phase2_discovery_research.md` §6), so a
/// typed word is one search rather than one per letter.
const Duration venueSearchDebounce = Duration(milliseconds: 400);

/// The lowest keto score the Discovery screen's *Keto 8+* chip keeps
/// (issue #40, D13). Compared against `utils/keto_score.dart`'s score,
/// inclusive.
const double ketoEightPlusThreshold = 8;

/// How many menus the Discovery screen's explicit "Estimate this list"
/// action fetches at once (issue #42, D13). The action runs only when the
/// user taps it, never on load or scroll; this bound keeps even that one
/// request from arriving at the platform as a burst.
const int venueEstimateConcurrency = 3;

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

/// The parser rejects a response naming more than this many dishes as
/// `badResponse` (architecture.md §9.4 rule 6).
const int maxAnalysedDishes = 150;

/// `why` is truncated at this many characters, never rejected for length
/// alone (architecture.md §9.4 rule 6, §9.1).
const int maxWhyLength = 300;

/// A `modification` longer than this demotes its yellow dish to
/// unclassified rather than being truncated: a cut-off waiter instruction
/// is worse than none (architecture.md §9.4 rule 6, §9.1).
const int maxModificationLength = 300;

/// The minimum word length counted when the parser checks whether an
/// LLM-returned dish name shares a word with a source dish name
/// (architecture.md §9.4 rule 3).
const int minOverlapWordLength = 3;

// ---------------------------------------------------------------------------
// LLM prompt text (architecture.md §9.1)
// ---------------------------------------------------------------------------

/// The net-carb limit, in grams, a dish must not exceed to be green
/// (`DishVerdict.orderAsIs`) when the user has not chosen one (issue #57).
/// README.md lines 64-69's traffic-light table sets it at 6 g.
const int defaultNetCarbLimitGrams = 6;

/// The lowest net-carb limit the Settings stepper offers (issue #57). A
/// stored value below it is clamped up to it on decode.
const int minNetCarbLimitGrams = 2;

/// The highest net-carb limit the Settings stepper offers (issue #57). A
/// stored value above it is clamped down to it on decode.
const int maxNetCarbLimitGrams = 25;

/// The placeholder [promptVerdictDefinitionsTemplate] and
/// [promptKetoRulesTemplate] carry where the net-carb limit goes, replaced
/// by [promptVerdictDefinitionsFor] and [promptKetoRulesFor].
const String netCarbLimitPlaceholder = '{limit}';

/// The three verdicts and their definitions, in the model-facing English
/// the system prompt sends verbatim (architecture.md §9.1) — so the model
/// and the UI legend describe the same three verdicts the same way.
/// Sourced from README.md lines 64-69 (the Traffic-Light Classification
/// table).
///
/// A template: the green definition's net-carb figure is
/// [netCarbLimitPlaceholder], filled by [promptVerdictDefinitionsFor] with
/// the user's limit (issue #57), so the prompt and the legend share one
/// text rather than forking it per limit. One line per verdict, in
/// `DishVerdict` order; the menu screen's legend splits on that.
const String promptVerdictDefinitionsTemplate = '''
orderAsIs — net carbohydrates {limit}g or less, a healthy fat-and-protein base, and no starchy side, sugary sauce, or flour coating: order it exactly as printed.
modifiable — the core protein, fish, egg, or salad is keto-compliant, but the dish arrives with a starchy side (fries, mash, rice, bread), a root vegetable (carrot, beet, corn), or a sugary sauce or glaze (teriyaki, honey, barbecue): order it with the stated substitution or removal.
nonKeto — the dish is built on a high-carbohydrate foundation no substitution can fix, such as pasta, pizza crust, a rice bowl, noodles, a breaded or battered protein, or a pastry or dessert base: skip it.''';

/// The keto rules the system prompt states alongside the verdict
/// definitions (architecture.md §9.1): net-carb threshold, what makes a
/// dish yellow, and what makes a dish red, plus the output rules the
/// parser (architecture.md §9.4) depends on.
///
/// A template, like [promptVerdictDefinitionsTemplate]: the threshold is
/// [netCarbLimitPlaceholder], filled by [promptKetoRulesFor].
const String promptKetoRulesTemplate = '''
Net carbs of {limit}g or less per dish make it green (orderAsIs).
Starchy sides, root vegetables, sugary sauces and glazes, breading, and bread that only carries the dish (a bun, pita, toast) make an otherwise-compliant dish yellow (modifiable): name the exact component to remove and the exact substitute to ask for.
Pasta, pizza, rice bowls, noodles, breaded or battered proteins, and pastry make a dish red (nonKeto), even with modifications, and get no modification text.
Write "why" and "modification" in the language the menu is written in, each under 300 characters. Return only dishes present in the input, using their given id and exact printed name.''';

/// [promptVerdictDefinitionsTemplate] with [netCarbLimitGrams] in place of
/// [netCarbLimitPlaceholder] — the text both the system prompt and the
/// menu screen's legend show (issue #57).
String promptVerdictDefinitionsFor(int netCarbLimitGrams) =>
    promptVerdictDefinitionsTemplate.replaceAll(
      netCarbLimitPlaceholder,
      '$netCarbLimitGrams',
    );

/// [promptKetoRulesTemplate] with [netCarbLimitGrams] in place of
/// [netCarbLimitPlaceholder] (issue #57).
String promptKetoRulesFor(int netCarbLimitGrams) => promptKetoRulesTemplate
    .replaceAll(netCarbLimitPlaceholder, '$netCarbLimitGrams');

/// [grams] clamped to [minNetCarbLimitGrams]..[maxNetCarbLimitGrams], the
/// range the Settings stepper offers (issue #57).
int clampNetCarbLimitGrams(int grams) =>
    grams.clamp(minNetCarbLimitGrams, maxNetCarbLimitGrams);

// ---------------------------------------------------------------------------
// Dietary rule toggles — prompt fragments (issue #56, architecture.md §9.1)
// ---------------------------------------------------------------------------

/// The dietary constraint the "Strict seed-oil free" toggle appends to the
/// system prompt (issue #56), as one line under the prompt's dietary
/// constraints section.
///
/// Model-facing English, like every other prompt text here: the prompt
/// already tells the model to write `why` and `modification` in the
/// menu's language, so this instruction is bilingual-agnostic. It is also
/// the value recorded in `ClassificationOptions.dietaryConstraints` and in
/// a cached analysis's options snapshot, so editing it re-analyses every
/// menu cached under the old wording — which is the point: a changed
/// instruction may change a verdict.
const String seedOilFreePromptFragment =
    'Strict seed-oil free: the user avoids industrial seed oils (canola, '
    'rapeseed, soybean, sunflower, corn, cottonseed and generic vegetable '
    'oil). A dish that is fried, deep-fried or cooked in one of them is '
    'modifiable, with a modification asking for it to be cooked in olive '
    'oil, butter or tallow instead, unless it is already nonKeto.';

/// The dietary constraint the "Dairy-free keto" toggle appends to the
/// system prompt (issue #56). See [seedOilFreePromptFragment] for why it
/// is English and why editing it re-analyses cached menus.
const String dairyFreePromptFragment =
    'Dairy-free keto: the user eats no dairy. A dish containing cheese, '
    'cream, butter, milk or yogurt is modifiable, with a modification '
    'asking for it without the dairy component, unless it is already '
    'nonKeto.';

/// The dietary constraint the "Carnivore only" toggle appends to the
/// system prompt (issue #56). See [seedOilFreePromptFragment] for why it
/// is English and why editing it re-analyses cached menus.
const String carnivoreOnlyPromptFragment =
    'Carnivore only: the user eats only animal foods (meat, fish, seafood, '
    'eggs and animal fats). A dish that includes any vegetable, salad, '
    'fruit, legume, herb garnish or other plant is modifiable, with a '
    'modification asking for only the meat, fish or eggs, with no plants, '
    'unless it is already nonKeto.';

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
// Shareable menu card text (issue #54)
// ---------------------------------------------------------------------------

/// Heading for the "order as-is" (green) group in `MenuShareText`'s
/// output, English. Bilingual and Dart-literal like the waiter templates
/// above, and for the same documented reason (this file's own doc
/// comment): the shared text follows the **menu's** language, detected
/// from the dish text, not the reader's UI locale, so it cannot be an ARB
/// key resolved against the current `Locale`.
const String shareGreenHeadingEn = 'Order as-is:';

/// Heading for the "order as-is" (green) group in `MenuShareText`'s
/// output, Hebrew. See [shareGreenHeadingEn].
const String shareGreenHeadingHe = 'להזמין כמו שהוא:';

/// Heading for the "order with changes" (yellow) group in
/// `MenuShareText`'s output, English. See [shareGreenHeadingEn].
const String shareYellowHeadingEn = 'Order with changes:';

/// Heading for the "order with changes" (yellow) group in
/// `MenuShareText`'s output, Hebrew. See [shareGreenHeadingEn].
const String shareYellowHeadingHe = 'להזמין עם שינויים:';

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
// carbModifiers — Hebrew (75 triggers → waiter sentence)
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
/// (`vocabulary_spec.md` "carbModifiers — Hebrew"). 75 entries: the
/// "/"-separated variants in the spec are flattened here into one map
/// entry per variant, sharing the same sentence. Includes three #12
/// audit additions (agent 1D): `מייפל` and `זיגוג בלסמי`, which had no
/// Hebrew counterpart at all, and `ראפ`, moved here from
/// [nonKetoBasesHe] to match its English counterpart `wrap` (D-V3).
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

  // #12 audit additions (agent 1D): `maple` and `balsamic glaze` had no
  // Hebrew counterpart at all, the exact silent-vocabulary-gap failure
  // mode CLAUDE.md warns about.
  'מייפל': 'אפשר בבקשה בלי סירופ המייפל?',
  'זיגוג בלסמי': 'אפשר בבקשה בלי זיגוג הבלסמי? הוא מצומצם עם סוכר.',

  // #12 audit fix (agent 1D): `ראפ` ("wrap") was in [nonKetoBasesHe]
  // (red, unsalvageable) while its English counterpart `wrap` is a
  // [carbModifiersEn] trigger (yellow, D-V3 — a wrap's tortilla merely
  // carries the filling and is removable, same as `tortilla`/`טורטייה`
  // above). Moved here to match D-V3 and the English vocabulary.
  'ראפ': 'אפשר בבקשה לקבל את המילוי בקערה, בלי הראפ?',
};

// ---------------------------------------------------------------------------
// nonKetoBases — English (92 triggers)
// ---------------------------------------------------------------------------

/// Non-keto-base triggers in English: any match makes a dish red with no
/// waiter script (`vocabulary_spec.md` "nonKetoBases — English"). 92
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
// nonKetoBases — Hebrew (107 triggers)
// ---------------------------------------------------------------------------

/// Non-keto-base triggers in Hebrew (`vocabulary_spec.md` "nonKetoBases —
/// Hebrew"). 107 entries, including 20 #12 audit additions (agent 1D)
/// for English triggers that had no Hebrew counterpart at all —
/// `fish and chips`/`fish chips`, `pancake(s)`, `waffle(s)`, `katsu`,
/// `milanese`, `macaroni`, `mac and cheese`, `polenta`, `grits`,
/// `empanada`, `gyoza`, `bao`, `arancini`, `croquette`, `pie`,
/// `burrito`, `quesadilla`, `taco shell` — the exact silent-vocabulary
/// gap CLAUDE.md warns about. `penne`'s transliteration (`פנה`) is
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
  'חלה', 'בייגל', 'קרואסון', 'דונאט', 'לביבות', 'ניוקי בטטה',

  // #12 audit additions (agent 1D): these English triggers had no Hebrew
  // counterpart at all — the exact silent-vocabulary-gap failure mode
  // CLAUDE.md warns about (English tests pass while the Hebrew
  // vocabulary is silently dead). `ראפ` ("wrap") used to be here too;
  // it moved to [carbModifiersHe] — see that map's doc comment.
  "פיש אנד צ'יפס", "דג וצ'יפס", // fish and chips / fish chips
  'פנקייק', 'פנקייקים', // pancake / pancakes
  'וופל', 'וופלים', // waffle / waffles
  'קטסו', // katsu
  'מילנז', // milanese
  'מקרוני', // macaroni
  "מק אנד צ'יז", // mac and cheese
  'פולנטה', // polenta
  'גריטס', // grits
  'אמפנדה', // empanada
  'גיוזה', // gyoza
  'באו', // bao
  "ארנצ'יני", // arancini
  'קרוקט', // croquette
  'פאי', // pie
  'בוריטו', // burrito
  'קסדיה', // quesadilla
  'קליפת טאקו', // taco shell
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
  // #12 audit addition (agent 1D), mirroring [nonKetoBaseLabelsEn]'s
  // `fish and chips`/`fish chips` → `battered fish`: names the batter,
  // not the chips.
  "פיש אנד צ'יפס": 'דג מצופה',
  "דג וצ'יפס": 'דג מצופה',
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

// ---------------------------------------------------------------------------
// Dietary rule toggles — rules-engine vocabulary (issue #56)
// ---------------------------------------------------------------------------
//
// Each toggle in Settings ("Your keto rules") adds one rule to the
// heuristic engine, active only while that toggle is on. A rule never
// turns a red dish into anything else; it turns a green dish yellow, and
// adds its sentence to a yellow one's script, whenever one of its
// triggers survives its guards. The triggers compile exactly like the
// carb vocabulary above (`classification_rules.dart`): a Latin word
// boundary for English, the unicode lookaround for Hebrew — never `\b`,
// which is ASCII-only in Dart.

/// Seed-oil triggers, English (issue #56): frying, and the industrial
/// seed oils by name. `fried` alone covers `deep fried`, `pan fried` and
/// `stir fried` once the normaliser has turned their hyphens into spaces.
/// Bare `corn`, `soy` and `sunflower` are deliberately absent: corn is
/// already a carb trigger, soy sauce is not an oil, and sunflower seeds
/// are not a cooking fat.
const List<String> seedOilTriggersEn = <String>[
  'fried',
  'deep fried',
  'canola',
  'rapeseed',
  'soybean oil',
  'soy oil',
  'sunflower oil',
  'vegetable oil',
  'corn oil',
  'cottonseed',
  'seed oil',
  'seed oils',
];

/// Seed-oil triggers, Hebrew (issue #56), mirroring [seedOilTriggersEn]:
/// the four forms of "fried", "frying" (`טיגון`, which also covers
/// `בטיגון עמוק`), and the oils by name. Bare `סויה` is absent for the
/// same reason as English `soy`: `רוטב סויה` is soy sauce.
const List<String> seedOilTriggersHe = <String>[
  'מטוגן',
  'מטוגנת',
  'מטוגנים',
  'מטוגנות',
  'טיגון',
  'קנולה',
  'שמן סויה',
  'שמן חמניות',
  'שמן צמחי',
  'שמן תירס',
  'שמן זרעים',
];

/// Dairy triggers, English (issue #56): the words the issue names —
/// cheese, cream, butter, yogurt — plus milk and the cheeses a menu names
/// without saying "cheese".
const List<String> dairyTriggersEn = <String>[
  'cheese',
  'cheeses',
  'cheesy',
  'cream',
  'creamy',
  'butter',
  'buttery',
  'buttermilk',
  'yogurt',
  'yoghurt',
  'milk',
  'feta',
  'parmesan',
  'mozzarella',
  'burrata',
  'cheddar',
  'ricotta',
  'labneh',
  'halloumi',
  'mascarpone',
  'gorgonzola',
  'brie',
  'camembert',
  'gouda',
  'creme fraiche',
  'kefir',
  'tzatziki',
  'paneer',
];

/// Dairy triggers, Hebrew (issue #56), mirroring [dairyTriggersEn]. The
/// construct forms `גבינת` and `חמאת` are their own keys ("goat cheese"
/// is `גבינת עיזים`, "garlic butter" `חמאת שום`), because the strict
/// right-hand boundary rightly refuses to match `גבינה` inside them.
/// `לבנה` (labneh) is absent: it is also the feminine "white", as in
/// `בירה לבנה`; `לאבנה` is the unambiguous spelling.
const List<String> dairyTriggersHe = <String>[
  'גבינה',
  'גבינות',
  'גבינת',
  'שמנת',
  'חמאה',
  'חמאת',
  'יוגורט',
  'חלב',
  'פטה',
  'פרמזן',
  'מוצרלה',
  'בוראטה',
  "צ'דר",
  'ריקוטה',
  'לאבנה',
  'חלומי',
  'מסקרפונה',
  'גורגונזולה',
  'קממבר',
  'גאודה',
  'רוקפור',
  'צפתית',
  'בולגרית',
  "קוטג'",
  'קרם',
  'קרמי',
  'קרמית',
  'קפיר',
  'צזיקי',
];

/// Plant words that make a dairy word something else: `coconut cream`,
/// `almond milk`, `peanut butter`, `vegan cheese`, `balsamic cream`
/// (issue #56). Same shape and window as [ketoQualifierGuardsEn].
const Map<String, GuardWords> dairyGuardsEn = <String, GuardWords>{
  'cream': (
    before: ['coconut', 'cashew', 'oat', 'soy', 'vegan', 'balsamic'],
    after: [],
  ),
  'milk': (
    before: ['coconut', 'almond', 'oat', 'soy', 'cashew', 'vegan'],
    after: [],
  ),
  'butter': (
    before: ['peanut', 'almond', 'cashew', 'nut', 'cocoa', 'vegan'],
    after: [],
  ),
  'cheese': (before: ['vegan', 'cashew'], after: []),
  'yogurt': (before: ['coconut', 'soy', 'almond', 'vegan'], after: []),
  'yoghurt': (before: ['coconut', 'soy', 'almond', 'vegan'], after: []),
};

/// See [dairyGuardsHe] — `חלב`, `יוגורט`, `שמנת`, `קרם`.
final GuardWords _hePlantMilkGuard = _heGuard(const [
  'קוקוס',
  'שקדים',
  'סויה',
  'שיבולת',
  'קשיו',
  'טבעוני',
  'טבעונית',
  'בלסמי',
  'בלסמית',
]);

/// See [dairyGuardsHe] — `חמאה`, `חמאת`.
final GuardWords _heNutButterGuard = _heGuard(const [
  'בוטנים',
  'שקדים',
  'קשיו',
  'קקאו',
  'טבעונית',
]);

/// See [dairyGuardsHe] — `גבינה`, `גבינות`, `גבינת`.
final GuardWords _heVeganCheeseGuard = _heGuard(const [
  'טבעונית',
  'טבעוניות',
  'קשיו',
]);

/// The Hebrew mirror of [dairyGuardsEn] (issue #56): `חלב קוקוס`,
/// `חמאת בוטנים`, `גבינה טבעונית`, `קרם בלסמי`. Bidirectional for the
/// reason [_heGuard] gives: a Hebrew modifier follows its noun.
final Map<String, GuardWords> dairyGuardsHe = <String, GuardWords>{
  'חלב': _hePlantMilkGuard,
  'יוגורט': _hePlantMilkGuard,
  'שמנת': _hePlantMilkGuard,
  'קרם': _hePlantMilkGuard,
  'חמאה': _heNutButterGuard,
  'חמאת': _heNutButterGuard,
  'גבינה': _heVeganCheeseGuard,
  'גבינות': _heVeganCheeseGuard,
  'גבינת': _heVeganCheeseGuard,
};

/// Plant triggers, English (issue #56): any vegetable, salad, fruit,
/// legume, herb or other plant a carnivore does not eat. Spices are
/// deliberately absent (`pepper` alone is almost always black pepper),
/// and so is `olive oil`: fats are the prompt's call, not the rules'.
const List<String> plantTriggersEn = <String>[
  'salad',
  'salads',
  'slaw',
  'coleslaw',
  'vegetable',
  'vegetables',
  'veggies',
  'greens',
  'lettuce',
  'tomato',
  'tomatoes',
  'cucumber',
  'cucumbers',
  'onion',
  'onions',
  'peppers',
  'bell pepper',
  'zucchini',
  'courgette',
  'eggplant',
  'aubergine',
  'mushroom',
  'mushrooms',
  'spinach',
  'broccoli',
  'cauliflower',
  'kale',
  'arugula',
  'cabbage',
  'avocado',
  'olives',
  'asparagus',
  'celery',
  'radish',
  'artichoke',
  'pickles',
  'beans',
  'chickpeas',
  'tahini',
  'herbs',
  'fruit',
];

/// Plant triggers, Hebrew (issue #56), mirroring [plantTriggersEn].
/// `פלפל` alone is absent for the same reason as English `pepper`
/// (`פלפל שחור` is black pepper); `פלפלים` and `פלפל קלוי` are kept.
const List<String> plantTriggersHe = <String>[
  'סלט',
  'סלטים',
  'ירק',
  'ירקות',
  'עלים',
  'חסה',
  'עגבניה',
  'עגבנייה',
  'עגבניות',
  'מלפפון',
  'מלפפונים',
  'בצל',
  'בצלים',
  'פלפלים',
  'פלפל קלוי',
  'קישוא',
  'קישואים',
  'חציל',
  'חצילים',
  'פטריה',
  'פטרייה',
  'פטריות',
  'תרד',
  'ברוקולי',
  'כרובית',
  'קייל',
  'ארוגולה',
  'רוקט',
  'כרוב',
  'אבוקדו',
  'זיתים',
  'אספרגוס',
  'סלרי',
  'צנון',
  'צנוניות',
  'ארטישוק',
  'חמוצים',
  'שעועית',
  'גרגרי חומוס',
  'טחינה',
  'עשבי תיבול',
  'פירות',
];

// ---------------------------------------------------------------------------
// Dietary rule toggles — waiter sentences and why strings (issue #56)
// ---------------------------------------------------------------------------
//
// Chosen by the dish's own language, like every other sentence the
// heuristic reads aloud (architecture.md §6.3, §12), which is why they
// live here and not in ARB.

/// The waiter sentence the seed-oil rule adds, English (issue #56).
const String seedOilFreeModificationEn =
    'Please cook it in olive oil, butter or tallow, with no canola, '
    'soybean, sunflower or other seed oil.';

/// The waiter sentence the seed-oil rule adds, Hebrew (issue #56).
const String seedOilFreeModificationHe =
    'אפשר בבקשה להכין את המנה בשמן זית, בחמאה או בשומן בקר, '
    'בלי שמן קנולה, סויה, חמניות או כל שמן זרעים אחר?';

/// The waiter sentence the dairy-free rule adds, English (issue #56).
const String dairyFreeModificationEn =
    'Please make it with no dairy: no cheese, cream, butter, milk or '
    'yogurt.';

/// The waiter sentence the dairy-free rule adds, Hebrew (issue #56).
const String dairyFreeModificationHe =
    'אפשר בבקשה להכין את המנה בלי מוצרי חלב: בלי גבינה, '
    'שמנת, חמאה, חלב או יוגורט?';

/// The waiter sentence the carnivore rule adds, English (issue #56).
const String carnivoreOnlyModificationEn =
    'Please serve only the meat, fish or eggs, with no vegetables, salad '
    'or other plants on the plate.';

/// The waiter sentence the carnivore rule adds, Hebrew (issue #56).
const String carnivoreOnlyModificationHe =
    'אפשר בבקשה להגיש רק את הבשר, הדג או הביצים, בלי ירקות, '
    'סלט או צמחים אחרים בצלחת?';

/// Shown for a dish a dietary rule alone made yellow, English (issue
/// #56). [yellowWhyEn] speaks of a carb component, which would be untrue
/// of a dairy or plant ingredient; a dish with a carb component as well
/// keeps [yellowWhyEn].
const String dietaryRuleWhyEn =
    'This dish is keto, but it breaks one of the rules you turned on in '
    'Settings. Ask for the change below.';

/// Shown for a dish a dietary rule alone made yellow, Hebrew (issue #56).
const String dietaryRuleWhyHe =
    'המנה מתאימה לקטו, אבל לא לאחד הכללים שהפעלתם '
    'בהגדרות. בקשו את השינוי שמופיע כאן.';

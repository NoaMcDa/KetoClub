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

/// How many menus the Discovery screen's quick score fetches at once
/// (issue #42, D13, D21) — the automatic run that starts when a result
/// list arrives and the explicit "Quick score the rest" tap alike. The
/// bound keeps either from arriving at the platform as a burst.
const int venueEstimateConcurrency = 3;

/// How many visible venues the Discovery screen scores on its own with the
/// rule engine when a result list arrives, or a chip change puts new
/// venues in view (architecture.md D21). Venues past this cap wait for the
/// explicit "Quick score the rest" tap. Never on scroll. `0` turns the
/// automatic run off, which the tests of the explicit action use.
const int venueAutoEstimateLimit = 12;

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
///
/// A sanity bound against a runaway reply, not a menu size: it was 150,
/// which real Israeli Wolt venues exceed (a supermarket lists many
/// hundreds), so a correct reply to a large menu was thrown away as
/// malformed (issue #188). The prompt side's own bound is the backend's
/// `user_prompt` limit; this only has to sit above any menu that fits it.
const int maxAnalysedDishes = 1000;

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
Drinks: cola, sprite, juice, lemonade, beer, sweet wine, and liqueur are red; iced coffee, latte, cappuccino, and tonic are yellow (ask for black coffee, unsweetened almond milk, or soda water instead); zero-sugar or diet versions of soda or beer, plain water, black coffee, espresso, tea, dry wine, and spirits are green.
Write "why" and "modification" in the language the menu is written in, each under 300 characters. Return only dishes present in the input, using their given id and exact printed name.
Hidden carbs: breading crumbs, sweet marinades, house dressings, thickeners and glazes often contain sugar, honey, flour or cornstarch even when the dish name reads clean. For each dish, list any such suspected or confirmed hidden carb under "hidden_carbs" as {source, certainty ("suspected" or "likely"), waiter_question} — the question to ask the waiter, in the menu's language, under 300 characters. Use an empty array when none apply.''';

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

/// Heading for the "with changes" (yellow) group in
/// `MenuShareText`'s output, English. See [shareGreenHeadingEn].
const String shareYellowHeadingEn = 'With changes:';

/// Heading for the "with changes" (yellow) group in
/// `MenuShareText`'s output, Hebrew. See [shareGreenHeadingEn].
const String shareYellowHeadingHe = 'עם שינויים:';

// ---------------------------------------------------------------------------
// Guard and suppression relation shapes (`vocabulary_spec.md`)
// ---------------------------------------------------------------------------

/// Words that cancel a trigger's match when they sit near it (D-V1 keto-
/// substitute guards): `before` looks up to two words to the left of the
/// trigger, `after` up to two words to the right. Most guards are
/// `before`-only; `spaghetti`'s is `after`-only (`spaghetti squash`).
typedef GuardWords = ({List<String> before, List<String> after});

// ---------------------------------------------------------------------------
// carbModifiers — English (62 triggers → waiter sentence)
// ---------------------------------------------------------------------------

const String _sSwapPotato =
    'Please swap the potatoes for a green salad or steamed vegetables.';
const String _sSwapMash = 'Swap the mash for leafy greens';
const String _sOmitBeetroot = 'Omit the beetroot from the dish';
const String _sBbq = 'Ask for barbecue glaze to be omitted (high in sugar)';

/// Carb-modifier triggers (waiter-script templates) in English, from
/// README's 13 verbatim, plus the false-green-gap additions, the D-V3
/// bread-carrier triggers, and the D-V4 additions (`vocabulary_spec.md`
/// "carbModifiers — English"). 62 entries.
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
  // Issue #190: a bare "Burger" classified green because only `bun` was
  // a trigger and menus rarely print the word. A burger arrives on a bun
  // unless it says otherwise, so the burger words carry the bun sentence.
  'burger':
      'Please serve the burger without the bun, wrapped in lettuce, and '
      'swap the fries for a green salad or a fried egg.',
  'burgers':
      'Please serve the burger without the bun, wrapped in lettuce, and '
      'swap the fries for a green salad or a fried egg.',
  'hamburger':
      'Please serve the burger without the bun, wrapped in lettuce, and '
      'swap the fries for a green salad or a fried egg.',
  'cheeseburger':
      'Please serve the burger without the bun, wrapped in lettuce, and '
      'swap the fries for a green salad or a fried egg.',
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

  // Drink triggers — yellow with a swap script (#216). Latte/cappuccino:
  // the dairy rule (dairyTriggersEn `milk`/`cream`) fires separately when
  // dairy-free is on, so the swap sentence here names non-dairy options only.
  // Tonic water: the drink is high in sugar; ask for plain soda water.
  // Syrup: any flavoured syrup in a drink or dessert — ask to skip it.
  'latte':
      'Please make it with black coffee or unsweetened almond milk, no '
      'added sugar.',
  'iced latte':
      'Please make it with black coffee or unsweetened almond milk, '
      'no added sugar.',
  'cappuccino':
      'Please make it with black coffee or unsweetened almond milk, '
      'no added sugar.',
  'iced coffee':
      'Please make it without sugar or flavoured syrup; just '
      'espresso and ice.',
  'frappe':
      'Please skip the sugar and any flavoured syrup; just espresso, '
      'ice, and water or unsweetened almond milk.',
  'tonic':
      'Please substitute soda water for the tonic; tonic is high in '
      'sugar.',
  'tonic water':
      'Please substitute soda water for the tonic; tonic is high '
      'in sugar.',
  'syrup': 'Please leave out the flavoured syrup.',
  'flavoured syrup': 'Please leave out the flavoured syrup.',
};

// ---------------------------------------------------------------------------
// carbModifiers — Hebrew (80 triggers → waiter sentence)
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
/// (`vocabulary_spec.md` "carbModifiers — Hebrew"). 80 entries: the
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

  // D-V3 bread carriers. `לחמניית`/`לחמנית` are the construct forms
  // ("לחמניית מחמצת", a sourdough bun): the trigger pattern is strict on
  // the right, so `לחמניה` never matches inside them and each needs its
  // own key, the way `גבינת` and `חמאת` do in the dairy list (issue #190).
  'לחמנייה': _sLachmaniya,
  'לחמניה': _sLachmaniya,
  'לחמניות': _sLachmaniya,
  'לחמניית': _sLachmaniya,
  'לחמנית': _sLachmaniya,
  // Issue #190, mirroring `burger` above: a bare "המבורגר" was green.
  // `צ'יזבורגר` needs its own key — a letter precedes `בורגר` inside it,
  // so the strict-left pattern never finds the shorter trigger there.
  'המבורגר': _sLachmaniya,
  'בורגר': _sLachmaniya,
  "צ'יזבורגר": _sLachmaniya,
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

  // Drink triggers — yellow with a swap script (#216). `הפוך` ("hafuch",
  // Israeli upside-down latte) is registered without a permissive prefix
  // (see classification_rules.dart `_noPrefixHebrewTriggers`) so the
  // grammatical particle ב/ה ("בהפוך") or ל ("להפוך" — "to flip") does
  // not false-yellow an unrelated phrase.
  'הפוך':
      'אפשר בבקשה קפה הפוך עם חלב שקדים ללא סוכר, בלי '
      'תוספת סירופ?',
  'הפוך קר':
      'אפשר בבקשה קפה הפוך קר עם חלב שקדים ללא סוכר, בלי '
      'תוספת סירופ?',
  'לאטה':
      'אפשר בבקשה להכין את הלאטה עם חלב שקדים ללא סוכר, בלי '
      'תוספת סירופ?',
  "קפוצ'ינו": "אפשר בבקשה להכין את הקפוצ'ינו עם חלב שקדים ללא סוכר?",
  'קפה קר': 'אפשר בבקשה קפה קר בלי סוכר ובלי סירופ?',
  'סירופ': 'אפשר בבקשה בלי הסירופ?',
  'טוניק': 'אפשר בבקשה לשים סודה במקום הטוניק? הטוניק עתיר סוכר.',
};

/// The drink entries of [nonKetoBasesEn] — red (#216): sugary drinks that
/// cannot be made keto. Spread into [nonKetoBasesEn] at the position they
/// have always had, and reused on their own by `utils/dish_kind.dart` to
/// tell a drink named in a food category from a dish (D21). Guards in
/// [ketoQualifierGuardsEn] rescue zero/diet variants. `beer batter` is a
/// breading trigger (D-V2), so a bare `beer` here is safe — the longer
/// trigger takes priority when both match the same text. `juice` is the
/// generic form; `orange juice` and `apple juice` are included for
/// display-label precision. `smoothie` lives here only (the milkshake
/// cluster above has `milkshake`, not `smoothie`).
const List<String> nonKetoDrinkBasesEn = <String>[
  'cola',
  'coke',
  'pepsi',
  'sprite',
  'fanta',
  'lemonade',
  'juice',
  'orange juice',
  'apple juice',
  'beer',
  'lager',
  'stout',
  'ale',
  'liqueur',
  'smoothie',
  'sweet wine',
  'moscato',
  'port wine',
];

// ---------------------------------------------------------------------------
// nonKetoBases — English (100 triggers)
// ---------------------------------------------------------------------------

/// Non-keto-base triggers in English: any match makes a dish red with no
/// waiter script (`vocabulary_spec.md` "nonKetoBases — English"). 100
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

  // Issue #190: the pastry counter. A cinnamon danish classified green
  // on a real Aroma menu because none of these was a trigger. `danish`
  // is guarded against `danish blue`/`danish cheese` (see
  // [ketoQualifierGuardsEn]); `pastry` also covers `pastry cream` and
  // `pastry base`, both of which are red anyway.
  'danish', 'pastry', 'pastries', 'rugelach', 'muffin', 'muffins',
  'scone', 'scones',

  // Drink bases — red (#216): see [nonKetoDrinkBasesEn].
  ...nonKetoDrinkBasesEn,

  // See the doc comment above: required by D-V3's decision record and by
  // nonKetoBaseLabelsEn, missing from the spec's own enumeration.
];

/// The drink entries of [nonKetoBasesHe] — red (#216); the Hebrew
/// [nonKetoDrinkBasesEn], spread into [nonKetoBasesHe] at the position
/// they have always had and reused by `utils/dish_kind.dart` (D21).
/// Guards in [ketoQualifierGuardsHe] rescue zero/diet variants. `בירה`
/// catches `בירה שחורה` too (both red). `מיץ` is a bare trigger with the
/// compound forms added for label precision; if it ever false-reds a
/// proper name ("מיצי"), drop it and keep only the compounds.
const List<String> nonKetoDrinkBasesHe = <String>[
  'קולה', // cola
  'קוקה קולה', // Coca-Cola (compound first — suppresses bare `קולה` match)
  'ספרייט', // sprite
  'פאנטה', // fanta
  'פריגת', // Prigat (Israeli juice brand)
  'מיץ', // juice (bare; see note above)
  'מיץ תפוזים', // orange juice
  'מיץ ענבים', // grape juice
  'לימונדה', // lemonade
  'בירה', // beer
  'בירה שחורה', // stout / dark beer
  'שיכר', // alcoholic malt drink
  'ליקר', // liqueur
  'סמוטי', // smoothie
  'יין מתוק', // sweet wine
];

// ---------------------------------------------------------------------------
// nonKetoBases — Hebrew (116 triggers)
// ---------------------------------------------------------------------------

/// Non-keto-base triggers in Hebrew (`vocabulary_spec.md` "nonKetoBases —
/// Hebrew"). 116 entries, including 20 #12 audit additions (agent 1D)
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
  // Issue #190: the pastry counter, found green on a real Aroma menu
  // (דניש קינמון, שמרים גבינה). `שמרים` here is the pastry (a yeast bun),
  // the only sense it has on a menu; `מאפה`/`מאפים` is the generic
  // pastry word Israeli bakeries name every counter item with.
  'דניש', // danish
  // Compiled with no permissive prefix (classification_rules.dart): the
  // prefixed form would match inside `משמרים` ("preservatives"), as in
  // "ללא חומרים משמרים" on a bread's description.
  'שמרים', // yeast pastry
  'מאפה', 'מאפים', // pastry / pastries
  'רוגלך', // rugelach
  'עוגיה', // cookie (singular; עוגיות is above)
  'מאפין', 'מאפינס', // muffin / muffins
  'סקון', // scone
  // Drink bases — red (#216): see [nonKetoDrinkBasesHe].
  ...nonKetoDrinkBasesHe,
];

// ---------------------------------------------------------------------------
// Dish kinds (architecture.md D21)
// ---------------------------------------------------------------------------
//
// The keto score and every verdict count cover food only: a drink, a sauce
// or add-on, a non-edible line (cutlery, a deposit, delivery) or a notice
// entry is still classified and listed, but never counted. The kind is
// read by `utils/dish_kind.dart`, from the category heading first and the
// dish name second, and is computed, never stored. Entries are written in
// their natural spelling and normalised at compile time, like every other
// list here. Hebrew headings are matched without the permissive prefix:
// a heading is not a sentence, and `ורטבים` in "תוספות ורטבים" (sides and
// sauces) must not turn a sides category into extras.

/// Category headings that hold drinks, English.
const List<String> drinkCategoryWordsEn = <String>[
  'drinks',
  'drink',
  'beverages',
  'beverage',
  'soft drinks',
  'hot drinks',
  'cold drinks',
  'beer',
  'beers',
  'wine',
  'wines',
  'cocktails',
  'alcohol',
  'bar',
  'coffee',
  'coffees',
  'tea',
  'shakes',
  'smoothies',
  'juices',
];

/// Category headings that hold drinks, Hebrew.
const List<String> drinkCategoryWordsHe = <String>[
  'שתייה',
  'שתיה',
  'שתייה קלה',
  'שתייה חמה',
  'שתייה קרה',
  'משקאות',
  'משקה',
  'בירות',
  'בירה',
  'יינות',
  'יין',
  'אלכוהול',
  'קוקטיילים',
  'קפה',
  'תה',
  'שייקים',
  'מיצים',
  'בר',
];

/// Category headings that hold sauces, add-ons and non-edible lines,
/// English. Not `sides`: a side of fries or salad is food, and a mixed
/// "Sauces & Sides" heading stays food through [foodCategoryWordsEn].
const List<String> extraCategoryWordsEn = <String>[
  'sauces',
  'sauce',
  'dips',
  'dip',
  'add-ons',
  'add ons',
  'extras',
  'toppings',
  'cutlery',
  'utensils',
  'deposit',
  'delivery',
  'gift card',
  'gift cards',
  'packaging',
];

/// [extraCategoryWordsEn] in Hebrew. **Not `תוספות`**: on an Israeli menu
/// it means sides (fries, salad, rice) — food — far more often than
/// add-ons; the test suite pins its absence. `סכום` is `סכו"ם` once the
/// normaliser has dropped the gershayim.
const List<String> extraCategoryWordsHe = <String>[
  'רטבים',
  'רוטב',
  'מטבלים',
  'סכום',
  'פיקדון',
  'משלוח',
  'דמי משלוח',
  'שובר',
  'שוברים',
  'גיפט קארד',
  'אריזה',
];

/// Headings that name food, English. When one of these sits beside a
/// drink or extras word ("Sauces & Sides", "Coffee & Pastries", "Beers &
/// Burgers") the heading decides nothing and each dish is read by its
/// own name instead: the croissant stays food, the latte reads as a
/// drink.
const List<String> foodCategoryWordsEn = <String>[
  'sides',
  'side dishes',
  'salads',
  'pastries',
  'pastry',
  'bakery',
  'breakfast',
  'brunch',
  'desserts',
  'dessert',
  'mains',
  'burgers',
  'sandwiches',
  'specials',
  'snacks',
];

/// [foodCategoryWordsEn] in Hebrew: "קפה ומאפה" is the common case.
const List<String> foodCategoryWordsHe = <String>[
  'תוספות',
  'סלטים',
  'מאפים',
  'מאפה',
  'קינוחים',
  'קינוח',
  'ארוחת בוקר',
  'בראנץ',
  'עיקריות',
  'המבורגרים',
  'סנדוויצים',
  'כריכים',
  'ספיישלים',
  'נשנושים',
];

/// Headings (and, at a price of zero, dish names) that are a notice to
/// the customer rather than something to order, English.
const List<String> noticeCategoryWordsEn = <String>[
  'dear customers',
  'notice',
  'announcement',
  'please note',
  'coming soon',
  'important',
];

/// [noticeCategoryWordsEn] in Hebrew.
const List<String> noticeCategoryWordsHe = <String>[
  'לקוחות יקרים',
  'הודעה',
  'שימו לב',
  'בקרוב',
  'חשוב',
];

/// The drink keys of [carbModifiersEn] — yellow drinks with a swap script
/// (#216) — as a list `utils/dish_kind.dart` can read. Every entry must
/// be a key of [carbModifiersEn]; a test pins it. `syrup` is left out:
/// it is a dessert word as often as a drink one.
const List<String> yellowDrinkTriggersEn = <String>[
  'latte',
  'iced latte',
  'cappuccino',
  'iced coffee',
  'frappe',
  'tonic',
  'tonic water',
];

/// [yellowDrinkTriggersEn] for [carbModifiersHe].
const List<String> yellowDrinkTriggersHe = <String>[
  'הפוך',
  'הפוך קר',
  'לאטה',
  "קפוצ'ינו",
  'קפה קר',
  'טוניק',
];

/// Drinks the rule engine has no trigger for because they are keto as
/// they are — water, black coffee, tea, dry wine, spirits — named so a
/// drink in a food category can still be told from a dish (D21).
const List<String> plainDrinkWordsEn = <String>[
  'water',
  'mineral water',
  'soda',
  'soda water',
  'sparkling water',
  'coffee',
  'espresso',
  'americano',
  'macchiato',
  'tea',
  'iced tea',
  'diet coke',
  'coke zero',
  'cocktail',
  'vodka',
  'whisky',
  'whiskey',
  'gin',
  'rum',
  'arak',
  'red wine',
  'white wine',
  'wine',
  'prosecco',
  'champagne',
  'milkshake',
];

/// [plainDrinkWordsEn] in Hebrew.
const List<String> plainDrinkWordsHe = <String>[
  'מים',
  'מים מינרלים',
  'סודה',
  'קפה',
  'אספרסו',
  'אמריקנו',
  'מקיאטו',
  'תה',
  'תה קר',
  'קוקטייל',
  'וודקה',
  'ויסקי',
  'גין',
  'רום',
  'ערק',
  'יין אדום',
  'יין לבן',
  'יין',
  'פרוסקו',
  'שמפניה',
  'מילקשייק',
  'קולה זירו',
];

/// Every word that marks a dish *name* as a drink, English: the red
/// drink bases, the yellow drink triggers and the plain drinks together.
const List<String> drinkNameTriggersEn = <String>[
  ...nonKetoDrinkBasesEn,
  ...yellowDrinkTriggersEn,
  ...plainDrinkWordsEn,
];

/// [drinkNameTriggersEn] in Hebrew.
const List<String> drinkNameTriggersHe = <String>[
  ...nonKetoDrinkBasesHe,
  ...yellowDrinkTriggersHe,
  ...plainDrinkWordsHe,
];

/// Words that mean a drink word in a dish name is an ingredient, not the
/// dish, English: "beer-battered fish", "wine-braised beef", "coffee-rubbed
/// steak" are food. Any one of them in the name keeps the dish food.
const List<String> drinkNameGuardWordsEn = <String>[
  'batter',
  'battered',
  'braised',
  'rubbed',
  'smoked',
  'glaze',
  'glazed',
  'sauce',
  'marinated',
  'marinade',
  'infused',
  'reduction',
];

/// [drinkNameGuardWordsEn] in Hebrew: "עוף ברוטב יין" is food.
const List<String> drinkNameGuardWordsHe = <String>[
  'בלילה',
  'בלילת',
  'ברוטב',
  'רוטב',
  'צלוי',
  'מעושן',
  'בציפוי',
  'זיגוג',
  'מרינדה',
  'מושרה',
];

// ---------------------------------------------------------------------------
// Carb-only dishes (issue #191)
// ---------------------------------------------------------------------------

/// Words that may sit beside a carb-modifier trigger in a dish **name**
/// without making it a different dish, English (issue #191): "Portion of
/// fries", "Plain pita", "Sourdough bun", "Large bag of chips". A name
/// made only of trigger words and these is the carb itself, not a dish
/// that arrives with it, so D-V3's "serve it without the bun" makes no
/// sense and the dish is red. Compared after normalisation.
const List<String> carbOnlyQualifiersEn = <String>[
  'a',
  'an',
  'of',
  'the',
  'and',
  'with',
  'portion',
  'side',
  'bag',
  'tray',
  'basket',
  'bowl',
  'extra',
  'plain',
  'regular',
  'large',
  'small',
  'big',
  'mini',
  'whole',
  'half',
  'fresh',
  'homemade',
  'home',
  'made',
  'house',
  'sourdough',
  'gluten',
  'free',
  'white',
  'brown',
  'wholemeal',
  'wholewheat',
  'crispy',
  'hot',
  'french',
  'steamed',
  'jasmine',
  'basmati',
  'curly',
  'thick',
  'thin',
  'cut',
  'seasoned',
  'salted',
  'baked',
  'roasted',
  'boiled',
  'fried',
  'style',
  'classic',
  'original',
];

/// The carb-modifier triggers the carb-only rule (issue #191) may fire on:
/// the starches and the breads — things that *are* the carb when nothing
/// else is on the plate. Every other modifier (a sauce, a root vegetable,
/// a dressing) is left out on purpose: "Carrots" or "Honey" as a dish name
/// is odd, but calling it "built on carrots, which cannot be made keto" is
/// wrong. The bread-*carried* dishes (burger, sandwich, wrap, toast) are
/// left out for the opposite reason: their filling exists even when the
/// name does not spell it out, and D-V3's yellow is the right answer.
/// Every entry must be a key of [carbModifiersEn] or [carbModifiersHe]; a
/// test asserts it.
const Set<String> carbOnlyEligibleTriggers = <String>{
  // Starches.
  'fries', 'chips', 'potato', 'potatoes', 'puree', 'mash', 'mashed potato',
  'mashed potatoes', 'potato mash', 'sweet potato', 'sweet potatoes',
  'rice', 'bulgur', 'quinoa', 'hummus',
  // Breads.
  'bread', 'pita', 'laffa', 'bun', 'buns', 'burger bun', 'baguette',
  'tortilla',
  // Hebrew starches.
  'פירה', 'מחית תפוחי אדמה', 'מחית תפו"א', 'פירה תפוחי אדמה', 'פירה תפו"א',
  "צ'יפס", 'תפוחי אדמה מטוגנים', 'קריספס', 'אורז', 'אורז יסמין',
  'אורז מלא', 'בטטה', 'בטטות', 'תפוח אדמה מתוק', 'תפוח אדמה',
  'תפוחי אדמה', 'תפו"א', 'תפוד', 'תפודים', 'בורגול', 'קינואה', 'חומוס',
  // Hebrew breads.
  'לחם', 'פיתה', 'לאפה', 'לחמנייה', 'לחמניה', 'לחמניות', 'לחמניית',
  'לחמנית', 'באגט', 'טורטייה', 'טורטיה',
};

/// Display labels for a carb-only red's `{base}` (issue #191), for the
/// triggers whose dictionary key is not a form that reads well on its own
/// — a construct form ("לחמניית" needs a following word) or a shorthand.
/// Every other trigger is its own label.
const Map<String, String> carbOnlyBaseLabels = <String, String>{
  'לחמניית': 'לחמנייה',
  'לחמנית': 'לחמנייה',
  'תפו"א': 'תפוחי אדמה',
  'תפוד': 'תפוח אדמה',
  'תפודים': 'תפוחי אדמה',
  'מחית תפו"א': 'מחית תפוחי אדמה',
  'פירה תפו"א': 'פירה תפוחי אדמה',
  'buns': 'bun',
  'burger bun': 'bun',
};

/// Protein and filling words, English, that mark a bread-named dish as
/// filled (issue #191): "Laffa" described as "shawarma, hummus, salad" is
/// a D-V3 yellow, not the carb itself. Read together with the plant and
/// dairy vocabularies (issue #56), which already name the salad half of
/// a filling. Compared after normalisation.
const List<String> fillingProteinTriggersEn = <String>[
  'chicken',
  'beef',
  'lamb',
  'steak',
  'meat',
  'meatballs',
  'shawarma',
  'kebab',
  'kebabs',
  'falafel',
  'sabich',
  'egg',
  'eggs',
  'omelette',
  'omelet',
  'tuna',
  'fish',
  'salmon',
  'turkey',
  'sausage',
  'pastrami',
  'bacon',
  'liver',
  'schnitzel',
  'burger',
  'patty',
];

/// Hebrew mirror of [fillingProteinTriggersEn] (issue #191).
const List<String> fillingProteinTriggersHe = <String>[
  'עוף',
  'בקר',
  'טלה',
  'סטייק',
  'בשר',
  'קציצה',
  'קציצות',
  'שווארמה',
  'שוארמה',
  'שווארמת',
  'קבב',
  'פלאפל',
  'סביח',
  'ביצה',
  'ביצים',
  'חביתה',
  'טונה',
  'דג',
  'דגים',
  'סלמון',
  'הודו',
  'נקניק',
  'נקניקיה',
  'פסטרמה',
  'בייקון',
  'כבד',
  'שניצל',
  'המבורגר',
  'קציצת',
];

/// The waiter sentence for a non-keto base that appears only among a
/// dish's options — a "choice of side" that offers pasta beside a salad
/// (issue #192). The dish itself is fine, so it is yellow, not red, and
/// the ask is to pick the other option. `{base}` is the base's label.
const String optionBaseModificationEn =
    'Among the options, skip the {base} and choose a salad or vegetables '
    'instead.';

/// Hebrew mirror of [optionBaseModificationEn] (issue #192).
const String optionBaseModificationHe =
    'מבין האפשרויות, בלי {base} — בחרו סלט או ירקות במקום.';

/// Hebrew mirror of [carbOnlyQualifiersEn] (issue #191): "פיתה רגילה",
/// "לחמניה ללא גלוטן", "מגש צ'יפס", "שקית צ'יפס", "לחמניית מחמצת". A
/// leftover word is looked up with a leading ה or ו stripped as well, so
/// "לחם הבית" and "הפיתה הרגילה" qualify through `בית` and `רגילה`.
const List<String> carbOnlyQualifiersHe = <String>[
  'מנת',
  'מנה',
  'מגש',
  'שקית',
  'סלסלת',
  'סלסלה',
  'קערת',
  'תוספת',
  'אקסטרה',
  'רגיל',
  'רגילה',
  'גדול',
  'גדולה',
  'קטן',
  'קטנה',
  'מיני',
  'ללא',
  'בלי',
  'גלוטן',
  'מחמצת',
  'מלא',
  'מלאה',
  'לבן',
  'לבנה',
  'טרי',
  'טריה',
  'טרייה',
  'בית',
  'ביתי',
  'ביתית',
  'חצי',
  'שלם',
  'שלמה',
  'חם',
  'חמה',
  'פריך',
  'פריכה',
  'עם',
  'מתובל',
  'מתובלים',
  'אפוי',
  'אפויים',
  'אפויות',
  'צלוי',
  'צלויים',
  'מבושל',
  'קלוי',
  'קלאסי',
  'קלאסית',
  'מטוגן',
  'מטוגנים',
  'מטוגנות',
  'דק',
  'עבה',
];

/// First words that mark an option value as a *removal* rather than an
/// ingredient, English (issue #192): "No onions", "Without the bun". A
/// value beginning with one names something the dish can be ordered
/// without, so the rule engine must not read it as something the dish
/// arrives with. Compared against the normalised value's first word.
const List<String> optionRemovalWordsEn = <String>['no', 'without', 'skip'];

/// Hebrew mirror of [optionRemovalWordsEn] (issue #192): "ללא חסה",
/// "בלי אלף האיים".
const List<String> optionRemovalWordsHe = <String>['ללא', 'בלי'];

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
  // `danish blue` is a cheese and `danish meatballs` a cuisine; `danish
  // cheese` stays red — it is how דניש גבינה, a cheese pastry, is printed.
  'danish': (before: [], after: ['blue', 'meatballs', 'rye', 'style']),
  // An egg muffin or a keto muffin is a breakfast, not a pastry.
  'muffin': (before: ['egg', 'keto', 'almond', 'coconut'], after: []),
  'muffins': (before: ['egg', 'keto', 'almond', 'coconut'], after: []),
  // A lettuce-wrapped or keto burger already has no bun (issue #190).
  'burger': (before: _bunlessBurgerWords, after: []),
  'burgers': (before: _bunlessBurgerWords, after: []),
  'hamburger': (before: _bunlessBurgerWords, after: []),
  'cheeseburger': (before: _bunlessBurgerWords, after: []),

  // Drink guards (#216): zero, diet, and sugar-free rescue cola/sprite/
  // beer/tonic so "Coca-Cola Zero" and "Diet Beer" are not marked red.
  // `after`-only: the qualifier follows the drink name in English ("Cola
  // Zero", "Sprite Zero") more often than it precedes it.
  'cola': (before: _sugarFreeWords, after: _sugarFreeWords),
  'coke': (before: _sugarFreeWords, after: _sugarFreeWords),
  'pepsi': (before: _sugarFreeWords, after: _sugarFreeWords),
  'sprite': (before: _sugarFreeWords, after: _sugarFreeWords),
  'fanta': (before: _sugarFreeWords, after: _sugarFreeWords),
  'beer': (before: _sugarFreeWords, after: _sugarFreeWords),
  'lager': (before: _sugarFreeWords, after: _sugarFreeWords),
  'ale': (before: _sugarFreeWords, after: _sugarFreeWords),
  'tonic': (before: _sugarFreeWords, after: _sugarFreeWords),
  'tonic water': (before: _sugarFreeWords, after: _sugarFreeWords),
  'juice': (before: _sugarFreeWords, after: _sugarFreeWords),
  'lemonade': (before: _sugarFreeWords, after: _sugarFreeWords),
};

/// Words before a burger word that mean it already comes without a bun.
const List<String> _bunlessBurgerWords = <String>[
  'lettuce',
  'keto',
  'bunless',
  'naked',
];

/// Guard words that rescue a sugary drink base (#216): zero, diet, and
/// explicit "no sugar" / "sugar free" labels — "Coca-Cola Zero",
/// "Diet Sprite", "sugar-free tonic". Checked on **both** sides so
/// "Zero Cola" and "Cola Zero" are both rescued.
const List<String> _sugarFreeWords = <String>[
  'zero',
  'diet',
  'sugar-free',
  'sugar free',
  'no sugar',
  'zero sugar',
  'unsweetened',
  'light',
];

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

/// See [ketoQualifierGuardsHe] — the burger words (issue #190): wrapped
/// in lettuce, or keto, and it already has no bun.
final GuardWords _heBurgerGuard = _heGuard(const ['חסה', 'בחסה', 'קטו']);

/// See [ketoQualifierGuardsHe] — `שמרים`: nutritional yeast is a keto
/// seasoning, not a pastry.
final GuardWords _heYeastGuard = _heGuard(const ['תזונתיים', 'תזונתי']);

/// Guard words that rescue a sugary Hebrew drink base (#216): זירו,
/// דיאט, and explicit "no sugar" labels. Bidirectional per [_heGuard]
/// so "קוקה קולה זירו" and "זירו קוקה קולה" are both rescued.
final GuardWords _heDrinkGuard = _heGuard(const [
  'זירו',
  'דיאט',
  'ללא סוכר',
  'ללא סוכרים',
]);

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
  'לחמניית': _heBreadGuard,
  'לחמנית': _heBreadGuard,
  'לחם': _heBreadGuard,
  'טוסט': _heToastGuard,
  'המבורגר': _heBurgerGuard,
  'בורגר': _heBurgerGuard,
  "צ'יזבורגר": _heBurgerGuard,
  'שמרים': _heYeastGuard,

  // Drink guards (#216): זירו/דיאט/ללא סוכר rescue the drink bases.
  'קולה': _heDrinkGuard,
  'קוקה קולה': _heDrinkGuard,
  'ספרייט': _heDrinkGuard,
  'פאנטה': _heDrinkGuard,
  'פריגת': _heDrinkGuard,
  'מיץ': _heDrinkGuard,
  'בירה': _heDrinkGuard,
  'בירה שחורה': _heDrinkGuard,
  'טוניק': _heDrinkGuard,
  'לימונדה': _heDrinkGuard,
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

// ---------------------------------------------------------------------------
// Pasted menus (architecture.md D18; issue #83)
// ---------------------------------------------------------------------------

/// A price a pasted line ends with, for `TextMenuSource` to strip: an
/// optional separator (`-`, an en or em dash, `:`), an optional leading
/// `₪`, the number (`45`, `45.90`, `45,90`) and an optional trailing `₪`,
/// `NIS` or `ILS`, anchored at the end of the line.
///
/// A bare trailing number counts as a price, so `Steak 300` loses its
/// `300`; that is the deliberate trade for never letting a price into the
/// text the classifier reads. The token must follow whitespace, a
/// separator or the start of the line, so a digit inside a word (`B12`)
/// is left alone. Matched case-insensitively.
final RegExp pastedPriceSuffix = RegExp(
  r'(?:^|\s+|\s*[-–—:]\s*)(?:₪\s*)?\d+(?:[.,]\d{1,2})?'
  r'(?:\s*(?:₪|NIS|ILS))?\s*$',
  caseSensitive: false,
);

/// The most words a line may have and still be read as a section header
/// when it is followed by a blank line (`TextMenuSource`).
const int pastedHeaderMaxWords = 4;

// ---------------------------------------------------------------------------
// Scanned menus (architecture.md D15; issues #82, #89)
// ---------------------------------------------------------------------------

/// The most pages one scan may hold, all sent in one vision request (D6).
///
/// The image picker's own `limit` is unreliable on Android, so the Scan
/// controller enforces this in Dart (issue #82). KetoClub's backend
/// enforces the same bound as `VISION_MAX_IMAGES` (issue #170); keep the
/// two equal, or a scan the app accepts is refused by the server.
const int maxScanPages = 6;

/// The most bytes one scanned page may hold: 3 MiB.
///
/// Enforced by the Scan controller (issue #82), and by KetoClub's backend
/// as `VISION_MAX_IMAGE_BYTES`, measured on the decoded bytes (issue
/// #170); keep the two equal.
const int maxScanPageBytes = 3 * 1024 * 1024;

/// The id of the one category a scanned menu's transcription holds
/// (`MenuResponseParser.parseScanned`; issue #89). The reply schema asks
/// for no structure beyond a dish list, so every dish is filed under it.
const String scannedCategoryId = 'scanned';

/// The name of [scannedCategoryId]'s category when the transcription is
/// not Hebrew. Like the waiter-script templates it is in the menu's
/// language, not the UI's (architecture.md §12): it heads the dishes as
/// the menu printed them, the way a platform's own category name does.
const String scannedCategoryNameEn = 'Scanned menu';

/// The name of [scannedCategoryId]'s category when any transcribed dish
/// name is Hebrew; see [scannedCategoryNameEn].
const String scannedCategoryNameHe = 'תפריט סרוק';

/// The prefix of a transcribed dish's id: the first dish is `v1`, then
/// `v2`, …, in the reply's order — the ids the vision preamble asks the
/// model for, assigned by the parser rather than trusted from it.
const String scannedDishIdPrefix = 'v';

/// The page filter value meaning "dishes whose page is unknown" on a
/// scanned menu (`MenuController.setPageFilter`; issue #300). Real pages
/// are 1-based (`Dish.page`), so 0 can never collide with one.
const int scanPageUnknown = 0;

/// The currency a scanned menu is stored with. A photograph's prices are
/// not read (every transcribed dish has price 0 and none is shown), and
/// KetoClub only serves Israeli venues, so this is only ever stored.
const String scannedMenuCurrency = 'ILS';

// ---------------------------------------------------------------------------
// Website menus (architecture.md D19; issue #181)
// ---------------------------------------------------------------------------

/// The largest HTML page a website fetch reads: 2 MiB. A PDF is capped at
/// [maxScanPageBytes] instead, since it goes on to the vision path as one
/// page. The backend's `WEBSITE_MAX_HTML_BYTES` is the same number.
const int websiteMaxHtmlBytes = 2 * 1024 * 1024;

/// The most of a site's `robots.txt` a phone reads: 512 KiB, the backend's
/// `WEBSITE_MAX_ROBOTS_BYTES`. A longer file is not refused: its first
/// 512 KiB are parsed, as the backend parses them (RFC 9309 §2.5).
const int websiteMaxRobotsBytes = 512 * 1024;

/// How long one request to a restaurant's site may take, direct or
/// through the backend's own per-hop budget.
const Duration websiteFetchTimeout = Duration(seconds: 15);

/// How long the web build waits for the backend's website route, which may
/// follow redirects and read `robots.txt` before answering.
const Duration websiteBackendTimeout = Duration(seconds: 60);

/// The name of the category a website menu read from page text is filed
/// under before its first header: `TextMenuSource.parse`'s
/// `uncategorisedName`, in the menu's language like
/// [scannedCategoryNameEn].
const String websiteCategoryNameEn = 'Menu';

/// [websiteCategoryNameEn] for a menu with any Hebrew dish name.
const String websiteCategoryNameHe = 'תפריט';

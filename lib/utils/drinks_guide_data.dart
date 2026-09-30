/// Static bilingual drinks guide data for the offline /drinks screen
/// (architecture.md §6.3, §12; issue #216).
///
/// Drink names and waiter-readable swap sentences live here as Dart
/// literals, not in ARB, because they are read aloud to a waiter in
/// the restaurant — they follow the menu's language convention, the
/// same documented exception that covers waiter scripts in
/// `constants.dart` (architecture.md §6.3).
///
/// Each [DrinkEntry] carries typical net-carb ranges sourced from
/// standard nutritional databases; all are labelled as estimates in
/// the UI — see `DrinksGuideScreen` for the disclaimer.
library;

/// One entry in the drinks guide: a drink name, its typical net-carb
/// range per standard serving, and the waiter-readable swap sentence
/// for yellow (swappable) drinks.
class DrinkEntry {
  /// Creates a drinks guide entry.
  const new({
    required this.name,
    required this.netCarbsRangeLabel,
    this.swapScript,
  });

  /// The drink name, in the menu's language.
  final String name;

  /// Typical net carbs per standard serving as a human-readable label,
  /// e.g. `'0–1 g'`. Always shown as an estimate.
  final String netCarbsRangeLabel;

  /// The waiter-readable swap sentence for yellow drinks, or null when
  /// the drink is already green (order as-is) or red (skip).
  final String? swapScript;
}

// ---------------------------------------------------------------------------
// English guide entries
// ---------------------------------------------------------------------------

/// English "order as-is" drinks — zero or near-zero net carbs.
const List<DrinkEntry> drinkGuideOrderAsIsEn = <DrinkEntry>[
  DrinkEntry(name: 'Still or sparkling water', netCarbsRangeLabel: '0 g'),
  DrinkEntry(name: 'Soda water (plain)', netCarbsRangeLabel: '0 g'),
  DrinkEntry(name: 'Espresso', netCarbsRangeLabel: '0 g'),
  DrinkEntry(name: 'Black coffee / Americano', netCarbsRangeLabel: '0 g'),
  DrinkEntry(name: 'Tea (unsweetened)', netCarbsRangeLabel: '0 g'),
  DrinkEntry(
    name: 'Coffee with heavy cream (no sugar)',
    netCarbsRangeLabel: '0–1 g',
  ),
  DrinkEntry(
    name: 'Zero-sugar cola / sprite / soda',
    netCarbsRangeLabel: '0 g',
  ),
  DrinkEntry(
    name: 'Dry white or red wine (one glass)',
    netCarbsRangeLabel: '2–4 g',
  ),
  DrinkEntry(
    name: 'Spirits: whisky, vodka, gin, tequila (neat or with soda)',
    netCarbsRangeLabel: '0 g',
  ),
];

/// English "ask for a swap" drinks — yellow, swappable with a script.
const List<DrinkEntry> drinkGuideAskForSwapEn = <DrinkEntry>[
  DrinkEntry(
    name: 'Latte / cappuccino',
    netCarbsRangeLabel: '10–12 g',
    swapScript:
        'Please make it with unsweetened almond milk or black coffee, no '
        'added sugar or syrup.',
  ),
  DrinkEntry(
    name: 'Iced coffee / frappé',
    netCarbsRangeLabel: '8–15 g',
    swapScript:
        'Please make it with no sugar or flavoured syrup — just espresso '
        'and ice, with soda water or unsweetened almond milk.',
  ),
  DrinkEntry(
    name: 'Gin and tonic',
    netCarbsRangeLabel: '15–20 g',
    swapScript:
        'Please make it with soda water and a squeeze of lime instead of '
        'tonic — tonic is high in sugar.',
  ),
  DrinkEntry(
    name: 'Mojito',
    netCarbsRangeLabel: '20–30 g',
    swapScript:
        'Please skip the sugar syrup and serve it with soda water, '
        'lime juice, and fresh mint over ice.',
  ),
  DrinkEntry(
    name: 'Cocktail with flavoured syrup',
    netCarbsRangeLabel: '15–30 g',
    swapScript:
        'Please omit all flavoured syrups and juice. Spirits, soda '
        'water, and fresh citrus are fine.',
  ),
];

/// English "skip" drinks — red, no keto-friendly substitute exists.
const List<DrinkEntry> drinkGuideSkipEn = <DrinkEntry>[
  DrinkEntry(
    name: 'Regular cola / sprite / soda',
    netCarbsRangeLabel: '35–40 g',
  ),
  DrinkEntry(name: 'Orange juice / apple juice', netCarbsRangeLabel: '25–30 g'),
  DrinkEntry(name: 'Lemonade (sweetened)', netCarbsRangeLabel: '25–30 g'),
  DrinkEntry(name: 'Beer / lager', netCarbsRangeLabel: '10–15 g'),
  DrinkEntry(
    name: 'Sweet wine / moscato / port',
    netCarbsRangeLabel: '10–20 g',
  ),
  DrinkEntry(name: 'Liqueur', netCarbsRangeLabel: '15–35 g'),
  DrinkEntry(name: 'Smoothie / milkshake', netCarbsRangeLabel: '30–60 g'),
  DrinkEntry(name: 'Flavoured milk drink', netCarbsRangeLabel: '20–30 g'),
];

// ---------------------------------------------------------------------------
// Hebrew guide entries
// ---------------------------------------------------------------------------

/// Hebrew "order as-is" drinks.
const List<DrinkEntry> drinkGuideOrderAsIsHe = <DrinkEntry>[
  DrinkEntry(name: 'מים (רגילים או מוגזים)', netCarbsRangeLabel: "0 ג'"),
  DrinkEntry(name: 'סודה / מים מוגזים ללא תוספת', netCarbsRangeLabel: "0 ג'"),
  DrinkEntry(name: 'אספרסו', netCarbsRangeLabel: "0 ג'"),
  DrinkEntry(name: 'קפה שחור / אמריקנו', netCarbsRangeLabel: "0 ג'"),
  DrinkEntry(name: 'תה (ללא סוכר)', netCarbsRangeLabel: "0 ג'"),
  DrinkEntry(
    name: 'קפה עם שמנת להקצפה (ללא סוכר)',
    netCarbsRangeLabel: "0–1 ג'",
  ),
  DrinkEntry(
    name: 'קולה זירו / ספרייט זירו / סודה דיאט',
    netCarbsRangeLabel: "0 ג'",
  ),
  DrinkEntry(
    name: 'יין לבן או אדום יבש (כוס אחת)',
    netCarbsRangeLabel: "2–4 ג'",
  ),
  DrinkEntry(
    name: "חריפים: וויסקי, וודקה, ג'ין, טקילה (נקי או עם סודה)",
    netCarbsRangeLabel: "0 ג'",
  ),
];

/// Hebrew "ask for a swap" drinks.
const List<DrinkEntry> drinkGuideAskForSwapHe = <DrinkEntry>[
  DrinkEntry(
    name: "לאטה / קפוצ'ינו",
    netCarbsRangeLabel: "10–12 ג'",
    swapScript: 'אפשר בבקשה עם חלב שקדים ללא סוכר, בלי סירופ?',
  ),
  DrinkEntry(
    name: 'קפה הפוך / קפה קר / פרפה',
    netCarbsRangeLabel: "8–15 ג'",
    swapScript:
        'אפשר בבקשה בלי סוכר ובלי סירופ — רק אספרסו, קרח '
        'וחלב שקדים ללא סוכר?',
  ),
  DrinkEntry(
    name: "ג'ין טוניק",
    netCarbsRangeLabel: "15–20 ג'",
    swapScript: 'אפשר בבקשה סודה עם לימון במקום הטוניק? הטוניק עתיר סוכר.',
  ),
  DrinkEntry(
    name: 'מוחיטו',
    netCarbsRangeLabel: "20–30 ג'",
    swapScript:
        "אפשר בבקשה בלי סירופ סוכר — רק ג'ין או ווודקה, סודה, "
        'לימון טרי ונענע?',
  ),
  DrinkEntry(
    name: 'קוקטייל עם סירופ',
    netCarbsRangeLabel: "15–30 ג'",
    swapScript:
        'אפשר בבקשה בלי סירופ ובלי מיץ? חריפים, סודה וסחיטת לימון — '
        'בסדר גמור.',
  ),
];

/// Hebrew "skip" drinks.
const List<DrinkEntry> drinkGuideSkipHe = <DrinkEntry>[
  DrinkEntry(
    name: 'קולה / ספרייט / סודה רגילה',
    netCarbsRangeLabel: "35–40 ג'",
  ),
  DrinkEntry(
    name: 'מיץ תפוזים / מיץ ענבים / פריגת',
    netCarbsRangeLabel: "25–30 ג'",
  ),
  DrinkEntry(name: 'לימונדה (ממותקת)', netCarbsRangeLabel: "25–30 ג'"),
  DrinkEntry(name: 'בירה / בירה שחורה / לאגר', netCarbsRangeLabel: "10–15 ג'"),
  DrinkEntry(name: 'יין מתוק / מוסקאטו / פורט', netCarbsRangeLabel: "10–20 ג'"),
  DrinkEntry(name: 'ליקר / מיסטי', netCarbsRangeLabel: "15–35 ג'"),
  DrinkEntry(name: 'סמוטי / מילקשייק', netCarbsRangeLabel: "30–60 ג'"),
  DrinkEntry(name: 'שייק חלב ממותק', netCarbsRangeLabel: "20–30 ג'"),
];

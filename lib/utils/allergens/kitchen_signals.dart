/// Kitchen cross-contact signals (Banto; ALG-07, issue #349; architecture.md
/// D26).
///
/// No menu says "shared fryer", but a menu reveals its kitchen: fries and
/// schnitzel on one list mean a fryer, pad thai means a wok, bread and pizza
/// mean flour in the air. [KitchenSignals.of] reads a whole [Menu], never a
/// dish, and reports each such fact as a [KitchenSignal]: what the menu
/// shows, which restrictions it threatens, the dishes that show it, and one
/// bilingual question to put to the staff.
///
/// Rules only, pure, profile-independent (D26, C1). A signal is a menu-level
/// fact beside the per-dish answer; it never changes a verdict and never says
/// a dish is fine. Its questions are phrased as questions, and none of them
/// uses a word of reassurance.
///
/// Detection reads each dish's rules text ([TextNormaliser.dishRulesText]:
/// name, description, option names and non-removal option values) and its
/// category heading, with the term lists below compiled exactly as the keto
/// vocabulary is (English with [latinTriggerPattern], Hebrew with
/// [hebrewTriggerPattern], guards through [ClassificationRules.isGuarded]).
/// The nuts and sesame signals, and the seafood a fryer or grill can carry,
/// come from [AllergenMatcher] and never from a list of this file.
///
/// The questions live here in Dart, in both languages, and not in the ARB
/// files: they are read aloud in the restaurant, in the menu's language (the
/// `architecture.md` §6.3 exception, as the waiter templates in
/// `constants.dart` are).
///
/// Python twin: `backend/app/keto/kitchen_signals.py`, pinned by the golden
/// `kitchen_signals.json`.
library;

import 'package:flutter/foundation.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/utils/allergens/allergen_matcher.dart';
import 'package:ketoclub/utils/allergens/vocabulary.dart';
import 'package:ketoclub/utils/classification_rules.dart';
import 'package:ketoclub/utils/constants.dart';
import 'package:ketoclub/utils/text_normaliser.dart';

/// What a menu reveals about its kitchen. Declaration order is the order
/// [KitchenSignals.of] reports in.
enum KitchenSignalKind {
  /// Fried dishes: fries, chips, schnitzel, anything battered or breaded.
  fryer,

  /// Wok cooking: stir-fries, pad thai, fried rice.
  wok,

  /// A grill that cooks meat and fish.
  sharedGrill,

  /// Bread, pastry or pizza: flour in the kitchen.
  bakery,

  /// Any dish naming nuts or peanuts.
  nuts,

  /// Any dish naming sesame or tahini.
  sesame,
}

/// The most dish names a [KitchenSignal] carries as evidence.
const int kitchenSignalEvidenceCap = 3;

/// One fact a menu reveals about its kitchen.
@immutable
final class KitchenSignal {
  /// Creates a signal.
  const new({
    required this.kind,
    required this.threatens,
    required this.evidence,
    required this.questionEn,
    required this.questionHe,
  });

  /// What the menu reveals.
  final KitchenSignalKind kind;

  /// The restrictions this kind of kitchen threatens, in taxonomy order.
  /// For a [KitchenSignalKind.fryer] it includes the seafood restrictions
  /// only when a fried dish names that seafood.
  final List<RestrictionId> threatens;

  /// The names of up to [kitchenSignalEvidenceCap] dishes that show it, as
  /// the menu prints them, in menu order.
  final List<String> evidence;

  /// The standard question for the staff, in English.
  final String questionEn;

  /// The standard question for the staff, in Hebrew.
  final String questionHe;

  /// The signal as the golden corpus writes it.
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind.name,
    'threatens': <String>[for (final id in threatens) id.name],
    'evidence': evidence,
    'questionEn': questionEn,
    'questionHe': questionHe,
  };

  @override
  bool operator ==(Object other) =>
      other is KitchenSignal &&
      other.kind == kind &&
      listEquals(other.threatens, threatens) &&
      listEquals(other.evidence, evidence) &&
      other.questionEn == questionEn &&
      other.questionHe == questionHe;

  @override
  int get hashCode => Object.hash(
    kind,
    Object.hashAll(threatens),
    Object.hashAll(evidence),
    questionEn,
    questionHe,
  );

  @override
  String toString() => 'KitchenSignal(${kind.name}, $evidence)';
}

// ---------------------------------------------------------------------------
// The term lists
// ---------------------------------------------------------------------------

/// English terms for a dish that is fried in oil. "pan fried", "stir fried"
/// and "air fried" are cancelled by [_friedGuardsEn]; "fried rice" is a wok
/// dish ([_wokEn]).
const List<String> _friedEn = <String>[
  'fried',
  'fries',
  'chips',
  'schnitzel',
  'tempura',
  'battered',
  'breaded',
  'crumbed',
  'fritters',
  'falafel',
  'onion rings',
  'nuggets',
  'katsu',
  'chicken tenders',
];

/// Hebrew terms for a fried dish. "אורז מטוגן" (fried rice) is a wok dish.
const List<String> _friedHe = <String>[
  'מטוגן',
  'מטוגנת',
  'מטוגנים',
  'מטוגנות',
  "צ'יפס",
  'שניצל',
  'שניצלים',
  'טמפורה',
  'פלאפל',
  'בציפוי',
  'בבלילה',
  'נאגטס',
  'טבעות בצל',
];

/// Guards that cancel a fried-dish trigger.
const Map<String, GuardWords> _friedGuardsEn = <String, GuardWords>{
  'fried': (before: <String>['stir', 'pan', 'air'], after: <String>['rice']),
  'chips': (before: <String>['chocolate', 'choc'], after: <String>[]),
};

/// Hebrew guards for [_friedHe].
const Map<String, GuardWords> _friedGuardsHe = <String, GuardWords>{
  'מטוגן': (before: <String>['אורז'], after: <String>[]),
};

/// English terms for wok cooking.
const List<String> _wokEn = <String>[
  'wok',
  'stir fry',
  'stir fried',
  'pad thai',
  'pad see ew',
  'chow mein',
  'lo mein',
  'kung pao',
  'yakisoba',
  'fried rice',
];

/// Hebrew terms for wok cooking.
const List<String> _wokHe = <String>[
  'ווק',
  'מוקפץ',
  'מוקפצת',
  'מוקפצים',
  'מוקפצות',
  'פאד תאי',
  "צ'או מיין",
  'לו מיין',
  'קונג פאו',
  'יאקיסובה',
  'אורז מטוגן',
];

/// Hebrew guards for [_wokHe]: "צ'יפס מוקפץ בשמן כמהין" is chips tossed in
/// oil, not a wok dish.
const Map<String, GuardWords> _wokGuardsHe = <String, GuardWords>{
  'מוקפץ': (before: <String>["צ'יפס"], after: <String>[]),
};

/// English terms for a grilled dish. A category heading with one of these
/// puts all its dishes on the grill.
const List<String> _grillEn = <String>[
  'grill',
  'grilled',
  'chargrilled',
  'charcoal',
  'plancha',
  'mangal',
  'open fire',
];

/// Hebrew terms for a grilled dish.
const List<String> _grillHe = <String>[
  'גריל',
  'על האש',
  'מנגל',
  'פחמים',
  "פלנצ'ה",
];

/// English meat terms, for telling a grill that cooks meat.
const List<String> _meatEn = <String>[
  'steak',
  'beef',
  'burger',
  'hamburger',
  'chicken',
  'lamb',
  'kebab',
  'kebabs',
  'ribs',
  'entrecote',
  'ribeye',
  'rib eye',
  'sirloin',
  'sausage',
  'merguez',
  'brisket',
  'turkey',
  'pork',
  'wings',
];

/// Hebrew meat terms.
const List<String> _meatHe = <String>[
  'סטייק',
  'סטקים',
  'בקר',
  'בשר',
  'עוף',
  'כבש',
  'קבב',
  'שיפוד',
  'שיפודים',
  'אנטריקוט',
  'המבורגר',
  'נקניקיה',
  'נקניקיות',
  'מרגז',
  'הודו',
  'צלעות',
  'פרגית',
  'פרגיות',
  'כנפיים',
  'אסאדו',
  'בריסקט',
];

/// Guards that cancel an English meat trigger (a plant-based burger).
const Map<String, GuardWords> _meatGuardsEn = <String, GuardWords>{
  'burger': (
    before: <String>['vegan', 'veggie', 'vegetarian', 'plant based', 'beyond'],
    after: <String>[],
  ),
  'hamburger': (
    before: <String>['vegan', 'veggie', 'vegetarian', 'plant based', 'beyond'],
    after: <String>[],
  ),
};

/// Guards that cancel a Hebrew meat trigger (a vegan burger, meatless).
const Map<String, GuardWords> _meatGuardsHe = <String, GuardWords>{
  'המבורגר': (
    before: <String>[],
    after: <String>['טבעוני', 'טבעונית', 'צמחוני', 'צמחונית'],
  ),
  'בשר': (before: <String>['ללא', 'בלי'], after: <String>['טבעוני', 'צמחי']),
};

/// English terms for flour work: bread, pastry, pizza.
const List<String> _bakeryEn = <String>[
  'bread',
  'baguette',
  'focaccia',
  'ciabatta',
  'sourdough',
  'challah',
  'bagel',
  'croissant',
  'pastry',
  'pastries',
  'pizza',
  'cake',
  'muffin',
  'scone',
  'danish',
  'brioche',
  'toast',
  'dough',
  'bourekas',
  'burekas',
  'borekas',
  'khachapuri',
  'malawach',
  'jachnun',
  'manakish',
  'cookie',
  'cookies',
  'brownie',
  'waffle',
  'waffles',
  'pancake',
  'pancakes',
];

/// Hebrew terms for flour work.
const List<String> _bakeryHe = <String>[
  'לחם',
  'חלה',
  'בגט',
  "פוקאצ'ה",
  "צ'יאבטה",
  'מאפה',
  'מאפים',
  'מאפי',
  'פיצה',
  'פיצות',
  'בורקס',
  'בורקסים',
  'קרואסון',
  'קרואסונים',
  'בייגל',
  'עוגה',
  'עוגות',
  'עוגת',
  'עוגיה',
  'עוגיות',
  'מאפין',
  'פנקייק',
  'פנקייקים',
  'ופל',
  'ופלים',
  "חצ'פורי",
  'מלוואח',
  "ג'חנון",
  'מנאקיש',
  'בריוש',
  'טוסט',
  'דניש',
  'סקונס',
  'בצק',
];

/// Hebrew terms compiled with no permissive prefix letter, as the keto
/// vocabulary does for "חלה": the prefix `ה` would read "החלה" ("began").
const Set<String> _noPrefixHe = <String>{'חלה'};

/// The seafood restrictions a fried or grilled dish can carry, in taxonomy
/// order: fish, crustaceans, molluscs.
const List<RestrictionId> _seafood = <RestrictionId>[
  RestrictionId.fish,
  RestrictionId.crustaceans,
  RestrictionId.molluscs,
];

/// The restrictions a [KitchenSignalKind.fryer] always threatens: celiac
/// and wheat, for the breaded and battered dishes that share the oil.
const List<RestrictionId> _fryerBase = <RestrictionId>[
  RestrictionId.wheat,
  RestrictionId.gluten,
];

/// What each kind threatens, except a fryer's seafood (see [_fryerBase]).
///
/// A wok threatens celiac and wheat (soy sauce, noodles), soy, peanut,
/// sesame (oil) and shellfish; a grill that cooks meat and fish threatens
/// fish and shellfish; flour threatens celiac, wheat, milk, eggs and
/// sesame (seeded bread); nuts threatens peanuts and tree nuts; sesame
/// threatens sesame.
const Map<KitchenSignalKind, List<RestrictionId>> _threatens =
    <KitchenSignalKind, List<RestrictionId>>{
      KitchenSignalKind.fryer: _fryerBase,
      KitchenSignalKind.wok: <RestrictionId>[
        RestrictionId.peanuts,
        RestrictionId.soy,
        RestrictionId.wheat,
        RestrictionId.gluten,
        RestrictionId.crustaceans,
        RestrictionId.molluscs,
        RestrictionId.sesame,
      ],
      KitchenSignalKind.sharedGrill: _seafood,
      KitchenSignalKind.bakery: <RestrictionId>[
        RestrictionId.milk,
        RestrictionId.eggs,
        RestrictionId.wheat,
        RestrictionId.gluten,
        RestrictionId.sesame,
      ],
      KitchenSignalKind.nuts: <RestrictionId>[
        RestrictionId.peanuts,
        RestrictionId.treeNuts,
      ],
      KitchenSignalKind.sesame: <RestrictionId>[RestrictionId.sesame],
    };

/// The standard question for each kind, English then Hebrew. Questions,
/// never assurances: none of them says a dish is fine.
const Map<KitchenSignalKind, (String, String)> _questions =
    <KitchenSignalKind, (String, String)>{
      KitchenSignalKind.fryer: (
        'Do the fried dishes share a fryer or frying oil with breaded or '
            'battered ones?',
        'האם המנות המטוגנות מטוגנות באותו שמן או באותה מטגנת עם מנות בציפוי '
            'או בבלילה?',
      ),
      KitchenSignalKind.wok: (
        'Is the wok shared between dishes, and is it cleaned between '
            'orders?',
        'האם אותו ווק משמש למנות שונות, והאם מנקים אותו בין הזמנות?',
      ),
      KitchenSignalKind.sharedGrill: (
        'Are meat and fish cooked on the same grill, and is it cleaned '
            'between orders?',
        'האם בשר ודגים מבושלים על אותו גריל, והאם מנקים אותו בין הזמנות?',
      ),
      KitchenSignalKind.bakery: (
        'Is flour or bread handled on the surfaces where other dishes are '
            'prepared?',
        'האם מכינים מנות אחרות על אותם משטחים שבהם עובדים עם קמח או לחם?',
      ),
      KitchenSignalKind.nuts: (
        'Are nuts used in this kitchen, and can my dish be prepared with '
            'no contact with them?',
        'האם משתמשים באגוזים במטבח הזה, ואפשר להכין את המנה שלי בלי מגע '
            'איתם?',
      ),
      KitchenSignalKind.sesame: (
        'Are sesame or tahini used on shared surfaces or utensils, and can '
            'my dish be prepared without them?',
        'האם משתמשים בשומשום או בטחינה על משטחים או כלים משותפים, ואפשר '
            'להכין את המנה שלי בלעדיהם?',
      ),
    };

// ---------------------------------------------------------------------------
// Compiling and matching
// ---------------------------------------------------------------------------

/// One compiled term and the guard that cancels it.
typedef _Compiled = ({RegExp pattern, GuardWords? guard});

List<_Compiled> _compileEn(
  List<String> terms, [
  Map<String, GuardWords> guards = const <String, GuardWords>{},
]) => <_Compiled>[
  for (final term in terms)
    (
      pattern: latinTriggerPattern(TextNormaliser.normalise(term)),
      guard: guards[term],
    ),
];

List<_Compiled> _compileHe(
  List<String> terms, [
  Map<String, GuardWords> guards = const <String, GuardWords>{},
]) => <_Compiled>[
  for (final term in terms)
    (
      pattern: hebrewTriggerPattern(
        TextNormaliser.normalise(term),
        allowPrefix: !_noPrefixHe.contains(term),
      ),
      guard: guards[term],
    ),
];

/// Whether any of [compiled] has an unguarded match in the normalised
/// [haystack].
bool _any(String haystack, List<_Compiled> compiled) {
  if (haystack.isEmpty) return false;
  for (final entry in compiled) {
    for (final match in entry.pattern.allMatches(haystack)) {
      if (!ClassificationRules.isGuarded(
        haystack,
        match.start,
        match.end,
        entry.guard,
      )) {
        return true;
      }
    }
  }
  return false;
}

final List<_Compiled> _fried = <_Compiled>[
  ..._compileEn(_friedEn, _friedGuardsEn),
  ..._compileHe(_friedHe, _friedGuardsHe),
];
final List<_Compiled> _wok = <_Compiled>[
  ..._compileEn(_wokEn),
  ..._compileHe(_wokHe, _wokGuardsHe),
];
final List<_Compiled> _grill = <_Compiled>[
  ..._compileEn(_grillEn),
  ..._compileHe(_grillHe),
];
final List<_Compiled> _meat = <_Compiled>[
  ..._compileEn(_meatEn, _meatGuardsEn),
  ..._compileHe(_meatHe, _meatGuardsHe),
];
final List<_Compiled> _bakery = <_Compiled>[
  ..._compileEn(_bakeryEn),
  ..._compileHe(_bakeryHe),
];

/// What one piece of text (a dish or a heading) shows.
typedef _Flags = ({
  bool fried,
  bool wok,
  bool grill,
  bool meat,
  bool bakery,
  bool nuts,
  bool sesame,
  Set<RestrictionId> seafood,
});

/// The flags of [haystack], with [hits] the matcher found in it. A guarded
/// hit ("almond-free") is no evidence that the kitchen handles the
/// allergen, so only unguarded hits count (ALG-04a).
_Flags _flagsOf(String haystack, List<AllergenHit> hits) {
  final ids = <RestrictionId>{
    for (final hit in hits)
      if (!hit.guarded) hit.id,
  };
  return (
    fried: _any(haystack, _fried),
    wok: _any(haystack, _wok),
    grill: _any(haystack, _grill),
    meat: _any(haystack, _meat),
    bakery: _any(haystack, _bakery),
    nuts:
        ids.contains(RestrictionId.peanuts) ||
        ids.contains(RestrictionId.treeNuts),
    sesame: ids.contains(RestrictionId.sesame),
    seafood: {
      for (final id in _seafood)
        if (ids.contains(id)) id,
    },
  );
}

/// [first] or [second], fieldwise.
_Flags _union(_Flags first, _Flags second) => (
  fried: first.fried || second.fried,
  wok: first.wok || second.wok,
  grill: first.grill || second.grill,
  meat: first.meat || second.meat,
  bakery: first.bakery || second.bakery,
  nuts: first.nuts || second.nuts,
  sesame: first.sesame || second.sesame,
  seafood: {...first.seafood, ...second.seafood},
);

/// A dish, its position in the menu and what it shows (its own text plus
/// its category heading).
typedef _Seen = ({int index, Dish dish, _Flags flags});

/// Up to [kitchenSignalEvidenceCap] distinct names, first occurrence kept.
List<String> _names(Iterable<_Seen> seen) {
  final names = <String>[];
  for (final entry in seen) {
    if (names.length == kitchenSignalEvidenceCap) break;
    if (!names.contains(entry.dish.name)) names.add(entry.dish.name);
  }
  return List<String>.unmodifiable(names);
}

/// The evidence for a grill: the first meat dish and the first fish dish
/// (they are why the grill is shared), then more grilled meat and fish
/// dishes in menu order up to the cap, all shown in menu order.
List<_Seen> _grillEvidence(List<_Seen> meat, List<_Seen> fish) {
  final onGrill = <_Seen>[
    ...meat,
    ...fish.where((entry) => !meat.any((m) => m.index == entry.index)),
  ]..sort((a, b) => a.index.compareTo(b.index));
  final picked = <int>{meat.first.index, fish.first.index};
  for (final entry in onGrill) {
    if (picked.length == kitchenSignalEvidenceCap) break;
    picked.add(entry.index);
  }
  return <_Seen>[
    for (final entry in onGrill)
      if (picked.contains(entry.index)) entry,
  ];
}

/// Finds the kitchen signals a menu reveals (ALG-07).
abstract final class KitchenSignals {
  /// Every [KitchenSignal] [menu] shows, in [KitchenSignalKind] order; an
  /// empty list when it shows none. Never throws.
  ///
  /// A dish shows a kind when its own text does or its category heading
  /// does. The kinds:
  ///
  /// * [KitchenSignalKind.fryer]: a dish with a fried-dish term. It also
  ///   threatens fish, crustaceans or molluscs when a fried dish names
  ///   that seafood ([AllergenMatcher]).
  /// * [KitchenSignalKind.wok]: a dish with a wok term.
  /// * [KitchenSignalKind.sharedGrill]: at least one grilled dish with a
  ///   meat term and at least one grilled dish naming fish ([AllergenMatcher]).
  /// * [KitchenSignalKind.bakery]: a dish with a bread, pastry or pizza
  ///   term.
  /// * [KitchenSignalKind.nuts]: a dish [AllergenMatcher] finds peanuts or
  ///   tree nuts in.
  /// * [KitchenSignalKind.sesame]: a dish [AllergenMatcher] finds sesame
  ///   in.
  static List<KitchenSignal> of(Menu menu) =>
      _read(menu, AllergenMatcher.find, AllergenMatcher.findInDish);

  /// [of] over [vocabulary] instead of [allergenVocabulary]: for the tests
  /// and the golden exporter, which pin this pass with a vocabulary of
  /// their own rather than the group files. Production code calls [of].
  static List<KitchenSignal> ofWith(
    Menu menu,
    Map<RestrictionId, RestrictionVocabulary> vocabulary,
  ) => _read(
    menu,
    (text) => AllergenMatcher.findWith(text, vocabulary),
    (dish) => AllergenMatcher.findInDishWith(dish, vocabulary),
  );

  static List<KitchenSignal> _read(
    Menu menu,
    List<AllergenHit> Function(String text) findInText,
    List<AllergenHit> Function(Dish dish) findInDish,
  ) {
    final seen = <_Seen>[];
    for (final category in menu.categories) {
      final heading = _flagsOf(
        TextNormaliser.normalise(category.name),
        findInText(category.name),
      );
      for (final dish in category.dishes) {
        final own = _flagsOf(
          TextNormaliser.dishRulesText(dish),
          findInDish(dish),
        );
        seen.add((index: seen.length, dish: dish, flags: _union(own, heading)));
      }
    }

    List<_Seen> where(bool Function(_Flags flags) test) => <_Seen>[
      for (final entry in seen)
        if (test(entry.flags)) entry,
    ];

    final fried = where((flags) => flags.fried);
    final wok = where((flags) => flags.wok);
    final bakery = where((flags) => flags.bakery);
    final nuts = where((flags) => flags.nuts);
    final sesame = where((flags) => flags.sesame);
    final grilledMeat = where((flags) => flags.grill && flags.meat);
    final grilledFish = where(
      (flags) => flags.grill && flags.seafood.contains(RestrictionId.fish),
    );
    final friedSeafood = <RestrictionId>{
      for (final entry in fried) ...entry.flags.seafood,
    };

    KitchenSignal signal(
      KitchenSignalKind kind,
      Iterable<_Seen> evidence, [
      List<RestrictionId>? threatens,
    ]) {
      final (questionEn, questionHe) = _questions[kind]!;
      return KitchenSignal(
        kind: kind,
        threatens: List<RestrictionId>.unmodifiable(
          threatens ?? _threatens[kind]!,
        ),
        evidence: _names(evidence),
        questionEn: questionEn,
        questionHe: questionHe,
      );
    }

    return List<KitchenSignal>.unmodifiable(<KitchenSignal>[
      if (fried.isNotEmpty)
        signal(KitchenSignalKind.fryer, fried, <RestrictionId>[
          ..._fryerBase,
          ..._seafood.where(friedSeafood.contains),
        ]),
      if (wok.isNotEmpty) signal(KitchenSignalKind.wok, wok),
      if (grilledMeat.isNotEmpty && grilledFish.isNotEmpty)
        signal(
          KitchenSignalKind.sharedGrill,
          _grillEvidence(grilledMeat, grilledFish),
        ),
      if (bakery.isNotEmpty) signal(KitchenSignalKind.bakery, bakery),
      if (nuts.isNotEmpty) signal(KitchenSignalKind.nuts, nuts),
      if (sesame.isNotEmpty) signal(KitchenSignalKind.sesame, sesame),
    ]);
  }

  /// The term lists, guards and threat table as the golden corpus writes
  /// them, so the Python twin's copies are pinned equal to these.
  static Map<String, Object?> vocabularyJson() {
    Map<String, Object?> guards(Map<String, GuardWords> table) =>
        <String, Object?>{
          for (final entry in table.entries)
            entry.key: <String, Object?>{
              'before': entry.value.before,
              'after': entry.value.after,
            },
        };
    return <String, Object?>{
      'friedEn': _friedEn,
      'friedHe': _friedHe,
      'friedGuardsEn': guards(_friedGuardsEn),
      'friedGuardsHe': guards(_friedGuardsHe),
      'wokEn': _wokEn,
      'wokHe': _wokHe,
      'wokGuardsHe': guards(_wokGuardsHe),
      'grillEn': _grillEn,
      'grillHe': _grillHe,
      'meatEn': _meatEn,
      'meatHe': _meatHe,
      'meatGuardsEn': guards(_meatGuardsEn),
      'meatGuardsHe': guards(_meatGuardsHe),
      'bakeryEn': _bakeryEn,
      'bakeryHe': _bakeryHe,
      'noPrefixHe': _noPrefixHe.toList(),
      'evidenceCap': kitchenSignalEvidenceCap,
      'fryerBase': <String>[for (final id in _fryerBase) id.name],
      'threatens': <String, Object?>{
        for (final entry in _threatens.entries)
          entry.key.name: <String>[for (final id in entry.value) id.name],
      },
      'questions': <String, Object?>{
        for (final entry in _questions.entries)
          entry.key.name: <String, Object?>{
            'en': entry.value.$1,
            'he': entry.value.$2,
          },
      },
    };
  }
}

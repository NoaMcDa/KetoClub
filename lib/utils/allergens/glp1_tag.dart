/// The small-portions tag: "protein-forward · small portion" (Banto; the
/// Allergens epic, ALG-17's GLP-1 follow-up, issue #359).
///
/// GLP-1 eating is a preference signal, not a restriction: the epic tags a
/// dish rather than colouring it. So this file never touches a verdict, a
/// state, a colour or a concern, and names no number (no menu supplies
/// one). It is device-only, after the profile chose (D26 C1): the wire, the
/// Python twin and the goldens do not move.
///
/// **Protein-forward** is read from the extraction roles ALG-03 already
/// asks for when the model listed the dish's ingredients: a protein at
/// `stated` or `likely`, and no carbohydrate base (an ingredient in the
/// `base` role that the keto rules flag). Where no model listed them (a
/// rules analysis, an empty extraction), the rules read the dish's own
/// name: it names a protein and the keto rules do not find it built on a
/// starch.
///
/// **Small portion** is read from the menu's words, since ALG-03 extracts
/// no portion hint: a starter, a small plate, a half or a kids' portion in
/// the dish's name, description or section heading, unless the name or
/// description also says it is large (double, jumbo, a platter, for
/// sharing).
library;

import 'package:flutter/foundation.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/concern.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/utils/classification_rules.dart';
import 'package:ketoclub/utils/text_normaliser.dart';

/// Proteins a dish can be named for, English. Compared after
/// normalisation. Breaded, fried-ball and sandwich dishes are left out on
/// purpose (schnitzel, falafel, sabich): the keto rules already find them
/// built on a starch, or they are not built around a protein.
const List<String> glp1ProteinEn = <String>[
  'chicken',
  'chicken breast',
  'beef',
  'lamb',
  'veal',
  'steak',
  'entrecote',
  'sirloin',
  'ribeye',
  'fillet',
  'meat',
  'meatballs',
  'kebab',
  'kebabs',
  'skewer',
  'skewers',
  'shawarma',
  'egg',
  'eggs',
  'omelette',
  'omelet',
  'shakshuka',
  'tuna',
  'fish',
  'salmon',
  'sea bass',
  'sea bream',
  'trout',
  'cod',
  'shrimp',
  'prawns',
  'calamari',
  'octopus',
  'turkey',
  'liver',
  'tofu',
  'tempeh',
];

/// Hebrew mirror of [glp1ProteinEn].
const List<String> glp1ProteinHe = <String>[
  'עוף',
  'חזה עוף',
  'פרגית',
  'פרגיות',
  'בקר',
  'טלה',
  'עגל',
  'סטייק',
  'אנטריקוט',
  'סינטה',
  'פילה',
  'בשר',
  'קציצות',
  'קבב',
  'שיפוד',
  'שיפודי',
  'שיפודים',
  'שווארמה',
  'שוארמה',
  'ביצה',
  'ביצים',
  'חביתה',
  'שקשוקה',
  'טונה',
  'דג',
  'דגים',
  'סלמון',
  'לברק',
  'דניס',
  'אמנון',
  'שרימפס',
  'קלמרי',
  'תמנון',
  'הודו',
  'כבד',
  'טופו',
];

/// Words that call a dish or its section small, English.
const List<String> glp1SmallEn = <String>[
  'starter',
  'starters',
  'appetizer',
  'appetizers',
  'appetiser',
  'appetisers',
  'small',
  'small plate',
  'small plates',
  'half portion',
  'half serving',
  'mini',
  'kids',
  'kids meal',
  'children',
  'tapas',
  'mezze',
  'meze',
  'side dish',
  'side dishes',
  'sides',
  'taster',
];

/// Hebrew mirror of [glp1SmallEn]. A bare `מיני` is left out: it more
/// often means "kinds of" ("מיני מאפים") than "mini".
const List<String> glp1SmallHe = <String>[
  'ראשונות',
  'מנה ראשונה',
  'מנות ראשונות',
  'קטן',
  'קטנה',
  'קטנות',
  'קטנים',
  'חצי מנה',
  'ילדים',
  'מנת ילדים',
  'טאפס',
  'מזטים',
  'תוספות',
];

/// Words that say a dish is large, English; any of them in the name or the
/// description withholds "small portion".
const List<String> glp1LargeEn = <String>[
  'large',
  'double',
  'triple',
  'xl',
  'xxl',
  'jumbo',
  'giant',
  'family',
  'platter',
  'sharing',
  'for two',
];

/// Hebrew mirror of [glp1LargeEn].
const List<String> glp1LargeHe = <String>[
  'גדול',
  'גדולה',
  'כפול',
  'כפולה',
  'ענק',
  'ענקית',
  'זוגי',
  'זוגית',
  'משפחתי',
  'משפחתית',
  'פלטה',
  'פלטת',
  'להתחלק',
];

/// [en] and [he] compiled as the keto vocabulary is
/// ([latinTriggerPattern], [hebrewTriggerPattern] with its prefixes).
List<RegExp> _compile(List<String> en, List<String> he) => <RegExp>[
  for (final word in en) latinTriggerPattern(TextNormaliser.normalise(word)),
  for (final word in he) hebrewTriggerPattern(TextNormaliser.normalise(word)),
];

final List<RegExp> _protein = _compile(glp1ProteinEn, glp1ProteinHe);
final List<RegExp> _small = _compile(glp1SmallEn, glp1SmallHe);
final List<RegExp> _large = _compile(glp1LargeEn, glp1LargeHe);

/// Whether any of [patterns] matches the normalised [raw].
bool _any(List<RegExp> patterns, String raw) {
  final text = TextNormaliser.normalise(raw);
  if (text.isEmpty) return false;
  return patterns.any((pattern) => pattern.hasMatch(text));
}

/// What the small-portions tag says about one dish; [isEmpty] when it says
/// nothing.
@immutable
final class Glp1Tag {
  /// Creates a tag.
  const new({this.proteinForward = false, this.smallPortion = false});

  /// The tag that says nothing.
  static const Glp1Tag none = Glp1Tag();

  /// Whether the dish is built around its protein.
  final bool proteinForward;

  /// Whether the menu calls the dish (or its section) small.
  final bool smallPortion;

  /// Whether the tag has nothing to show.
  bool get isEmpty => !proteinForward && !smallPortion;

  @override
  bool operator ==(Object other) =>
      other is Glp1Tag &&
      other.proteinForward == proteinForward &&
      other.smallPortion == smallPortion;

  @override
  int get hashCode => Object.hash(proteinForward, smallPortion);

  @override
  String toString() =>
      'Glp1Tag(proteinForward: $proteinForward, smallPortion: $smallPortion)';
}

/// Reads the small-portions tag of a dish; pure and never throws.
abstract final class Glp1Tags {
  /// The tag of [dish] under the section [heading], from [analysed]'s
  /// ingredient list when the model gave one and from the rules otherwise.
  static Glp1Tag of(Dish dish, AnalysedDish? analysed, {String heading = ''}) {
    final ingredients = analysed?.ingredients ?? const <ExtractedIngredient>[];
    return Glp1Tag(
      proteinForward: ingredients.isEmpty
          ? _proteinForwardByRules(dish)
          : _proteinForwardByRoles(ingredients),
      smallPortion: _smallPortion(dish, heading),
    );
  }

  /// A firm protein and no carbohydrate base among the model's
  /// [ingredients].
  static bool _proteinForwardByRoles(List<ExtractedIngredient> ingredients) {
    bool firm(ExtractedIngredient ingredient) =>
        ingredient.certainty != Certainty.suspected;
    final protein = ingredients.any(
      (ingredient) =>
          ingredient.role == ComponentRole.protein && firm(ingredient),
    );
    if (!protein) return false;
    return !ingredients.any(
      (ingredient) =>
          ingredient.role == ComponentRole.base &&
          firm(ingredient) &&
          _isCarb(ingredient.name),
    );
  }

  /// Whether the keto rules flag [name] as a starch, a bread or a sugar.
  static bool _isCarb(String name) {
    final match = ClassificationRules.match(name);
    return match.isNonKeto || match.instructions.isNotEmpty;
  }

  /// The dish's name names a protein and the keto rules do not find the
  /// dish built on a starch.
  static bool _proteinForwardByRules(Dish dish) =>
      _any(_protein, dish.name) &&
      !ClassificationRules.matchDish(dish).isNonKeto;

  /// A small word in the name, the description or the heading, and no
  /// large word in the name or the description.
  static bool _smallPortion(Dish dish, String heading) {
    final own = '${dish.name}\n${dish.description}';
    if (_any(_large, own)) return false;
    return _any(_small, own) || _any(_small, heading);
  }
}

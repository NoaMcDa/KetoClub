/// What a menu line *is* — food, a drink, an extra, or a notice — so the
/// keto score and the verdict counts can cover food alone (architecture.md
/// D21).
///
/// The kind is computed, never stored: `Dish` carries no field for it, the
/// Hive cache is unchanged, and a dish the menu does not hold is food.
/// Evidence is read in order — the category heading first, the dish name
/// second, never the description — and on doubt the answer is food, since
/// leaving a real dish out of the score is the worse mistake.
library;

import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/utils/classification_rules.dart';
import 'package:ketoclub/utils/constants.dart';
import 'package:ketoclub/utils/text_normaliser.dart';

/// The kinds a menu line can be. Only [food] counts toward the keto score
/// and the verdict counts. Every kind is still classified, and every kind
/// but [notice] is listed on the menu screen (issue #445).
enum DishKind {
  /// Something to eat: the default, and the only kind that is counted.
  food,

  /// A beverage, soft or alcoholic, hot or cold.
  drink,

  /// A sauce, dip or add-on, or a non-edible line such as cutlery, a
  /// deposit, delivery or a gift card.
  extra,

  /// A notice to the customer printed as a menu line, such as a Wolt
  /// "Dear customers" category or a "coming soon" placeholder. Not drawn
  /// as a dish: the menu screen keeps it behind one quiet line instead.
  notice,
}

/// Whether a kind is counted (D21).
extension DishKindCounting on DishKind {
  /// True for [DishKind.food] only.
  bool get countsTowardScore => this == DishKind.food;
}

/// One compiled vocabulary list, ready to run over normalised text.
final class _Vocabulary {
  new({
    required List<String> en,
    required List<String> he,
    required bool allowHebrewPrefix,
  }) : _patterns = <RegExp>[
         for (final word in en)
           latinTriggerPattern(TextNormaliser.normalise(word)),
         for (final word in he)
           hebrewTriggerPattern(
             TextNormaliser.normalise(word),
             allowPrefix: allowHebrewPrefix,
           ),
       ];

  final List<RegExp> _patterns;

  bool matches(String normalised) =>
      _patterns.any((pattern) => pattern.hasMatch(normalised));
}

// Category headings are matched without the permissive Hebrew prefix: a
// heading is not a sentence, and `ורטבים` in "תוספות ורטבים" must not fire
// the sauces word. Dish names keep the classifier's permissive rule, so
// "הקולה" and "בקפה" still read as the drink they name.
final _Vocabulary _drinkCategories = _Vocabulary(
  en: drinkCategoryWordsEn,
  he: drinkCategoryWordsHe,
  allowHebrewPrefix: false,
);
final _Vocabulary _extraCategories = _Vocabulary(
  en: extraCategoryWordsEn,
  he: extraCategoryWordsHe,
  allowHebrewPrefix: false,
);
// The food veto keeps the permissive prefix: "קפה ומאפה" carries its food
// word as `ומאפה`, and a veto can only ever turn an exclusion into "count
// it", which is the safe direction.
final _Vocabulary _foodCategories = _Vocabulary(
  en: foodCategoryWordsEn,
  he: foodCategoryWordsHe,
  allowHebrewPrefix: true,
);
final _Vocabulary _noticeWords = _Vocabulary(
  en: noticeCategoryWordsEn,
  he: noticeCategoryWordsHe,
  allowHebrewPrefix: false,
);
final _Vocabulary _drinkNames = _Vocabulary(
  en: drinkNameTriggersEn,
  he: drinkNameTriggersHe,
  allowHebrewPrefix: true,
);
final _Vocabulary _drinkNameGuards = _Vocabulary(
  en: drinkNameGuardWordsEn,
  he: drinkNameGuardWordsHe,
  allowHebrewPrefix: true,
);
// A non-edible line named as such (issue #472): no permissive prefix, so
// `נר` ("candle") never fires inside a longer word's particle.
final _Vocabulary _extraNames = _Vocabulary(
  en: extraNameWordsEn,
  he: extraNameWordsHe,
  allowHebrewPrefix: false,
);
final _Vocabulary _plainDrinkNames = _Vocabulary(
  en: plainDrinkWordsEn,
  he: plainDrinkWordsHe,
  allowHebrewPrefix: true,
);
final _Vocabulary _drinkHeadingGuards = _Vocabulary(
  en: drinkHeadingGuardWordsEn,
  he: drinkHeadingGuardWordsHe,
  allowHebrewPrefix: true,
);

/// [drinkHeadingBasesEn] and [drinkHeadingBasesHe] compiled, English
/// first, each with its label; headings match without the prefix.
final List<({RegExp pattern, String label})> _drinkHeadingBases = [
  for (final MapEntry(key: word, value: label) in drinkHeadingBasesEn.entries)
    (
      pattern: latinTriggerPattern(TextNormaliser.normalise(word)),
      label: label,
    ),
  for (final MapEntry(key: word, value: label) in drinkHeadingBasesHe.entries)
    (
      pattern: hebrewTriggerPattern(
        TextNormaliser.normalise(word),
        allowPrefix: false,
      ),
      label: label,
    ),
];

/// The kind a category heading alone implies, or [DishKind.food] when it
/// implies nothing — a "Mains" heading says nothing about a drink filed
/// under it, which is what [dishKindOf]'s name fallback is for.
///
/// Order: a notice word wins (a "Dear customers" heading is a notice even
/// when it mentions delivery); then a drink or an extras word — unless a
/// food word sits beside it ("Sauces & Sides", "תוספות ורטבים", "קפה
/// ומאפה", "Beers & Burgers"), in which case the heading decides nothing
/// and each dish is read by its own name.
DishKind categoryKindOf(String categoryName) {
  final heading = TextNormaliser.normalise(categoryName);
  if (heading.isEmpty) return DishKind.food;
  if (_noticeWords.matches(heading)) return DishKind.notice;
  if (_foodCategories.matches(heading)) return DishKind.food;
  if (_drinkCategories.matches(heading)) return DishKind.drink;
  if (_extraCategories.matches(heading)) return DishKind.extra;
  return DishKind.food;
}

/// The kind of [dish] filed under the category named [category].
///
/// The heading decides when it can ([categoryKindOf]); otherwise the dish
/// *name* is read — never the description, so "served with a glass of
/// wine" cannot turn a steak into a drink. A name that is a notice word at
/// a price of zero is a notice; a name that is cutlery, a candle or a
/// greeting card ([extraNameWordsEn], issue #472) is an extra under any
/// heading; a name holding a drink word with none of the ingredient
/// guards ("beer-battered", "wine-braised", "ברוטב יין") is a drink;
/// anything else is food.
DishKind dishKindOf({required String category, required Dish dish}) {
  final fromHeading = categoryKindOf(category);
  if (fromHeading != DishKind.food) return fromHeading;
  final name = TextNormaliser.normalise(dish.name);
  if (name.isEmpty) return DishKind.food;
  if (dish.price == 0 && _noticeWords.matches(name)) return DishKind.notice;
  if (_extraNames.matches(name)) return DishKind.extra;
  if (_drinkNames.matches(name) && !_drinkNameGuards.matches(name)) {
    return DishKind.drink;
  }
  return DishKind.food;
}

/// The red base a drink takes from its heading (issue #474), or null.
///
/// A sugary drink named by a brand or a fruit alone ("היינקן", "תפוז")
/// says nothing the vocabulary knows, but the heading that sorted it
/// says what it is: a drink ([dishKindOf]) under a beer, juice or shake
/// heading ([drinkHeadingBasesEn], [drinkHeadingBasesHe]) is that drink.
/// A plain drink ([plainDrinkWordsEn]: wine, water, spirits) and a name
/// with a [drinkHeadingGuardWordsEn] word ("זירו", "unsweetened") are
/// left alone. The label is the heading's first base word, in the
/// heading's language.
String? headingDrinkBase({required String category, required Dish dish}) {
  if (dishKindOf(category: category, dish: dish) != DishKind.drink) {
    return null;
  }
  final heading = TextNormaliser.normalise(category);
  final name = TextNormaliser.normalise(dish.name);
  if (_plainDrinkNames.matches(name) || _drinkHeadingGuards.matches(name)) {
    return null;
  }
  for (final base in _drinkHeadingBases) {
    if (base.pattern.hasMatch(heading)) return base.label;
  }
  return null;
}

/// The kind of every dish on [menu], by dish id, computed once per menu.
/// A dish id listed under two categories takes the first one's heading,
/// as `Menu.categoryNameOf` does.
Map<String, DishKind> dishKindsOf(Menu menu) {
  final kinds = <String, DishKind>{};
  for (final category in menu.categories) {
    for (final dish in category.dishes) {
      kinds.putIfAbsent(
        dish.id,
        () => dishKindOf(category: category.name, dish: dish),
      );
    }
  }
  return kinds;
}

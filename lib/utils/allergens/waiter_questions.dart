/// The waiter question on every concern (Banto; the Allergens epic,
/// ALG-08b, issue #350; architecture.md D26).
///
/// A [Concern] the rule engine finds carries no question, and one the
/// model returns may carry none. [WaiterQuestions.fill] gives each concern
/// of an evaluated dish the question that would settle it, composed here
/// from sentence templates per restriction, certainty and source, in the
/// **menu's** language: the question is read to a waiter in that
/// restaurant, so like the "without" sentences of `profile_evaluator.dart`
/// and the keto templates of `constants.dart` it lives in Dart and not in
/// the ARB files (architecture.md §6.3 and §12, the documented exception).
///
/// It runs on the device only, after the profile has chosen its concerns
/// (`ProfileEvaluator.evaluate`); the wire, the Python twin and the
/// goldens are untouched (D26 C1). A question the model already wrote is
/// kept.
///
/// Every sentence is a question. None says a dish is fine and none uses a
/// word of reassurance (file 09 §6); a table test sweeps them for "safe"
/// and "בטוח".
library;

import 'package:ketoclub/models/concern.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/utils/allergens/taxonomy.dart';

/// "Can this be made without …?" for a restriction stated in the dish
/// itself; `{subject}` is [WaiterQuestions.subject].
const String waiterQuestionWithoutEn = 'Can this be made without {subject}?';

/// [waiterQuestionWithoutEn] in Hebrew.
const String waiterQuestionWithoutHe = 'אפשר להכין את המנה בלי {subject}?';

/// For a removable option that holds the restriction; `{item}` is the
/// option's words as the menu printed them.
const String waiterQuestionOptionEn =
    "Can this be served without '{item}', so there is no {subject} in it?";

/// [waiterQuestionOptionEn] in Hebrew.
const String waiterQuestionOptionHe =
    "אפשר להגיש את המנה בלי '{item}', כדי שלא יהיה בה {subject}?";

/// For words that usually or sometimes carry the restriction, a hidden
/// source above all ("soy sauce" → wheat, "marinated" → soy); `{item}` is
/// the words as the menu printed them.
const String waiterQuestionCarrierEn =
    "The menu says '{item}': does it contain {subject}?";

/// [waiterQuestionCarrierEn] in Hebrew.
const String waiterQuestionCarrierHe =
    "בתפריט כתוב '{item}' — האם יש בזה {subject}?";

/// For an ingredient the model read in the dish, not words of the menu,
/// that may carry the restriction; `{item}` is the ingredient as the model
/// named it.
const String waiterQuestionIngredientEn =
    "Is there '{item}' in this dish, and does it contain {subject}?";

/// [waiterQuestionIngredientEn] in Hebrew.
const String waiterQuestionIngredientHe =
    "האם יש במנה '{item}', והאם יש בזה {subject}?";

/// For a concern with no words to quote.
const String waiterQuestionGeneralEn =
    'Does this dish contain {subject}, even in a sauce, a dressing or a '
    'garnish?';

/// [waiterQuestionGeneralEn] in Hebrew.
const String waiterQuestionGeneralHe =
    'האם יש במנה {subject}, גם ברוטב או בתוספת?';

/// The most characters of matched text a question quotes; a longer slice
/// is a sentence, not an ingredient, and the general question is used.
const int _maxQuotedLength = 40;

/// Composes and fills waiter questions; see the library comment.
abstract final class WaiterQuestions {
  /// [concerns] with every missing or blank [Concern.waiterQuestion]
  /// filled by [questionFor] in Hebrew when [hebrew], else English. A
  /// question already there is kept. The order and every other field are
  /// unchanged. Pure; never throws.
  static List<Concern> fill(List<Concern> concerns, {required bool hebrew}) =>
      List<Concern>.unmodifiable(<Concern>[
        for (final concern in concerns)
          if (concern.waiterQuestion?.trim().isNotEmpty ?? false)
            concern
          else
            Concern(
              restrictionId: concern.restrictionId,
              source: concern.source,
              certainty: concern.certainty,
              tier: concern.tier,
              matchedText: concern.matchedText,
              waiterQuestion: questionFor(concern, hebrew: hebrew),
            ),
      ]);

  /// The question that would settle [concern], in Hebrew when [hebrew].
  ///
  /// By source and certainty, with `{subject}` the restriction as the
  /// thing avoided ([subject]) and `{item}` the menu's own words:
  ///
  /// * an option value, stated or likely → "Can this be served without
  ///   '{item}', so there is no {subject} in it?";
  /// * stated in the name, the description or the model's ingredients →
  ///   "Can this be made without {subject}?";
  /// * a likely or suspected ingredient the model read → "Is there
  ///   '{item}' in this dish, and does it contain {subject}?";
  /// * a hidden source, or a likely or suspected finding anywhere else
  ///   → "The menu says '{item}': does it contain {subject}?";
  /// * with no words to quote, or words that are only the restriction's
  ///   own name (a guarded "sesame-free" lowered to suspected) → "Does
  ///   this dish contain {subject}, even in a sauce, a dressing or a
  ///   garnish?".
  static String questionFor(Concern concern, {required bool hebrew}) {
    final subjectText = subject(concern.restrictionId, hebrew: hebrew);
    final quotable = _quotable(concern.matchedText);
    final item =
        quotable != null &&
            quotable.toLowerCase() != subjectText.toLowerCase() &&
            quotable.toLowerCase() !=
                subject(concern.restrictionId, hebrew: !hebrew).toLowerCase()
        ? quotable
        : null;
    final String template;
    if (item != null &&
        concern.source == ConcernSource.option &&
        concern.certainty != Certainty.suspected) {
      template = hebrew ? waiterQuestionOptionHe : waiterQuestionOptionEn;
    } else if (concern.certainty == Certainty.stated &&
        concern.source != ConcernSource.hidden) {
      template = hebrew ? waiterQuestionWithoutHe : waiterQuestionWithoutEn;
    } else if (item != null && concern.source == ConcernSource.model) {
      template = hebrew
          ? waiterQuestionIngredientHe
          : waiterQuestionIngredientEn;
    } else if (item != null) {
      template = hebrew ? waiterQuestionCarrierHe : waiterQuestionCarrierEn;
    } else {
      template = hebrew ? waiterQuestionGeneralHe : waiterQuestionGeneralEn;
    }
    return template
        .replaceAll('{subject}', subjectText)
        .replaceAll('{item}', item ?? '');
  }

  /// [id] as the thing a dish must not contain, in Hebrew when [hebrew]:
  /// the restriction's own name for an allergen, celiac disease or an
  /// intolerance (lower-cased in English), and what the diet leaves out
  /// for vegan, vegetarian and keto, whose names are not ingredients.
  static String subject(RestrictionId id, {required bool hebrew}) {
    switch (id) {
      case RestrictionId.vegan:
        return hebrew
            ? 'מוצרים מן החי (בשר, דגים, חלב, ביצים או דבש)'
            : 'animal products (meat, fish, dairy, eggs or honey)';
      case RestrictionId.vegetarian:
        return hebrew ? 'בשר, עוף או דגים' : 'meat, poultry or fish';
      case RestrictionId.keto:
        return hebrew ? 'סוכר או קמח' : 'sugar or flour';
      case RestrictionId.peanuts:
      case RestrictionId.treeNuts:
      case RestrictionId.milk:
      case RestrictionId.lactose:
      case RestrictionId.eggs:
      case RestrictionId.soy:
      case RestrictionId.wheat:
      case RestrictionId.gluten:
      case RestrictionId.fish:
      case RestrictionId.crustaceans:
      case RestrictionId.molluscs:
      case RestrictionId.sesame:
      case RestrictionId.celery:
      case RestrictionId.mustard:
      case RestrictionId.lupin:
      case RestrictionId.sulphites:
      case RestrictionId.legumes:
        final restriction = restrictionFor(id);
        return hebrew ? restriction.nameHe : restriction.nameEn.toLowerCase();
    }
  }

  /// [matched] trimmed, when it is short enough to quote as the menu's
  /// own words; null otherwise.
  static String? _quotable(String? matched) {
    final item = matched?.trim();
    if (item == null || item.isEmpty || item.length > _maxQuotedLength) {
      return null;
    }
    return item;
  }
}

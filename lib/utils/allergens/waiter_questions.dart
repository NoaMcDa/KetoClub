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
import 'package:ketoclub/utils/allergens/allergen_matcher.dart';
import 'package:ketoclub/utils/allergens/taxonomy.dart';
import 'package:ketoclub/utils/allergens/vocab_religious.dart';
import 'package:ketoclub/utils/classification_rules.dart';

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

/// The opening of every heads-up question (ALG-17: FODMAP, histamine and
/// small portions), which names what the person goes easy on; `{subject}`
/// is [WaiterQuestions.subject].
const String waiterQuestionHeadsUpEn = 'I go easy on {subject}.';

/// [waiterQuestionHeadsUpEn] in Hebrew; the subject takes the preposition
/// ב, attached.
const String waiterQuestionHeadsUpHe = 'אני ממעיט/ה ב{subject}.';

/// For a dose sensitivity (FODMAP, histamine) with the menu's words to
/// quote, after [waiterQuestionHeadsUpEn].
const String waiterQuestionLessOfItemEn =
    "The menu says '{item}': can this be made with less of it?";

/// [waiterQuestionLessOfItemEn] in Hebrew.
const String waiterQuestionLessOfItemHe =
    "בתפריט כתוב '{item}' — אפשר להכין את המנה עם פחות מזה?";

/// For a dose sensitivity with no words to quote.
const String waiterQuestionLessEn =
    'Is there any in this dish, and can it be made with less?';

/// [waiterQuestionLessEn] in Hebrew.
const String waiterQuestionLessHe = 'יש כאלה במנה, ואפשר להכין אותה עם פחות?';

/// For small portions (GLP-1) with the menu's words to quote.
const String waiterQuestionSmallerItemEn =
    "The menu says '{item}': is there a smaller or lighter version of this "
    'dish?';

/// [waiterQuestionSmallerItemEn] in Hebrew.
const String waiterQuestionSmallerItemHe =
    "בתפריט כתוב '{item}' — יש גרסה קטנה או קלה יותר של המנה?";

/// For small portions with no words to quote.
const String waiterQuestionSmallerEn =
    'Is there a smaller or lighter version of this dish?';

/// [waiterQuestionSmallerEn] in Hebrew.
const String waiterQuestionSmallerHe = 'יש גרסה קטנה או קלה יותר של המנה?';

/// For kosher's meat with dairy (issue #342) when both are stated in the
/// dish; `{item}` is the dairy words as the menu printed them.
const String waiterQuestionMeatDairyWithoutEn =
    "Can this be made without the '{item}', so there is no dairy with the "
    'meat?';

/// [waiterQuestionMeatDairyWithoutEn] in Hebrew.
const String waiterQuestionMeatDairyWithoutHe =
    "אפשר להכין את המנה בלי '{item}', כדי שלא יהיה בה בשר עם חלב?";

/// For meat with dairy where the dairy is only likely (a sauce that is
/// usually made with butter or cream).
const String waiterQuestionMeatDairyAskEn =
    'Is there any dairy (butter, cream, cheese) in this meat dish?';

/// [waiterQuestionMeatDairyAskEn] in Hebrew.
const String waiterQuestionMeatDairyAskHe =
    'יש במנה הבשרית הזו מוצרי חלב (חמאה, שמנת, גבינה)?';

/// For meat with dairy where one of them is only an option; `{meat}` and
/// `{dairy}` are the menu's words. It offers to leave one off.
const String waiterQuestionMeatDairyOptionEn =
    "This dish has '{meat}' and '{dairy}': can one of them be left off, so "
    'there is no meat with dairy?';

/// [waiterQuestionMeatDairyOptionEn] in Hebrew.
const String waiterQuestionMeatDairyOptionHe =
    "במנה יש '{meat}' וגם '{dairy}' — אפשר לוותר על אחד מהם, כדי שלא יהיה "
    'בה בשר עם חלב?';

/// For oral allergy syndrome (issue #342) with the menu's words to quote:
/// raw fruit and vegetables are the trouble, and cooked ones usually are
/// not, so it asks whether the item is raw and can be cooked.
const String waiterQuestionCookedItemEn =
    "The menu says '{item}': is it raw, and can it be served cooked?";

/// [waiterQuestionCookedItemEn] in Hebrew.
const String waiterQuestionCookedItemHe =
    "בתפריט כתוב '{item}' — זה לא מבושל, ואפשר להגיש את זה מבושל?";

/// For oral allergy syndrome with no words to quote.
const String waiterQuestionCookedEn =
    'Is any of it raw in this dish, and can it be served cooked?';

/// [waiterQuestionCookedEn] in Hebrew.
const String waiterQuestionCookedHe =
    'יש כאלה במנה שאינם מבושלים, ואפשר להגיש אותם מבושלים?';

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
  ///
  /// Two kinds of restriction ask their own way (ALG-17). A heads-up
  /// restriction ([headsUpRestrictions]) never asks for a dish "without"
  /// something: FODMAP and histamine ask for less of it, small portions for
  /// a smaller or lighter version, each after "I go easy on {subject}."
  /// Kosher and halal (issue #342) name the component the concern's words
  /// are ([componentSubject]: "Can this be made without pork?"), and
  /// kosher's meat with dairy asks its own way
  /// ([ClassificationRules.isMeatWithDairy]).
  /// The user's own restriction ([RestrictionId.custom]) names their own
  /// word as the subject — [ownWord] when given (the evaluator passes the
  /// word as the user wrote it, so "ובכוסברה" on the menu still reads
  /// "בלי כוסברה"), else the matched text — so "kiwi" reads "Can this be
  /// made without kiwi?".
  static String questionFor(
    Concern concern, {
    required bool hebrew,
    String? ownWord,
  }) {
    final id = concern.restrictionId;
    if (headsUpRestrictions.contains(id)) {
      return _headsUpQuestion(concern, hebrew: hebrew);
    }
    final meatWithDairy = ClassificationRules.meatWithDairyParts(concern);
    if (meatWithDairy != null) {
      return _meatWithDairyQuestion(concern, meatWithDairy, hebrew: hebrew);
    }
    final subjectText = switch (id) {
      RestrictionId.custom =>
        _quotable(ownWord) ??
            _quotable(concern.matchedText) ??
            subject(id, hebrew: hebrew),
      RestrictionId.kosher || RestrictionId.halal =>
        componentSubject(concern.matchedText, hebrew: hebrew) ??
            subject(id, hebrew: hebrew),
      _ => subject(id, hebrew: hebrew),
    };
    final quotable = _quotable(concern.matchedText);
    final item =
        quotable != null &&
            quotable.toLowerCase() != subjectText.toLowerCase() &&
            quotable.toLowerCase() != subject(id, hebrew: !hebrew).toLowerCase()
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

  /// The question for kosher's meat with dairy (issue #342): with an
  /// option on one side, whether one of them can be left off; with both
  /// stated in the dish, whether it can be made without the dairy; else
  /// whether there is dairy in the meat dish. Never says "kosher".
  static String _meatWithDairyQuestion(
    Concern concern,
    ({String meat, String dairy}) parts, {
    required bool hebrew,
  }) {
    final meat = _quotable(parts.meat);
    final dairy = _quotable(parts.dairy);
    if (concern.source == ConcernSource.option &&
        meat != null &&
        dairy != null) {
      return (hebrew
              ? waiterQuestionMeatDairyOptionHe
              : waiterQuestionMeatDairyOptionEn)
          .replaceAll('{meat}', meat)
          .replaceAll('{dairy}', dairy);
    }
    if (concern.certainty == Certainty.stated && dairy != null) {
      return (hebrew
              ? waiterQuestionMeatDairyWithoutHe
              : waiterQuestionMeatDairyWithoutEn)
          .replaceAll('{item}', dairy);
    }
    return hebrew ? waiterQuestionMeatDairyAskHe : waiterQuestionMeatDairyAskEn;
  }

  /// The component a kosher or halal concern's [matched] words name
  /// ([religiousComponents]: pork, shellfish, alcohol …), in Hebrew when
  /// [hebrew]: the first component whose words the matcher finds in them.
  /// Null when none does (a model's own concern may quote anything).
  static String? componentSubject(String? matched, {required bool hebrew}) {
    final text = matched?.trim() ?? '';
    if (text.isEmpty) return null;
    for (final component in religiousComponents) {
      if (AllergenMatcher.findWith(text, component.vocabulary).isNotEmpty) {
        return hebrew ? component.subjectHe : component.subjectEn;
      }
    }
    return null;
  }

  /// The question for a heads-up restriction (ALG-17): "I go easy on
  /// {subject}." then, for small portions, "is there a smaller or lighter
  /// version?", for oral allergy syndrome (issue #342) "is it raw, and can
  /// it be served cooked?", and for the dose sensitivities (FODMAP,
  /// histamine, nightshades, MSG, caffeine, salicylates) "can this be made
  /// with less of it?", quoting the menu's words when there are some to
  /// quote.
  static String _headsUpQuestion(Concern concern, {required bool hebrew}) {
    final id = concern.restrictionId;
    final item = _quotable(concern.matchedText);
    final smaller = id == RestrictionId.glp1;
    final String ask;
    if (id == RestrictionId.oralAllergy) {
      ask = item == null
          ? (hebrew ? waiterQuestionCookedHe : waiterQuestionCookedEn)
          : (hebrew ? waiterQuestionCookedItemHe : waiterQuestionCookedItemEn);
    } else if (smaller) {
      ask = item == null
          ? (hebrew ? waiterQuestionSmallerHe : waiterQuestionSmallerEn)
          : (hebrew
                ? waiterQuestionSmallerItemHe
                : waiterQuestionSmallerItemEn);
    } else {
      ask = item == null
          ? (hebrew ? waiterQuestionLessHe : waiterQuestionLessEn)
          : (hebrew ? waiterQuestionLessOfItemHe : waiterQuestionLessOfItemEn);
    }
    final opening = (hebrew ? waiterQuestionHeadsUpHe : waiterQuestionHeadsUpEn)
        .replaceAll('{subject}', subject(id, hebrew: hebrew));
    return '$opening ${ask.replaceAll('{item}', item ?? '')}';
  }

  /// [id] as the thing a dish must not contain, in Hebrew when [hebrew]:
  /// the restriction's own name for an allergen, celiac disease or an
  /// intolerance (lower-cased in English), and what the diet leaves out
  /// for vegan, vegetarian, keto and the issue #342 diets (pescatarian,
  /// paleo, Whole30, AIP, Jain), whose names are not ingredients.
  ///
  /// Issue #342: fava names the beans (its name carries "favism", a
  /// condition, not a food); the heads-up sensitivities name the foods
  /// that carry them, as FODMAP and histamine do.
  ///
  /// ALG-17: alpha-gal names the class of foods (its name is a sugar no
  /// menu prints); FODMAP, histamine and small portions name what the
  /// person goes easy on; the user's own restriction, whose words are in
  /// the profile and not here, reads "the foods I listed" (a concern of it
  /// quotes its own words instead, in [questionFor]).
  ///
  /// Kosher and halal (issue #342) name their components, never the
  /// restriction: a question asks about pork or alcohol, not about
  /// "kosher", which no waiter's answer about one dish can settle. A
  /// concern of theirs names the one component its words are
  /// ([componentSubject]) in [questionFor].
  static String subject(RestrictionId id, {required bool hebrew}) {
    switch (id) {
      case RestrictionId.alphaGal:
        return hebrew
            ? "בשר יונקים או מוצריו (בקר, כבש, חזיר, ג'לטין או שומן מן החי)"
            : 'mammal meat or its products (beef, lamb, pork, gelatin or '
                  'lard)';
      case RestrictionId.fodmap:
        return hebrew
            ? 'בצל, שום ומזונות עתירי פודמאפ'
            : 'onion, garlic and other high-FODMAP foods';
      case RestrictionId.histamine:
        return hebrew
            ? 'מזונות מיושנים, מעושנים, כבושים או מותססים'
            : 'aged, smoked, pickled or fermented foods';
      case RestrictionId.glp1:
        return hebrew
            ? 'מנות גדולות ומזון מטוגן, שמנתי או מתוק מאוד'
            : 'large portions and fried, creamy or very sweet food';
      case RestrictionId.custom:
        return hebrew ? 'המזונות שציינתי' : 'the foods I listed';
      case RestrictionId.fava:
        return hebrew ? 'פול' : 'fava beans (broad beans)';
      case RestrictionId.nightshades:
        return hebrew
            ? 'עגבנייה, תפוח אדמה, חציל ופלפלים'
            : 'tomato, potato, aubergine and peppers';
      case RestrictionId.msg:
        return hebrew
            ? 'מונוסודיום גלוטמט (MSG) ואבקות מרק'
            : 'MSG (monosodium glutamate) and stock powders';
      case RestrictionId.caffeine:
        return hebrew
            ? 'קפה, תה, קולה ומקורות קפאין אחרים'
            : 'coffee, tea, cola and other caffeine';
      case RestrictionId.salicylates:
        return hebrew
            ? 'מזון מתובל מאוד, עשבי תיבול, עגבניות, פירות יער ומזונות '
                  'עתירי סליצילטים'
            : 'spices, herbs, tomato, berries and other high-salicylate '
                  'foods';
      case RestrictionId.oralAllergy:
        return hebrew
            ? 'פירות וירקות לא מבושלים'
            : 'raw fruit and raw vegetables';
      case RestrictionId.pescatarian:
        return hebrew ? 'בשר או עוף' : 'meat or poultry';
      case RestrictionId.paleo:
        return hebrew
            ? 'דגנים, קטניות, מוצרי חלב או סוכר מעובד'
            : 'grains, legumes, dairy or refined sugar';
      case RestrictionId.whole30:
        return hebrew
            ? 'סוכר, דגנים, קטניות, מוצרי חלב או אלכוהול'
            : 'sugar, grains, legumes, dairy or alcohol';
      case RestrictionId.aip:
        return hebrew
            ? 'דגנים, קטניות, מוצרי חלב, ביצים, אגוזים, זרעים או סולניים'
            : 'grains, legumes, dairy, eggs, nuts, seeds or nightshades';
      case RestrictionId.jain:
        return hebrew
            ? 'בשר, דגים, ביצים, דבש, בצל, שום או ירקות שורש'
            : 'meat, fish, eggs, honey, onion, garlic or root vegetables';
      case RestrictionId.vegan:
        return hebrew
            ? 'מוצרים מן החי (בשר, דגים, חלב, ביצים או דבש)'
            : 'animal products (meat, fish, dairy, eggs or honey)';
      case RestrictionId.vegetarian:
        return hebrew ? 'בשר, עוף או דגים' : 'meat, poultry or fish';
      case RestrictionId.keto:
        return hebrew ? 'סוכר או קמח' : 'sugar or flour';
      case RestrictionId.kosher:
        return hebrew
            ? 'חזיר, פירות ים או בשר עם חלב'
            : 'pork, shellfish or meat with dairy';
      case RestrictionId.halal:
        return hebrew ? "חזיר, אלכוהול או ג'לטין" : 'pork, alcohol or gelatin';
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
      case RestrictionId.buckwheat:
      case RestrictionId.kiwi:
      case RestrictionId.peach:
      case RestrictionId.apple:
      case RestrictionId.banana:
      case RestrictionId.orange:
      case RestrictionId.beef:
      case RestrictionId.pork:
      case RestrictionId.chicken:
      case RestrictionId.gelatin:
      case RestrictionId.yam:
      case RestrictionId.corn:
      case RestrictionId.sunflower:
      case RestrictionId.flax:
      case RestrictionId.chickpea:
      case RestrictionId.lentil:
      case RestrictionId.pea:
      case RestrictionId.fenugreek:
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

/// The on-device profile evaluator (Banto; ALG-04b, related to #346;
/// architecture.md D26).
///
/// [ProfileEvaluator.evaluate] turns one analysed dish, the dish itself
/// and the user's [DietaryProfile] into an [EvaluatedDish]: the concerns
/// that matter to this profile and one of four [DishState]s. It runs only
/// on the device, because the profile never leaves it (D26 C1): the
/// server and the model find every restriction for everyone, and this is
/// where the profile chooses among them.
///
/// The wire verdict ([AnalysedDish.verdict]) is never rewritten; the state
/// sits beside it, and with an empty profile it is today's verdict mapped
/// one to one (orderAsIs → fits, modifiable → fitsWithChange, nonKeto →
/// avoid) with today's waiter script, so a keto-only user sees nothing
/// new.
///
/// The "ask for it without …" sentences are written here, in English and
/// Hebrew, rather than in ARB, for the reason the keto waiter templates
/// live in `constants.dart` (architecture.md §6.3, §12): they are read to a
/// waiter in the menu's language, not the UI's. No sentence here, and no
/// state, ever says a dish is safe (file 09 §6).
library;

import 'package:flutter/foundation.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/concern.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/utils/allergens/allergen_matcher.dart';
import 'package:ketoclub/utils/allergens/custom_terms.dart';
import 'package:ketoclub/utils/allergens/declarations.dart';
import 'package:ketoclub/utils/allergens/taxonomy.dart';
import 'package:ketoclub/utils/allergens/waiter_questions.dart';
import 'package:ketoclub/utils/classification_rules.dart';
import 'package:ketoclub/utils/text_normaliser.dart';

/// The English waiter sentence for one removable item; `{item}` is the
/// item as the menu (or the model) wrote it, quoted in straight single
/// quotes so the waiter hears the menu's own words (ALG-05).
const String removeItemModificationEn = "Ask for it without '{item}'";

/// The Hebrew waiter sentence for one removable item; `{item}` as in
/// [removeItemModificationEn].
const String removeItemModificationHe = "לבקש את המנה בלי '{item}'";

/// The most words [ProfileEvaluator.quotedItem] lets an item grow to.
const int _maxQuotedWords = 3;

/// The Hebrew letter tav, the ending of a construct form ("גבינת").
const int _tav = 0x05EA;

/// The Hebrew maqaf, which joins a construct form to its noun.
const int _maqafUnit = 0x05BE;

/// Whether [unit] separates two words of a quoted item: a space, a tab,
/// a no-break space or the maqaf.
bool _isWordGap(int unit) =>
    unit == 0x20 || unit == 0x09 || unit == 0xA0 || unit == _maqafUnit;

/// Whether [unit] ends a quoted item: a comma, a full stop, a vertical
/// bar or a line break.
bool _isItemStop(int unit) =>
    unit == 0x2C ||
    unit == 0x2E ||
    unit == 0x7C ||
    unit == 0x0A ||
    unit == 0x0D;

/// Whether [unit] is a Hebrew point or cantillation mark (not the maqaf),
/// which may follow a word's last letter.
bool _isHebrewMark(int unit) =>
    unit >= 0x0591 && unit <= 0x05C7 && unit != _maqafUnit;

/// Whether [text]'s last letter, past any Hebrew points, is a tav.
bool _endsInTav(String text) {
  for (var i = text.length - 1; i >= 0; i--) {
    final unit = text.codeUnitAt(i);
    if (_isHebrewMark(unit)) continue;
    return unit == _tav;
  }
  return false;
}

/// What a dish is for one profile (ALG-05), derived on the device.
///
/// The order is the order of severity: a later value outranks an earlier
/// one when several findings disagree.
enum DishState {
  /// Nothing in the profile was found, and keto (when in the profile) is
  /// satisfied. Never "safe": the menu text is all the app read.
  fits,

  /// Fits once something removable is left off, or a keto change is made.
  fitsWithChange,

  /// A strict entry has a suspected finding: ask the restaurant.
  ask,

  /// A stated or likely finding sits in the dish itself, or keto (when in
  /// the profile) rules it out.
  avoid,
}

/// One dish as one profile sees it (ALG-04b).
@immutable
final class EvaluatedDish {
  /// Creates the evaluation of [dish].
  const new({
    required this.dish,
    required this.concerns,
    required this.state,
    this.modification,
    this.declarations = const <Declaration>[],
  });

  /// The analysed dish, wire verdict untouched.
  final AnalysedDish dish;

  /// The concerns for the profile's restrictions, keto excluded and the
  /// entries' exceptions applied, one per restriction in taxonomy order.
  final List<Concern> concerns;

  /// The derived state.
  final DishState state;

  /// The waiter script for this profile, one instruction per line, in the
  /// menu's language: keto's script (when keto applies) then one "without"
  /// sentence per removable item. Null when nothing is to be changed, and
  /// always null for [DishState.avoid].
  final String? modification;

  /// The declarations that lowered or cleared one of the profile's
  /// concerns (ALG-09), in the order read: what the Why sheet quotes for a
  /// concern at [EvidenceTier.declared]. Empty when none applied.
  final List<Declaration> declarations;

  @override
  bool operator ==(Object other) =>
      other is EvaluatedDish &&
      other.dish == dish &&
      listEquals(other.concerns, concerns) &&
      other.state == state &&
      other.modification == modification &&
      listEquals(other.declarations, declarations);

  @override
  int get hashCode => Object.hash(
    dish,
    Object.hashAll(concerns),
    state,
    modification,
    Object.hashAll(declarations),
  );

  @override
  String toString() =>
      'EvaluatedDish(${dish.dishId}: ${state.name}, '
      '${concerns.length} concerns)';
}

/// One piece of evidence: a concern, whether what it names can be left
/// off the dish, and the words a "without" sentence would use.
typedef _Evidence = ({Concern concern, bool removable, String? item});

/// The roles a diner can leave off or swap (ALG-03).
const Set<ComponentRole> _removableRoles = <ComponentRole>{
  ComponentRole.side,
  ComponentRole.sauce,
  ComponentRole.garnish,
  ComponentRole.option,
};

/// The weaker of two certainties (stated > likely > suspected).
Certainty _weaker(Certainty a, Certainty b) => a.index >= b.index ? a : b;

/// Whether [certainty] is stated or likely: strong enough to act on.
bool _isFirm(Certainty certainty) => certainty != Certainty.suspected;

/// Evaluates analysed dishes against a dietary profile (ALG-04b).
abstract final class ProfileEvaluator {
  /// Evaluates [analysed], the analysis of [dish], for [profile], with
  /// sentences in Hebrew when [hebrew] is true and English when false;
  /// when null, in the language of the dish's own text (§12), as the rule
  /// engine chooses it. Pure; never throws.
  ///
  /// 1. **Concerns** are the union of the rule engine's findings over
  ///    [dish] ([ClassificationRules.allergenFindings], whatever the
  ///    analysis carried), the concerns on [analysed], and those read
  ///    from [AnalysedDish.ingredients] by [AllergenMatcher.find] on each
  ///    name (source [ConcernSource.model], certainty the weaker of the
  ///    ingredient's and the trigger's, the ingredient's role carried).
  ///    The user's own words ([DietaryProfile.customTerms], ALG-17) are
  ///    read by the same two passes over a vocabulary of those words alone
  ///    ([customTermVocabulary]), on the device only (D26 C1).
  /// 2. Only the profile's restrictions are kept; keto is never a concern
  ///    (it stays the wire verdict), and a concern whose matched text
  ///    contains one of its entry's exceptions as whole words is dropped.
  /// 3. **State**, worst first: a stated or likely concern on a part that
  ///    cannot be left off (a base, a protein, an unknown role; the name,
  ///    the description or a hidden source) → [DishState.avoid], as is a
  ///    `nonKeto` verdict when the profile holds keto; a suspected concern
  ///    on a strict restriction (an allergen or celiac) → [DishState.ask];
  ///    a stated or likely concern only on removable parts (a side, a
  ///    sauce, a garnish, an option), or a `modifiable` verdict when the
  ///    profile holds keto → [DishState.fitsWithChange]; otherwise
  ///    [DishState.fits]. A suspected concern on a flexible restriction is
  ///    listed but moves nothing, and a heads-up restriction's
  ///    ([headsUpRestrictions]: FODMAP, histamine, small portions) concern
  ///    is always suspected ([_headsUp]), so none of them ever moves a
  ///    dish (ALG-17).
  ///
  /// Between 2 and 3, **declarations** (ALG-09; [Declarations.of] over
  /// the dish's declared tags, its own text and its category [heading])
  /// lower the concerns they declare absent: see [_applyDeclarations].
  /// Every kept concern carries a waiter question in the same language
  /// ([WaiterQuestions.fill], ALG-08b): the model's own when it wrote one.
  ///
  /// An empty profile holds keto: it is the keto-only user of today's
  /// app, and the result is the identity mapping of the wire verdict.
  static EvaluatedDish evaluate(
    AnalysedDish analysed,
    Dish dish,
    DietaryProfile profile, {
    bool? hebrew,
    String? heading,
  }) {
    final hasKeto = profile.isEmpty || profile.contains(RestrictionId.keto);
    final isHebrew =
        hebrew ??
        TextNormaliser.containsHebrew(TextNormaliser.dishRulesText(dish));

    final (:evidence, :declarations) = _applyDeclarations(<_Evidence>[
      for (final evidence in _evidence(analysed, dish, profile.customTerms))
        if (_applies(evidence.concern, profile)) _headsUp(evidence),
    ], Declarations.of(dish, heading: heading));

    var avoid = hasKeto && analysed.verdict == DishVerdict.nonKeto;
    var ask = false;
    final items = <String>[];
    for (final (:concern, :removable, :item) in evidence) {
      final firm = _isFirm(concern.certainty);
      if (firm && !removable) {
        avoid = true;
      } else if (firm) {
        if (item != null && !items.contains(item)) items.add(item);
      } else if (restrictionFor(concern.restrictionId).isStrict) {
        ask = true;
      }
    }

    final ketoChange = hasKeto && analysed.verdict == DishVerdict.modifiable
        ? analysed.modification
        : null;
    final template = isHebrew
        ? removeItemModificationHe
        : removeItemModificationEn;
    final lines = <String>[
      ?ketoChange,
      for (final item in _withoutCovered(items))
        template.replaceAll('{item}', item),
    ];
    final change = lines.isEmpty ? null : lines.join('\n');

    final DishState state;
    if (avoid) {
      state = DishState.avoid;
    } else if (ask) {
      state = DishState.ask;
    } else if (change != null) {
      state = DishState.fitsWithChange;
    } else {
      state = DishState.fits;
    }
    return EvaluatedDish(
      dish: analysed,
      concerns: WaiterQuestions.fill(
        _askOwnWords(
          _onePerRestriction(evidence),
          profile.customTerms,
          hebrew: isHebrew,
        ),
        hebrew: isHebrew,
      ),
      state: state,
      modification: state == DishState.avoid ? null : change,
      declarations: declarations,
    );
  }

  /// [evidence] after the dish's [declarations] (ALG-09; file 09: a
  /// declaration never clears a strict entry). For each restriction some
  /// [DeclarationPolarity.absent] declaration names, every concern about
  /// it is lowered by one step, once however many declarations name it
  /// (stated → likely → suspected) and moved to [EvidenceTier.declared];
  /// a suspected concern stays suspected for a strict entry and is
  /// cleared for a flexible one. A declaration with no matching concern
  /// adds nothing, and a [DeclarationPolarity.present] one changes
  /// nothing here (the matcher already reads a "contains" phrase).
  /// Returns the lowered evidence and the declarations that touched it.
  static ({List<_Evidence> evidence, List<Declaration> declarations})
  _applyDeclarations(List<_Evidence> evidence, List<Declaration> declarations) {
    final absent = <RestrictionId>{
      for (final declaration in declarations)
        if (declaration.polarity == DeclarationPolarity.absent)
          ...declaration.restrictionIds,
    };
    final touched = <RestrictionId>{
      for (final item in evidence)
        if (absent.contains(item.concern.restrictionId))
          item.concern.restrictionId,
    };
    if (touched.isEmpty) {
      return (evidence: evidence, declarations: const <Declaration>[]);
    }
    final lowered = <_Evidence>[];
    for (final item in evidence) {
      final concern = item.concern;
      if (!touched.contains(concern.restrictionId)) {
        lowered.add(item);
        continue;
      }
      final strict = restrictionFor(concern.restrictionId).isStrict;
      final Certainty certainty;
      switch (concern.certainty) {
        case Certainty.stated:
          certainty = Certainty.likely;
        case Certainty.likely:
          certainty = Certainty.suspected;
        case Certainty.suspected:
          if (!strict) continue;
          certainty = Certainty.suspected;
      }
      lowered.add((
        concern: Concern(
          restrictionId: concern.restrictionId,
          source: concern.source,
          certainty: certainty,
          tier: EvidenceTier.declared,
          matchedText: concern.matchedText,
          waiterQuestion: concern.waiterQuestion,
        ),
        removable: item.removable,
        item: item.item,
      ));
    }
    return (
      evidence: lowered,
      declarations: List<Declaration>.unmodifiable(<Declaration>[
        for (final declaration in declarations)
          if (declaration.polarity == DeclarationPolarity.absent &&
              declaration.restrictionIds.any(touched.contains))
            declaration,
      ]),
    );
  }

  /// The words a "without" sentence quotes for [matched], a slice the
  /// matcher found in [field], as the menu printed them (ALG-05).
  ///
  /// The item is [matched] itself, except when its last word is a Hebrew
  /// construct form (the slice ends in ת, "גבינת") and [field] continues
  /// with another word: then it runs through that one word ("גבינת
  /// שמנת"), as long as the item stays at most three words, and never past
  /// a comma, a full stop, `|`, a line break or the end of [field]. A
  /// [matched] that [field] does not contain is returned trimmed. Pure;
  /// never throws.
  static String quotedItem(String field, String matched) {
    final item = matched.trim();
    final start = item.isEmpty ? -1 : field.indexOf(item);
    if (start < 0) return item;
    final words = item.split(RegExp(r'[\s\u05BE]+')).length;
    if (words >= _maxQuotedWords || !_endsInTav(item)) return item;
    var cursor = start + item.length;
    if (cursor >= field.length || !_isWordGap(field.codeUnitAt(cursor))) {
      return item;
    }
    while (cursor < field.length && _isWordGap(field.codeUnitAt(cursor))) {
      cursor++;
    }
    final wordStart = cursor;
    while (cursor < field.length) {
      final unit = field.codeUnitAt(cursor);
      if (_isWordGap(unit) || _isItemStop(unit)) break;
      cursor++;
    }
    if (cursor == wordStart) return item;
    return field.substring(start, cursor);
  }

  /// [concerns] with each of the user's own concerns (ALG-17) given the
  /// question that names their word as they wrote it ("כוסברה" for a
  /// menu's "ובכוסברה"), read back from [customTerms]' vocabulary; a
  /// question already there is kept, and every other concern is returned
  /// as it is.
  static List<Concern> _askOwnWords(
    List<Concern> concerns,
    List<String> customTerms, {
    required bool hebrew,
  }) {
    if (customTerms.isEmpty) return concerns;
    final own = customTermVocabulary(customTerms);
    return <Concern>[
      for (final concern in concerns)
        if (concern.restrictionId != RestrictionId.custom ||
            (concern.waiterQuestion?.trim().isNotEmpty ?? false))
          concern
        else
          Concern(
            restrictionId: concern.restrictionId,
            source: concern.source,
            certainty: concern.certainty,
            tier: concern.tier,
            matchedText: concern.matchedText,
            waiterQuestion: WaiterQuestions.questionFor(
              concern,
              hebrew: hebrew,
              ownWord: AllergenMatcher.findWith(
                concern.matchedText ?? '',
                own,
              ).firstOrNull?.term,
            ),
          ),
    ];
  }

  /// [evidence] as a heads-up when its restriction is one
  /// ([headsUpRestrictions], ALG-17): FODMAP, histamine and small portions
  /// depend on a dose no menu states, so a finding of theirs is lowered to
  /// [Certainty.suspected] ("may be high in …"), which a flexible entry
  /// lists and lets move nothing. Its tier, source and words are kept:
  /// the onion is still stated on the menu. Every other concern is
  /// returned as it is.
  static _Evidence _headsUp(_Evidence evidence) {
    final concern = evidence.concern;
    if (!headsUpRestrictions.contains(concern.restrictionId) ||
        concern.certainty == Certainty.suspected) {
      return evidence;
    }
    return (
      concern: Concern(
        restrictionId: concern.restrictionId,
        source: concern.source,
        certainty: Certainty.suspected,
        tier: concern.tier,
        matchedText: concern.matchedText,
        waiterQuestion: concern.waiterQuestion,
      ),
      removable: evidence.removable,
      item: evidence.item,
    );
  }

  /// The key a concern is kept once under ([_onePerRestriction],
  /// `GroupEvaluator.combine`): its restriction, and for the user's own
  /// restriction ([RestrictionId.custom], ALG-17) also its words, so
  /// "kiwi" and "coriander" in one dish are two concerns, not one.
  static String concernKey(Concern concern) =>
      concern.restrictionId == RestrictionId.custom
      ? '${concern.restrictionId.name}:'
            '${AllergenMatcher.matchText(concern.matchedText ?? '')}'
      : concern.restrictionId.name;

  /// Every piece of evidence about [dish], whatever the profile: the rule
  /// engine's findings, the analysis's own concerns, then the concerns
  /// read from its ingredients. With [customTerms], the user's own words
  /// (ALG-17), the same two passes run once more over a vocabulary of
  /// those words alone ([customTermVocabulary]): on the device only.
  static List<_Evidence> _evidence(
    AnalysedDish analysed,
    Dish dish,
    List<String> customTerms,
  ) {
    final own = customTermVocabulary(customTerms);
    _Evidence ofConcern(Concern concern) {
      final removable = concern.source == ConcernSource.option;
      final matched = concern.matchedText;
      return (
        concern: concern,
        removable: removable,
        item: removable && matched != null ? _optionItem(dish, matched) : null,
      );
    }

    _Evidence ofIngredient(ExtractedIngredient ingredient, AllergenHit hit) => (
      concern: Concern(
        restrictionId: hit.id,
        source: ConcernSource.model,
        certainty: _weaker(
          ingredient.certainty,
          Certainty.values.byName(hit.certainty.name),
        ),
        tier:
            ingredient.certainty == Certainty.stated &&
                !hit.hidden &&
                !hit.guarded
            ? EvidenceTier.stated
            : EvidenceTier.inferred,
        matchedText: ingredient.name,
      ),
      removable: _removableRoles.contains(ingredient.role),
      item: ingredient.name,
    );

    return <_Evidence>[
      for (final concern in ClassificationRules.allergenFindings(dish))
        ofConcern(concern),
      for (final concern in analysed.concerns) ofConcern(concern),
      for (final ingredient in analysed.ingredients)
        for (final hit in AllergenMatcher.find(ingredient.name))
          ofIngredient(ingredient, hit),
      if (own.isNotEmpty) ...<_Evidence>[
        for (final concern in ClassificationRules.allergenFindings(
          dish,
          vocabulary: own,
        ))
          ofConcern(concern),
        for (final ingredient in analysed.ingredients)
          for (final hit in AllergenMatcher.findWith(ingredient.name, own))
            ofIngredient(ingredient, hit),
      ],
    ];
  }

  /// [matched], an option concern's slice, quoted from the first of
  /// [dish]'s option values that contains it ([quotedItem]); [matched]
  /// itself, trimmed, when none does.
  static String _optionItem(Dish dish, String matched) {
    for (final option in dish.options) {
      for (final value in option.values) {
        if (value.contains(matched)) return quotedItem(value, matched);
      }
    }
    return matched.trim();
  }

  /// [items] without any item that a longer one already quotes as whole
  /// words ("שמנת" inside "גבינת שמנת"), in their first order.
  static List<String> _withoutCovered(List<String> items) => <String>[
    for (final item in items)
      if (!items.any(
        (other) =>
            other.length > item.length &&
            RegExp('(^|[\\s\\u05BE])${RegExp.escape(item)}(\$|[\\s\\u05BE])')
                .hasMatch(other),
      ))
        item,
  ];

  /// Whether [concern] is about a restriction [profile] holds, other than
  /// keto, and none of that entry's exceptions covers it.
  static bool _applies(Concern concern, DietaryProfile profile) {
    if (concern.restrictionId == RestrictionId.keto) return false;
    final entry = profile.entryFor(concern.restrictionId);
    if (entry == null) return false;
    final text = concern.matchedText;
    if (text == null) return true;
    final haystack = AllergenMatcher.matchText(text);
    for (final exception in entry.exceptions) {
      final phrase = AllergenMatcher.matchText(exception);
      if (phrase.isEmpty) continue;
      final pattern = TextNormaliser.containsHebrew(phrase)
          ? hebrewTriggerPattern(phrase)
          : latinTriggerPattern(phrase);
      if (pattern.hasMatch(haystack)) return false;
    }
    return true;
  }

  /// [evidence] reduced to one concern per restriction ([concernKey]: per
  /// word for the user's own), in taxonomy order: the surest, and at a tie
  /// the one that cannot be left off, then the earliest.
  static List<Concern> _onePerRestriction(List<_Evidence> evidence) {
    final best = <String, _Evidence>{};
    for (final candidate in evidence) {
      final key = concernKey(candidate.concern);
      final kept = best[key];
      if (kept == null || _outranks(candidate, kept)) best[key] = candidate;
    }
    return List<Concern>.unmodifiable(
      inTaxonomyOrder(<Concern>[for (final kept in best.values) kept.concern]),
    );
  }

  /// [concerns] sorted by restriction in taxonomy order, keeping their
  /// order within one restriction (the user's own words, ALG-17). Pure.
  static List<Concern> inTaxonomyOrder(List<Concern> concerns) {
    final indexed = concerns.indexed.toList()
      ..sort((a, b) {
        final byId = a.$2.restrictionId.index.compareTo(
          b.$2.restrictionId.index,
        );
        return byId != 0 ? byId : a.$1.compareTo(b.$1);
      });
    return <Concern>[for (final (_, concern) in indexed) concern];
  }

  /// Whether [candidate] should replace [kept] as its restriction's one
  /// concern.
  static bool _outranks(_Evidence candidate, _Evidence kept) {
    final a = candidate.concern.certainty.index;
    final b = kept.concern.certainty.index;
    if (a != b) return a < b;
    return kept.removable && !candidate.removable;
  }
}

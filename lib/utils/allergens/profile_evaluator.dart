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
import 'package:ketoclub/utils/allergens/taxonomy.dart';
import 'package:ketoclub/utils/classification_rules.dart';
import 'package:ketoclub/utils/text_normaliser.dart';

/// The English waiter sentence for one removable item; `{item}` is the
/// item as the menu (or the model) wrote it.
const String removeItemModificationEn = 'Ask for it without {item}';

/// The Hebrew waiter sentence for one removable item; `{item}` as in
/// [removeItemModificationEn].
const String removeItemModificationHe = 'לבקש את המנה בלי {item}';

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

  @override
  bool operator ==(Object other) =>
      other is EvaluatedDish &&
      other.dish == dish &&
      listEquals(other.concerns, concerns) &&
      other.state == state &&
      other.modification == modification;

  @override
  int get hashCode =>
      Object.hash(dish, Object.hashAll(concerns), state, modification);

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
  ///    listed but moves nothing.
  ///
  /// An empty profile holds keto: it is the keto-only user of today's
  /// app, and the result is the identity mapping of the wire verdict.
  static EvaluatedDish evaluate(
    AnalysedDish analysed,
    Dish dish,
    DietaryProfile profile, {
    bool? hebrew,
  }) {
    final hasKeto = profile.isEmpty || profile.contains(RestrictionId.keto);
    final isHebrew =
        hebrew ??
        TextNormaliser.containsHebrew(TextNormaliser.dishRulesText(dish));

    final evidence = <_Evidence>[
      for (final evidence in _evidence(analysed, dish))
        if (_applies(evidence.concern, profile)) evidence,
    ];

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
      for (final item in items) template.replaceAll('{item}', item),
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
      concerns: _onePerRestriction(evidence),
      state: state,
      modification: state == DishState.avoid ? null : change,
    );
  }

  /// Every piece of evidence about [dish], whatever the profile: the rule
  /// engine's findings, the analysis's own concerns, then the concerns
  /// read from its ingredients.
  static List<_Evidence> _evidence(AnalysedDish analysed, Dish dish) {
    _Evidence ofConcern(Concern concern) {
      final removable = concern.source == ConcernSource.option;
      return (
        concern: concern,
        removable: removable,
        item: removable ? concern.matchedText : null,
      );
    }

    return <_Evidence>[
      for (final concern in ClassificationRules.allergenFindings(dish))
        ofConcern(concern),
      for (final concern in analysed.concerns) ofConcern(concern),
      for (final ingredient in analysed.ingredients)
        for (final hit in AllergenMatcher.find(ingredient.name))
          (
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
          ),
    ];
  }

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

  /// [evidence] reduced to one concern per restriction, in taxonomy
  /// order: the surest, and at a tie the one that cannot be left off,
  /// then the earliest.
  static List<Concern> _onePerRestriction(List<_Evidence> evidence) {
    final best = <RestrictionId, _Evidence>{};
    for (final candidate in evidence) {
      final kept = best[candidate.concern.restrictionId];
      if (kept == null || _outranks(candidate, kept)) {
        best[candidate.concern.restrictionId] = candidate;
      }
    }
    final ids = best.keys.toList()..sort((a, b) => a.index.compareTo(b.index));
    return List<Concern>.unmodifiable(<Concern>[
      for (final id in ids) best[id]!.concern,
    ]);
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

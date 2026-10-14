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
      concerns: _onePerRestriction(evidence),
      state: state,
      modification: state == DishState.avoid ? null : change,
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

  /// Every piece of evidence about [dish], whatever the profile: the rule
  /// engine's findings, the analysis's own concerns, then the concerns
  /// read from its ingredients.
  static List<_Evidence> _evidence(AnalysedDish analysed, Dish dish) {
    _Evidence ofConcern(Concern concern) {
      final removable = concern.source == ConcernSource.option;
      final matched = concern.matchedText;
      return (
        concern: concern,
        removable: removable,
        item: removable && matched != null ? _optionItem(dish, matched) : null,
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

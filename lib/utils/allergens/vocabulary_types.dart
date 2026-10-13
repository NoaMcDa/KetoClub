/// The shape of one restriction's trigger vocabulary (Banto; ALG-01,
/// issue #343).
///
/// Its own file so the six group files (`vocab_*.dart`) can import the
/// types while `vocabulary.dart` imports the groups, with no import cycle.
/// Import `vocabulary.dart`, which re-exports this file, everywhere else.
library;

import 'package:flutter/foundation.dart';

/// How sure a trigger makes the matcher that a restriction is present.
///
/// The wire form is [name]; match it with [tryParse], never by ordinal.
enum TriggerCertainty {
  /// The menu text names the thing itself ("sesame", "טחינה"). Every
  /// direct trigger is stated.
  stated,

  /// A hidden source that usually carries it ("soy sauce" → wheat).
  likely,

  /// A hidden source that sometimes carries it ("vegetable stock" →
  /// celery).
  suspected;

  /// The certainty whose [name] equals [wire], or null when none does.
  static TriggerCertainty? tryParse(String wire) {
    for (final certainty in TriggerCertainty.values) {
      if (certainty.name == wire) return certainty;
    }
    return null;
  }
}

/// A hidden-source trigger: a sauce, a dish or a technique that may carry
/// a restriction without naming it.
@immutable
final class HiddenTrigger {
  /// Creates a hidden trigger for [term], as written on a menu.
  const new({
    required this.term,
    required this.certainty,
    required this.source,
  });

  /// The trigger as a menu writes it, correctly spelled; the matcher
  /// normalises it.
  final String term;

  /// How sure a match makes the matcher. Never [TriggerCertainty.stated]:
  /// a stated trigger is a direct one.
  final TriggerCertainty certainty;

  /// Where the entry comes from, as a citation of the allergen
  /// documentation: `"11 §6.2"` is file 11, section 6.2.
  final String source;

  @override
  bool operator ==(Object other) =>
      other is HiddenTrigger &&
      other.term == term &&
      other.certainty == certainty &&
      other.source == source;

  @override
  int get hashCode => Object.hash(term, certainty, source);

  @override
  String toString() => 'HiddenTrigger($term, ${certainty.name})';
}

/// The guard phrases of one restriction, or of one of its terms
/// ([RestrictionVocabulary.termGuards]).
///
/// **A guard lowers, never cancels** (doc 11 §0; ALG-04a): a trigger with
/// a guard directly beside it is still reported, as
/// [TriggerCertainty.suspected] and marked guarded, because a menu phrase
/// is never proof that an allergen is absent ("almond milk" may be steamed
/// with dairy milk; a "nut-free" pesto may hold pine nuts).
///
/// A guard counts only in the slot **adjacent** to its trigger: a
/// `before` phrase must end on the word just before the matched span, an
/// `after` phrase must start on the word just after it. So "no sesame or
/// tahini" lowers sesame and leaves tahini stated. A guard is written
/// relative to the trigger it lowers: "sesame-free" is `afterEn:
/// ['free']` (normalised "sesame free"), "no sesame" is `beforeEn:
/// ['no']`, "ללא שומשום" is `beforeHe: ['ללא']`, "חלב סויה" is `afterHe:
/// ['סויה']`. The direction matters: `beforeEn: ['free']` would also lower
/// "free range eggs". English guards apply to the English triggers, Hebrew
/// guards to the Hebrew ones; each phrase is normalised before it is
/// compared, and every word of a multi-word phrase must be adjacent. A
/// Hebrew guard's first word may carry grammatical prefix letters: up to
/// two of בהוכלמש before the trigger ("וללא טחינה"), only the article ה
/// after it ("חלב השקדים"; "חלב וסויה" is milk *and* soy, not soy milk).
@immutable
final class AllergenGuards {
  /// Creates a guard set. Every list defaults to empty.
  const new({
    this.beforeEn = const <String>[],
    this.afterEn = const <String>[],
    this.beforeHe = const <String>[],
    this.afterHe = const <String>[],
  });

  /// English phrases that lower an English trigger from the words just
  /// before it.
  final List<String> beforeEn;

  /// English phrases that lower an English trigger from the words just
  /// after it.
  final List<String> afterEn;

  /// Hebrew phrases that lower a Hebrew trigger from the words just before
  /// it.
  final List<String> beforeHe;

  /// Hebrew phrases that lower a Hebrew trigger from the words just after
  /// it.
  final List<String> afterHe;
}

/// One restriction's bilingual trigger vocabulary.
///
/// Terms are written as a menu prints them, correctly spelled, and are
/// normalised by the matcher (`TextNormaliser.normalise`), exactly as the
/// keto vocabulary in `constants.dart` is. English terms match with the
/// ASCII word boundary (`latinTriggerPattern`); Hebrew terms with the
/// Hebrew lookaround (`hebrewTriggerPattern`), which allows up to two
/// grammatical prefix letters (בטחינה, והשומשום) unless the term is listed
/// in [noPrefixHe].
@immutable
final class RestrictionVocabulary {
  /// Creates a vocabulary. Every list defaults to empty.
  const new({
    this.directEn = const <String>[],
    this.directHe = const <String>[],
    this.hiddenEn = const <HiddenTrigger>[],
    this.hiddenHe = const <HiddenTrigger>[],
    this.guards = const AllergenGuards(),
    this.termGuards = const <String, AllergenGuards>{},
    this.noPrefixHe = const <String>[],
    this.sources = const <String>[],
  });

  /// The vocabulary with no triggers, for a group not filled yet.
  static const RestrictionVocabulary empty = RestrictionVocabulary();

  /// English words that name the restriction's food directly ("sesame",
  /// "tahini"); a hit is [TriggerCertainty.stated].
  final List<String> directEn;

  /// Hebrew words that name it directly ("שומשום", "טחינה"); a hit is
  /// [TriggerCertainty.stated].
  final List<String> directHe;

  /// English hidden-source triggers, each with its own certainty.
  final List<HiddenTrigger> hiddenEn;

  /// Hebrew hidden-source triggers, each with its own certainty.
  final List<HiddenTrigger> hiddenHe;

  /// Phrases that lower any of this restriction's triggers beside them.
  final AllergenGuards guards;

  /// Phrases that lower one term only, keyed by the term as written in a
  /// trigger list, applied on top of [guards]: the compounds that name
  /// another food ("rice flour" is not wheat flour, "almond milk" not
  /// dairy milk, "oyster mushroom" not an oyster, "crab apple" not a
  /// crab). The guard is the other word of the compound, so `'flour':
  /// AllergenGuards(beforeEn: ['rice'])` lowers wheat's "flour" in "rice
  /// flour" and nothing else. A compound that names an allergen of its own
  /// is still a trigger of that one ("almond milk" is tree nuts, stated).
  final Map<String, AllergenGuards> termGuards;

  /// Hebrew terms, from [directHe] or [hiddenHe] and spelled the same,
  /// compiled with no permissive prefix, because a prefix letter turns
  /// them into another word (ש + חיטה is שחיטה, "slaughter") — the
  /// allergen twin of `constants.dart`'s no-prefix triggers. A prefixed
  /// form that should still match is then listed as its own term.
  final List<String> noPrefixHe;

  /// Citations for the direct triggers and guards, each like `"11 §11"`
  /// or `"12 §1.1"` (file and section of the allergen documentation).
  final List<String> sources;

  /// Whether the vocabulary has no trigger at all.
  bool get isEmpty =>
      directEn.isEmpty &&
      directHe.isEmpty &&
      hiddenEn.isEmpty &&
      hiddenHe.isEmpty;
}

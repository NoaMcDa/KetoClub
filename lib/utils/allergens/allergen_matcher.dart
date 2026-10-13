/// The allergen trigger matcher (Banto; ALG-01, issue #343; ALG-04a).
///
/// [AllergenMatcher.find] runs every restriction's vocabulary
/// ([allergenVocabulary]) over a text and reports every trigger it finds,
/// for every restriction — profile-independent (architecture.md D26, C1):
/// what the person cares about is decided later, on the device.
///
/// It reuses the keto engine's matching: terms are normalised with
/// [TextNormaliser.normalise], English ones compiled with
/// [latinTriggerPattern], Hebrew ones with [hebrewTriggerPattern] (the
/// permissive prefix unless the term is in
/// [RestrictionVocabulary.noPrefixHe]). Three rules are its own (ALG-04a),
/// and none of them changes a keto result:
///
/// - **A guard lowers, never cancels.** A guarded trigger is still a hit,
///   [TriggerCertainty.suspected] and [AllergenHit.guarded]: the app never
///   tells an allergic person something is absent on a heuristic.
/// - **A guard counts only in the slot adjacent to its term** (see
///   [AllergenGuards]), not anywhere in the keto engine's two-word window,
///   and a term's own guards ([RestrictionVocabulary.termGuards]) apply on
///   top of its restriction's.
/// - **The maqaf joins words.** The Hebrew hyphen U+05BE becomes a space
///   before the text is normalised ("חמאת־בוטנים" reads as two words),
///   where [TextNormaliser.normalise] deletes it as a Hebrew point; see
///   [AllergenMatcher.matchText]. Terms and guard phrases are read the same
///   way, so a term written with a maqaf ("סויה־דבש") still matches.
library;

import 'package:flutter/foundation.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/utils/allergens/taxonomy.dart';
import 'package:ketoclub/utils/allergens/vocabulary.dart';
import 'package:ketoclub/utils/classification_rules.dart'
    show hebrewTriggerPattern, latinTriggerPattern;
import 'package:ketoclub/utils/text_normaliser.dart';

/// One trigger the matcher found.
@immutable
final class AllergenHit {
  /// Creates a hit for [id] on [term], spanning [start]-[end].
  const new({
    required this.id,
    required this.term,
    required this.certainty,
    required this.start,
    required this.end,
    this.guarded = false,
  });

  /// The restriction the trigger belongs to.
  final RestrictionId id;

  /// The trigger as its vocabulary spells it (not normalised), so it can
  /// be shown or read back.
  final String term;

  /// [TriggerCertainty.stated] for a direct trigger; a hidden trigger's
  /// own certainty otherwise; always [TriggerCertainty.suspected] when
  /// [guarded].
  final TriggerCertainty certainty;

  /// Where the match starts, in UTF-16 code units of the **normalised**
  /// text the matcher read: [AllergenMatcher.matchText] for
  /// [AllergenMatcher.find], [AllergenMatcher.dishMatchText] for
  /// [AllergenMatcher.findInDish] (the normaliser's output, with a maqaf
  /// read as a space). A Hebrew prefix letter the pattern allowed is part
  /// of the span.
  final int start;

  /// Where the match ends (exclusive), in the same units as [start].
  final int end;

  /// Whether a guard sat beside the trigger ("almond milk", "peanut-free")
  /// and lowered the hit to [TriggerCertainty.suspected]. A guard never
  /// removes a hit.
  final bool guarded;

  @override
  bool operator ==(Object other) =>
      other is AllergenHit &&
      other.id == id &&
      other.term == term &&
      other.certainty == certainty &&
      other.start == start &&
      other.end == end &&
      other.guarded == guarded;

  @override
  int get hashCode => Object.hash(id, term, certainty, start, end, guarded);

  @override
  String toString() =>
      'AllergenHit(${id.name}, $term, ${certainty.name}, $start-$end'
      '${guarded ? ', guarded' : ''})';
}

/// One guard phrase, normalised and split into its words.
typedef _Phrase = List<String>;

/// The guards that apply to one trigger: its restriction's, in the
/// trigger's language, plus its own [RestrictionVocabulary.termGuards].
typedef _TriggerGuards = ({List<_Phrase> before, List<_Phrase> after});

/// One compiled trigger: its term as written, its pattern, its certainty,
/// its guards and whether it is Hebrew (whose guards may carry prefix
/// letters).
typedef _CompiledTrigger = ({
  String term,
  RegExp pattern,
  TriggerCertainty certainty,
  _TriggerGuards guards,
  bool hebrew,
});

/// One restriction's compiled vocabulary, with its taxonomy position for
/// the tie-break.
typedef _CompiledRestriction = ({
  RestrictionId id,
  int order,
  List<_CompiledTrigger> triggers,
});

/// [phrases], normalised and split into words; a phrase that normalises
/// to nothing is dropped (it would sit beside every trigger).
List<_Phrase> _phrases(Iterable<String> phrases) => <_Phrase>[
  for (final phrase in phrases)
    if (AllergenMatcher.matchText(phrase) case final normalised
        when normalised.isNotEmpty)
      normalised.split(' '),
];

/// The guards of a trigger spelled [term] in [entry]: the restriction's
/// own in the trigger's language, then the term's.
_TriggerGuards _guardsFor(
  RestrictionVocabulary entry,
  String term, {
  required bool hebrew,
}) {
  final own = entry.termGuards[term];
  final global = entry.guards;
  return hebrew
      ? (
          before: _phrases(<String>[...global.beforeHe, ...?own?.beforeHe]),
          after: _phrases(<String>[...global.afterHe, ...?own?.afterHe]),
        )
      : (
          before: _phrases(<String>[...global.beforeEn, ...?own?.beforeEn]),
          after: _phrases(<String>[...global.afterEn, ...?own?.afterEn]),
        );
}

/// Compiles [vocabulary], in taxonomy order. A term that normalises to
/// nothing is skipped: its pattern would match everywhere.
List<_CompiledRestriction> _compile(
  Map<RestrictionId, RestrictionVocabulary> vocabulary,
) {
  final compiled = <_CompiledRestriction>[];
  for (final (order, restriction) in restrictionTaxonomy.indexed) {
    final entry = vocabulary[restriction.id];
    if (entry == null) continue;
    final noPrefix = entry.noPrefixHe.toSet();
    final triggers = <_CompiledTrigger>[];

    void latin(String term, TriggerCertainty certainty) {
      final normalised = AllergenMatcher.matchText(term);
      if (normalised.isEmpty) return;
      triggers.add((
        term: term,
        pattern: latinTriggerPattern(normalised),
        certainty: certainty,
        guards: _guardsFor(entry, term, hebrew: false),
        hebrew: false,
      ));
    }

    void hebrew(String term, TriggerCertainty certainty) {
      final normalised = AllergenMatcher.matchText(term);
      if (normalised.isEmpty) return;
      triggers.add((
        term: term,
        pattern: hebrewTriggerPattern(
          normalised,
          allowPrefix: !noPrefix.contains(term),
        ),
        certainty: certainty,
        guards: _guardsFor(entry, term, hebrew: true),
        hebrew: true,
      ));
    }

    for (final term in entry.directEn) {
      latin(term, TriggerCertainty.stated);
    }
    for (final term in entry.directHe) {
      hebrew(term, TriggerCertainty.stated);
    }
    for (final trigger in entry.hiddenEn) {
      latin(trigger.term, trigger.certainty);
    }
    for (final trigger in entry.hiddenHe) {
      hebrew(trigger.term, trigger.certainty);
    }

    compiled.add((id: restriction.id, order: order, triggers: triggers));
  }
  return compiled;
}

/// The prefix a Hebrew guard's first word may carry in the slot before
/// its trigger: one or two of the grammatical prefix letters ב/ה/ו/כ/ל/מ/ש,
/// the set [hebrewTriggerPattern] allows before a term ("וללא טחינה").
final RegExp _hebrewBeforePrefix = RegExp(r'^[בהוכלמש]{1,2}$');

/// The one prefix a Hebrew guard's first word may carry in the slot after
/// its trigger: the article ה of a construct phrase ("חלב השקדים").
/// Nothing else: "חלב וסויה" is milk *and* soy, not soy milk.
final RegExp _hebrewAfterPrefix = RegExp(r'^ה$');

/// Whether [words] is [phrase] word for word, its first word allowed a
/// prefix matching [prefix] when [prefix] is not null.
bool _isPhrase(List<String> words, _Phrase phrase, RegExp? prefix) {
  for (final (index, guard) in phrase.indexed) {
    final word = words[index];
    if (word == guard) continue;
    if (index > 0 || prefix == null || !word.endsWith(guard)) return false;
    if (!prefix.hasMatch(word.substring(0, word.length - guard.length))) {
      return false;
    }
  }
  return true;
}

/// Whether one of [trigger]'s guards sits in the slot adjacent to the
/// match spanning [start]-[end] of the normalised [haystack]: a `before`
/// phrase ending on the word just before it, or an `after` phrase starting
/// on the word just after it (ALG-04a). Unlike the keto engine's two-word
/// window (`ClassificationRules.isGuarded`, which this file no longer
/// calls), a guard beside a neighbouring term never reaches this one.
bool _isAdjacentGuarded(
  String haystack,
  int start,
  int end,
  _CompiledTrigger trigger,
) {
  final guards = trigger.guards;
  if (guards.before.isNotEmpty) {
    final beforeText = haystack.substring(0, start).trimRight();
    if (beforeText.isNotEmpty) {
      final words = beforeText.split(' ');
      for (final phrase in guards.before) {
        if (phrase.length > words.length) continue;
        if (_isPhrase(
          words.sublist(words.length - phrase.length),
          phrase,
          trigger.hebrew ? _hebrewBeforePrefix : null,
        )) {
          return true;
        }
      }
    }
  }
  if (guards.after.isNotEmpty) {
    final afterText = haystack.substring(end).trimLeft();
    if (afterText.isNotEmpty) {
      final words = afterText.split(' ');
      for (final phrase in guards.after) {
        if (phrase.length > words.length) continue;
        if (_isPhrase(
          words.sublist(0, phrase.length),
          phrase,
          trigger.hebrew ? _hebrewAfterPrefix : null,
        )) {
          return true;
        }
      }
    }
  }
  return false;
}

/// Every vocabulary map compiled so far, keyed on the map instance: a
/// vocabulary is compiled once, however many texts it reads (thousands
/// of patterns per registry). Keyed on identity, so an equal but distinct
/// map compiles on its own; the vocabularies are `const`, so a map never
/// changes after it is compiled.
final Expando<List<_CompiledRestriction>> _compiledCache =
    Expando<List<_CompiledRestriction>>('compiled allergen vocabulary');

/// [vocabulary], compiled on first use and cached ([_compiledCache]).
List<_CompiledRestriction> _compiled(
  Map<RestrictionId, RestrictionVocabulary> vocabulary,
) => _compiledCache[vocabulary] ??= _compile(vocabulary);

/// [allergenVocabulary], compiled on first use.
List<_CompiledRestriction> get _registry => _compiled(allergenVocabulary);

/// Every hit of [compiled] in the normalised [haystack], guarded or not,
/// ordered
/// by start, then taxonomy order, then vocabulary order (direct English,
/// direct Hebrew, hidden English, hidden Hebrew, each as listed, and a
/// trigger's own matches left to right).
List<AllergenHit> _findIn(
  String haystack,
  List<_CompiledRestriction> compiled,
) {
  if (haystack.isEmpty) return const <AllergenHit>[];
  final found = <({AllergenHit hit, int order, int sequence})>[];
  for (final restriction in compiled) {
    for (final trigger in restriction.triggers) {
      for (final match in trigger.pattern.allMatches(haystack)) {
        final guarded = _isAdjacentGuarded(
          haystack,
          match.start,
          match.end,
          trigger,
        );
        found.add((
          hit: AllergenHit(
            id: restriction.id,
            term: trigger.term,
            certainty: guarded ? TriggerCertainty.suspected : trigger.certainty,
            start: match.start,
            end: match.end,
            guarded: guarded,
          ),
          order: restriction.order,
          sequence: found.length,
        ));
      }
    }
  }
  // Every key is distinct by `sequence`, so the order is total and the
  // result does not depend on the sort being stable.
  found.sort((a, b) {
    final byStart = a.hit.start.compareTo(b.hit.start);
    if (byStart != 0) return byStart;
    final byOrder = a.order.compareTo(b.order);
    if (byOrder != 0) return byOrder;
    return a.sequence.compareTo(b.sequence);
  });
  return List<AllergenHit>.unmodifiable(found.map((entry) => entry.hit));
}

/// The Hebrew maqaf, U+05BE: a hyphen that joins two words ("חמאת־בוטנים").
const String _maqaf = '־';

/// [raw] with every maqaf a space. Length-preserving, so a span over the
/// result is a span over [raw] too.
String _spaceMaqaf(String raw) => raw.replaceAll(_maqaf, ' ');

/// [dish] with every maqaf in its name, description, option names and
/// option values a space; everything else as it was.
Dish _spaceMaqafInDish(Dish dish) => Dish(
  id: dish.id,
  name: _spaceMaqaf(dish.name),
  description: _spaceMaqaf(dish.description),
  price: dish.price,
  options: <DishOption>[
    for (final option in dish.options)
      DishOption(
        name: _spaceMaqaf(option.name),
        values: <String>[for (final value in option.values) _spaceMaqaf(value)],
      ),
  ],
  imageUrl: dish.imageUrl,
  page: dish.page,
);

/// Finds allergen and diet triggers in menu text (ALG-01).
///
/// Reports every restriction it finds, whatever the profile (C1); a
/// longer and a shorter trigger of one restriction that both match
/// ("peanut butter", "peanut") are both reported, and a guarded trigger
/// is reported too, lowered (ALG-04a). Never throws.
abstract final class AllergenMatcher {
  /// The text [find] reads and its offsets index: [rawText] with every
  /// maqaf a space, then [TextNormaliser.normalise]d. The keto engine
  /// reads `TextNormaliser.normalise(rawText)`, which deletes the maqaf;
  /// the two differ only where [rawText] holds one.
  static String matchText(String rawText) =>
      TextNormaliser.normalise(_spaceMaqaf(rawText));

  /// The text [findInDish] reads and its offsets index:
  /// [TextNormaliser.dishRulesText] of [dish] with every maqaf a space, so
  /// removal option values are skipped exactly as the keto engine skips
  /// them ("ללא־שומשום" is a removal here).
  static String dishMatchText(Dish dish) =>
      TextNormaliser.dishRulesText(_spaceMaqafInDish(dish));

  /// Every trigger hit in [rawText], both languages, unconditionally —
  /// Israeli menus mix scripts. Offsets index [matchText].
  static List<AllergenHit> find(String rawText) =>
      _findIn(matchText(rawText), _registry);

  /// Every trigger hit in [dish]: its name, description, option group
  /// names and option values, skipping removal values ("No sesame",
  /// "ללא טחינה") as `ClassificationRules.matchDish` does. Offsets index
  /// [dishMatchText].
  static List<AllergenHit> findInDish(Dish dish) =>
      _findIn(dishMatchText(dish), _registry);

  /// [find] over [vocabulary] instead of [allergenVocabulary], compiled
  /// once per map instance: for the tests and the golden exporter, which
  /// pin the matcher's behaviour with a vocabulary of their own rather than
  /// the group files. Production code calls [find].
  static List<AllergenHit> findWith(
    String rawText,
    Map<RestrictionId, RestrictionVocabulary> vocabulary,
  ) => _findIn(matchText(rawText), _compiled(vocabulary));

  /// [findInDish] over [vocabulary]; see [findWith].
  static List<AllergenHit> findInDishWith(
    Dish dish,
    Map<RestrictionId, RestrictionVocabulary> vocabulary,
  ) => _findIn(dishMatchText(dish), _compiled(vocabulary));
}

/// The allergen trigger matcher (Banto; ALG-01, issue #343).
///
/// [AllergenMatcher.find] runs every restriction's vocabulary
/// ([allergenVocabulary]) over a text and reports every unguarded trigger
/// it finds, for every restriction — profile-independent (architecture.md
/// D26, C1): what the person cares about is decided later, on the device.
///
/// It reuses the keto engine's matching exactly: terms are normalised with
/// [TextNormaliser.normalise], English ones compiled with
/// [latinTriggerPattern], Hebrew ones with [hebrewTriggerPattern] (the
/// permissive prefix unless the term is in
/// [RestrictionVocabulary.noPrefixHe]), and guards applied with
/// [ClassificationRules.isGuarded]. Nothing here changes a keto result.
library;

import 'package:flutter/foundation.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/utils/allergens/taxonomy.dart';
import 'package:ketoclub/utils/allergens/vocabulary.dart';
import 'package:ketoclub/utils/classification_rules.dart';
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
  });

  /// The restriction the trigger belongs to.
  final RestrictionId id;

  /// The trigger as its vocabulary spells it (not normalised), so it can
  /// be shown or read back.
  final String term;

  /// [TriggerCertainty.stated] for a direct trigger; a hidden trigger's
  /// own certainty otherwise.
  final TriggerCertainty certainty;

  /// Where the match starts, in UTF-16 code units of the **normalised**
  /// text the matcher read: `TextNormaliser.normalise(text)` for
  /// [AllergenMatcher.find], `TextNormaliser.dishRulesText(dish)` for
  /// [AllergenMatcher.findInDish]. A Hebrew prefix letter the pattern
  /// allowed is part of the span.
  final int start;

  /// Where the match ends (exclusive), in the same units as [start].
  final int end;

  @override
  bool operator ==(Object other) =>
      other is AllergenHit &&
      other.id == id &&
      other.term == term &&
      other.certainty == certainty &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(id, term, certainty, start, end);

  @override
  String toString() =>
      'AllergenHit(${id.name}, $term, ${certainty.name}, $start-$end)';
}

/// One compiled trigger: its term as written, its pattern, its certainty
/// and whether the Hebrew guards (rather than the English ones) apply.
typedef _CompiledTrigger = ({
  String term,
  RegExp pattern,
  TriggerCertainty certainty,
  bool hebrew,
});

/// The guard window shape [ClassificationRules.isGuarded] reads.
typedef _Guard = ({List<String> before, List<String> after});

/// One restriction's compiled vocabulary, with its taxonomy position for
/// the tie-break.
typedef _CompiledRestriction = ({
  RestrictionId id,
  int order,
  List<_CompiledTrigger> triggers,
  _Guard guardEn,
  _Guard guardHe,
});

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
      final normalised = TextNormaliser.normalise(term);
      if (normalised.isEmpty) return;
      triggers.add((
        term: term,
        pattern: latinTriggerPattern(normalised),
        certainty: certainty,
        hebrew: false,
      ));
    }

    void hebrew(String term, TriggerCertainty certainty) {
      final normalised = TextNormaliser.normalise(term);
      if (normalised.isEmpty) return;
      triggers.add((
        term: term,
        pattern: hebrewTriggerPattern(
          normalised,
          allowPrefix: !noPrefix.contains(term),
        ),
        certainty: certainty,
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

    final guards = entry.guards;
    compiled.add((
      id: restriction.id,
      order: order,
      triggers: triggers,
      guardEn: (before: guards.beforeEn, after: guards.afterEn),
      guardHe: (before: guards.beforeHe, after: guards.afterHe),
    ));
  }
  return compiled;
}

/// [allergenVocabulary], compiled on first use (a top-level `final`
/// initialises lazily).
final List<_CompiledRestriction> _registry = _compile(allergenVocabulary);

/// Every unguarded hit of [compiled] in the normalised [haystack], ordered
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
      final guard = trigger.hebrew ? restriction.guardHe : restriction.guardEn;
      for (final match in trigger.pattern.allMatches(haystack)) {
        if (ClassificationRules.isGuarded(
          haystack,
          match.start,
          match.end,
          guard,
        )) {
          continue;
        }
        found.add((
          hit: AllergenHit(
            id: restriction.id,
            term: trigger.term,
            certainty: trigger.certainty,
            start: match.start,
            end: match.end,
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

/// Finds allergen and diet triggers in menu text (ALG-01).
///
/// Reports every restriction it finds, whatever the profile (C1); a
/// longer and a shorter trigger of one restriction that both match
/// ("peanut butter", "peanut") are both reported. Never throws.
abstract final class AllergenMatcher {
  /// Every unguarded trigger hit in [rawText], both languages,
  /// unconditionally — Israeli menus mix scripts. Offsets index
  /// `TextNormaliser.normalise(rawText)`.
  static List<AllergenHit> find(String rawText) =>
      _findIn(TextNormaliser.normalise(rawText), _registry);

  /// Every unguarded trigger hit in [dish]: its name, description, option
  /// group names and option values, skipping removal values ("No sesame",
  /// "ללא טחינה") exactly as [ClassificationRules.matchDish] does — the
  /// text is [TextNormaliser.dishRulesText], which the offsets index.
  static List<AllergenHit> findInDish(Dish dish) =>
      _findIn(TextNormaliser.dishRulesText(dish), _registry);

  /// [find] over [vocabulary] instead of [allergenVocabulary], compiled
  /// on every call: for the tests and the golden exporter, which pin the
  /// matcher's behaviour with a vocabulary of their own rather than the
  /// group files. Production code calls [find].
  static List<AllergenHit> findWith(
    String rawText,
    Map<RestrictionId, RestrictionVocabulary> vocabulary,
  ) => _findIn(TextNormaliser.normalise(rawText), _compile(vocabulary));

  /// [findInDish] over [vocabulary]; see [findWith].
  static List<AllergenHit> findInDishWith(
    Dish dish,
    Map<RestrictionId, RestrictionVocabulary> vocabulary,
  ) => _findIn(TextNormaliser.dishRulesText(dish), _compile(vocabulary));
}

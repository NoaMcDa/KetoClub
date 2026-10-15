/// Group evaluation: one menu read for several people at once (Banto; the
/// Allergens epic, ALG-12, issue #354).
///
/// Built on top of [ProfileEvaluator.evaluate], never inside it: the
/// extraction is per menu, the evaluation runs once per selected profile,
/// and the state a dish shows is the *strictest* across them (avoid > ask >
/// fits with a change > fits), with every person's own result kept for the
/// card's breakdown. Like the evaluator it runs only on the device; no
/// profile, and no name, leaves it (D26 C1). Pure; never throws.
library;

import 'package:flutter/foundation.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/concern.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/named_profile.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/utils/allergens/confirmations.dart';
import 'package:ketoclub/utils/allergens/declarations.dart';
import 'package:ketoclub/utils/allergens/kitchen_reach.dart';
import 'package:ketoclub/utils/allergens/profile_evaluator.dart';
import 'package:ketoclub/utils/dietary_profile_strictness.dart';

/// One person's evaluation of a dish.
@immutable
final class PersonEvaluation {
  /// Creates [person]'s [evaluated] result.
  const new({required this.person, required this.evaluated});

  /// Whose result this is.
  final NamedProfile person;

  /// [ProfileEvaluator.evaluate]'s result for [person]'s profile.
  final EvaluatedDish evaluated;

  /// [evaluated]'s state.
  DishState get state => evaluated.state;

  @override
  bool operator ==(Object other) =>
      other is PersonEvaluation &&
      other.person == person &&
      other.evaluated == evaluated;

  @override
  int get hashCode => Object.hash(person, evaluated);

  @override
  String toString() => 'PersonEvaluation(${person.id}: ${state.name})';
}

/// A dish as a group sees it: the strictest result, and each person's.
@immutable
final class GroupEvaluation {
  /// Creates the group's evaluation from [combined] and [people].
  const new({required this.combined, required this.people});

  /// The strictest state, every person's concerns, and the waiter lines
  /// they share ([GroupEvaluator.combine]).
  final EvaluatedDish combined;

  /// Each selected person's own result, in the order they were given.
  final List<PersonEvaluation> people;

  /// [combined]'s state.
  DishState get state => combined.state;

  @override
  bool operator ==(Object other) =>
      other is GroupEvaluation &&
      other.combined == combined &&
      listEquals(other.people, people);

  @override
  int get hashCode => Object.hash(combined, Object.hashAll(people));

  @override
  String toString() =>
      'GroupEvaluation(${state.name}, ${people.length} people)';
}

/// Evaluates analysed dishes for several profiles at once (ALG-12).
abstract final class GroupEvaluator {
  /// The strictest of [states]: avoid, then ask, then fits with a change,
  /// then fits ([DishState]'s own order). [DishState.fits] for none.
  static DishState strictest(Iterable<DishState> states) {
    var worst = DishState.fits;
    for (final state in states) {
      if (state.index > worst.index) worst = state;
    }
    return worst;
  }

  /// The one profile the menu screen words, filters and counts a group
  /// by: [profiles] itself when there is one; otherwise every entry of
  /// every profile, first occurrence first, each restriction once.
  ///
  /// An entry keeps only the exceptions every profile holding it shares,
  /// since one person's exception must not excuse the others; the user's
  /// own restriction (ALG-17) holds every person's words, in the order
  /// first met, since each person's word is a restriction of its own. When any
  /// profile holds keto (an empty one does, as everywhere) and the union
  /// holds something else, keto is added last, so the union still says
  /// that keto applies. The union is never evaluated: each person is, on
  /// their own ([evaluate]).
  static DietaryProfile union(List<DietaryProfile> profiles) {
    if (profiles.isEmpty) return DietaryProfile.empty;
    if (profiles.length == 1) return profiles.single;
    var merged = DietaryProfile.empty;
    for (final profile in profiles) {
      for (final entry in profile.entries) {
        if (merged.contains(entry.restrictionId)) continue;
        final shared = <String>[
          for (final exception in entry.exceptions)
            if (profiles.every(
              (other) =>
                  !other.contains(entry.restrictionId) ||
                  other
                      .entryFor(entry.restrictionId)!
                      .exceptions
                      .contains(exception),
            ))
              exception,
        ];
        merged = merged.withEntry(entry.restrictionId, exceptions: shared);
      }
    }
    final words = <String>[];
    final seen = <String>{};
    for (final profile in profiles) {
      for (final word in profile.customTerms) {
        if (seen.add(word.toLowerCase())) words.add(word);
      }
    }
    if (words.isNotEmpty) {
      // Built directly rather than through `withEntry`, whose cap
      // (`ProfileEntry.maxTerms`) is one person's: no one's word is cut.
      merged = DietaryProfile(
        entries: List<ProfileEntry>.unmodifiable(<ProfileEntry>[
          for (final entry in merged.entries)
            if (entry.restrictionId == RestrictionId.custom)
              ProfileEntry(
                restrictionId: RestrictionId.custom,
                terms: List<String>.unmodifiable(words),
              )
            else
              entry,
        ]),
      );
    }
    final anyKeto = profiles.any((profile) => profile.holdsKeto);
    if (anyKeto && !merged.isEmpty && !merged.contains(RestrictionId.keto)) {
      merged = merged.withEntry(RestrictionId.keto);
    }
    return merged;
  }

  /// Evaluates [analysed], the analysis of [dish], once for each of
  /// [people] and combines the results ([combine]).
  ///
  /// Each person goes through exactly the single-profile pipeline:
  /// [ProfileEvaluator.evaluate] with [hebrew] and the section [heading]
  /// (its declarations, ALG-09), then [applyKitchenSignals] with [kitchen]
  /// (ALG-07) for that person's profile — so a fryer demotes a dish for
  /// the person whose strict entry it reaches, and the strictest state
  /// carries it. What the staff said about the dish ([confirmations],
  /// ALG-14) is a fact about the dish, so it reaches every person. With
  /// one person the combined result is exactly that person's evaluation.
  /// [people] must not be empty.
  static GroupEvaluation evaluate(
    AnalysedDish analysed,
    Dish dish,
    List<NamedProfile> people, {
    bool? hebrew,
    String? heading,
    KitchenReach kitchen = KitchenReach.empty,
    List<ConfirmationEvidence> confirmations = const <ConfirmationEvidence>[],
  }) {
    final results = <PersonEvaluation>[
      for (final person in people)
        PersonEvaluation(
          person: person,
          evaluated: applyKitchenSignals(
            ProfileEvaluator.evaluate(
              analysed,
              dish,
              person.profile,
              hebrew: hebrew,
              heading: heading,
              confirmations: confirmations,
            ),
            dish,
            person.profile,
            kitchen,
          ),
        ),
    ];
    return GroupEvaluation(
      combined: combine(<EvaluatedDish>[
        for (final result in results) result.evaluated,
      ]),
      people: List<PersonEvaluation>.unmodifiable(results),
    );
  }

  /// Several people's evaluations of one dish as one: the [strictest]
  /// state; every concern, one per restriction in taxonomy order (the
  /// surest, and at a tie the first); every declaration that applied to
  /// anyone, once (ALG-09), and so every staff answer (ALG-14); and each
  /// waiter line any of them needs, once,
  /// in order — none for [DishState.avoid], as the evaluator itself
  /// does. One evaluation is returned as it is. [evaluated] must
  /// not be empty.
  static EvaluatedDish combine(List<EvaluatedDish> evaluated) {
    if (evaluated.length == 1) return evaluated.single;
    final state = strictest(evaluated.map((result) => result.state));
    final best = <String, Concern>{};
    for (final result in evaluated) {
      for (final concern in result.concerns) {
        final key = ProfileEvaluator.concernKey(concern);
        final kept = best[key];
        if (kept == null || concern.certainty.index < kept.certainty.index) {
          best[key] = concern;
        }
      }
    }
    final lines = <String>[];
    if (state != DishState.avoid) {
      for (final result in evaluated) {
        for (final line in (result.modification ?? '').split('\n')) {
          final trimmed = line.trim();
          if (trimmed.isNotEmpty && !lines.contains(trimmed)) {
            lines.add(trimmed);
          }
        }
      }
    }
    final declarations = <Declaration>[];
    for (final result in evaluated) {
      for (final declaration in result.declarations) {
        if (!declarations.contains(declaration)) {
          declarations.add(declaration);
        }
      }
    }
    final confirmations = <ConfirmationEvidence>[
      for (final result in evaluated) ...result.confirmations,
    ];
    return EvaluatedDish(
      dish: evaluated.first.dish,
      declarations: List<Declaration>.unmodifiable(declarations),
      confirmations: List<ConfirmationEvidence>.unmodifiable(
        confirmations.toSet(),
      ),
      concerns: List<Concern>.unmodifiable(
        ProfileEvaluator.inTaxonomyOrder(best.values.toList()),
      ),
      state: state,
      modification: lines.isEmpty ? null : lines.join('\n'),
    );
  }
}

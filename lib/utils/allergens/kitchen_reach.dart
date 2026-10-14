/// What a menu's kitchen means for one profile (Banto; ALG-07, issue #349;
/// architecture.md D26).
///
/// [KitchenSignals] reads the kitchen a menu reveals; this file decides
/// what that does to a profile. [KitchenReach.of] reads a menu once: its
/// signals, the dishes each kind reaches ([KitchenSignals.scopeOf]) and
/// the menu's language. [KitchenReach.strictThreats] lists the signals
/// that threaten a strict entry of a profile, the ones the menu screen's
/// kitchen notice shows, and [applyKitchenSignals] demotes a dish that
/// fits to "ask" when one of them reaches it (a fryer, a shared grill, a
/// bakery or a wok; nuts and sesame are named in the notice and demote
/// nothing, see [KitchenSignals.scopeOf]).
///
/// Only strict entries (an allergen or celiac disease; [RestrictionKind
/// .isStrict]) are touched: cross-contact is a trace, which matters to an
/// allergy and to celiac disease and not to an intolerance or a diet. A
/// keto-only profile holds no strict entry, so nothing here changes it.
/// The wire verdict is never rewritten; only the on-device
/// [EvaluatedDish] moves.
library;

import 'package:flutter/foundation.dart';
import 'package:ketoclub/models/concern.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/utils/allergens/kitchen_signals.dart';
import 'package:ketoclub/utils/allergens/profile_evaluator.dart';
import 'package:ketoclub/utils/allergens/taxonomy.dart';
import 'package:ketoclub/utils/dish_kind.dart';
import 'package:ketoclub/utils/text_normaliser.dart';

/// One kitchen signal and the strict entries of a profile it threatens,
/// in taxonomy order. Never empty.
typedef KitchenThreat = ({KitchenSignal signal, List<RestrictionId> strict});

/// A menu's kitchen signals with the dishes each one reaches (ALG-07).
@immutable
final class KitchenReach {
  /// Creates a reach from parts already read; [KitchenReach.of] reads
  /// them from a menu.
  const new({required this.signals, required this.scope, required this.hebrew});

  /// Reads [menu]'s signals ([KitchenSignals.of]), their scope
  /// ([KitchenSignals.scopeOf]) and its language. Pure; never throws.
  ///
  /// The scope leaves out drinks and notices ([dishKindsOf], D21): a can
  /// of cola or a "dear customers" line shares no fryer, wok, grill or
  /// counter, while a side or a sauce (an extra) does. So does each
  /// signal's evidence, which the kitchen notice shows as "Seen in": a
  /// name is kept only when a food or extra dish carries it, so a
  /// placeholder entry ("💙") is never named as a fried dish.
  factory of(Menu menu) {
    final found = KitchenSignals.of(menu);
    if (found.isEmpty) return empty;
    final kinds = dishKindsOf(menu);
    bool prepared(String id) => switch (kinds[id]) {
      DishKind.drink || DishKind.notice => false,
      DishKind.food || DishKind.extra || null => true,
    };
    final preparedNames = <String>{
      for (final dish in menu.allDishes)
        if (prepared(dish.id)) dish.name,
    };
    final signals = List<KitchenSignal>.unmodifiable(<KitchenSignal>[
      for (final signal in found)
        KitchenSignal(
          kind: signal.kind,
          threatens: signal.threatens,
          evidence: List<String>.unmodifiable(
            signal.evidence.where(preparedNames.contains),
          ),
          questionEn: signal.questionEn,
          questionHe: signal.questionHe,
        ),
    ]);
    final buffer = StringBuffer();
    for (final dish in menu.allDishes) {
      buffer
        ..write(TextNormaliser.dishSearchText(dish))
        ..write(' ');
    }
    return KitchenReach(
      signals: signals,
      scope: <KitchenSignalKind, Set<String>>{
        for (final MapEntry(key: kind, value: ids) in KitchenSignals.scopeOf(
          menu,
        ).entries)
          kind: Set<String>.unmodifiable(ids.where(prepared)),
      },
      hebrew: TextNormaliser.containsHebrew(buffer.toString()),
    );
  }

  /// A menu that shows no signal.
  static const KitchenReach empty = KitchenReach(
    signals: <KitchenSignal>[],
    scope: <KitchenSignalKind, Set<String>>{},
    hebrew: false,
  );

  /// The signals the menu shows, in [KitchenSignalKind] order, their
  /// evidence limited to food and extra dishes.
  final List<KitchenSignal> signals;

  /// The ids of the dishes each kind reaches.
  final Map<KitchenSignalKind, Set<String>> scope;

  /// Whether the menu reads as Hebrew (any dish's text holds a Hebrew
  /// letter), the language the notice's staff questions are shown in
  /// (architecture.md §12).
  final bool hebrew;

  /// Every signal that threatens a strict entry of [profile], with those
  /// entries, in [KitchenSignalKind] order. Empty for a profile with no
  /// strict entry, keto-only included.
  List<KitchenThreat> strictThreats(DietaryProfile profile) => <KitchenThreat>[
    for (final signal in signals)
      if (_strictIn(signal, profile) case final strict when strict.isNotEmpty)
        (signal: signal, strict: strict),
  ];

  /// Whether a [kind] signal reaches the dish [dishId].
  bool reaches(KitchenSignalKind kind, String dishId) =>
      scope[kind]?.contains(dishId) ?? false;

  /// [signal]'s threatened ids that [profile] holds and are strict.
  static List<RestrictionId> _strictIn(
    KitchenSignal signal,
    DietaryProfile profile,
  ) => List<RestrictionId>.unmodifiable(<RestrictionId>[
    for (final id in signal.threatens)
      if (profile.contains(id) && restrictionFor(id).isStrict) id,
  ]);
}

/// [evaluated], the evaluation of [dish] for [profile], with [kitchen]'s
/// cross-contact applied (ALG-07): a dish in state [DishState.fits] that a
/// signal threatening a strict entry reaches becomes [DishState.ask], with
/// one concern per such entry it did not already carry: source
/// [ConcernSource.kitchen], certainty `suspected`, tier `inferred`, the
/// kind's name as `matchedText`, and the signal's staff question in the
/// dish's own language as `waiterQuestion` (§12, as the evaluator writes
/// its sentences). At several signals for one entry, the first in
/// [KitchenSignalKind] order speaks.
///
/// Every other dish is returned as it is: one with a change keeps its
/// change, one to ask or avoid already says more than the kitchen would,
/// and flexible entries are never touched. The wire verdict
/// ([EvaluatedDish.dish]) is never rewritten. Pure; never throws.
EvaluatedDish applyKitchenSignals(
  EvaluatedDish evaluated,
  Dish dish,
  DietaryProfile profile,
  KitchenReach kitchen,
) {
  if (evaluated.state != DishState.fits || kitchen.signals.isEmpty) {
    return evaluated;
  }
  final reaching = <RestrictionId, KitchenSignal>{};
  for (final (:signal, :strict) in kitchen.strictThreats(profile)) {
    if (!kitchen.reaches(signal.kind, dish.id)) continue;
    for (final id in strict) {
      reaching.putIfAbsent(id, () => signal);
    }
  }
  if (reaching.isEmpty) return evaluated;

  final hebrew = TextNormaliser.containsHebrew(
    TextNormaliser.dishRulesText(dish),
  );
  final held = <RestrictionId>{
    for (final concern in evaluated.concerns) concern.restrictionId,
  };
  final concerns = <Concern>[
    ...evaluated.concerns,
    for (final MapEntry(key: id, value: signal) in reaching.entries)
      if (!held.contains(id))
        Concern(
          restrictionId: id,
          source: ConcernSource.kitchen,
          certainty: Certainty.suspected,
          tier: EvidenceTier.inferred,
          matchedText: signal.kind.name,
          waiterQuestion: hebrew ? signal.questionHe : signal.questionEn,
        ),
  ]..sort((a, b) => a.restrictionId.index.compareTo(b.restrictionId.index));
  return EvaluatedDish(
    dish: evaluated.dish,
    concerns: List<Concern>.unmodifiable(concerns),
    state: DishState.ask,
    modification: evaluated.modification,
  );
}

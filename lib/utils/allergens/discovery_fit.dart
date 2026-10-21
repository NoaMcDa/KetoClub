/// How well one venue's menu fits the active profiles, for the Discovery
/// card (Banto; issue #410, related to #342; architecture.md D26).
///
/// [DiscoveryFit.of] runs the menu screen's own on-device pipeline over an
/// analysis the device already holds — the cached one, or the quick
/// score's rules-only estimate (D21, D25) — and counts the result: each
/// dish through [GroupEvaluator.evaluate] (so [ProfileEvaluator.evaluate]
/// with the section heading, then [applyKitchenSignals] with the menu's
/// [KitchenReach]) for every active person, the strictest state kept, and
/// the states counted over food dishes only ([VerdictCounts.ofStates],
/// D21). With one person that is their own evaluation; with more it is
/// what fits *everyone* (ALG-12).
///
/// Nothing here calls a model or the network, and the profile never
/// leaves the device (D26 C1): the analysis is profile-independent and
/// the profile chooses among its findings here, as on the menu screen.
library;

import 'package:flutter/foundation.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/named_profile.dart';
import 'package:ketoclub/models/trip_destination.dart';
import 'package:ketoclub/utils/allergens/group_evaluator.dart';
import 'package:ketoclub/utils/allergens/kitchen_reach.dart';
import 'package:ketoclub/utils/allergens/profile_evaluator.dart';
import 'package:ketoclub/utils/banto_mode.dart';
import 'package:ketoclub/utils/profile_wording.dart';
import 'package:ketoclub/utils/verdict_counts.dart';

/// One venue's fit for the active profiles: the food-only state counts and
/// the wording the card says them in.
@immutable
final class DiscoveryFit {
  /// Creates a fit of [counts] worded by [wording].
  const new({required this.counts, required this.wording});

  /// The wording for [people]'s union ([GroupEvaluator.union]) in a build
  /// with [bantoMode]: [ProfileWording.ketoOnly] when the flag is off or
  /// no active profile holds a restriction besides keto, which is when a
  /// Discovery card stays exactly today's.
  static ProfileWording wordingFor(
    List<NamedProfile> people, {
    bool bantoMode = BantoMode.enabled,
  }) => ProfileWording.of(
    GroupEvaluator.union(<DietaryProfile>[
      for (final person in people) person.profile,
    ]),
    bantoMode: bantoMode,
  );

  /// [analysis] over [menu] evaluated for [people] (see the library
  /// comment), or null when there is nothing to say: [people] is empty,
  /// the wording is keto-only ([wordingFor]), or no food dish was placed.
  /// [trip] is trip mode's destination (ALG-13), as the menu screen passes
  /// it. Pure; never throws.
  static DiscoveryFit? of(
    Menu menu,
    MenuAnalysed analysis,
    List<NamedProfile> people, {
    TripDestination? trip,
    bool bantoMode = BantoMode.enabled,
  }) {
    if (people.isEmpty) return null;
    final wording = wordingFor(people, bantoMode: bantoMode);
    if (!wording.usesStates) return null;
    final analysedById = <String, AnalysedDish>{
      for (final dish in analysis.dishes) dish.dishId: dish,
    };
    final kitchen = KitchenReach.of(menu);
    final states = <String, DishState>{
      for (final category in menu.categories)
        for (final dish in category.dishes)
          if (analysedById[dish.id] case final analysed?)
            dish.id: GroupEvaluator.evaluate(
              analysed,
              dish,
              people,
              heading: category.name,
              kitchen: kitchen,
              trip: trip,
            ).state,
    };
    final counts = VerdictCounts.ofStates(menu, states);
    if (counts.total == 0) return null;
    return DiscoveryFit(counts: counts, wording: wording);
  }

  /// The food dishes in each state: [VerdictCounts.green] fits (for
  /// everyone, in a group), [VerdictCounts.yellow] fits with a change,
  /// [VerdictCounts.ask] is one to ask about and [VerdictCounts.red] one
  /// to avoid.
  final VerdictCounts counts;

  /// How the card words [counts]; never [ProfileWording.ketoOnly].
  final ProfileWording wording;

  /// Whether at least one food dish fits, as it is or with a change: what
  /// the "Fits my profile" chip keeps.
  bool get hasFittingDish => counts.green + counts.yellow > 0;

  @override
  bool operator ==(Object other) =>
      other is DiscoveryFit &&
      other.counts == counts &&
      other.wording == wording;

  @override
  int get hashCode => Object.hash(counts, wording);

  @override
  String toString() => 'DiscoveryFit(${wording.name}, $counts)';
}

/// Trip mode's regulation hints (Banto; the Allergens epic, ALG-13, issue
/// #355): per strict profile entry, what the destination's allergen law
/// obliges a restaurant to tell.
///
/// Read from two pieces of taxonomy data: [Restriction.jurisdictions],
/// which lists name a restriction, and [jurisdictionListScope], whether that
/// list binds a restaurant or only packaged food. The distinction is the
/// whole point (file 10 §ALG-13, file 12 §4): Israel's 2028 rule and the
/// US FASTER Act cover packaged food, so in both home markets the hint is
/// "ask every time"; only in the EU and the UK, and in large Californian
/// chains, must a restaurant be able to answer. Each of those facts was
/// checked against web sources on 2026-10-19 (file 12 §8.1): SB 68 was
/// signed and took effect on 1 July 2026, Japan's labelling rules leave
/// restaurants out, and Israel's restaurant duty, if it comes, is years
/// away.
///
/// A hint is never a reason to ask less: even where a restaurant must be
/// able to tell, the app's floor is "ask the restaurant".
library;

import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/models/trip_destination.dart';
import 'package:ketoclub/utils/allergens/taxonomy.dart';

/// What the destination's law says about one strict restriction.
enum RegulationHint {
  /// On the destination's list, and the list binds restaurants: the
  /// restaurant must be able to tell you.
  restaurantMustTell,

  /// On the destination's list for packaged food only: restaurants owe
  /// you nothing, so ask every time.
  packagedOnly,

  /// On the US list for packaged food; only chains of 20 or more
  /// locations must list it per dish in California (SB 68, from 1 July
  /// 2026). Ask every time.
  packagedOnlyLargeChains,

  /// On no list at the destination: ask every time.
  notRegulated,
}

/// Trip mode's regulation hints.
abstract final class TripRegulation {
  /// The hint for [id] at [destination], or null when [id] is not strict:
  /// a flexible restriction (an intolerance, a diet, keto) is on no
  /// allergen list, and trip mode shows it no hint. Pure; total over every
  /// [RestrictionId] and [TripDestination] (a table test pins every pair).
  static RegulationHint? hintFor(
    RestrictionId id,
    TripDestination destination,
  ) {
    final restriction = restrictionFor(id);
    if (!restriction.isStrict) return null;
    final jurisdiction = destination.jurisdiction;
    if (!restriction.jurisdictions.contains(jurisdiction)) {
      return RegulationHint.notRegulated;
    }
    return switch (jurisdictionListScope[jurisdiction]) {
      ListScope.restaurants => RegulationHint.restaurantMustTell,
      ListScope.packagedFoodAndLargeChains =>
        RegulationHint.packagedOnlyLargeChains,
      ListScope.packagedFood || null => RegulationHint.packagedOnly,
    };
  }
}

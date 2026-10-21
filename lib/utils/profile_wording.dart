/// How a dietary profile asks the menu screen to word its verdicts (Banto,
/// ALG-05, issue #347; architecture.md D26).
///
/// Lives in `utils/` rather than beside `widgets/verdict_copy.dart`, which
/// turns it into words, because `MenuController` (in `state/`, ranked below
/// `widgets/`) decides with it how to filter and count.
library;

import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/utils/banto_mode.dart';
import 'package:ketoclub/utils/dietary_profile_strictness.dart';

/// The three ways the menu screen words a dish.
enum ProfileWording {
  /// No restriction besides keto, or a build without Banto: today's
  /// three verdicts and today's words, byte for byte.
  ketoOnly,

  /// A restriction besides keto, none of them strict (an intolerance or a
  /// diet): four states, and "fits" may be said.
  flexible,

  /// At least one strict restriction (an allergen or celiac disease), or
  /// kosher or halal (issue #342): four states, and a dish with nothing
  /// found reads "No trigger found — ask the restaurant", never "fits" and
  /// never "safe" (file 09 §3.6). Kosher and halal are flexible, but a
  /// "fits" beside them would read as "kosher" or "halal", which only the
  /// restaurant can say.
  strict;

  /// The wording for [profile] in a build with [bantoMode].
  static ProfileWording of(
    DietaryProfile profile, {
    bool bantoMode = BantoMode.enabled,
  }) {
    if (!bantoMode || !profile.hasNonKetoEntry) return ketoOnly;
    return profile.hasStrictEntry || profile.hasReligiousEntry
        ? strict
        : flexible;
  }

  /// Whether the menu screen shows four states rather than three verdicts.
  bool get usesStates => this != ketoOnly;
}

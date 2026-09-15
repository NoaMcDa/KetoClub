/// The menu-level "keto score" shown on the classified menu screen's
/// header (issue #29's artboard shows e.g. `9.1`), computed from the
/// verdict counts a [MenuAnalysed](`lib/models/analysis.dart`) result
/// produces.
library;

/// How much a modifiable (yellow) dish counts toward [ketoScore], relative
/// to a green dish's full weight of 1.0.
///
/// This lives here, not in `lib/utils/constants.dart`, because this file
/// does not own that file (see the pull request that added this one); a
/// weight this local to one formula is arguably better kept next to it
/// regardless.
const double _yellowWeight = 0.5;

/// Scores a menu's overall keto-friendliness out of 10, from how many of
/// its dishes the classifier placed in each verdict.
///
/// `score = 10 * (green + 0.5 * yellow) / (green + yellow + red)`, rounded
/// to one decimal place. A green dish counts in full, a yellow one at
/// [_yellowWeight] because it needs a swap before it is safe to order, and
/// a red dish counts for nothing but still enlarges the denominator, so a
/// menu that leans non-keto scores lower even though no red dish adds to
/// the numerator.
///
/// **Unclassified dishes play no part in this formula at all** — there is
/// no `unclassifiedCount` parameter, and dishes the classifier could not
/// place are counted in neither the weighted sum nor the denominator.
/// They were never judged, so treating "the model stayed silent on this
/// dish" the same as "the model judged it and found it non-keto" would
/// let the engine's own gaps drag a menu's score down for something that
/// was never actually checked.
///
/// Returns null when [greenCount] + [yellowCount] + [redCount] is 0 —
/// no dish was placed at all, whether because the menu is empty or
/// because the analysis found nothing to classify — rather than a
/// spurious `0.0`. **Callers must not show a score at all unless the menu
/// has a `MenuAnalysed` result** (`MenuController.ketoScoreOutOfTen`
/// already enforces this): a `MenuAnalysisFailed` result has no verdict
/// counts to compute from, and rendering null there as `0.0` would tell
/// the user "this menu is zero keto-friendly", a materially different and
/// false claim from "we could not read this menu".
///
/// This formula, and the 0.5 yellow weight in particular, is invented
/// product logic with no nutrition research behind it — there is no
/// source for "a dish that needs one swap is worth exactly half a safe
/// one" beyond it sounding reasonable. It renders as a single, confident
/// decimal next to food a person is about to order and eat, which claims
/// more precision and authority than the formula actually has. Issue #41
/// (Phase 2) is where this gets a real basis, changes, or is removed
/// outright; nothing here should be read as settled.
double? ketoScore({
  required int greenCount,
  required int yellowCount,
  required int redCount,
}) {
  final total = greenCount + yellowCount + redCount;
  if (total == 0) return null;
  final weighted = greenCount + _yellowWeight * yellowCount;
  final score = 10 * weighted / total;
  return double.parse(score.toStringAsFixed(1));
}

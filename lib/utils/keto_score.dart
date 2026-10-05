/// The menu-level "keto score" shown on the classified menu screen's
/// header (issue #29's artboard shows e.g. `9.1`), computed from the
/// verdict counts a [MenuAnalysed](`lib/models/analysis.dart`) result
/// produces.
library;

/// How much a modifiable (yellow) dish with no hidden-carb flag counts
/// toward [ketoScore], relative to a green dish's full weight of 1.0.
///
/// This lives here, not in `lib/utils/constants.dart`, because this file
/// does not own that file (see the pull request that added this one); a
/// weight this local to one formula is arguably better kept next to it
/// regardless.
const double _yellowWeight = 0.5;

/// How much a hidden-carb-demoted yellow dish counts toward [ketoScore],
/// relative to a green dish's full weight of 1.0 (issue #213).
///
/// Lower than [_yellowWeight] (0.5) because the dish was only demoted
/// because a hidden ingredient is *suspected* — the waiter may confirm
/// the dish is actually safe, so it is not quite as penalising as a
/// definitively-modified yellow. Decision D13 (architecture.md §14)
/// states the formula is a UI ranking heuristic with no nutrition basis.
const double _hiddenCarbYellowWeight = 0.25;

/// Scores a menu's overall keto-friendliness out of 10, from how many of
/// its dishes the classifier placed in each verdict.
///
/// `score = 10 * (green + 0.5 * otherYellow + 0.25 * hiddenYellow)`
/// `/  (green + otherYellow + hiddenYellow + red)`, rounded to one
/// decimal place. A green dish counts in full; a yellow with modifications
/// (but no hidden-carb flag) counts at [_yellowWeight] (0.5); a
/// hidden-carb-demoted yellow counts at [_hiddenCarbYellowWeight] (0.25)
/// — lower because the demotion may be a false alarm the waiter can clear
/// up on the spot; a red dish counts for nothing but enlarges the
/// denominator (issue #213, architecture.md D13).
///
/// **Unclassified dishes play no part in this formula at all** — there is
/// no `unclassifiedCount` parameter, and dishes the classifier could not
/// place are counted in neither the weighted sum nor the denominator.
/// They were never judged, so treating "the model stayed silent on this
/// dish" the same as "the model judged it and found it non-keto" would
/// let the engine's own gaps drag a menu's score down for something that
/// was never actually checked.
///
/// Returns null when the total is 0 — no dish was placed at all, whether
/// because the menu is empty or because the analysis found nothing to
/// classify — rather than a spurious `0.0`. **Callers must not show a
/// score at all unless the menu has a `MenuAnalysed` result**
/// (`MenuController.ketoScoreOutOfTen` already enforces this): a
/// `MenuAnalysisFailed` result has no verdict counts to compute from,
/// and rendering null there as `0.0` would tell the user "this menu is
/// zero keto-friendly", a materially different and false claim from "we
/// could not read this menu".
///
/// **Which dishes feed the counts is decided upstream, in
/// `utils/verdict_counts.dart` (D21): food only.** A drink, a sauce or
/// add-on, or a notice line is classified and listed but never counted,
/// so ten safe drinks cannot lift a menu's score; every caller reduces
/// an analysis through `VerdictCounts.of` rather than counting verdicts
/// itself.
///
/// This formula is invented product logic with no nutrition research
/// behind it. Decision D13 (architecture.md §14, issue #41) looked for
/// a basis, found none, and kept the formula with that status stated
/// plainly: a UI ranking heuristic, never a health claim. The venue
/// cards reuse this function rather than a second formula, show it only
/// from an analysis already cached, and mark rules-only numbers as an
/// estimate through the engine label.
double? ketoScore({
  required int greenCount,
  required int hiddenCarbYellowCount,
  required int otherYellowCount,
  required int redCount,
}) {
  final yellowCount = hiddenCarbYellowCount + otherYellowCount;
  final total = greenCount + yellowCount + redCount;
  if (total == 0) return null;
  final weighted =
      greenCount +
      _yellowWeight * otherYellowCount +
      _hiddenCarbYellowWeight * hiddenCarbYellowCount;
  final score = 10 * weighted / total;
  return double.parse(score.toStringAsFixed(1));
}

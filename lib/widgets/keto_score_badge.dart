import 'package:flutter/material.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/theme/app_typography.dart';
import 'package:ketoclub/theme/verdict_colors.dart';

/// The score at or above which the badge reads as a positive claim (green).
const double ketoScoreGreenFloor = 7;

/// The score at or above which the badge reads as a middling one (amber);
/// below it the badge is muted.
const double ketoScoreAmberFloor = 4;

/// The tone the keto score digit is drawn in (issue #241): `green.ink` from
/// [ketoScoreGreenFloor] up, `amber.ink` from [ketoScoreAmberFloor] up to
/// that, and [muted] below — a low score must not read as a positive claim.
///
/// Pure. The score is rounded to the one decimal place the badge prints
/// first, so a "7.0" on screen is never toned as a 6.x.
Color scoreTone(
  double score, {
  required VerdictColors verdicts,
  required Color muted,
}) {
  final shown = double.parse(score.toStringAsFixed(1));
  if (shown >= ketoScoreGreenFloor) return verdicts.green.ink;
  if (shown >= ketoScoreAmberFloor) return verdicts.amber.ink;
  return muted;
}

/// The menu header's keto score (issue #29): a serif-display digit over a
/// small uppercase "KETO SCORE" label, matching `.design/Main.dc.html`'s
/// header row.
///
/// **Renders nothing when [score] is null**, never a fallback `0.0`.
/// `MenuController.ketoScoreOutOfTen`'s own doc comment explains why: null
/// means "not computable" — no `MenuAnalysed` result to score from — and
/// rendering it as zero would tell the user "this menu is zero
/// keto-friendly", a materially different and false claim. This widget is
/// the one call site that renders the score, so keeping that promise here
/// is what keeps it everywhere.
class KetoScoreBadge extends StatelessWidget {
  /// Creates a badge for [score], out of 10, or an empty widget when
  /// [score] is null.
  const new({required this.score, this.inline = false, super.key});

  /// The score to show, out of 10 — see `MenuController.ketoScoreOutOfTen`
  /// for how it is computed — or null to render nothing.
  final double? score;

  /// Whether to set the label beside the number, on its baseline, at the
  /// venue card's smaller size (`.design/Discovery.dc.html`: a 17px number
  /// then the label) rather than stacked under a 24px number as in the
  /// menu header (`.design/Main.dc.html`).
  final bool inline;

  @override
  Widget build(BuildContext context) {
    final currentScore = score;
    if (currentScore == null) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    // Toned by band (issue #241), not a fixed green: a 3.2 must not read
    // as a positive claim. The muted band is the theme's `ink3`.
    final scoreColor = scoreTone(
      currentScore,
      verdicts: VerdictColors.of(context),
      muted: theme.colorScheme.onSurfaceVariant,
    );
    final labelStyle = theme.textTheme.labelSmall;
    final formatted = currentScore.toStringAsFixed(1);

    final number = Text(
      formatted,
      style: AppTypography.displayStyle(
        size: inline ? 17 : 24,
        color: scoreColor,
      ),
    );
    final label = Text(
      // `text-transform: uppercase` in the artboard is presentational
      // only; `toUpperCase()` is a no-op on the Hebrew string, which
      // has no case, so this stays correct in both languages.
      l10n.menuKetoScoreLabel.toUpperCase(),
      style: labelStyle?.copyWith(fontSize: 9, letterSpacing: 0.8),
    );

    return Semantics(
      label: l10n.menuKetoScoreSemanticLabel(formatted),
      excludeSemantics: true,
      // Both call sites (`VenueCard`'s header, `MenuScreen`'s header)
      // place this badge as a non-flexible sibling of an `Expanded` name,
      // itself often inside a `Column` — the chain hands a non-flex
      // child unbounded constraints on *both* axes for measurement
      // (Flutter's own Flex layout algorithm), so a bare `FittedBox`
      // here would itself throw ("was given an infinite size during
      // layout") rather than merely overflow. Capping both `maxWidth`
      // and `maxHeight` below is what makes the constraints `FittedBox`
      // sees always finite, regardless of what an ambient Row/Column
      // offers; at a large text scale (architecture.md §8.3's pass), the
      // "KETO SCORE" label is the widest part of the badge and can by
      // itself outgrow that cap, so `FittedBox` shrinks the whole badge
      // to fit it rather than overflowing the header `Row` on its
      // trailing side. Neither bound clips this badge at a normal text
      // scale — its natural size is well under both.
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 160, maxHeight: 80),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.topEnd,
          child: inline
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [number, const SizedBox(width: 4), label],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [number, label],
                ),
        ),
      ),
    );
  }
}

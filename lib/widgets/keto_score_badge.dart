import 'package:flutter/material.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/theme/app_typography.dart';
import 'package:ketoclub/theme/verdict_colors.dart';

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
  const new({required this.score, super.key});

  /// The score to show, out of 10 — see `MenuController.ketoScoreOutOfTen`
  /// for how it is computed — or null to render nothing.
  final double? score;

  @override
  Widget build(BuildContext context) {
    final currentScore = score;
    if (currentScore == null) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    // The artboard renders the digit in `--green-ink` regardless of the
    // score's own value — a fixed "positive" tone for the whole badge, not
    // a severity gradient — so this reads `VerdictColors.of` rather than
    // branching on `currentScore`.
    final scoreColor = VerdictColors.of(context).green.ink;
    final labelStyle = theme.textTheme.labelSmall;
    final formatted = currentScore.toStringAsFixed(1);

    return Semantics(
      label: l10n.menuKetoScoreSemanticLabel(formatted),
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            formatted,
            style: AppTypography.displayStyle(size: 24, color: scoreColor),
          ),
          Text(
            // `text-transform: uppercase` in the artboard is presentational
            // only; `toUpperCase()` is a no-op on the Hebrew string, which
            // has no case, so this stays correct in both languages.
            l10n.menuKetoScoreLabel.toUpperCase(),
            style: labelStyle?.copyWith(letterSpacing: 1.1),
          ),
        ],
      ),
    );
  }
}

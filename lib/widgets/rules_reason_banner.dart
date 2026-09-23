import 'package:flutter/material.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/widgets/failure_copy.dart';

/// A non-blocking banner naming why a menu's analysis is a rules result,
/// shown above the dish list (issue #119).
///
/// `EngineChip` already names the reason in a chip-sized phrase; this
/// widget renders the full, localised sentence [analysisFailureMessage]
/// already writes for a hard [MenuAnalysisFailed] — today that sentence
/// was rendered only for that hard failure, never for a [MenuAnalysed]
/// result stamped [RulesEngine], even though both carry the identical
/// [MenuAnalysisFailureReason] and both leave the user reading rule-based
/// verdicts without knowing why the AI engine did not answer.
///
/// Renders nothing for [LlmEngine] — an AI result needs no explanation —
/// so a caller can pass `MenuController.engine` straight through without
/// its own null or type check. [MenuAnalysisFailureReason.consentWithheld]
/// is the one reason the user can fix from this very screen, so its
/// banner alone offers a shortcut to Settings, reusing the app bar
/// action's own `/settings` route name rather than a new one — this
/// widget's layer (architecture.md §5) sits below `app.dart`, which owns
/// that constant, so the route name is written out here exactly as
/// `menu_screen.dart`'s own Settings action already does.
class RulesReasonBanner extends StatelessWidget {
  /// Creates a banner for the engine that produced an analysis, or
  /// nothing when [engine] is an [LlmEngine] result.
  const new({required this.engine, super.key});

  /// Which engine produced the analysis being shown.
  final AnalysisEngine engine;

  @override
  Widget build(BuildContext context) {
    final rules = engine;
    if (rules is! RulesEngine) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final message = analysisFailureMessage(rules.reason, l10n);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline,
                size: 18,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(color: colorScheme.onSurfaceVariant),
                ),
              ),
              if (rules.reason == MenuAnalysisFailureReason.consentWithheld)
                _settingsAction(context, l10n, colorScheme),
            ],
          ),
        ),
      ),
    );
  }

  /// The "Open Settings" action shown only for
  /// [MenuAnalysisFailureReason.consentWithheld] — the one reason the user
  /// can fix from Settings, which is why no other reason gets an action.
  Widget _settingsAction(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme colorScheme,
  ) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: TextButton(
        onPressed: () => Navigator.pushNamed(context, '/settings'),
        style: TextButton.styleFrom(foregroundColor: colorScheme.primary),
        child: Text(l10n.actionOpenSettings),
      ),
    );
  }
}

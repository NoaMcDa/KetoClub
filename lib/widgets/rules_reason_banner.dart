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
///
/// **Retry, for the reasons that can genuinely turn out differently on a
/// second try (issue #68).** [MenuAnalysisFailureReason.offline],
/// [MenuAnalysisFailureReason.timeout],
/// [MenuAnalysisFailureReason.rateLimited],
/// [MenuAnalysisFailureReason.badResponse] and
/// [MenuAnalysisFailureReason.backendUnreachable] each offer [onRetry] as
/// a button, when a caller supplies one — architecture.md §10's table
/// names "retry" or "retry / report" as every one of their ways out.
/// [MenuAnalysisFailureReason.notConfigured] gets no action: its own way
/// out is "none from the app". [onRetry] is otherwise unused; passing one
/// costs nothing for a reason that never renders it.
class RulesReasonBanner extends StatelessWidget {
  /// Creates a banner for the engine that produced an analysis, or
  /// nothing when [engine] is an [LlmEngine] result. [onRetry], when
  /// given, backs the Retry action shown for every reason this class doc
  /// comment lists as retryable.
  const new({required this.engine, this.onRetry, super.key});

  /// Which engine produced the analysis being shown.
  final AnalysisEngine engine;

  /// Re-runs the analysis that produced [engine]. Read only for a reason
  /// this widget renders a Retry action for.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final rules = engine;
    if (rules is! RulesEngine) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final message = analysisFailureMessage(rules.reason, l10n);
    final retryCallback = onRetry;

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
              if (retryCallback != null && _isRetryable(rules.reason))
                _retryAction(l10n, colorScheme, retryCallback),
            ],
          ),
        ),
      ),
    );
  }

  /// Whether [reason] offers a Retry action, per this class doc comment.
  /// An exhaustive switch with no `default`: adding a reason without
  /// deciding whether it retries is a compile error (architecture.md
  /// §10).
  static bool _isRetryable(MenuAnalysisFailureReason reason) =>
      switch (reason) {
        MenuAnalysisFailureReason.offline => true,
        MenuAnalysisFailureReason.timeout => true,
        MenuAnalysisFailureReason.rateLimited => true,
        MenuAnalysisFailureReason.badResponse => true,
        MenuAnalysisFailureReason.backendUnreachable => true,
        MenuAnalysisFailureReason.notConfigured => false,
        MenuAnalysisFailureReason.consentWithheld => false,
        MenuAnalysisFailureReason.noDishesFound => false,
      };

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

  /// The Retry action shown for every reason [_isRetryable] approves.
  Widget _retryAction(
    AppLocalizations l10n,
    ColorScheme colorScheme,
    VoidCallback onRetry,
  ) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: TextButton(
        onPressed: onRetry,
        style: TextButton.styleFrom(foregroundColor: colorScheme.primary),
        child: Text(l10n.actionRetry),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/widgets/app_notice.dart';
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
/// its own null or type check. [MenuAnalysisFailureReason.consentWithheld],
/// [MenuAnalysisFailureReason.apiKeyMissing] and
/// [MenuAnalysisFailureReason.apiKeyRejected] are the reasons the user can
/// fix from Settings, so their banners alone offer a shortcut there,
/// reusing the app bar action's own `/settings` route name rather than a
/// new one — this
/// widget's layer (architecture.md §5) sits below `app.dart`, which owns
/// that constant, so the route name is written out here exactly as
/// `menu_screen.dart`'s own Settings action already does.
///
/// Drawn as an [AppNotice.info] line (issue #260): it explains, it asks
/// for nothing, so it is one muted line with an icon, and its actions move
/// under the text on a phone-width screen rather than squeezing it.
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
    final message = analysisFailureMessage(rules.reason, l10n);
    final retryCallback = onRetry;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppNotice.info(
        message: message,
        actions: [
          if (_isFixableInSettings(rules.reason))
            _settingsAction(context, l10n),
          if (retryCallback != null && _isRetryable(rules.reason))
            _retryAction(l10n, retryCallback),
        ],
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
        MenuAnalysisFailureReason.apiKeyMissing => false,
        MenuAnalysisFailureReason.apiKeyRejected => false,
        MenuAnalysisFailureReason.noDishesFound => false,
      };

  /// Whether [reason] is one the user fixes in Settings, and so offers the
  /// "Open Settings" action: consent withheld, or the Gemini key used on
  /// iOS and Android missing or refused (architecture.md D17). Retrying
  /// cannot help any of them, which is why none of them is retryable.
  /// An exhaustive switch with no `default`, like [_isRetryable].
  static bool _isFixableInSettings(MenuAnalysisFailureReason reason) =>
      switch (reason) {
        MenuAnalysisFailureReason.consentWithheld => true,
        MenuAnalysisFailureReason.apiKeyMissing => true,
        MenuAnalysisFailureReason.apiKeyRejected => true,
        MenuAnalysisFailureReason.offline => false,
        MenuAnalysisFailureReason.timeout => false,
        MenuAnalysisFailureReason.rateLimited => false,
        MenuAnalysisFailureReason.badResponse => false,
        MenuAnalysisFailureReason.backendUnreachable => false,
        MenuAnalysisFailureReason.notConfigured => false,
        MenuAnalysisFailureReason.noDishesFound => false,
      };

  /// The "Open Settings" action shown only for the reasons
  /// [_isFixableInSettings] approves — the ones the user can fix from
  /// Settings, which is why no other reason gets this action.
  AppNoticeAction _settingsAction(BuildContext context, AppLocalizations l10n) {
    return AppNoticeAction(
      label: l10n.actionOpenSettings,
      onPressed: () => Navigator.pushNamed(context, '/settings'),
    );
  }

  /// The Retry action shown for every reason [_isRetryable] approves.
  AppNoticeAction _retryAction(AppLocalizations l10n, VoidCallback onRetry) {
    return AppNoticeAction(label: l10n.actionRetry, onPressed: onRetry);
  }
}

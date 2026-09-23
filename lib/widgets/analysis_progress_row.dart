import 'package:flutter/material.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
// `show`, because material.dart exports a `MenuController` of its own and
// this file needs only the phase enum.
import 'package:ketoclub/state/menu_controller.dart' show LoadPhase;

/// The "what is happening now" row shown above an unjudged menu while it
/// is being classified (issue #65): a small spinner and a label naming
/// the engine at work — "Asking the AI…" or "Applying the rules…" — or a
/// neutral "Analysing the menu…" before either has started.
///
/// Renders nothing outside [LoadPhase.isClassifying]: fetching has its
/// own full-screen copy on the menu screen, and an idle screen has
/// nothing to wait for. The label is a live region, so a screen reader
/// hears the engine change when an AI call falls back to the rules.
class AnalysisProgressRow extends StatelessWidget {
  /// Creates a row describing [phase].
  const new({required this.phase, super.key});

  /// The menu controller's current phase.
  final LoadPhase phase;

  @override
  Widget build(BuildContext context) {
    final label = _labelFor(phase, AppLocalizations.of(context)!);
    if (label == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          const SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Semantics(
              liveRegion: true,
              child: Text(label, style: theme.textTheme.bodyMedium),
            ),
          ),
        ],
      ),
    );
  }
}

/// The progress copy for [phase], or null when [phase] is not a
/// classifying phase and no row is shown.
///
/// An exhaustive switch with no `default`, so a new [LoadPhase] value has
/// to be placed deliberately (architecture.md §10).
String? _labelFor(LoadPhase phase, AppLocalizations l10n) => switch (phase) {
  LoadPhase.idle || LoadPhase.fetching => null,
  LoadPhase.classifying => l10n.menuProgressAnalysing,
  LoadPhase.classifyingLlm => l10n.menuProgressAskingAi,
  LoadPhase.classifyingRules => l10n.menuProgressApplyingRules,
};

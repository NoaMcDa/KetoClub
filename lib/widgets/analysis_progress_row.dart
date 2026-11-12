import 'package:flutter/material.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
// `show`, because material.dart exports a `MenuController` of its own and
// this file needs only the phase enum.
import 'package:ketoclub/state/menu_controller.dart' show LoadPhase;
import 'package:ketoclub/widgets/keto_loader.dart';

/// The "what is happening now" row shown above an unjudged menu while it
/// is being classified (issue #65): a [KetoLoaderStrip] — the small orbit
/// of a steak, an egg and a lettuce leaf (issue #451) — naming the engine
/// at work, "Asking the AI…" or "Applying the rules…", or a neutral
/// "Analysing the menu…" before either has started, with a line of
/// kitchen talk under it while the wait goes on.
///
/// Renders nothing outside [LoadPhase.isClassifying]: fetching has its
/// own loader on the menu screen, and an idle screen has nothing to wait
/// for. The label is a live region, so a screen reader hears the engine
/// change when an AI call falls back to the rules; the kitchen talk is
/// never announced.
class AnalysisProgressRow extends StatelessWidget {
  /// Creates a row describing [phase].
  const new({required this.phase, super.key});

  /// The menu controller's current phase.
  final LoadPhase phase;

  @override
  Widget build(BuildContext context) {
    final label = _labelFor(phase, AppLocalizations.of(context)!);
    if (label == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: KetoLoaderStrip(status: label),
    );
  }
}

String? _labelFor(LoadPhase phase, AppLocalizations l10n) => switch (phase) {
  LoadPhase.idle || LoadPhase.fetching => null,
  LoadPhase.classifying => l10n.menuProgressAnalysing,
  LoadPhase.classifyingLlm => l10n.menuProgressAskingAi,
  LoadPhase.classifyingRules => l10n.menuProgressApplyingRules,
};

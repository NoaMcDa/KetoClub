import 'package:flutter/material.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/failures.dart';

/// Which engine produced a menu analysis: the AI model, or the on-device
/// rules fallback (architecture.md §6.2, §6.6).
///
/// The AI variant names the model that answered ("AI · {model}"); the
/// rules variant always carries the reason the LLM was not used
/// ("Rules ({reason})"), both in the chip itself and — since the rules
/// variant also always carries the "not AI-verified" meaning, that its
/// greens have not been checked by the LLM — as a [Tooltip] so that
/// meaning is available without depending on colour.
///
/// Each label is built from two sibling [Text] widgets rather than one
/// interpolated string, so a caller can still find the bare "AI" or
/// "Rules" text by itself (as the flow tests and `menu_screen.dart` do)
/// while the chip reads as one phrase visually. A [Semantics] wrapper
/// gives a screen reader the full phrase as a single announcement.
///
/// Neither engine is a keto verdict, so this reads its colours from
/// [ColorScheme] rather than `VerdictColors` (architecture.md §6.6): the AI
/// engine uses the theme's primary/accent colour, and the rules fallback a
/// neutral outline colour, so the chip stays legible in both themes without
/// its own hard-coded palette.
class EngineChip extends StatelessWidget {
  /// Creates a chip for [engine].
  const new({required this.engine, super.key});

  /// Which engine produced the analysis being shown.
  final AnalysisEngine engine;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    return switch (engine) {
      LlmEngine(:final model) => Semantics(
        label: l10n.engineChipAiSemanticLabel(model),
        excludeSemantics: true,
        child: _chip(
          icon: Icons.auto_awesome,
          color: colorScheme.primary,
          labelParts: [l10n.engineChipAi, ' · $model'],
        ),
      ),
      RulesEngine(:final reason) => Semantics(
        label: l10n.engineChipRulesSemanticLabel(_reasonLabel(reason, l10n)),
        excludeSemantics: true,
        child: Tooltip(
          message: l10n.rulesNotVerifiedHint,
          child: _chip(
            icon: Icons.rule,
            color: colorScheme.onSurfaceVariant,
            labelParts: [
              l10n.engineChipRules,
              ' (${_reasonLabel(reason, l10n)})',
            ],
          ),
        ),
      ),
    };
  }

  Widget _chip({
    required IconData icon,
    required Color color,
    required List<String> labelParts,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            for (final part in labelParts)
              Text(
                part,
                style: TextStyle(color: color, fontWeight: FontWeight.w600),
              ),
          ],
        ),
      ),
    );
  }
}

/// A short, chip-sized phrase naming why the router fell back to the rules
/// engine for [reason], read from [l10n].
///
/// An exhaustive switch with no `default`: adding a
/// [MenuAnalysisFailureReason] value without updating this function is a
/// compile error (architecture.md §10). [MenuAnalysisFailureReason
/// .unauthorised] never reaches [RulesEngine] in practice — the router
/// never falls back for it (architecture.md §6.2) — but the switch still
/// covers it so this stays exhaustive if that ever changes.
String _reasonLabel(
  MenuAnalysisFailureReason reason,
  AppLocalizations l10n,
) => switch (reason) {
  MenuAnalysisFailureReason.notConfigured => l10n.engineChipReasonNotConfigured,
  MenuAnalysisFailureReason.offline => l10n.engineChipReasonOffline,
  MenuAnalysisFailureReason.timeout => l10n.engineChipReasonTimeout,
  MenuAnalysisFailureReason.rateLimited => l10n.engineChipReasonRateLimited,
  MenuAnalysisFailureReason.unauthorised => l10n.engineChipReasonUnauthorised,
  MenuAnalysisFailureReason.badResponse => l10n.engineChipReasonBadResponse,
  MenuAnalysisFailureReason.noDishesFound => l10n.engineChipReasonNoDishesFound,
};

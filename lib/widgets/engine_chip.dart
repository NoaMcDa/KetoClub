import 'package:flutter/material.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/models/analysis.dart';

/// Which engine produced a menu analysis: the AI model, or the on-device
/// rules fallback (architecture.md §6.2, §6.6).
///
/// The AI variant names the model that answered ("AI · {model}"). The
/// rules variant reads just "Rules": the reason the LLM was not used
/// lives beside this chip in the rules-reason banner, so restating it
/// here used to read as the same thing twice on one screen (issue
/// #169). The
/// [Tooltip] still explains "not AI-verified" so a user hovering the
/// chip understands the difference between the two engines. A screen
/// reader hears "Rules engine, not AI-verified" as one announcement, so
/// the reason phrase is not lost from accessibility either — it moves to
/// the banner, which is where the sighted user sees it.
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
      RulesEngine() => Semantics(
        // The semantic label deliberately no longer names the reason
        // (issue #169). The rules banner beside this chip already
        // announces the reason as a full sentence; a screen reader
        // hearing both would hear the same reason twice.
        label: l10n.rulesNotVerifiedHint,
        excludeSemantics: true,
        child: Tooltip(
          message: l10n.rulesNotVerifiedHint,
          child: _chip(
            icon: Icons.rule,
            color: colorScheme.onSurfaceVariant,
            labelParts: [l10n.engineChipRules],
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

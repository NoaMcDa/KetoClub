import 'package:flutter/material.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/models/analysis.dart';

/// Which engine produced a menu analysis: the AI model, or the on-device
/// rules fallback (architecture.md §6.2, §6.6).
///
/// The rules variant always carries the "not AI-verified" meaning — its
/// greens have not been checked by the LLM — surfaced here as a
/// [Tooltip] so it is available without depending on colour.
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
      LlmEngine() => _chip(
        icon: Icons.auto_awesome,
        label: l10n.engineChipAi,
        color: colorScheme.primary,
      ),
      RulesEngine() => Tooltip(
        message: l10n.rulesNotVerifiedHint,
        child: _chip(
          icon: Icons.rule,
          label: l10n.engineChipRules,
          color: colorScheme.onSurfaceVariant,
        ),
      ),
    };
  }

  Widget _chip({
    required IconData icon,
    required String label,
    required Color color,
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
            Text(
              label,
              style: TextStyle(color: color, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

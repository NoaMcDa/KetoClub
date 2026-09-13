import 'package:flutter/material.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/models/analysis.dart';

/// Which engine produced a menu analysis: the AI model, or the on-device
/// rules fallback (architecture.md §6.2, §6.6).
///
/// The rules variant always carries the "not AI-verified" meaning — its
/// greens have not been checked by the LLM — surfaced here as a
/// [Tooltip] so it is available without depending on colour.
class EngineChip extends StatelessWidget {
  /// Creates a chip for [engine].
  const new({required this.engine, super.key});

  /// Which engine produced the analysis being shown.
  final AnalysisEngine engine;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return switch (engine) {
      LlmEngine() => _chip(
        icon: Icons.auto_awesome,
        label: l10n.engineChipAi,
        color: Colors.blue.shade700,
      ),
      RulesEngine() => Tooltip(
        message: l10n.rulesNotVerifiedHint,
        child: _chip(
          icon: Icons.rule,
          label: l10n.engineChipRules,
          color: Colors.grey.shade700,
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

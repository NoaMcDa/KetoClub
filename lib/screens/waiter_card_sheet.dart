import 'package:flutter/material.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/widgets/waiter_script_widget.dart';

/// The full-screen waiter card: [row]'s modification, shown large enough
/// and with enough contrast to hand the phone across a table
/// (architecture.md §6.3).
///
/// The dish name is rendered exactly as printed, in the menu's own
/// language, matching [WaiterScriptWidget.script]'s convention
/// (architecture.md §12) — neither is translated to the UI language.
class WaiterCardSheet extends StatelessWidget {
  /// Creates a card for [row]. In practice [row]'s analysis is always a
  /// [DishVerdict.modifiable] verdict, since the menu screen only opens
  /// this sheet from a dish card's own script affordance, shown for no
  /// other verdict; a row with no modification renders the dish name with
  /// no script section rather than crashing, since a screen must never
  /// fail to show what it already has.
  const new({required this.row, super.key});

  /// The dish, its category, and its verdict.
  final DishRow row;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final script = row.analysis?.modification;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(24, 24, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.waiterCardTitle, style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Text(row.dish.name, style: theme.textTheme.headlineSmall),
            if (script != null) ...[
              const SizedBox(height: 24),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  border: Border.all(color: theme.colorScheme.outline),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: DefaultTextStyle.merge(
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface,
                      height: 1.3,
                    ),
                    child: WaiterScriptWidget(script: script),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

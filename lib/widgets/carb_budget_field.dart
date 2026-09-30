import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/state/carb_budget_controller.dart';
import 'package:provider/provider.dart';

/// A numeric text field that lets the user set a per-session net-carb
/// budget (issue #215).
///
/// When [isBudgetAvailable] is false (rules engine, or no analysis yet),
/// the field is replaced by a disabled-state banner explaining why, styled
/// like the field's own container. The field is always shown for an LLM
/// result, even mid-load, so the user can type the budget before the menu
/// finishes classifying.
///
/// Reads and writes [CarbBudgetController] from the [MultiProvider] above
/// [MaterialApp].
class CarbBudgetField extends StatefulWidget {
  /// Creates the field.
  ///
  /// [isBudgetAvailable] should be
  /// `controller.isBudgetAvailable` from the enclosing [MenuController].
  const new({required this.isBudgetAvailable, super.key});

  /// Whether the budget can be applied to the current analysis.
  ///
  /// False when there is no LLM analysis yet — the budget field requires
  /// a net-carb estimate on each dish to be meaningful.
  final bool isBudgetAvailable;

  @override
  State<CarbBudgetField> createState() => _CarbBudgetFieldState();
}

class _CarbBudgetFieldState extends State<CarbBudgetField> {
  late final TextEditingController _text;

  @override
  void initState() {
    super.initState();
    final budget = context.read<CarbBudgetController>();
    _text = TextEditingController(text: budget.budgetGrams?.toString() ?? '');
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _onSubmit(String value) {
    final budget = context.read<CarbBudgetController>();
    final parsed = int.tryParse(value.trim());
    if (parsed == null) {
      budget.clear();
    } else {
      budget.setBudget(parsed);
      // Mirror the clamped value back into the text field.
      final clamped = budget.budgetGrams;
      if (clamped != null && clamped.toString() != value.trim()) {
        _text.text = clamped.toString();
      }
    }
  }

  void _onClear() {
    context.read<CarbBudgetController>().clear();
    _text.clear();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (!widget.isBudgetAvailable) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(
                Icons.nightlight_round,
                size: 16,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.carbBudgetDisabledReason,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListenableBuilder(
      listenable: context.watch<CarbBudgetController>(),
      builder: (context, _) {
        final budget = context.read<CarbBudgetController>();
        final hasBudget = budget.hasBudget;
        return TextField(
          controller: _text,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          textInputAction: TextInputAction.done,
          onSubmitted: _onSubmit,
          onEditingComplete: () => _onSubmit(_text.text),
          decoration: InputDecoration(
            labelText: l10n.carbBudgetFieldLabel,
            hintText: l10n.carbBudgetFieldHint,
            suffixIcon: hasBudget
                ? IconButton(
                    tooltip: l10n.carbBudgetFieldClear,
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: _onClear,
                  )
                : null,
            isDense: true,
          ),
        );
      },
    );
  }
}

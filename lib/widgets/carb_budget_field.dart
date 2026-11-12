import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/state/carb_budget_controller.dart';
import 'package:provider/provider.dart';

/// A numeric text field that lets the user set a per-session net-carb
/// budget (issue #215).
///
/// When [isBudgetAvailable] is false (rules engine, or no analysis yet),
/// nothing is rendered (issue #235): a user who cannot use the feature is
/// not shown a notice about it on every menu, and the menu legend mentions
/// the budget once instead. The field is always shown for an LLM result,
/// even mid-load, so the user can type the budget before the menu finishes
/// classifying.
///
/// Reads and writes [CarbBudgetController] from the [MultiProvider] above
/// [MaterialApp], and follows it (issue #286): a budget cleared or set
/// elsewhere — the menu's "Clear filter" — shows here at once, rather than
/// the number the field was built with.
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

  /// The budget this field shows and follows ([_follow]).
  late final CarbBudgetController _budget;

  @override
  void initState() {
    super.initState();
    _budget = context.read<CarbBudgetController>()..addListener(_follow);
    _text = TextEditingController(text: _shown(_budget.budgetGrams));
  }

  @override
  void dispose() {
    _budget.removeListener(_follow);
    _text.dispose();
    super.dispose();
  }

  /// The field's text for [grams]: the number, or empty for no budget.
  static String _shown(int? grams) => grams?.toString() ?? '';

  /// Puts the controller's budget in the field whenever it changes, from
  /// here (the clamped value) or from anywhere else (issue #286).
  void _follow() {
    final shown = _shown(_budget.budgetGrams);
    if (_text.text != shown) _text.text = shown;
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

    if (!widget.isBudgetAvailable) return const SizedBox.shrink();

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

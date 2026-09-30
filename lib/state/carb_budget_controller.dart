import 'package:flutter/foundation.dart';

/// Session-only net-carb budget for tonight (issue #215).
///
/// Sits alongside `LocaleController` and `ThemeModeController` in the
/// `MultiProvider` above `MaterialApp`, so every route can reach it via
/// `context.read<CarbBudgetController>()`. Unlike those two, it has no
/// persistence — no `SettingsStore` dependency, no `.load()`, no write —
/// because a budget for tonight is intentionally ephemeral: it resets when
/// the app is fully restarted (D8 clarification, architecture.md §14).
///
/// The budget is an inclusive upper bound in grams: a dish with a
/// `netCarbsEstimate` of exactly [budgetGrams] passes the filter.
/// Dishes with no estimate are never filtered out: the filter is only
/// meaningful for values the LLM engine produced, and silently hiding
/// estimate-less dishes would misrepresent the menu.
final class CarbBudgetController extends ChangeNotifier {
  /// Creates a controller with no budget set.
  ///
  /// No I/O is performed here, matching the rule in CLAUDE.md that no
  /// constructor reached from `di.dart` may perform plugin I/O.
  new();

  int? _budgetGrams;

  /// The current budget in grams, or null when none has been set.
  int? get budgetGrams => _budgetGrams;

  /// Whether a budget is set. Convenience for widgets and
  /// `MenuController.isBudgetAvailable`.
  bool get hasBudget => _budgetGrams != null;

  /// Sets the budget to [grams], clamped to the range 1–150 (grams).
  ///
  /// Values below 1 are treated as 1; values above 150 are treated as 150.
  /// Notifies listeners whenever the stored value actually changes.
  void setBudget(int grams) {
    final clamped = grams.clamp(1, 150);
    if (clamped == _budgetGrams) return;
    _budgetGrams = clamped;
    notifyListeners();
  }

  /// Clears the budget; notifies listeners when one was set.
  void clear() {
    if (_budgetGrams == null) return;
    _budgetGrams = null;
    notifyListeners();
  }
}

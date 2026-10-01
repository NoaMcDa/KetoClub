import 'package:flutter/material.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';

/// The menu screen's collapsible "Filters" row (issue #234): one compact
/// disclosure line above the category chips, with the search field, the
/// carb budget and the verdict legend — passed in as [child] — behind it,
/// so the first dish card fits on a phone screen without scrolling.
///
/// Stateless: the screen owns [expanded], the same way it owns the
/// legend's own disclosure flag. A collapsed [child] is kept mounted but
/// offstage rather than dropped from the tree, so what the user typed
/// into the search or budget field is still there when the row is opened
/// again — and since the query and the budget keep narrowing the list
/// while hidden, the row names how many of them are active
/// ([activeCount]) so a shorter list never looks unexplained.
///
/// A [Semantics] wrapper marks the row as a button carrying Flutter's own
/// `expanded` flag, matching the dish card's script disclosure
/// (`docs/ACCESSIBILITY.md` §3).
class MenuFiltersRow extends StatelessWidget {
  /// Creates the row; [child] is shown below it while [expanded].
  const new({
    required this.expanded,
    required this.onToggle,
    required this.child,
    this.activeCount = 0,
    super.key,
  });

  /// Whether [child] is currently shown.
  final bool expanded;

  /// Called when the row is tapped, to toggle [expanded].
  final VoidCallback onToggle;

  /// How many of the controls inside [child] are narrowing the list right
  /// now — a typed search, a set budget. Zero shows the bare label.
  final int activeCount;

  /// The controls behind the disclosure.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final label = activeCount > 0
        ? l10n.menuFiltersActive(activeCount)
        : l10n.menuFilters;
    final ink = activeCount > 0
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          expanded: expanded,
          label: label,
          // The InkWell's own tap action is excluded with its children,
          // so the node carries the tap itself — a screen reader can open
          // the row, not just hear it.
          onTap: onToggle,
          excludeSemantics: true,
          child: InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.tune, size: 16, color: ink),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      label,
                      style: theme.textTheme.labelLarge?.copyWith(color: ink),
                    ),
                  ),
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 150),
                    child: Icon(Icons.expand_more, size: 18, color: ink),
                  ),
                ],
              ),
            ),
          ),
        ),
        Visibility(
          visible: expanded,
          maintainState: true,
          child: Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: child,
          ),
        ),
      ],
    );
  }
}

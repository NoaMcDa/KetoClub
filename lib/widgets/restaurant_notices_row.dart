import 'package:flutter/material.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/widgets/focus_ring.dart';

/// The menu screen's one quiet place for the restaurant's own notices
/// (issue #445): a collapsed disclosure line, "2 notes from the
/// restaurant", with each notice's text behind it.
///
/// A notice is a menu line nobody can order, such as "for allergen
/// information contact the restaurant" under a "שימו לב" heading
/// (`DishKind.notice`). It is no longer drawn as a dish card with a price
/// and a category chip, but it is not thrown away either: an allergen
/// notice matters to some diners, so it stays one tap away here.
///
/// Stateless: the screen owns [expanded], as it does for `MenuFiltersRow`,
/// whose look this row shares. The notice text is the restaurant's, in the
/// menu's language, and is shown as written; only the row's own label is
/// localised.
class RestaurantNoticesRow extends StatelessWidget {
  /// Creates the row for [notices], which must not be empty.
  const new({
    required this.notices,
    required this.expanded,
    required this.onToggle,
    super.key,
  });

  /// The notice lines, in menu order: each one's name and description are
  /// its text.
  final List<Dish> notices;

  /// Whether the notices' text is currently shown.
  final bool expanded;

  /// Called when the row is tapped, to toggle [expanded].
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final ink = theme.colorScheme.onSurfaceVariant;
    final label = l10n.menuRestaurantNotices(notices.length);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          expanded: expanded,
          label: label,
          // The InkWell's own tap action is excluded with its children,
          // so the node carries the tap itself, as `MenuFiltersRow` does.
          onTap: onToggle,
          excludeSemantics: true,
          child: FocusRing(
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              onTap: onToggle,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: ink),
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
        ),
        if (expanded)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [for (final notice in notices) _notice(theme, notice)],
            ),
          ),
      ],
    );
  }

  /// One notice: its name, then its description when it has one.
  Widget _notice(ThemeData theme, Dish notice) {
    final name = notice.name.trim();
    final description = notice.description.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (name.isNotEmpty) Text(name, style: theme.textTheme.bodyMedium),
          if (description.isNotEmpty)
            Text(
              description,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

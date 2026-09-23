import 'package:flutter/material.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';

/// The horizontal row of category chips above the dish list (issue #51):
/// one chip per name in `MenuController.visibleCategories`, in menu order.
///
/// Purely a row of buttons — it does not scroll anything itself. Only the
/// screen holds the `GlobalKey`s per category header and the
/// `ScrollController` a jump needs, so a tap is reported outward through
/// [onSelected] and the scrolling is entirely the caller's job.
///
/// Renders nothing for an empty [categories] — no menu loaded yet, or
/// every dish filtered or searched away — so a caller can pass
/// `MenuController.visibleCategories` straight through with no guard of
/// its own.
class CategoryChips extends StatelessWidget {
  /// Creates a chip row for [categories], reporting a tap through
  /// [onSelected].
  const new({required this.categories, required this.onSelected, super.key});

  /// The categories to show a chip for, in the order they should appear.
  final List<String> categories;

  /// Called with the tapped chip's category name.
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    if (categories.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    // A scrollable Row rather than a horizontal ListView: a menu has a
    // handful of categories, so building every chip up front costs
    // nothing, and it keeps the loaded menu's one ListView the only one
    // on the screen — a widget test can still find it by type alone.
    return SizedBox(
      height: 36,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < categories.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Semantics(
                button: true,
                label: l10n.categoryChipSemanticLabel(categories[i]),
                excludeSemantics: true,
                child: ActionChip(
                  label: Text(categories[i]),
                  onPressed: () => onSelected(categories[i]),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

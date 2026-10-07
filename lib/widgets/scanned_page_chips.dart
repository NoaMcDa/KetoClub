import 'package:flutter/material.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/utils/constants.dart';
import 'package:ketoclub/widgets/focus_ring.dart';

/// The row of chips that filters a scanned menu by page: "All pages", one
/// "Page n" chip per page and, when some dishes could not be placed, a
/// "Page unknown" chip.
///
/// Purely controlled: [selected] says which chip is on and a tap is
/// reported through [onSelected] as null (all pages), a 1-based page
/// number, or [scanPageUnknown]. Renders nothing for a single page with no
/// unplaced dishes, where there is nothing to filter.
class ScannedPageChips extends StatelessWidget {
  /// Creates a chip row for [pageCount] pages, plus the unknown chip when
  /// [hasUnknown], with [selected] on.
  const new({
    required this.pageCount,
    required this.hasUnknown,
    required this.selected,
    required this.onSelected,
    this.wrap = false,
    super.key,
  });

  /// How many pages the scan has.
  final int pageCount;

  /// Whether some dishes could not be placed on any page.
  final bool hasUnknown;

  /// The chosen filter: null for all pages, a 1-based page number, or
  /// [scanPageUnknown].
  final int? selected;

  /// Called with null, a page number or [scanPageUnknown] when a chip is
  /// tapped.
  final ValueChanged<int?> onSelected;

  /// Whether the chips wrap onto further lines instead of scrolling
  /// sideways, as in `CategoryChips`' two-pane side pane.
  final bool wrap;

  @override
  Widget build(BuildContext context) {
    if (pageCount < 2 && !hasUnknown) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    Widget chip(String label, int? value) => Semantics(
      label: l10n.scannedPageChipSemanticLabel(label),
      excludeSemantics: true,
      child: FocusRing(
        borderRadius: BorderRadius.circular(8),
        child: ChoiceChip(
          label: Text(label),
          selected: selected == value,
          onSelected: (_) => onSelected(value),
        ),
      ),
    );
    final chips = [
      chip(l10n.scannedPageChipAll, null),
      for (var n = 1; n <= pageCount; n++)
        chip(l10n.scannedMenuPageLabel(n), n),
      if (hasUnknown) chip(l10n.scannedPageUnknown, scanPageUnknown),
    ];
    if (wrap) return Wrap(spacing: 8, runSpacing: 8, children: chips);
    return SizedBox(
      height: 36,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < chips.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              chips[i],
            ],
          ],
        ),
      ),
    );
  }
}

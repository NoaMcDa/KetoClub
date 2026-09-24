import 'package:flutter/material.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/theme/verdict_colors.dart';

/// The three verdict counters that double as the menu filter (issue #29):
/// *"The three counters under the venue name are the filter — tap one"*
/// (`.design/Main.dc.html`'s `tileDefs`). Tapping an inactive tile narrows
/// `MenuController.visibleRows` to that verdict alone
/// ([MenuFilter.greenOnly], [MenuFilter.yellowOnly] or
/// [MenuFilter.redOnly]); tapping the active tile returns to
/// [MenuFilter.all].
///
/// A plain `Row` of three equally-flexed tiles, not a `SegmentedButton`:
/// each tile carries its own count as the loudest element, which a
/// segmented control's shared label style cannot do, and the artboard
/// shows independent tinted cards rather than one joined control.
class VerdictCounterTiles extends StatelessWidget {
  /// Creates tiles for [greenCount], [yellowCount] and [redCount]. Which
  /// tile reads as active is derived from [filter]; a tap reports the
  /// [MenuFilter] the screen should switch to through [onFilterChanged].
  const new({
    required this.greenCount,
    required this.yellowCount,
    required this.redCount,
    required this.filter,
    required this.onFilterChanged,
    super.key,
  });

  /// How many dishes are [DishVerdict.orderAsIs] — see
  /// `MenuController.greenCount`.
  final int greenCount;

  /// How many dishes are [DishVerdict.modifiable] — see
  /// `MenuController.yellowCount`.
  final int yellowCount;

  /// How many dishes are [DishVerdict.nonKeto] — see
  /// `MenuController.redCount`.
  final int redCount;

  /// The menu's current filter, read to decide which tile (if any) shows
  /// as active.
  final MenuFilter filter;

  /// Called with the [MenuFilter] a tap selects: the tile's own
  /// single-verdict filter when it was inactive, or [MenuFilter.all] when
  /// it was the active tile being tapped again.
  final ValueChanged<MenuFilter> onFilterChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final verdictColors = VerdictColors.of(context);
    return Row(
      children: [
        Expanded(
          child: _Tile(
            count: greenCount,
            label: l10n.tileGreenLabel,
            icon: Icons.check_circle,
            tone: verdictColors.green,
            active: filter == MenuFilter.greenOnly,
            onTap: () => onFilterChanged(
              filter == MenuFilter.greenOnly
                  ? MenuFilter.all
                  : MenuFilter.greenOnly,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _Tile(
            count: yellowCount,
            label: l10n.tileYellowLabel,
            icon: Icons.edit_note,
            tone: verdictColors.amber,
            active: filter == MenuFilter.yellowOnly,
            onTap: () => onFilterChanged(
              filter == MenuFilter.yellowOnly
                  ? MenuFilter.all
                  : MenuFilter.yellowOnly,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _Tile(
            count: redCount,
            label: l10n.tileRedLabel,
            icon: Icons.cancel,
            tone: verdictColors.red,
            active: filter == MenuFilter.redOnly,
            onTap: () => onFilterChanged(
              filter == MenuFilter.redOnly
                  ? MenuFilter.all
                  : MenuFilter.redOnly,
            ),
          ),
        ),
      ],
    );
  }
}

/// One counter tile: a verdict icon in [tone]'s rail colour, the count, and
/// the verdict label, tinted and bordered in [tone] when [active]
/// (`.design/Main.dc.html`'s per-tile `bg`/`border`/`numColor`/
/// `labelColor`).
///
/// The icon pairs with the tile's colour rather than standing alone — the
/// same icon-and-colour rule the verdict pill follows (architecture.md
/// §6.6) — so a colour-blind user reading this tile still gets a second,
/// shape-based signal for which verdict it counts, on top of the label
/// text itself.
class _Tile extends StatelessWidget {
  const new({
    required this.count,
    required this.label,
    required this.icon,
    required this.tone,
    required this.active,
    required this.onTap,
  });

  final int count;
  final String label;

  /// The verdict icon shown beside the count, matching the verdict pill's
  /// own icon for the same verdict.
  final IconData icon;
  final VerdictTone tone;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    // Unselected reads the theme's own secondary text colour for the
    // label — the artboard's muted `--ink3` has no direct `ThemeData`
    // counterpart (see `app_tokens.dart`), so this uses the same
    // muted-label token `EngineChip`'s rules variant already reads.
    final mutedLabel =
        theme.textTheme.bodySmall?.color ?? theme.colorScheme.onSurfaceVariant;
    final numberColor = active
        ? tone.ink
        : (theme.textTheme.titleLarge?.color ?? theme.colorScheme.onSurface);
    final labelColor = active ? tone.ink : mutedLabel;

    return Semantics(
      button: true,
      selected: active,
      label: l10n.tileSemanticLabel(label, count),
      hint: active ? l10n.tileSemanticHintClear : l10n.tileSemanticHintFilter,
      // `excludeSemantics: true` (below) hides this tile's own children
      // from the semantics tree, including the `tap` action `InkWell`
      // would otherwise have contributed on its own — without wiring
      // `onTap` here directly, this node's `button`/`hint` would promise
      // a screen-reader user something to double-tap that in fact carries
      // no action, a real gap this pass's own semantics test caught.
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: active ? tone.tint : theme.cardColor,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: active ? tone.rail : theme.dividerColor,
              width: 1.5,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Scaled down rather than left to overflow: at a large text
                // scale, a three-digit count plus this icon can outgrow a
                // narrow tile's own width (each tile is one third of the
                // row, per architecture.md §8.3's large-text pass) — a
                // shrunk pair reads better than a RenderFlex overflow.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 13, color: tone.rail),
                      const SizedBox(width: 6),
                      Text(
                        '$count',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: numberColor,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  label.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: labelColor,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

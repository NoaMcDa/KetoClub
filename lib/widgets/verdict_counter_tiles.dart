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

/// One counter tile: a coloured dot, the count, and the verdict label,
/// tinted and bordered in [tone] when [active] (`.design/Main.dc.html`'s
/// per-tile `bg`/`border`/`numColor`/`labelColor`).
class _Tile extends StatelessWidget {
  const new({
    required this.count,
    required this.label,
    required this.tone,
    required this.active,
    required this.onTap,
  });

  final int count;
  final String label;
  final VerdictTone tone;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    // Unselected reads the artboard's muted `--ink3`, which the theme
    // carries as `labelSmall`'s colour (and `onSurfaceVariant`).
    final mutedLabel =
        theme.textTheme.labelSmall?.color ?? theme.colorScheme.onSurfaceVariant;
    final numberColor = active
        ? tone.ink
        : (theme.textTheme.titleLarge?.color ?? theme.colorScheme.onSurface);
    final labelColor = active ? tone.ink : mutedLabel;

    return Semantics(
      button: true,
      selected: active,
      label: l10n.tileSemanticLabel(label, count),
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
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 11,
                      height: 11,
                      decoration: BoxDecoration(
                        color: tone.rail,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '$count',
                      // The artboard's tile count: 18px extra-bold, line
                      // height 1 (`.design/Main.dc.html`).
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontSize: 18,
                        height: 1,
                        fontWeight: FontWeight.w800,
                        color: numberColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  label.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontSize: 9.5,
                    color: labelColor,
                    letterSpacing: 0.5,
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

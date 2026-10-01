import 'package:flutter/material.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/theme/verdict_colors.dart';

/// The net-carb chip's background for [verdict]: the plain card surface
/// for green (the artboard's `--surface`), and [tone]'s own tint for amber
/// and red (`--amber-tint` / `--red-tint`).
Color netCarbsChipBackground(
  ThemeData theme,
  DishVerdict verdict,
  VerdictTone tone,
) => switch (verdict) {
  DishVerdict.orderAsIs => theme.cardColor,
  DishVerdict.modifiable || DishVerdict.nonKeto => tone.tint,
};

/// The net-carb chip (architecture.md §17.4, reversed by issue #30): a
/// small rounded-rectangle label in a verdict's [tone], deliberately not a
/// pill with an edge so it never reads as tappable (issue #259).
///
/// Shared by the dish card (an estimate in grams, [AnalysedDish]) and the
/// drinks guide (a typical range). The caller composes the visible [label]
/// and the screen-reader [semanticLabel], so each can frame its number as
/// an estimate in its own words — never a bare number.
class NetCarbsChip extends StatelessWidget {
  /// Creates a chip showing [label] in [tone]'s ink on [background],
  /// announced to a screen reader as [semanticLabel] instead.
  const new({
    required this.label,
    required this.semanticLabel,
    required this.tone,
    required this.background,
    super.key,
  });

  /// The visible text, already framed as an estimate.
  final String label;

  /// What a screen reader announces in place of [label].
  final String semanticLabel;

  /// The verdict tone, for the chip's foreground colour.
  final VerdictTone tone;

  /// The chip's background, from [netCarbsChipBackground].
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: tone.ink,
            ),
          ),
        ),
      ),
    );
  }
}

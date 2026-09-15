import 'package:flutter/material.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/theme/verdict_colors.dart';

/// One dish verdict, shown as an icon **and** a colour together
/// (architecture.md §6.6), styled as the artboard's `.pill` — uppercase,
/// letter-spaced, 10px, 800-weight, rounded corners rather than a fully
/// round badge (`.design/Main.dc.html` around line 178, the
/// `verdictStyles` table).
///
/// Colour alone would be unreadable to a colour-blind user, so every
/// verdict pairs a distinct [Icon] with a localised label; neither is
/// ever shown without the other. The pair is wrapped in one [Semantics]
/// node so a screen reader announces a single clean label instead of the
/// icon and text as two disjoint nodes.
class StatusBadge extends StatelessWidget {
  /// Creates a badge for [verdict].
  const new({required this.verdict, super.key});

  /// The verdict this badge represents.
  final DishVerdict verdict;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final tone = VerdictColors.of(context).forVerdict(verdict);
    final spec = _specFor(verdict, l10n);
    // The artboard's pill foreground is the loud "-on" colour for green and
    // amber, whose pill background is the saturated base colour, but the
    // "-ink" colour for red, whose pill background is itself a tint — see
    // VerdictTone's class doc comment for why the two verdicts differ.
    final foreground = verdict == DishVerdict.nonKeto ? tone.ink : tone.on;
    return Semantics(
      label: l10n.pillSemanticLabel(spec.label),
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tone.pill,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(7, 4, 9, 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(spec.icon, size: 12, color: foreground),
              const SizedBox(width: 5),
              Text(
                spec.label.toUpperCase(),
                style: TextStyle(
                  color: foreground,
                  fontWeight: FontWeight.w800,
                  fontSize: 10,
                  letterSpacing: 0.7,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The icon and label for one [DishVerdict]; colour comes from
/// [VerdictColors], read in [StatusBadge.build] rather than stored here, so
/// this spec never needs its own light/dark values.
class _BadgeSpec {
  const new({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

/// The [_BadgeSpec] for [verdict], with its label read from [l10n].
///
/// An exhaustive switch with no `default`: adding a [DishVerdict] value
/// without updating this function is a compile error (architecture.md §10).
_BadgeSpec _specFor(DishVerdict verdict, AppLocalizations l10n) =>
    switch (verdict) {
      DishVerdict.orderAsIs => _BadgeSpec(
        icon: Icons.check_circle,
        label: l10n.verdictOrderAsIs,
      ),
      DishVerdict.modifiable => _BadgeSpec(
        icon: Icons.edit_note,
        label: l10n.verdictModifiable,
      ),
      DishVerdict.nonKeto => _BadgeSpec(
        icon: Icons.cancel,
        label: l10n.verdictNonKeto,
      ),
    };

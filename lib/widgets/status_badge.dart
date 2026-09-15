import 'package:flutter/material.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/theme/verdict_colors.dart';

/// One dish verdict, shown as an icon **and** a colour together
/// (architecture.md §6.6).
///
/// Colour alone would be unreadable to a colour-blind user, so every
/// verdict pairs a distinct [Icon] with a localised label; neither is
/// ever shown without the other.
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
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tone.tint,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tone.rail),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(spec.icon, size: 16, color: tone.rail),
            const SizedBox(width: 6),
            Text(
              spec.label,
              style: TextStyle(color: tone.rail, fontWeight: FontWeight.w600),
            ),
          ],
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

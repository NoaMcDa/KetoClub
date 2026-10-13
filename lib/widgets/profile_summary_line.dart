import 'package:flutter/material.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/utils/allergens/taxonomy.dart';
import 'package:ketoclub/widgets/focus_ring.dart';
import 'package:ketoclub/widgets/restriction_picker_sheet.dart';

/// The one-line restriction profile summary in the menu screen's Filters
/// row (Banto, ALG-02b, issue #344): "Checking for: sesame, lactose", in
/// the UI language, so the user always sees what the verdicts were read
/// against. Tapping it calls [onTap], which opens Settings.
///
/// Draws nothing for an empty profile. It names the restrictions only; it
/// never calls a dish or a menu safe.
class ProfileSummaryLine extends StatelessWidget {
  /// Creates the summary of [profile].
  const new({required this.profile, required this.onTap, super.key});

  /// The restrictions to name, in the order the user added them.
  final DietaryProfile profile;

  /// Called when the line is tapped.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (profile.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context);
    final names = profile.entries
        .map(
          (entry) => restrictionDisplayName(
            restrictionFor(entry.restrictionId),
            locale,
          ),
        )
        .join(', ');
    final text = l10n.menuProfileSummary(names);
    return Semantics(
      button: true,
      label: text,
      onTap: onTap,
      excludeSemantics: true,
      child: FocusRing(
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    text,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

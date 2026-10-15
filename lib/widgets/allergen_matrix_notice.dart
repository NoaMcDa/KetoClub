import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/utils/allergens/allergen_matrix.dart';
import 'package:ketoclub/utils/banto_mode.dart';
import 'package:ketoclub/widgets/app_notice.dart';

/// The key of the allergen-information notice, when it shows.
const Key allergenMatrixNoticeKey = ValueKey<String>('allergenMatrixNotice');

/// The key of the line listing the rows that matched no dish.
const Key allergenMatrixUnmatchedKey = ValueKey<String>(
  'allergenMatrixUnmatched',
);

/// The menu screen's allergen-information notice (Banto; ALG-16, related
/// to #358; architecture.md D26): "Allergen information from the
/// restaurant, dated 1 Oct 2026", one [AppNotice.info] line when the
/// restaurant's own allergen matrix is on file for the venue.
///
/// A fact, not a badge: it says where the information came from and how
/// old it is, never that the venue or a dish is safe, and nothing about
/// it ranks or rates the venue (no restaurant can buy a rating; D26's "no
/// rating" rule). Under it, the rows the app could not pair with exactly
/// one dish by name ([AllergenMatrixMatch.unmatched]) are listed as the
/// restaurant printed them, so a row applied to nothing is visible rather
/// than guessed at.
///
/// Builds nothing with [bantoMode] off or with no [match]. Adds 12 px
/// under itself when it shows, as the menu's other notices do.
class AllergenMatrixNotice extends StatelessWidget {
  /// Creates the notice for [match].
  const new({
    required this.match,
    this.bantoMode = BantoMode.enabled,
    super.key,
  });

  /// The venue's matrix matched against its menu, or null for none.
  final AllergenMatrixMatch? match;

  /// Whether this build shows Banto surfaces.
  final bool bantoMode;

  @override
  Widget build(BuildContext context) {
    final current = match;
    if (!bantoMode || current == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final localeTag = Localizations.localeOf(context).toLanguageTag();
    // The day is a calendar date at midnight UTC: formatted as it is, never
    // shifted into the device's zone, where it could fall a day earlier.
    final dated = DateFormat.yMMMd(localeTag).format(current.matrix.validFrom);
    final unmatched = current.unmatched;
    return Padding(
      key: allergenMatrixNoticeKey,
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppNotice.info(
            message: l10n.allergenMatrixNotice(dated),
            icon: Icons.fact_check_outlined,
          ),
          if (unmatched.isNotEmpty) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsetsDirectional.symmetric(horizontal: 12),
              child: Text(
                l10n.allergenMatrixUnmatched(
                  unmatched.length,
                  <String>[for (final entry in unmatched) entry.row.name]
                      .join(', '),
                ),
                key: allergenMatrixUnmatchedKey,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

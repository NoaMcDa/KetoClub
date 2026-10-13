import 'package:flutter/material.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/utils/allergens/taxonomy.dart';
import 'package:ketoclub/widgets/app_sheet.dart';

/// The kinds the picker groups by, in display order: the strict kinds
/// first. [RestrictionKind.keto] is absent on purpose — keto stays the
/// existing "Your keto rules" toggles.
const List<RestrictionKind> restrictionKindOrder = <RestrictionKind>[
  RestrictionKind.allergen,
  RestrictionKind.autoimmune,
  RestrictionKind.intolerance,
  RestrictionKind.lifestyle,
  RestrictionKind.religiousComponent,
];

/// The key of the picker row for [id], so a test can tap it without a text
/// lookup that the Settings list behind the sheet could make ambiguous.
Key restrictionOptionKey(RestrictionId id) =>
    ValueKey<String>('restrictionOption_${id.name}');

/// [restriction]'s name in the UI language of [locale]: Hebrew under `he`,
/// English otherwise.
///
/// The taxonomy's names follow the *menu's* language where they sit beside
/// dish text (architecture.md §12); in Settings and in this picker they
/// label the user's own choices, so they follow the UI locale instead.
String restrictionDisplayName(Restriction restriction, Locale locale) =>
    locale.languageCode == 'he' ? restriction.nameHe : restriction.nameEn;

/// The short label of [kind]: allergy, autoimmune, intolerance or diet.
///
/// A lifestyle diet, a religious component and keto all read as "diet";
/// strictness is never shown as a severity (there is none), only implied by
/// the kind.
String restrictionKindLabel(AppLocalizations l10n, RestrictionKind kind) =>
    switch (kind) {
      RestrictionKind.allergen => l10n.restrictionKindAllergy,
      RestrictionKind.autoimmune => l10n.restrictionKindAutoimmune,
      RestrictionKind.intolerance => l10n.restrictionKindIntolerance,
      RestrictionKind.lifestyle ||
      RestrictionKind.religiousComponent ||
      RestrictionKind.keto => l10n.restrictionKindDiet,
    };

/// One line saying which official allergen lists name [restriction]: the
/// US list, the EU list (which Israel's follows), both or neither.
String restrictionJurisdictionHint(
  AppLocalizations l10n,
  Restriction restriction,
) {
  final us = restriction.jurisdictions.contains(Jurisdiction.us);
  final eu = restriction.jurisdictions.contains(Jurisdiction.eu);
  final lists = switch ((us, eu)) {
    (true, true) => 'usEu',
    (true, false) => 'us',
    (false, true) => 'eu',
    (false, false) => 'none',
  };
  return l10n.restrictionJurisdictionHint(lists);
}

/// The taxonomy entries the picker offers when the profile already holds
/// [added]: every restriction except keto and those already added, in
/// taxonomy order.
List<Restriction> availableRestrictions(Set<RestrictionId> added) => [
  for (final restriction in restrictionTaxonomy)
    if (restriction.kind != RestrictionKind.keto &&
        !added.contains(restriction.id))
      restriction,
];

/// Opens the [RestrictionPickerSheet] and answers the restriction chosen,
/// or null when the sheet is dismissed without a choice.
///
/// Capped at the app's sheet width ([showKetoClubSheet]).
Future<RestrictionId?> showRestrictionPickerSheet({
  required BuildContext context,
  required Set<RestrictionId> added,
}) => showKetoClubSheet<RestrictionId>(
  context: context,
  showDragHandle: true,
  builder: (_) => RestrictionPickerSheet(added: added),
);

/// A modal sheet listing the restrictions a profile can add (Banto,
/// ALG-02a, issue #344), grouped by kind, each with its name in the UI
/// language and a one-line hint naming the official allergen lists that
/// include it. Tapping one pops the sheet with its [RestrictionId].
///
/// Keto and every id in [added] are left out. There is no severity control:
/// a restriction is added or it is not.
class RestrictionPickerSheet extends StatelessWidget {
  /// Creates the picker, leaving out [added].
  const new({required this.added, super.key});

  /// The restrictions already in the profile, which the picker leaves out.
  final Set<RestrictionId> added;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context);
    final available = availableRestrictions(added);

    // A plain Column, not a lazy ListView: about twenty rows, and every
    // row must exist in the tree so a test or a screen reader finds it.
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsetsDirectional.fromSTEB(8, 0, 8, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 8),
              child: Text(
                l10n.restrictionPickerTitle,
                style: theme.textTheme.titleMedium,
              ),
            ),
            for (final kind in restrictionKindOrder)
              ..._group(context, l10n, locale, kind, available),
          ],
        ),
      ),
    );
  }

  /// The heading and rows of [kind] among [available]; nothing when no
  /// restriction of that kind is left to add.
  List<Widget> _group(
    BuildContext context,
    AppLocalizations l10n,
    Locale locale,
    RestrictionKind kind,
    List<Restriction> available,
  ) {
    final members = [
      for (final restriction in available)
        if (restriction.kind == kind) restriction,
    ];
    if (members.isEmpty) return const <Widget>[];
    return [
      Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 4),
        child: Semantics(
          header: true,
          child: Text(
            restrictionKindLabel(l10n, kind),
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(fontSize: 12, letterSpacing: 0.6),
          ),
        ),
      ),
      for (final restriction in members)
        ListTile(
          key: restrictionOptionKey(restriction.id),
          title: Text(restrictionDisplayName(restriction, locale)),
          subtitle: Text(restrictionJurisdictionHint(l10n, restriction)),
          onTap: () => Navigator.pop(context, restriction.id),
        ),
    ];
  }
}

import 'package:flutter/material.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/utils/allergens/taxonomy.dart';
import 'package:ketoclub/utils/allergens/vocabulary.dart';
import 'package:ketoclub/widgets/app_sheet.dart';

/// The kinds the picker groups by, in display order: the strict kinds
/// first. [RestrictionKind.keto] is absent on purpose — keto stays the
/// existing "Your keto rules" toggles.
const List<RestrictionKind> restrictionKindOrder = <RestrictionKind>[
  RestrictionKind.allergen,
  RestrictionKind.autoimmune,
  RestrictionKind.medical,
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

/// The short label of [kind]: allergy, autoimmune, health condition,
/// intolerance or diet.
///
/// A lifestyle diet, a religious component and keto all read as "diet";
/// strictness is never shown as a severity (there is none), only implied by
/// the kind.
String restrictionKindLabel(AppLocalizations l10n, RestrictionKind kind) =>
    switch (kind) {
      RestrictionKind.allergen => l10n.restrictionKindAllergy,
      RestrictionKind.autoimmune => l10n.restrictionKindAutoimmune,
      RestrictionKind.medical => l10n.restrictionKindMedical,
      RestrictionKind.intolerance => l10n.restrictionKindIntolerance,
      RestrictionKind.lifestyle ||
      RestrictionKind.religiousComponent ||
      RestrictionKind.keto => l10n.restrictionKindDiet,
    };

/// The key of the picker's "Add your own" text field (ALG-17).
const Key restrictionOwnFieldKey = ValueKey<String>('restrictionOwnField');

/// The key of the picker's "Add" button beside [restrictionOwnFieldKey].
const Key restrictionOwnAddKey = ValueKey<String>('restrictionOwnAdd');

/// What the picker answers: a restriction from the taxonomy, or one of the
/// user's own words for [RestrictionId.custom] (ALG-17).
@immutable
final class RestrictionPick {
  /// A taxonomy restriction, [id].
  const new restriction(RestrictionId this.id) : term = null;

  /// One of the user's own words, [term], as typed and trimmed.
  const new own(String this.term) : id = null;

  /// The restriction picked, or null for an own word.
  final RestrictionId? id;

  /// The own word typed, or null for a taxonomy restriction.
  final String? term;

  @override
  bool operator ==(Object other) =>
      other is RestrictionPick && other.id == id && other.term == term;

  @override
  int get hashCode => Object.hash(id, term);

  /// The kind of pick only: an own word is the user's health data and
  /// stays out of logs (D26 C1).
  @override
  String toString() =>
      id == null ? 'RestrictionPick(own)' : 'RestrictionPick(${id!.name})';
}

/// How [entry] is named in Settings, the profile editor and the menu's
/// "Checking for" line, in [locale]'s language: the restriction's name, or
/// for the user's own restriction (ALG-17) their words, as they wrote
/// them.
String profileEntryDisplayName(ProfileEntry entry, Locale locale) =>
    entry.restrictionId == RestrictionId.custom && entry.terms.isNotEmpty
    ? entry.terms.join(', ')
    : restrictionDisplayName(restrictionFor(entry.restrictionId), locale);

/// One line saying which official allergen lists name [restriction]: the
/// US list, the EU list (which Israel's follows), both or neither. The
/// ALG-17 restrictions say what they are instead: a heads-up from common
/// guidance ([headsUpRestrictions]), or, for alpha-gal, that dairy is the
/// Milk entry's.
///
/// Issue #342: fava says it is G6PD deficiency and not an allergy; a
/// single legume ([restrictionParent]) that it stands apart from all
/// legumes; a food on Japan's recommended list ([japanRecommendedOnly])
/// that it is recommended there and mandatory nowhere; and a restriction
/// on Japan's mandatory list alone (buckwheat) that it is on Japan's.
String restrictionJurisdictionHint(
  AppLocalizations l10n,
  Restriction restriction,
) {
  if (headsUpRestrictions.contains(restriction.id)) {
    return l10n.restrictionHeadsUpHint;
  }
  if (restriction.id == RestrictionId.alphaGal) {
    return l10n.restrictionAlphaGalHint;
  }
  if (restriction.id == RestrictionId.fava) return l10n.restrictionFavaHint;
  if (restrictionParent.containsKey(restriction.id)) {
    return l10n.restrictionLegumePartHint;
  }
  if (japanRecommendedOnly.contains(restriction.id)) {
    return l10n.restrictionJapanRecommendedHint;
  }
  final us = restriction.jurisdictions.contains(Jurisdiction.us);
  final eu = restriction.jurisdictions.contains(Jurisdiction.eu);
  if (!us && !eu && restriction.jurisdictions.contains(Jurisdiction.jp)) {
    return l10n.restrictionJapanListHint;
  }
  final lists = switch ((us, eu)) {
    (true, true) => 'usEu',
    (true, false) => 'us',
    (false, true) => 'eu',
    (false, false) => 'none',
  };
  return l10n.restrictionJurisdictionHint(lists);
}

/// Whether the picker and the onboarding offer [id]: once its vocabulary
/// holds a term (issue #342).
///
/// A restriction with an empty vocabulary would find nothing on any menu,
/// so a profile holding it would read every dish as having no concern
/// for it — for a strict restriction, a silence that looks like an
/// answer. The research restrictions are added with empty vocabularies
/// (the contract step) and appear here one group at a time, as each
/// follow-up fills its file. Keto (whose words live in the rule engine)
/// and the user's own restriction (typed, not picked) are never offered
/// as rows anyway.
bool restrictionOffered(RestrictionId id) =>
    !(allergenVocabulary[id]?.isEmpty ?? true);

/// The taxonomy entries the picker offers when the profile already holds
/// [added]: every restriction [offered] (by default
/// [restrictionOffered]) except keto, the user's own (which is typed, not
/// picked) and those already added, in taxonomy order — except that a
/// child ([restrictionParent]: chickpeas under legumes) follows its parent
/// when the parent is offered too.
List<Restriction> availableRestrictions(
  Set<RestrictionId> added, {
  bool Function(RestrictionId id) offered = restrictionOffered,
}) => childrenAfterParents([
  for (final restriction in restrictionTaxonomy)
    if (restriction.kind != RestrictionKind.keto &&
        restriction.id != RestrictionId.custom &&
        !added.contains(restriction.id) &&
        offered(restriction.id))
      restriction,
]);

/// [restrictions] in their order, except that each child
/// ([restrictionParent]) is moved to just after its parent when the
/// parent is among them; a child whose parent is not stays where it was.
List<Restriction> childrenAfterParents(List<Restriction> restrictions) {
  final present = <RestrictionId>{
    for (final restriction in restrictions) restriction.id,
  };
  return <Restriction>[
    for (final restriction in restrictions)
      if (!present.contains(restrictionParent[restriction.id])) ...[
        restriction,
        for (final child in restrictions)
          if (restrictionParent[child.id] == restriction.id) child,
      ],
  ];
}

/// Whether [restriction]'s English or Hebrew name holds [query], ignoring
/// case and surrounding spaces; an empty query matches everything. The
/// picker's search (issue #342), which searches both languages whatever
/// the UI locale, so "חומוס" finds chickpeas under an English UI.
bool restrictionMatchesQuery(Restriction restriction, String query) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return true;
  return restriction.nameEn.toLowerCase().contains(needle) ||
      restriction.nameHe.contains(needle);
}

/// The key of the picker's search field (issue #342).
const Key restrictionSearchFieldKey = ValueKey<String>(
  'restrictionSearchField',
);

/// Whether the picker has anything left to offer [profile]: a taxonomy
/// restriction it does not hold, or room for another own word
/// ([ProfileEntry.maxTerms]).
bool canAddToProfile(DietaryProfile profile) =>
    availableRestrictions(<RestrictionId>{
      for (final entry in profile.entries) entry.restrictionId,
    }).isNotEmpty ||
    profile.customTerms.length < ProfileEntry.maxTerms;

/// Opens the [RestrictionPickerSheet] and answers the choice — a
/// restriction or an own word — or null when the sheet is dismissed
/// without one.
///
/// Capped at the app's sheet width ([showKetoClubSheet]).
Future<RestrictionPick?> showRestrictionPickerSheet({
  required BuildContext context,
  required Set<RestrictionId> added,
}) => showKetoClubSheet<RestrictionPick>(
  context: context,
  showDragHandle: true,
  builder: (_) => RestrictionPickerSheet(added: added),
);

/// A modal sheet listing the restrictions a profile can add (Banto,
/// ALG-02a, issue #344), grouped by kind, each with its name in the UI
/// language and a one-line hint naming the official allergen lists that
/// include it. Tapping one pops the sheet with its [RestrictionId].
///
/// A search field above the list (issue #342) narrows it by name, in
/// either language ([restrictionMatchesQuery]), so the list stays usable
/// as it grows; a kind with no match loses its heading, and a search that
/// matches nothing points to "Add your own". A child restriction (a single
/// legume) is listed indented, right after its parent.
///
/// Keto and every id in [added] are left out. There is no severity control:
/// a restriction is added or it is not. Below the list, "Add your own"
/// (ALG-17) takes a word the taxonomy does not have ("kiwi", "כוסברה")
/// and pops the sheet with it; the word is matched on this device only
/// and checked as strictly as an allergy.
///
/// Tapping a row pops [RestrictionPick.restriction]; adding a word pops
/// [RestrictionPick.own].
class RestrictionPickerSheet extends StatefulWidget {
  /// Creates the picker, leaving out [added] and every restriction that is
  /// not [offered].
  const new({
    required this.added,
    this.offered = restrictionOffered,
    super.key,
  });

  /// The restrictions already in the profile, which the picker leaves out.
  final Set<RestrictionId> added;

  /// Which restrictions the picker may offer at all; by default those
  /// whose vocabulary holds a term ([restrictionOffered]).
  final bool Function(RestrictionId id) offered;

  @override
  State<RestrictionPickerSheet> createState() => _RestrictionPickerSheetState();
}

class _RestrictionPickerSheetState extends State<RestrictionPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context);
    final available = [
      for (final restriction in availableRestrictions(
        widget.added,
        offered: widget.offered,
      ))
        if (restrictionMatchesQuery(restriction, _query)) restriction,
    ];

    // A plain Column, not a lazy ListView: every row must exist in the
    // tree so a test or a screen reader finds it; the search narrows it.
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
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 4),
              child: TextField(
                key: restrictionSearchFieldKey,
                onChanged: (value) => setState(() => _query = value),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  labelText: l10n.restrictionSearchField,
                  prefixIcon: const Icon(Icons.search),
                ),
              ),
            ),
            for (final kind in restrictionKindOrder)
              ..._group(context, l10n, locale, kind, available),
            if (available.isEmpty && _query.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 0),
                child: Text(
                  l10n.restrictionSearchEmpty,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            const _OwnRestrictionField(),
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
    final shown = <RestrictionId>{for (final member in members) member.id};
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
          // A child sits indented under its parent when both are shown.
          contentPadding: shown.contains(restrictionParent[restriction.id])
              ? const EdgeInsetsDirectional.only(start: 40, end: 16)
              : null,
          title: Text(restrictionDisplayName(restriction, locale)),
          subtitle: Text(restrictionJurisdictionHint(l10n, restriction)),
          onTap: () => Navigator.pop(
            context,
            RestrictionPick.restriction(restriction.id),
          ),
        ),
    ];
  }
}

/// The picker's "Add your own" group (ALG-17): a heading, a note that the
/// word is checked on this device only and as strictly as an allergy, a
/// text field and an "Add" button that pops the sheet with the trimmed
/// word. A blank word adds nothing.
class _OwnRestrictionField extends StatefulWidget {
  const new();

  @override
  State<_OwnRestrictionField> createState() => _OwnRestrictionFieldState();
}

class _OwnRestrictionFieldState extends State<_OwnRestrictionField> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final term = _controller.text.trim();
    if (term.isEmpty) return;
    Navigator.pop(context, RestrictionPick.own(term));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              l10n.restrictionOwnTitle,
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: 12,
                letterSpacing: 0.6,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.restrictionOwnNote,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: restrictionOwnFieldKey,
                  controller: _controller,
                  maxLength: ProfileEntry.maxTermLength,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    labelText: l10n.restrictionOwnField,
                    counterText: '',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                key: restrictionOwnAddKey,
                onPressed: _submit,
                child: Text(l10n.restrictionOwnAdd),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

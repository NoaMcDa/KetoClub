import 'package:flutter/material.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/models/named_profile.dart';
import 'package:ketoclub/widgets/app_sheet.dart';
import 'package:ketoclub/widgets/focus_ring.dart';
import 'package:ketoclub/widgets/profile_names.dart';

/// The menu screen's combine control, public so a test can tap it.
const Key groupCombineControlKey = Key('groupCombineControl');

/// The checkbox of the profile [id] in the combine sheet.
Key groupCombineOptionKey(String id) =>
    ValueKey<String>('groupCombineOption_$id');

/// The combine sheet's Apply button.
const Key groupCombineApplyKey = Key('groupCombineApply');

/// The combine sheet's chef card button.
const Key groupCombineChefCardKey = Key('groupCombineChefCard');

/// The combine sheet's "Manage people in Settings" button.
const Key groupCombineManageKey = Key('groupCombineManage');

/// The menu screen's "Checking for: Me, Dana" line when the device holds
/// more than one profile (Banto, ALG-12, issue #354): it names the people
/// the menu is read for and opens the combine sheet when tapped. It takes
/// the place of the restriction summary (`ProfileSummaryLine`), which
/// names restrictions rather than people.
class GroupCombineControl extends StatelessWidget {
  /// Creates the control naming [people].
  const new({required this.people, required this.onTap, super.key});

  /// The profiles the menu is read for.
  final List<NamedProfile> people;

  /// Opens the combine sheet.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final text = l10n.menuProfileSummary(profileDisplayNames(l10n, people));
    final color = theme.colorScheme.onSurfaceVariant;
    return Semantics(
      button: true,
      label: text,
      onTap: onTap,
      excludeSemantics: true,
      child: FocusRing(
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          key: groupCombineControlKey,
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 6),
                  child: Icon(Icons.group_outlined, size: 18, color: color),
                ),
                Expanded(
                  child: Text(
                    text,
                    style: theme.textTheme.bodySmall?.copyWith(color: color),
                  ),
                ),
                Icon(Icons.expand_more, size: 18, color: color),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Opens the [GroupCombineSheet] and answers the ids the user applied, or
/// null when the sheet is dismissed or left for Settings ([onManage]).
Future<List<String>?> showGroupCombineSheet({
  required BuildContext context,
  required List<NamedProfile> profiles,
  required List<NamedProfile> active,
  required VoidCallback onManage,
  required ValueChanged<List<NamedProfile>> onChefCard,
}) => showKetoClubSheet<List<String>>(
  context: context,
  showDragHandle: true,
  builder: (_) => GroupCombineSheet(
    profiles: profiles,
    initiallyActive: <String>{for (final person in active) person.id},
    onManage: onManage,
    onChefCard: onChefCard,
  ),
);

/// Checks which profiles a menu is read for (Banto, ALG-12, issue #354):
/// one checkbox per profile on the device, with its restrictions under its
/// name. Apply pops the sheet with the checked ids, in [profiles]' order;
/// at least one must stay checked. The chef card button calls [onChefCard]
/// with the checked people, for a card with one section per person, and
/// "Manage people in Settings" closes the sheet and calls [onManage].
class GroupCombineSheet extends StatefulWidget {
  /// Creates the sheet over [profiles], [initiallyActive] checked.
  const new({
    required this.profiles,
    required this.initiallyActive,
    required this.onManage,
    required this.onChefCard,
    super.key,
  });

  /// Every profile on the device.
  final List<NamedProfile> profiles;

  /// The ids checked when the sheet opens.
  final Set<String> initiallyActive;

  /// Called after the sheet closes for Settings.
  final VoidCallback onManage;

  /// Opens the chef card for the checked people, over the sheet.
  final ValueChanged<List<NamedProfile>> onChefCard;

  @override
  State<GroupCombineSheet> createState() => _GroupCombineSheetState();
}

class _GroupCombineSheetState extends State<GroupCombineSheet> {
  late final Set<String> _checked = <String>{...widget.initiallyActive};

  List<NamedProfile> get _selected => <NamedProfile>[
    for (final person in widget.profiles)
      if (_checked.contains(person.id)) person,
  ];

  void _toggle(String id, {required bool on}) => setState(() {
    if (on) {
      _checked.add(id);
    } else if (_checked.length > 1) {
      _checked.remove(id);
    }
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context);
    final selected = _selected;
    // A plain Column: at most eight rows, every one in the tree for a test
    // or a screen reader.
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
                l10n.groupCombineTitle,
                style: theme.textTheme.titleMedium,
              ),
            ),
            for (final person in widget.profiles)
              CheckboxListTile(
                key: groupCombineOptionKey(person.id),
                value: _checked.contains(person.id),
                title: Text(profileDisplayName(l10n, person)),
                subtitle: Text(
                  profileRestrictionsLine(l10n, locale, person.profile),
                ),
                controlAffinity: ListTileControlAffinity.leading,
                onChanged: (on) => _toggle(person.id, on: on ?? false),
              ),
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 0),
              child: FilledButton(
                key: groupCombineApplyKey,
                onPressed: () => Navigator.pop(context, <String>[
                  for (final person in selected) person.id,
                ]),
                child: Text(l10n.groupCombineApply),
              ),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 0),
              child: OutlinedButton.icon(
                key: groupCombineChefCardKey,
                icon: const Icon(Icons.restaurant_menu),
                label: Text(l10n.groupCombineChefCard),
                onPressed: () => widget.onChefCard(selected),
              ),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(8, 4, 8, 0),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  key: groupCombineManageKey,
                  onPressed: () {
                    Navigator.pop(context);
                    widget.onManage();
                  },
                  child: Text(l10n.groupCombineManage),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

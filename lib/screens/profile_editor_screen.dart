import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/models/named_profile.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/screens/chef_card_screen.dart';
import 'package:ketoclub/screens/premium_gate.dart';
import 'package:ketoclub/services/platform/menu_sharer.dart';
import 'package:ketoclub/services/platform/screen_brightness.dart';
import 'package:ketoclub/state/settings_controller.dart';
import 'package:ketoclub/utils/allergens/profile_transfer.dart';
import 'package:ketoclub/utils/allergens/taxonomy.dart';
import 'package:ketoclub/utils/premium_gates.dart';
import 'package:ketoclub/widgets/content_width.dart';
import 'package:ketoclub/widgets/exceptions_sheet.dart';
import 'package:ketoclub/widgets/profile_name_dialog.dart';
import 'package:ketoclub/widgets/profile_names.dart';
import 'package:ketoclub/widgets/restriction_picker_sheet.dart';
import 'package:provider/provider.dart';

/// The editor's "Add restriction" button.
const Key profileEditorAddKey = Key('profileEditorAdd');

/// The editor's Rename button.
const Key profileEditorRenameKey = Key('profileEditorRename');

/// The editor's "Share this profile" button.
const Key profileEditorExportKey = Key('profileEditorExport');

/// The editor's chef card button.
const Key profileEditorChefCardKey = Key('profileEditorChefCard');

/// The editor's "Delete this profile" button (not on the user's own).
const Key profileEditorDeleteKey = Key('profileEditorDelete');

/// The confirm button of the export dialog.
const Key profileExportConfirmKey = Key('profileExportConfirm');

/// The confirm button of the delete dialog.
const Key profileDeleteConfirmKey = Key('profileDeleteConfirm');

/// The row of [id] in the editor's restrictions.
Key profileEditorRowKey(RestrictionId id) =>
    ValueKey<String>('profileEditorRow_${id.name}');

/// The remove button of [id]'s row in the editor.
Key profileEditorRemoveKey(RestrictionId id) =>
    ValueKey<String>('profileEditorRemove_${id.name}');

/// The row of [term], one of the user's own words (ALG-17), in the editor.
Key profileEditorOwnTermRowKey(String term) =>
    ValueKey<String>('profileEditorOwnTermRow_$term');

/// The remove button of [term]'s row in the editor.
Key profileEditorOwnTermRemoveKey(String term) =>
    ValueKey<String>('profileEditorOwnTermRemove_$term');

/// Edits one named profile (Banto, ALG-12, issue #354): its restrictions,
/// added through the same picker as "My restrictions"
/// ([RestrictionPickerSheet]) and removed one by one; its name; sharing it
/// as text, after a dialog that says it is health data; its own chef card;
/// and, for anyone but the user, deleting it.
///
/// Reads the [SettingsController] from `provider`, which the caller
/// supplies with the route. Pops itself once the profile is deleted.
class ProfileEditorScreen extends StatelessWidget {
  /// Creates the editor of the profile [profileId].
  const new({
    required this.profileId,
    this.screenBrightness = const NoOpScreenBrightness(),
    this.menuSharer,
    super.key,
  });

  /// The profile edited.
  final String profileId;

  /// Raised while this person's chef card is open.
  final ScreenBrightness screenBrightness;

  /// Shares the profile and the chef card; with none, the profile is
  /// copied to the clipboard instead.
  final MenuSharer? menuSharer;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context);
    final controller = context.watch<SettingsController>();
    final person = controller.profileById(profileId);
    if (person == null) return const Scaffold(body: SizedBox.shrink());
    final busy = controller.isBusy;
    final name = profileDisplayName(l10n, person);
    final entries = person.profile.entries;
    final added = <RestrictionId>{
      for (final entry in entries) entry.restrictionId,
    };
    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: ContentWidth(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.settingsProfilesNote, style: theme.textTheme.bodySmall),
              const SizedBox(height: 16),
              Semantics(
                header: true,
                child: Text(
                  l10n.profileEditorRestrictions,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              if (entries.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(l10n.profileKetoOnly),
                ),
              for (final entry in entries)
                if (entry.restrictionId == RestrictionId.custom)
                  for (final term in entry.terms)
                    _ownTermRow(l10n, controller, term)
                else
                  _row(context, l10n, controller, entry.restrictionId, locale),
              if (canAddToProfile(person.profile))
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    key: profileEditorAddKey,
                    icon: const Icon(Icons.add),
                    label: Text(l10n.settingsRestrictionsAdd),
                    onPressed: busy
                        ? null
                        : () => unawaited(_pick(context, controller, added)),
                  ),
                ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    key: profileEditorRenameKey,
                    icon: const Icon(Icons.edit_outlined),
                    label: Text(l10n.profileEditorRename),
                    onPressed: busy
                        ? null
                        : () => unawaited(_rename(context, controller, person)),
                  ),
                  OutlinedButton.icon(
                    key: profileEditorExportKey,
                    icon: const Icon(Icons.ios_share),
                    label: Text(l10n.profileEditorExport),
                    onPressed: () => unawaited(_export(context, person)),
                  ),
                  FilledButton.icon(
                    key: profileEditorChefCardKey,
                    icon: const Icon(Icons.restaurant_menu),
                    label: Text(l10n.chefCardShowButton),
                    onPressed: () => Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => ChefCardScreen(
                          profile: person.profile,
                          trip: controller.tripDestination,
                          screenBrightness: screenBrightness,
                          menuSharer: menuSharer,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (!person.isPrimary) ...[
                const SizedBox(height: 24),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    key: profileEditorDeleteKey,
                    style: TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                    ),
                    icon: const Icon(Icons.delete_outline),
                    label: Text(l10n.profileEditorDelete),
                    onPressed: busy
                        ? null
                        : () => unawaited(_delete(context, controller, person)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(
    BuildContext context,
    AppLocalizations l10n,
    SettingsController controller,
    RestrictionId id,
    Locale locale,
  ) {
    final restriction = restrictionFor(id);
    final name = restrictionDisplayName(restriction, locale);
    final exceptions =
        controller.profileById(profileId)?.profile.entryFor(id)?.exceptions ??
        const <String>[];
    return Semantics(
      onTapHint: l10n.exceptionsEditHint,
      child: ListTile(
        key: profileEditorRowKey(id),
        contentPadding: EdgeInsets.zero,
        title: Text(name),
        subtitle: RestrictionRowSubtitle(
          kindLabel: restrictionKindLabel(l10n, restriction.kind),
          exceptions: exceptions,
        ),
        onTap: controller.isBusy
            ? null
            : () => unawaited(_editExceptions(context, controller, id)),
        trailing: IconButton(
          key: profileEditorRemoveKey(id),
          icon: const Icon(Icons.close),
          tooltip: l10n.settingsRestrictionsRemove(name),
          onPressed: controller.isBusy
              ? null
              : () =>
                    unawaited(controller.removeRestrictionFrom(profileId, id)),
        ),
      ),
    );
  }

  /// Opens the exceptions sheet for [id] and saves what the user keeps
  /// (#417). Dismissing the sheet changes nothing.
  Future<void> _editExceptions(
    BuildContext context,
    SettingsController controller,
    RestrictionId id,
  ) async {
    final held = controller
        .profileById(profileId)
        ?.profile
        .entryFor(id)
        ?.exceptions;
    if (held == null) return;
    final saved = await showExceptionsSheet(
      context: context,
      restriction: id,
      exceptions: held,
    );
    if (saved == null) return;
    await controller.setExceptionsFor(profileId, id, saved);
  }

  Future<void> _pick(
    BuildContext context,
    SettingsController controller,
    Set<RestrictionId> added,
  ) async {
    final picked = await showRestrictionPickerSheet(
      context: context,
      added: added,
    );
    if (picked == null) return;
    final term = picked.term;
    final id = picked.id;
    // A second restriction is Premium (ALG-18); what is saved stays.
    final adding = term != null ? RestrictionId.custom : id;
    final held = controller.profileById(profileId)?.profile;
    if (adding != null && held != null && context.mounted) {
      final allowed = await passPremiumGate(
        context,
        PremiumFeature.restrictions,
        locks: (access) => PremiumGates.locksAddingRestriction(
          access,
          profile: held,
          adding: adding,
        ),
      );
      if (!allowed) return;
    }
    if (term != null) {
      await controller.addCustomTermTo(profileId, term);
    } else if (id != null) {
      await controller.addRestrictionTo(profileId, id);
    }
  }

  /// One of the person's own words (ALG-17): the word, "Your own · checked
  /// strictly" and a remove button for that word alone.
  Widget _ownTermRow(
    AppLocalizations l10n,
    SettingsController controller,
    String term,
  ) => ListTile(
    key: profileEditorOwnTermRowKey(term),
    contentPadding: EdgeInsets.zero,
    title: Text(term),
    subtitle: Text(l10n.restrictionOwnRowSubtitle),
    trailing: IconButton(
      key: profileEditorOwnTermRemoveKey(term),
      icon: const Icon(Icons.close),
      tooltip: l10n.settingsRestrictionsRemove(term),
      onPressed: controller.isBusy
          ? null
          : () => unawaited(controller.removeCustomTermFrom(profileId, term)),
    ),
  );

  Future<void> _rename(
    BuildContext context,
    SettingsController controller,
    NamedProfile person,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final name = await showProfileNameDialog(
      context,
      title: l10n.profileNameRenameTitle,
      initial: person.name,
      allowEmpty: person.isPrimary,
    );
    if (name == null) return;
    await controller.renameProfile(profileId, name);
  }

  /// Says the profile is health data, and only once the user agrees shares
  /// it as text ([ProfileTransfer.encode]), or copies it when there is no
  /// share sheet.
  Future<void> _export(BuildContext context, NamedProfile person) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final name = profileDisplayName(l10n, person);
    final agreed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.profileExportTitle),
        content: Text(l10n.profileExportBody(name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.actionCancel),
          ),
          FilledButton(
            key: profileExportConfirmKey,
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.profileExportConfirm),
          ),
        ],
      ),
    );
    if (agreed != true) return;
    // The stored name, not the display one: the user's own unnamed
    // profile travels with no name, for the receiver to give it one.
    final text = ProfileTransfer.encode(
      name: person.name,
      profile: person.profile,
    );
    final sharer = menuSharer;
    if (sharer != null) {
      await sharer.shareText(text, subject: name);
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    messenger.showSnackBar(SnackBar(content: Text(l10n.profileExportCopied)));
  }

  Future<void> _delete(
    BuildContext context,
    SettingsController controller,
    NamedProfile person,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final navigator = Navigator.of(context);
    final agreed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.profileDeleteTitle(profileDisplayName(l10n, person))),
        content: Text(l10n.profileDeleteBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.actionCancel),
          ),
          FilledButton(
            key: profileDeleteConfirmKey,
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.profileDeleteConfirm),
          ),
        ],
      ),
    );
    if (agreed != true) return;
    await controller.deleteProfile(profileId);
    navigator.pop();
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/screens/premium_gate.dart';
import 'package:ketoclub/screens/profile_editor_screen.dart';
import 'package:ketoclub/screens/profile_import_screen.dart';
import 'package:ketoclub/services/platform/menu_sharer.dart';
import 'package:ketoclub/services/platform/screen_brightness.dart';
import 'package:ketoclub/state/settings_controller.dart';
import 'package:ketoclub/utils/premium_gates.dart';
import 'package:ketoclub/widgets/profile_name_dialog.dart';
import 'package:ketoclub/widgets/profile_names.dart';
import 'package:provider/provider.dart';

/// The row of the profile [id] in Settings' people group.
Key settingsProfileRowKey(String id) =>
    ValueKey<String>('settingsProfileRow_$id');

/// The people group's "Add person" button.
const Key settingsProfilesAddKey = Key('settingsProfilesAdd');

/// The people group's "Import a profile" button.
const Key settingsProfilesImportKey = Key('settingsProfilesImport');

/// The rows of Settings' "People on this device" group (Banto, ALG-12,
/// issue #354): one per profile — its name, "Me" for the user's own until
/// renamed, and its restrictions — each opening the [ProfileEditorScreen];
/// then "Add person", which asks for a name and opens the new person's
/// editor, and "Import a profile", which opens the
/// [ProfileImportScreen]. Settings draws the group around these rows.
class SettingsProfilesList extends StatelessWidget {
  /// Creates the rows.
  const new({
    this.screenBrightness = const NoOpScreenBrightness(),
    this.menuSharer,
    super.key,
  });

  /// Passed to the editor, for a person's chef card.
  final ScreenBrightness screenBrightness;

  /// Passed to the editor, for sharing a profile and a chef card.
  final MenuSharer? menuSharer;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context);
    final controller = context.watch<SettingsController>();
    final busy = controller.isBusy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final person in controller.profiles)
          ListTile(
            key: settingsProfileRowKey(person.id),
            leading: Icon(
              person.isPrimary ? Icons.person_outline : Icons.group_outlined,
            ),
            title: Text(profileDisplayName(l10n, person)),
            subtitle: Text(
              profileRestrictionsLine(l10n, locale, person.profile),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => unawaited(_open(context, controller, person.id)),
          ),
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(8, 4, 8, 8),
          child: Wrap(
            spacing: 8,
            children: [
              if (controller.canAddProfile) ...[
                TextButton.icon(
                  key: settingsProfilesAddKey,
                  icon: const Icon(Icons.person_add_alt),
                  label: Text(l10n.settingsProfilesAdd),
                  onPressed: busy
                      ? null
                      : () => unawaited(_add(context, controller)),
                ),
                TextButton.icon(
                  key: settingsProfilesImportKey,
                  icon: const Icon(Icons.download_outlined),
                  label: Text(l10n.settingsProfilesImport),
                  onPressed: () => unawaited(_import(context, controller)),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// Whether another person may be added: Premium's group profiles
  /// (ALG-18). The people already on the device stay, whatever the plan.
  Future<bool> _mayAddPerson(BuildContext context) => passPremiumGate(
    context,
    PremiumFeature.groupProfiles,
    locks: PremiumGates.locksAddingPerson,
  );

  Future<void> _import(
    BuildContext context,
    SettingsController controller,
  ) async {
    if (!await _mayAddPerson(context) || !context.mounted) return;
    await _push(context, controller, const ProfileImportScreen());
  }

  Future<void> _add(BuildContext context, SettingsController controller) async {
    if (!await _mayAddPerson(context) || !context.mounted) return;
    final l10n = AppLocalizations.of(context)!;
    final name = await showProfileNameDialog(
      context,
      title: l10n.profileNameAddTitle,
    );
    if (name == null) return;
    final id = await controller.addProfile(name);
    if (id == null || !context.mounted) return;
    await _open(context, controller, id);
  }

  Future<void> _open(
    BuildContext context,
    SettingsController controller,
    String id,
  ) => _push(
    context,
    controller,
    ProfileEditorScreen(
      profileId: id,
      screenBrightness: screenBrightness,
      menuSharer: menuSharer,
    ),
  );

  /// Pushes [screen] with [controller] provided to it: Settings' own
  /// provider sits on its route, which a pushed route does not inherit.
  Future<void> _push(
    BuildContext context,
    SettingsController controller,
    Widget screen,
  ) => Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => ChangeNotifierProvider<SettingsController>.value(
        value: controller,
        child: screen,
      ),
    ),
  );
}

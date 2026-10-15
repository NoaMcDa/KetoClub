import 'package:flutter/material.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/models/named_profile.dart';
import 'package:ketoclub/state/settings_controller.dart';
import 'package:ketoclub/utils/allergens/profile_transfer.dart';
import 'package:ketoclub/widgets/app_notice.dart';
import 'package:ketoclub/widgets/content_width.dart';
import 'package:ketoclub/widgets/profile_names.dart';
import 'package:provider/provider.dart';

/// The import screen's paste field.
const Key profileImportFieldKey = Key('profileImportField');

/// The import screen's "Read profile" button.
const Key profileImportReadKey = Key('profileImportRead');

/// The line shown when the pasted text is not a shared profile.
const Key profileImportInvalidKey = Key('profileImportInvalid');

/// The name field of the import preview.
const Key profileImportNameKey = Key('profileImportName');

/// The import preview's "Save on this device" button.
const Key profileImportSaveKey = Key('profileImportSave');

/// Imports a profile someone shared as text (Banto, ALG-12, issue #354).
///
/// Says first that a shared profile is health data. The pasted text is
/// read on the device ([ProfileTransfer.decode]) and shown — the name,
/// editable, and the restrictions — under "Save this profile on this
/// device?"; nothing is stored until the user taps Save, which adds it as
/// a new person ([SettingsController.addProfile]) and closes the screen.
/// Reads the [SettingsController] from `provider`, supplied by the caller.
class ProfileImportScreen extends StatefulWidget {
  /// Creates the import screen.
  const new({super.key});

  @override
  State<ProfileImportScreen> createState() => _ProfileImportScreenState();
}

class _ProfileImportScreenState extends State<ProfileImportScreen> {
  final TextEditingController _paste = TextEditingController();
  final TextEditingController _name = TextEditingController();

  /// What the paste held, once read; null before, or when unreadable.
  SharedProfile? _read;

  /// Whether the last read failed.
  bool _invalid = false;

  @override
  void dispose() {
    _paste.dispose();
    _name.dispose();
    super.dispose();
  }

  void _readPaste() {
    final read = ProfileTransfer.decode(_paste.text);
    setState(() {
      _read = read;
      _invalid = read == null;
      _name.text = read?.name ?? '';
    });
  }

  Future<void> _save(SettingsController controller) async {
    final read = _read;
    if (read == null) return;
    final navigator = Navigator.of(context);
    final id = await controller.addProfile(_name.text, profile: read.profile);
    if (id != null) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context);
    final controller = context.watch<SettingsController>();
    final read = _read;
    final canSave =
        read != null &&
        controller.canAddProfile &&
        !controller.isBusy &&
        NamedProfile.normaliseName(_name.text).isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.profileImportTitle)),
      body: ContentWidth(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppNotice.info(
                message: l10n.profileImportBody,
                icon: Icons.health_and_safety_outlined,
              ),
              const SizedBox(height: 16),
              TextField(
                key: profileImportFieldKey,
                controller: _paste,
                minLines: 3,
                maxLines: 6,
                decoration: InputDecoration(labelText: l10n.profileImportField),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: OutlinedButton(
                  key: profileImportReadKey,
                  onPressed: _readPaste,
                  child: Text(l10n.profileImportRead),
                ),
              ),
              if (_invalid) ...[
                const SizedBox(height: 8),
                Text(
                  l10n.profileImportInvalid,
                  key: profileImportInvalidKey,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
              if (read != null) ...[
                const SizedBox(height: 20),
                Text(l10n.profileImportAsk, style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                TextField(
                  key: profileImportNameKey,
                  controller: _name,
                  maxLength: NamedProfile.maxNameLength,
                  decoration: InputDecoration(labelText: l10n.profileNameLabel),
                  onChanged: (_) => setState(() {}),
                ),
                Text(profileRestrictionsLine(l10n, locale, read.profile)),
                if (!controller.canAddProfile) ...[
                  const SizedBox(height: 8),
                  Text(
                    l10n.profileImportFull,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                FilledButton(
                  key: profileImportSaveKey,
                  onPressed: canSave ? () => _save(controller) : null,
                  child: Text(l10n.profileImportSave),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

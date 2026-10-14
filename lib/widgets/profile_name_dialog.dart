import 'package:flutter/material.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/models/named_profile.dart';

/// The name field of [showProfileNameDialog].
const Key profileNameFieldKey = Key('profileNameField');

/// The Save button of [showProfileNameDialog].
const Key profileNameSaveKey = Key('profileNameSave');

/// Asks for a profile's name (Banto, ALG-12, issue #354) under [title],
/// starting from [initial], and answers what was typed, or null when the
/// dialog is cancelled. [allowEmpty] lets Save answer a blank name, which
/// for the user's own profile restores "Me".
Future<String?> showProfileNameDialog(
  BuildContext context, {
  required String title,
  String initial = '',
  bool allowEmpty = false,
}) => showDialog<String>(
  context: context,
  builder: (_) => _ProfileNameDialog(
    title: title,
    initial: initial,
    allowEmpty: allowEmpty,
  ),
);

class _ProfileNameDialog extends StatefulWidget {
  const new({
    required this.title,
    required this.initial,
    required this.allowEmpty,
  });

  final String title;
  final String initial;
  final bool allowEmpty;

  @override
  State<_ProfileNameDialog> createState() => _ProfileNameDialogState();
}

class _ProfileNameDialogState extends State<_ProfileNameDialog> {
  late final TextEditingController _field = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  bool get _canSave => widget.allowEmpty || _field.text.trim().isNotEmpty;

  void _save() {
    if (_canSave) Navigator.pop(context, _field.text);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        key: profileNameFieldKey,
        controller: _field,
        autofocus: true,
        maxLength: NamedProfile.maxNameLength,
        textCapitalization: TextCapitalization.words,
        decoration: InputDecoration(labelText: l10n.profileNameLabel),
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _save(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.actionCancel),
        ),
        FilledButton(
          key: profileNameSaveKey,
          onPressed: _canSave ? _save : null,
          child: Text(l10n.profileNameSave),
        ),
      ],
    );
  }
}

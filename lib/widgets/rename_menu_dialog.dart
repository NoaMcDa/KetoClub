import 'package:flutter/material.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';

/// What the user typed into the rename dialog (issue #315): the raw text of
/// both fields, untrimmed. Empty text means "no name" or "no city"; the
/// receiver trims and maps it to null.
typedef MenuRename = ({String name, String city});

/// Opens the dialog that names a scanned menu (issue #315) and completes
/// with what the user saved, or null when they cancelled or dismissed it.
///
/// The fields start at [initialName] and [initialCity] (null reads as
/// empty). Pure UI: it neither trims nor stores anything, so the Menu and
/// Recent screens share one dialog and each hands the result to its own
/// controller.
Future<MenuRename?> showRenameMenuDialog(
  BuildContext context, {
  required String? initialName,
  required String? initialCity,
}) => showDialog<MenuRename>(
  context: context,
  builder: (context) =>
      RenameMenuDialog(initialName: initialName, initialCity: initialCity),
);

/// An [AlertDialog] with a name field and a city field for a scanned menu
/// (issue #315), a Cancel button and a Save button.
///
/// Save pops the dialog with a [MenuRename]; Cancel pops with null.
class RenameMenuDialog extends StatefulWidget {
  /// Creates the dialog, its fields seeded with [initialName] and
  /// [initialCity] (null reads as empty).
  const new({required this.initialName, required this.initialCity, super.key});

  /// The name already on file for the menu, or null when there is none.
  final String? initialName;

  /// The city already on file for the menu, or null when there is none.
  final String? initialCity;

  @override
  State<RenameMenuDialog> createState() => _RenameMenuDialogState();
}

class _RenameMenuDialogState extends State<RenameMenuDialog> {
  late final TextEditingController _name;
  late final TextEditingController _city;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initialName ?? '');
    _city = TextEditingController(text: widget.initialCity ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _city.dispose();
    super.dispose();
  }

  void _save() =>
      Navigator.of(context)
          .pop<MenuRename>((name: _name.text, city: _city.text));

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.menuRenameTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const ValueKey('menuRenameName'),
              controller: _name,
              autofocus: true,
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(hintText: l10n.menuRenameHint),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('menuRenameCity'),
              controller: _city,
              textInputAction: TextInputAction.done,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(hintText: l10n.menuRenameCityHint),
              onSubmitted: (_) => _save(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.actionCancel),
        ),
        FilledButton(
          key: const ValueKey('menuRenameSave'),
          onPressed: _save,
          child: Text(l10n.menuRenameSave),
        ),
      ],
    );
  }
}

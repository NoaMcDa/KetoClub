import 'package:flutter/material.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';

/// A modal bottom sheet for writing, editing or clearing a personal note on
/// a dish (issue #52, architecture.md D8): a short annotation for the
/// user's own benefit, e.g. "Waitstaff happily substituted cauliflower".
///
/// The note stays on-device. This sheet never sends it anywhere — see
/// `NotesStore`'s own doc comment for that boundary — it only collects the
/// text and hands it to [onSave] or triggers [onClear].
class NoteEditorSheet extends StatefulWidget {
  /// Creates a sheet for [dishName], seeded with [initialNote] (blank when
  /// there is none yet). [onSave] is called with the field's trimmed text
  /// when the user taps Save; [onClear] when they tap Clear. Either one
  /// closes the sheet.
  const new({
    required this.dishName,
    required this.initialNote,
    required this.onSave,
    required this.onClear,
    super.key,
  });

  /// The dish this note is about, shown as the sheet's subheading.
  final String dishName;

  /// The note already on file for this dish, or null when there is none.
  /// Seeds the text field; [ValueChanged] callers pass the up-to-date
  /// value from their own store, not a value this widget caches itself.
  final String? initialNote;

  /// Called with the field's trimmed text when the user taps Save. An
  /// empty result (the field was cleared by hand) is still passed through
  /// rather than treated as a tap of [onClear]: the caller — `noteFor`'s
  /// owner — is the one place that already knows an empty save should
  /// read as a clear (`MenuController.setNote`'s own doc comment).
  final ValueChanged<String> onSave;

  /// Called when the user taps Clear, removing any existing note.
  final VoidCallback onClear;

  @override
  State<NoteEditorSheet> createState() => _NoteEditorSheetState();
}

class _NoteEditorSheetState extends State<NoteEditorSheet> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialNote ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    widget.onSave(_controller.text.trim());
    Navigator.of(context).pop();
  }

  void _clear() {
    widget.onClear();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final hasExistingNote =
        widget.initialNote != null && widget.initialNote!.isNotEmpty;
    return SafeArea(
      child: Padding(
        padding: EdgeInsetsDirectional.only(
          start: 24,
          end: 24,
          top: 24,
          bottom: 24 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.noteEditorTitle, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(widget.dishName, style: theme.textTheme.bodySmall),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              autofocus: true,
              maxLines: 4,
              minLines: 2,
              decoration: InputDecoration(
                hintText: l10n.noteEditorHint,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                if (hasExistingNote)
                  TextButton(
                    onPressed: _clear,
                    child: Text(l10n.noteEditorClear),
                  ),
                const Spacer(),
                ElevatedButton(
                  onPressed: _save,
                  child: Text(l10n.noteEditorSave),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

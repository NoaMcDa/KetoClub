import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';

/// Splits a waiter script into its numbered instructions.
///
/// `AnalysedDish.modification` is one newline-separated string today,
/// whichever engine wrote it (architecture.md §6.3): the heuristic engine
/// joins its `CARB_MODIFIERS` templates with `\n`, and the LLM prompt asks
/// for "one instruction per line". Splitting on `\n`, trimming each piece,
/// and dropping anything that trims to empty (a stray trailing newline)
/// turns that into the artboard's numbered rows. A script with no newline
/// at all — a single sentence — yields exactly one line, numbered "1"
/// like any other: this never returns an empty list for a non-empty
/// [script], since [WaiterScriptWidget]'s own contract requires one.
List<String> _splitScriptLines(String script) => script
    .split('\n')
    .map((line) => line.trim())
    .where((line) => line.isNotEmpty)
    .toList();

/// A waiter instruction, rendered as numbered, selectable lines with a
/// button to copy the whole script (architecture.md §6.3, §6.6).
///
/// [script] is `AnalysedDish.modification`, in whichever language the
/// menu is in, never the UI language (architecture.md §12) — this widget
/// renders it verbatim, only reflowed into numbered lines, and adds no
/// translated wording of its own beyond the copy affordance. Copying
/// always puts [script] itself on the clipboard, never the numbering this
/// widget draws around it.
class WaiterScriptWidget extends StatelessWidget {
  /// Creates a widget showing [script] as numbered lines, calling
  /// [onCopied] once the text has been copied to the clipboard.
  const new({required this.script, this.onCopied, super.key});

  /// The waiter instruction text, in the menu's language. Never empty.
  final String script;

  /// Called after [script] has been copied to the clipboard.
  final VoidCallback? onCopied;

  /// Copies [script] verbatim to the clipboard, notifies [onCopied], and
  /// shows a brief confirmation when [context] has a [ScaffoldMessenger].
  Future<void> _copy(BuildContext context, AppLocalizations l10n) async {
    await Clipboard.setData(ClipboardData(text: script));
    onCopied?.call();
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(l10n.actionCopied)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final lines = _splitScriptLines(script);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // One Semantics node for every numbered line, so a screen reader
        // announces the whole script as a single block rather than each
        // ordinal circle and line of text as its own disjoint node
        // (architecture.md §8.3). The label is the script's own lines,
        // in the menu's language, exactly as printed — never translated
        // or re-worded, per this widget's own doc comment. Visual
        // selection (SelectableText) and the copy button below are
        // unaffected: excludeSemantics only replaces what a screen reader
        // announces, not what a sighted user can tap or select.
        Semantics(
          label: lines.join(' '),
          excludeSemantics: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < lines.length; i++)
                Padding(
                  padding: EdgeInsetsDirectional.only(
                    bottom: i == lines.length - 1 ? 0 : 12,
                  ),
                  child: _NumberedLine(number: i + 1, text: lines[i]),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: FilledButton.icon(
            onPressed: () => _copy(context, l10n),
            icon: const Icon(Icons.copy),
            label: Text(l10n.waiterCardCopyButton),
          ),
        ),
      ],
    );
  }
}

/// One numbered instruction: a circled ordinal beside its selectable text.
class _NumberedLine extends StatelessWidget {
  const new({required this.number, required this.text});

  /// This line's 1-based position among the script's lines.
  final int number;

  /// This line's instruction text, verbatim from the script.
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 14,
          backgroundColor: theme.colorScheme.primary,
          foregroundColor: theme.colorScheme.onPrimary,
          child: Text(
            number.toString(),
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: SelectableText(text, style: theme.textTheme.bodyLarge),
          ),
        ),
      ],
    );
  }
}

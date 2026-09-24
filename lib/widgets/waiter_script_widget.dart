import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/theme/verdict_colors.dart';
import 'package:ketoclub/widgets/content_direction.dart';

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
  const new({
    required this.script,
    this.onCopied,
    this.prominent = false,
    super.key,
  });

  /// The waiter instruction text, in the menu's language. Never empty.
  final String script;

  /// Called after [script] has been copied to the clipboard.
  final VoidCallback? onCopied;

  /// Whether to draw the lines at the full-screen Waiter Card's size
  /// (`.design/WaiterCard.dc.html`: 21px medium text, a 30px number)
  /// rather than the dish card's inline size (`.design/Main.dc.html`:
  /// 13px text at a 1.55 line height).
  final bool prominent;

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
        for (var i = 0; i < lines.length; i++)
          Padding(
            padding: EdgeInsetsDirectional.only(
              bottom: i == lines.length - 1 ? 0 : 12,
            ),
            child: _NumberedLine(
              number: i + 1,
              text: lines[i],
              prominent: prominent,
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

/// One numbered instruction: a circled number in the modifiable verdict's
/// amber — the artboards' colour for everything a waiter is asked to
/// change — and the selectable instruction text beside it.
class _NumberedLine extends StatelessWidget {
  const new({
    required this.number,
    required this.text,
    required this.prominent,
  });

  /// The 1-based line number shown in the leading circle.
  final int number;

  /// The instruction text for this line.
  final String text;

  /// See [WaiterScriptWidget.prominent].
  final bool prominent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final amber = VerdictColors.of(context).forVerdict(DishVerdict.modifiable);
    final diameter = prominent ? 30.0 : 24.0;
    final textStyle = prominent
        ? theme.textTheme.bodyLarge?.copyWith(
            fontSize: 21,
            fontWeight: FontWeight.w500,
            height: 1.38,
          )
        : theme.textTheme.bodyMedium?.copyWith(fontSize: 13, height: 1.55);
    // The script is in the menu's language (architecture.md §12), so the
    // whole numbered line — number first — follows that language's
    // direction, not the UI's.
    return Directionality(
      textDirection: contentDirection(text, Directionality.of(context)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: diameter,
            height: diameter,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: amber.pill,
              shape: BoxShape.circle,
            ),
            child: Text(
              number.toString(),
              style: theme.textTheme.labelLarge?.copyWith(
                fontSize: prominent ? 15 : 12,
                color: amber.on,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          SizedBox(width: prominent ? 14 : 10),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: prominent ? 0 : 2),
              child: SelectableText(text, style: textStyle),
            ),
          ),
        ],
      ),
    );
  }
}

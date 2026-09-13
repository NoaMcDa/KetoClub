import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';

/// A waiter instruction: selectable, copyable text, and nothing else
/// (architecture.md §6.3, §6.6).
///
/// [script] is `AnalysedDish.modification`, in whichever language the
/// menu is in, never the UI language (architecture.md §12) — this widget
/// renders it verbatim and adds no translated wording of its own beyond
/// the copy affordance.
class WaiterScriptWidget extends StatelessWidget {
  /// Creates a widget showing [script], calling [onCopied] once the text
  /// has been copied to the clipboard.
  const new({required this.script, this.onCopied, super.key});

  /// The waiter instruction text, in the menu's language. Never empty.
  final String script;

  /// Called after [script] has been copied to the clipboard.
  final VoidCallback? onCopied;

  /// Copies [script] to the clipboard, notifies [onCopied], and shows a
  /// brief confirmation when [context] has a [ScaffoldMessenger].
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: SelectableText(script)),
        IconButton(
          tooltip: l10n.actionCopy,
          icon: const Icon(Icons.copy),
          onPressed: () => _copy(context, l10n),
        ),
      ],
    );
  }
}

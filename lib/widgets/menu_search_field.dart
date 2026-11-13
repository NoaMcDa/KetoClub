import 'package:flutter/material.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';

/// The search field at the top of the loaded menu (issue #51): narrows
/// `MenuController.visibleRows` by a dish's name and description as the
/// user types, combined with whatever verdict filter is already active.
///
/// The text lives in `MenuController.query`, passed in as [query] (issue
/// #286): the field sits in a lazy list, so scrolling it far out of view,
/// or the window crossing the menu's two-pane width, builds it afresh,
/// and a field that kept the text only in its own state came back empty
/// while the query still filtered the dishes. Its [TextEditingController]
/// starts from [query] and follows it only when [query] changes to
/// something other than what the field already reads — cleared from
/// elsewhere, say — so a rebuild while the user types (every keystroke
/// sets the query, which rebuilds the screen) never resets the text or
/// moves the cursor.
class MenuSearchField extends StatefulWidget {
  /// Creates a search field showing [query] that reports every change,
  /// including the clear button's tap, through [onChanged].
  const new({required this.onChanged, this.query = '', super.key});

  /// The search text the field shows: `MenuController.query`.
  final String query;

  /// Called with the field's current text on every change. Called with
  /// `''` when the clear button is tapped, even if the field already read
  /// `''` (idempotent, so a caller need not special-case it).
  final ValueChanged<String> onChanged;

  @override
  State<MenuSearchField> createState() => _MenuSearchFieldState();
}

class _MenuSearchFieldState extends State<MenuSearchField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.query,
  );

  @override
  void didUpdateWidget(MenuSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.query == _controller.text) return;
    _controller.value = TextEditingValue(
      text: widget.query,
      selection: TextSelection.collapsed(offset: widget.query.length),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _clear() {
    _controller.clear();
    widget.onChanged('');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Semantics(
      textField: true,
      label: l10n.menuSearchSemanticLabel,
      child: TextField(
        controller: _controller,
        onChanged: widget.onChanged,
        decoration: InputDecoration(
          isDense: true,
          hintText: l10n.menuSearchHint,
          prefixIcon: const Icon(Icons.search),
          // A ValueListenableBuilder over the controller itself — rather
          // than a manual listener plus setState — so the clear button
          // appears and disappears exactly when the field's own text does,
          // with no extra state to keep in sync.
          suffixIcon: ValueListenableBuilder<TextEditingValue>(
            valueListenable: _controller,
            builder: (_, value, _) => value.text.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    icon: const Icon(Icons.clear),
                    tooltip: l10n.menuSearchClear,
                    onPressed: _clear,
                  ),
          ),
        ),
      ),
    );
  }
}

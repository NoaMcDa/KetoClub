import 'package:flutter/material.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';

/// The search field at the top of the loaded menu (issue #51): narrows
/// `MenuController.visibleRows` by a dish's name and description as the
/// user types, combined with whatever verdict filter is already active.
///
/// Owns its own [TextEditingController] rather than taking the current
/// text as a constructor parameter — nothing above this widget needs the
/// raw text, only the normalised match `MenuController.setQuery` already
/// does through [onChanged] — so a rebuild of the screen around it (a new
/// filter, a pulled-to-refresh menu) never resets what the user is
/// mid-typing or moves the cursor.
class MenuSearchField extends StatefulWidget {
  /// Creates a search field that reports every change, including the
  /// clear button's tap, through [onChanged].
  const new({required this.onChanged, super.key});

  /// Called with the field's current text on every change. Called with
  /// `''` when the clear button is tapped, even if the field already read
  /// `''` (idempotent, so a caller need not special-case it).
  final ValueChanged<String> onChanged;

  @override
  State<MenuSearchField> createState() => _MenuSearchFieldState();
}

class _MenuSearchFieldState extends State<MenuSearchField> {
  final TextEditingController _controller = TextEditingController();

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

import 'package:flutter/material.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/utils/banto_mode.dart';
import 'package:ketoclub/widgets/app_sheet.dart';

/// The key of the helper-tool sheet's body.
const Key helperToolSheetKey = ValueKey<String>('helperToolSheet');

/// The key of the helper-tool sheet's "Got it" button.
const Key helperToolOkKey = ValueKey<String>('helperToolOk');

/// Opens the [HelperToolSheet] as a modal bottom sheet capped at the app's
/// sheet width ([showKetoClubSheet]).
///
/// With [bantoMode] off nothing opens and the future completes at once, so
/// a caller needs no gate of its own.
Future<void> showHelperToolSheet(
  BuildContext context, {
  bool bantoMode = BantoMode.enabled,
}) {
  if (!bantoMode) return Future<void>.value();
  return showKetoClubSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => HelperToolSheet(bantoMode: bantoMode),
  );
}

/// "A helper, not a guarantee" (Banto, ALG-11, issue #353): the
/// helper-tool sentence, shown once when the first restriction of any kind
/// is added in Settings. The first-run onboarding carries the same sentence
/// on its own page, and every menu's legend ends on it.
///
/// One sentence for every restriction (the owner's decision, 2026-10-11):
/// the app reads menus, cannot see the kitchen and promises no accuracy.
///
/// With [bantoMode] off the widget builds nothing.
class HelperToolSheet extends StatelessWidget {
  /// Creates the sheet.
  const new({this.bantoMode = BantoMode.enabled, super.key});

  /// Whether this build shows Banto surfaces; the sheet is empty without.
  final bool bantoMode;

  @override
  Widget build(BuildContext context) {
    if (!bantoMode) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        key: helperToolSheetKey,
        padding: const EdgeInsetsDirectional.fromSTEB(24, 0, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                l10n.helperToolTitle,
                style: theme.textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 12),
            Text(l10n.helperToolSentence, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 20),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FilledButton(
                key: helperToolOkKey,
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.helperToolOk),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

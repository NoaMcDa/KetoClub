import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/state/scan_controller.dart';
import 'package:ketoclub/utils/venue_route.dart';
import 'package:provider/provider.dart';

/// The Scan tab (architecture.md §6.6, D18; issues #11, #83): a field to
/// paste a menu's text into and an Analyse button that opens it.
///
/// Photographing a physical menu is still to come (#82 adds those actions
/// around this field); pasting is the path that needs no camera and no
/// OCR. Analyse stores the parsed menu through [ScanController] and then
/// pushes `/venue/scan/{id}`, so the menu screen loads, classifies and
/// caches it exactly like a venue from a delivery platform.
///
/// A `StatefulWidget` only to own the [TextEditingController]; the pasted
/// text itself lives in [ScanController].
class ScanScreen extends StatefulWidget {
  /// Creates the Scan tab.
  const new({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final TextEditingController _field = TextEditingController();

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  Future<void> _analyse() async {
    final controller = context.read<ScanController>();
    final ref = await controller.submitPaste(
      uncategorisedName: AppLocalizations.of(context)!.sourceScanned,
    );
    if (ref == null || !mounted) return;
    Navigator.pushNamed(context, venueRoutePath(ref));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final controller = context.watch<ScanController>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.scanTitle)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(l10n.scanPasteIntro, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 16),
          TextField(
            controller: _field,
            onChanged: (value) => controller.text = value,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            minLines: 8,
            maxLines: 14,
            decoration: InputDecoration(
              labelText: l10n.scanPasteLabel,
              hintText: l10n.scanPasteHint,
              alignLabelWithHint: true,
              border: const OutlineInputBorder(),
            ),
          ),
          if (controller.emptyPaste) ...[
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              child: Text(
                l10n.scanEmptyPaste,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: controller.canAnalyse
                  ? () => unawaited(_analyse())
                  : null,
              child: Text(l10n.scanAnalyse),
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';

/// The Scan tab's placeholder screen (architecture.md §6.6; issue #11).
///
/// Physical-menu scanning is Phase 4 (`CLAUDE.md` "What is NOT built yet");
/// this screen exists only so the tab has somewhere to land, with localized
/// copy explaining that plainly rather than showing a blank page.
class ScanScreen extends StatelessWidget {
  /// Creates the Scan placeholder screen.
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.scanPlaceholderTitle)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.document_scanner_outlined, size: 48),
              const SizedBox(height: 16),
              Text(l10n.scanPlaceholderBody, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}

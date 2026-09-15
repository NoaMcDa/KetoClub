import 'package:flutter/material.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';

/// The Saved tab's placeholder screen (architecture.md §6.6; issue #11).
///
/// Saving a venue is not built yet (`CLAUDE.md` "What is NOT built yet"
/// lists community and history features as Phase 3); this screen exists
/// only so the tab has somewhere to land, with localized copy explaining
/// that plainly rather than showing a blank page.
class SavedScreen extends StatelessWidget {
  /// Creates the Saved placeholder screen.
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.savedPlaceholderTitle)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.bookmark_border, size: 48),
              const SizedBox(height: 16),
              Text(l10n.savedPlaceholderBody, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/state/venue_search_controller.dart';
import 'package:ketoclub/utils/constants.dart';
import 'package:provider/provider.dart';

/// The first screen: paste a venue link and open its menu
/// (architecture.md §6.5 Tier A, §6.6).
///
/// Nearby search (Tier B) is out of scope for this screen; it reads a
/// [VenueSearchController] for the current input and its resolution and
/// otherwise does no work of its own.
class VenueSearchScreen extends StatelessWidget {
  /// Creates the venue search screen.
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final controller = context.watch<VenueSearchController>();
    final resolved = controller.resolved;

    return Scaffold(
      appBar: AppBar(
        title: const Text(appName),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: l10n.actionOpenSettings,
            onPressed: () => Navigator.pushNamed(context, '/settings'),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              onChanged: controller.setInput,
              decoration: InputDecoration(
                labelText: l10n.venueSearchLabel,
                hintText: l10n.venueSearchHint,
                errorText: controller.isInvalid
                    ? l10n.venueSearchInvalid
                    : null,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: resolved == null
                  ? null
                  : () => Navigator.pushNamed(
                      context,
                      '/venue/${resolved.source.name}/${resolved.platformId}',
                    ),
              child: Text(l10n.venueSearchOpen),
            ),
          ],
        ),
      ),
    );
  }
}

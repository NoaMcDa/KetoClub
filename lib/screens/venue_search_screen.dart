import 'package:flutter/material.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/state/venue_search_controller.dart';
import 'package:ketoclub/utils/constants.dart';
import 'package:provider/provider.dart';

/// The first screen: paste a venue link and open its menu
/// (architecture.md §6.5 Tier A, §6.6; `.design/Discovery.dc.html`).
///
/// Nearby search (Tier B) is out of scope for this screen; it reads a
/// [VenueSearchController] for the current input and its resolution and
/// otherwise does no work of its own.
///
/// This screen is a tab root under `AppShell` (`widgets/app_shell.dart`),
/// which already supplies a Settings tab in the bottom navigation — the
/// standalone app bar this screen carried before the bottom nav shipped
/// (issue #11) is gone, matching the sibling tab roots `ScanScreen` and
/// `SavedScreen`, neither of which duplicates a cross-tab shortcut in its
/// own app bar either.
///
/// The artboard this screen is built from also shows a location eyebrow
/// ("Looking around Rothschild 22"), filter chips ("Nearby", "Keto 8+",
/// "Open now", "Grill") and a scrollable list of nearby venues. None of
/// that is built here: `LocationService` and any Wolt venue-search
/// endpoint are Phase 2, blocked on issue #38 (architecture.md §6.5,
/// §17.2; `CLAUDE.md` "What is NOT built yet"). Rendering those chips or
/// that list from static or empty data would filter and list nothing, and
/// would look broken rather than merely unfinished — so the space they
/// would occupy is a single honest empty state explaining that only a
/// pasted link works today, instead.
class VenueSearchScreen extends StatelessWidget {
  /// Creates the venue search screen.
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final controller = context.watch<VenueSearchController>();
    final resolved = controller.resolved;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(appName, style: Theme.of(context).textTheme.labelSmall),
              const SizedBox(height: 4),
              Text(
                l10n.discoveryTitle,
                style: Theme.of(context).textTheme.displaySmall,
              ),
              const SizedBox(height: 20),
              TextField(
                onChanged: controller.setInput,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
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
              const SizedBox(height: 32),
              _emptyState(context, l10n),
            ],
          ),
        ),
      ),
    );
  }

  /// Explains what actually works today, standing in for the artboard's
  /// filter chips and nearby-venue list (see the class doc): there is no
  /// search yet, so a user who types a restaurant name and sees nothing
  /// happen must understand why rather than conclude the app is broken.
  /// Shown regardless of the field's state, since it is guidance for
  /// what to type, not feedback on what was typed — the field's own
  /// `errorText` above already covers unreadable input.
  Widget _emptyState(BuildContext context, AppLocalizations l10n) {
    final ink2 = Theme.of(context).colorScheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.link, size: 40, color: ink2),
        const SizedBox(height: 12),
        Text(
          l10n.discoveryEmptyTitle,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 6),
        Text(
          l10n.discoveryEmptyBody,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }
}

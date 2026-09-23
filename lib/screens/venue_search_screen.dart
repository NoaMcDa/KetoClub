import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/platform/connectivity.dart';
import 'package:ketoclub/state/venue_search_controller.dart';
import 'package:ketoclub/utils/constants.dart';
import 'package:ketoclub/widgets/offline_banner.dart';
import 'package:provider/provider.dart';

/// The first screen: paste a venue link and open its menu
/// (architecture.md §6.5 Tier A, §6.6; `.design/Discovery.dc.html`).
///
/// Nearby search (Tier B) is out of scope for this screen; it reads a
/// [VenueSearchController] for the current input and its resolution, and
/// for the last venue opened (issue #55), and otherwise does no work of
/// its own.
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
///
/// A `StatefulWidget` for the same one reason `SavedScreen` and
/// `SettingsScreen` are: [VenueSearchController.load] must run after the
/// first frame, not from `build`, so this screen defers it from
/// `initState` the same way theirs do.
class VenueSearchScreen extends StatefulWidget {
  /// Creates the venue search screen, showing the persistent offline
  /// banner (issue #68) over [connectivity].
  const new({required this.connectivity, super.key});

  /// Backs the persistent offline banner (issue #68). This screen makes
  /// no fetch of its own to retry, so it checks once, on screen open,
  /// and never again — see [OfflineBanner]'s own doc comment.
  final Connectivity connectivity;

  @override
  State<VenueSearchScreen> createState() => _VenueSearchScreenState();
}

class _VenueSearchScreenState extends State<VenueSearchScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(context.read<VenueSearchController>().load());
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final controller = context.watch<VenueSearchController>();
    final resolved = controller.resolved;
    final lastVenue = controller.lastVenue;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              OfflineBanner(connectivity: widget.connectivity),
              Text(appName, style: Theme.of(context).textTheme.labelSmall),
              const SizedBox(height: 4),
              Text(
                l10n.discoveryTitle,
                style: Theme.of(context).textTheme.displaySmall,
              ),
              if (lastVenue != null) ...[
                const SizedBox(height: 16),
                _continueRow(context, l10n, lastVenue),
              ],
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

  /// The "Continue with {venue}" row (issue #55): tapping it opens
  /// [lastVenue]'s menu route exactly as the search field's own submit
  /// affordance does, using [VenueSearchController.lastVenueName] for
  /// the venue's display name.
  Widget _continueRow(
    BuildContext context,
    AppLocalizations l10n,
    VenueRef lastVenue,
  ) {
    final name =
        context.read<VenueSearchController>().lastVenueName ??
        lastVenue.platformId;
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: const Icon(Icons.history),
        title: Text(l10n.venueSearchContinueWith(name)),
        onTap: () => Navigator.pushNamed(
          context,
          '/venue/${lastVenue.source.name}/${lastVenue.platformId}',
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

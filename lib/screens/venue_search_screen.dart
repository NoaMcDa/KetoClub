import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/location/location_service.dart';
import 'package:ketoclub/services/platform/connectivity.dart';
import 'package:ketoclub/state/venue_search_controller.dart';
import 'package:ketoclub/utils/constants.dart';
import 'package:ketoclub/widgets/failure_copy.dart';
import 'package:ketoclub/widgets/offline_banner.dart';
import 'package:ketoclub/widgets/skeletons.dart';
import 'package:ketoclub/widgets/venue_card.dart';
import 'package:provider/provider.dart';

/// The Discovery screen (issue #40; architecture.md §6.5, §6.6, D13;
/// `phase2_discovery_research.md` §6; `.design/Discovery.dc.html`): a
/// "Looking around" header with a location button, the search field, the
/// filter chips and the venue cards.
///
/// Everything it shows comes from a [VenueSearchController]; this screen
/// does no work of its own beyond passing the UI language — the one
/// [Localizations] resolved, whether from Settings or the device — into
/// each search.
///
/// **The paste path is unchanged.** The field still accepts a Wolt link,
/// a slug or a 10bis id, and the open button below it still pushes
/// `/venue/{source}/{id}` for whatever [VenueSearchController.resolved]
/// holds, as does submitting a pasted link from the keyboard. Anything
/// else typed is a name, searched after a short pause.
///
/// **No location prompt on open.** The permission prompt appears only
/// when the user taps the location button or "Use my location", so it is
/// always something they asked for; until then the screen explains the
/// three ways in (location, name, link).
///
/// **The header's place name** is the nearest result's street address,
/// or "Your location" when the results carry none. The artboard's
/// "Rothschild 22" is the user's own street, which needs reverse
/// geocoding that no anonymous Wolt endpoint provides
/// (`phase2_discovery_research.md` §6) — deferred, not dropped.
///
/// **Card numbers follow D13**: a score and counts only for venues whose
/// analysis is already cached on the device, the *Keto 8+* chip only once
/// some card has them, and no menu fetched on load or on scroll. Above
/// the cards, while any visible card lacks numbers, an "Estimate this
/// list" button (issue #42) fetches those menus once, on the user's tap
/// only, and scores them with the on-device rules; the numbers it adds
/// carry the rules engine's estimate marker.
///
/// A permanently denied permission (issue #40) also offers "Open Settings",
/// which deep-links to the platform's own permission page through
/// [LocationService.openSettings]; a location service that is off offers
/// "Turn on location", the same call with `servicesOff: true`.
///
/// This screen is a tab root under `AppShell` (`widgets/app_shell.dart`),
/// which supplies the bottom navigation. The venue list is a [Column] in
/// the page's own scroll view rather than a lazy list: a search answers
/// a few dozen venues at most, and every card is then in the element tree
/// for tests and for screen readers alike.
class VenueSearchScreen extends StatefulWidget {
  /// Creates the Discovery screen, showing the persistent offline banner
  /// (issue #68) over [connectivity], and reaching the platform's own
  /// settings (issue #40) through [locationService].
  const new({
    required this.connectivity,
    required this.locationService,
    super.key,
  });

  /// Backs the persistent offline banner (issue #68). It checks once, on
  /// screen open — see [OfflineBanner]'s own doc comment.
  final Connectivity connectivity;

  /// Opens the platform's own settings on a permanent denial or a location
  /// service that is off (issue #40). The same instance
  /// `VenueSearchController` reads a position from — `di.dart` and the
  /// tests both pass one [LocationService] to both.
  final LocationService locationService;

  @override
  State<VenueSearchScreen> createState() => _VenueSearchScreenState();
}

class _VenueSearchScreenState extends State<VenueSearchScreen> {
  final TextEditingController _field = TextEditingController();
  final FocusNode _fieldFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(context.read<VenueSearchController>().load());
    });
  }

  @override
  void dispose() {
    _field.dispose();
    _fieldFocus.dispose();
    super.dispose();
  }

  /// The UI language code every search is made in.
  String get _language => Localizations.localeOf(context).languageCode;

  void _openVenue(VenueRef ref) {
    Navigator.pushNamed(context, '/venue/${ref.source.name}/${ref.platformId}');
  }

  void _locate() {
    unawaited(
      context.read<VenueSearchController>().locate(language: _language),
    );
  }

  void _onSubmitted(String value) {
    final controller = context.read<VenueSearchController>();
    final resolved = controller.resolved;
    if (controller.isPaste && resolved != null) {
      _openVenue(resolved);
      return;
    }
    controller.search(value, language: _language, immediate: true);
  }

  /// Opens the platform's own settings (issue #40) — the app's permission
  /// page for `servicesOff: false`, the device's location toggle for
  /// `servicesOff: true`. Fire-and-forget: the screen has nothing to show
  /// for the result, whether the user grants it or backs out again.
  void _openSettings({required bool servicesOff}) {
    unawaited(widget.locationService.openSettings(servicesOff: servicesOff));
  }

  void _clearSearch() {
    _field.clear();
    context.read<VenueSearchController>().clearSearch();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final controller = context.watch<VenueSearchController>();
    final resolved = controller.resolved;
    final lastVenue = controller.lastVenue;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsetsDirectional.fromSTEB(20, 16, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OfflineBanner(connectivity: widget.connectivity),
              _header(context, l10n, controller),
              const SizedBox(height: 12),
              Text(appName, style: textTheme.labelSmall),
              const SizedBox(height: 4),
              Text(l10n.discoveryTitle, style: textTheme.displaySmall),
              if (lastVenue != null) ...[
                const SizedBox(height: 16),
                _continueRow(context, l10n, lastVenue),
              ],
              const SizedBox(height: 20),
              TextField(
                controller: _field,
                focusNode: _fieldFocus,
                textInputAction: TextInputAction.search,
                onChanged: (value) =>
                    controller.search(value, language: _language),
                onSubmitted: _onSubmitted,
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
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: FilledButton(
                  onPressed: resolved == null
                      ? null
                      : () => _openVenue(resolved),
                  child: Text(l10n.venueSearchOpen),
                ),
              ),
              const SizedBox(height: 24),
              if (controller.phase == DiscoveryPhase.idle &&
                  controller.failure == null &&
                  controller.results.isNotEmpty) ...[
                _chips(l10n, controller),
                const SizedBox(height: 16),
              ],
              _body(context, l10n, controller),
            ],
          ),
        ),
      ),
    );
  }

  /// "Looking around {place}" with the location button at its end.
  Widget _header(
    BuildContext context,
    AppLocalizations l10n,
    VenueSearchController controller,
  ) {
    final textTheme = Theme.of(context).textTheme;
    final locating = controller.phase == DiscoveryPhase.locating;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                // Presentational upper case, as in the artboard; a no-op
                // on the Hebrew string, which has no case.
                l10n.discoveryLookingAround.toUpperCase(),
                style: textTheme.labelSmall?.copyWith(letterSpacing: 1),
              ),
              const SizedBox(height: 2),
              Text(
                _place(l10n, controller),
                style: textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        IconButton.filled(
          tooltip: l10n.discoveryUseLocation,
          icon: const Icon(Icons.my_location),
          onPressed: locating ? null : _locate,
        ),
      ],
    );
  }

  /// The header's place: the nearest result's address, "Your location"
  /// without one, or "Location not set" before any position was read.
  String _place(AppLocalizations l10n, VenueSearchController controller) {
    if (controller.position == null) return l10n.discoveryLocationNotSet;
    for (final venue in controller.results) {
      final address = venue.address;
      if (address != null && address.trim().isNotEmpty) return address;
    }
    return l10n.discoveryAroundYou;
  }

  /// The chip row: *Nearby*, *Keto 8+* (only once a card has numbers,
  /// D13), *Open now* and the one most common cuisine, when there is one.
  /// A horizontally scrollable [Row], as `CategoryChips` is.
  Widget _chips(AppLocalizations l10n, VenueSearchController controller) {
    final cuisine = controller.topCuisine;
    final chips = <(DiscoveryChip, String)>[
      (DiscoveryChip.nearby, l10n.discoveryChipNearby),
      if (controller.hasAnyNumbers)
        (DiscoveryChip.ketoEightPlus, l10n.discoveryChipKetoEightPlus),
      (DiscoveryChip.openNow, l10n.discoveryChipOpenNow),
      if (cuisine != null)
        (DiscoveryChip.cuisine, VenueCard.cuisineLabel(cuisine)),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (chip, label) in chips)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: ChoiceChip(
                label: Text(label),
                selected: controller.activeChip == chip,
                onSelected: (_) => controller.selectChip(chip),
              ),
            ),
        ],
      ),
    );
  }

  /// Everything below the chips, by precedence: work in flight, a failed
  /// search, a location that could not be read, no results, the cards, or
  /// the untouched starting state.
  Widget _body(
    BuildContext context,
    AppLocalizations l10n,
    VenueSearchController controller,
  ) {
    switch (controller.phase) {
      case DiscoveryPhase.locating:
        return _skeletons(l10n.discoveryLocating);
      case DiscoveryPhase.searching:
        return _skeletons(l10n.discoverySearching);
      case DiscoveryPhase.idle:
        break;
    }

    final failure = controller.failure;
    if (failure != null) {
      return _message(
        context,
        icon: Icons.cloud_off,
        body: venueSearchFailureMessage(failure, l10n),
        actions: [
          OutlinedButton(
            onPressed: () => unawaited(controller.retry()),
            child: Text(l10n.actionRetry),
          ),
        ],
      );
    }

    if (!controller.hasSearched) {
      final outcome = controller.locationOutcome;
      if (outcome is LocationDenied) return _denied(context, l10n, outcome);
      if (outcome is LocationUnavailable) {
        return _unavailable(context, l10n, outcome.reason);
      }
      return _message(
        context,
        icon: Icons.travel_explore,
        title: l10n.discoveryEmptyTitle,
        body: l10n.discoveryEmptyBody,
        actions: [
          OutlinedButton.icon(
            onPressed: _locate,
            icon: const Icon(Icons.my_location),
            label: Text(l10n.discoveryUseLocation),
          ),
        ],
      );
    }

    if (controller.results.isEmpty) {
      return _message(
        context,
        icon: Icons.search_off,
        title: l10n.discoveryNoResultsTitle,
        body: l10n.discoveryNoResultsBody,
        actions: [
          OutlinedButton(
            onPressed: _clearSearch,
            child: Text(l10n.discoveryClearSearch),
          ),
        ],
      );
    }

    final visible = controller.visibleResults;
    if (visible.isEmpty) {
      return _message(
        context,
        icon: Icons.filter_alt_off,
        body: l10n.discoveryNoChipResults,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (controller.isEstimating || controller.hasVisibleWithoutNumbers) ...[
          _estimateRow(context, l10n, controller),
          const SizedBox(height: 16),
        ],
        for (var i = 0; i < visible.length; i++) ...[
          if (i > 0) const SizedBox(height: 19),
          VenueCard(
            venue: visible[i],
            numbers: controller.cardNumbers(visible[i]),
            distanceKm: controller.distanceKmTo(visible[i]),
            onTap: () => _openVenue(visible[i].ref),
          ),
        ],
      ],
    );
  }

  /// The "Estimate this list" action (issue #42, D13) and the line saying
  /// what it does: rules on this device, not the AI. While it runs, the
  /// button is disabled and reads "Estimating {done} of {total}…"; a
  /// static icon rather than a spinner, so nothing animates forever.
  Widget _estimateRow(
    BuildContext context,
    AppLocalizations l10n,
    VenueSearchController controller,
  ) {
    final estimating = controller.isEstimating;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OutlinedButton.icon(
          onPressed: estimating
              ? null
              : () => unawaited(controller.estimateVisible()),
          icon: Icon(estimating ? Icons.hourglass_top : Icons.rule),
          label: Text(
            estimating
                ? l10n.discoveryEstimating(
                    controller.estimatedCount,
                    controller.estimateTotal,
                  )
                : l10n.discoveryEstimateList,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          l10n.discoveryEstimateHint,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _denied(
    BuildContext context,
    AppLocalizations l10n,
    LocationDenied outcome,
  ) {
    return _message(
      context,
      icon: Icons.location_disabled,
      title: l10n.discoveryLocationDeniedTitle,
      body: outcome.permanently
          ? l10n.discoveryLocationDeniedForeverBody
          : l10n.discoveryLocationDeniedBody,
      actions: [
        TextButton(
          onPressed: _fieldFocus.requestFocus,
          child: Text(l10n.discoveryTypeNameInstead),
        ),
        if (outcome.permanently)
          OutlinedButton(
            onPressed: () => _openSettings(servicesOff: false),
            child: Text(l10n.discoveryOpenSettings),
          )
        else
          OutlinedButton(onPressed: _locate, child: Text(l10n.actionRetry)),
      ],
    );
  }

  Widget _unavailable(
    BuildContext context,
    AppLocalizations l10n,
    LocationUnavailableReason reason,
  ) {
    final (body, canRetry) = switch (reason) {
      LocationUnavailableReason.servicesOff => (
        l10n.discoveryLocationServicesOff,
        true,
      ),
      LocationUnavailableReason.insecureContext => (
        l10n.discoveryLocationInsecureContext,
        false,
      ),
      LocationUnavailableReason.timeout => (
        l10n.discoveryLocationTimeout,
        true,
      ),
      LocationUnavailableReason.unsupported => (
        l10n.discoveryLocationUnsupported,
        false,
      ),
    };
    return _message(
      context,
      icon: Icons.location_off,
      title: l10n.discoveryLocationUnavailableTitle,
      body: body,
      actions: [
        TextButton(
          onPressed: _fieldFocus.requestFocus,
          child: Text(l10n.discoveryTypeNameInstead),
        ),
        if (reason == LocationUnavailableReason.servicesOff)
          OutlinedButton(
            onPressed: () => _openSettings(servicesOff: true),
            child: Text(l10n.discoveryTurnOnLocation),
          ),
        if (canRetry)
          OutlinedButton(onPressed: _locate, child: Text(l10n.actionRetry)),
      ],
    );
  }

  /// Three [VenueCardSkeleton]s in place of the old spinner, for a locate
  /// or a search in flight (issue #63): a run of static, two-tone cards
  /// shaped like the ones about to load, rather than a bare progress
  /// ring. Wrapped in one live [Semantics] label naming what is loading,
  /// since the cards themselves exclude their own semantics — a screen
  /// reader hears [label] once, not three times.
  Widget _skeletons(String label) {
    return Semantics(
      liveRegion: true,
      label: label,
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          VenueCardSkeleton(),
          SizedBox(height: 19),
          VenueCardSkeleton(),
          SizedBox(height: 19),
          VenueCardSkeleton(),
        ],
      ),
    );
  }

  /// An icon, an optional [title], [body] and a row of [actions]: the
  /// shape of every non-list state on this screen.
  Widget _message(
    BuildContext context, {
    required IconData icon,
    required String body,
    String? title,
    List<Widget> actions = const <Widget>[],
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 40, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(height: 12),
        if (title != null) ...[
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
        ],
        Text(body, style: theme.textTheme.bodyMedium),
        if (actions.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: actions),
        ],
      ],
    );
  }

  /// The "Continue with {venue}" row (issue #55): tapping it opens
  /// [lastVenue]'s menu route exactly as the open button does, using
  /// [VenueSearchController.lastVenueName] for the venue's display name.
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
        onTap: () => _openVenue(lastVenue),
      ),
    );
  }
}

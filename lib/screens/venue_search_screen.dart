import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/screens/drinks_guide_screen.dart';
import 'package:ketoclub/services/location/location_service.dart';
import 'package:ketoclub/services/platform/connectivity.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/state/venue_search_controller.dart';
import 'package:ketoclub/utils/constants.dart';
import 'package:ketoclub/utils/venue_route.dart';
import 'package:ketoclub/widgets/consent_disclosure_banner.dart';
import 'package:ketoclub/widgets/content_width.dart';
import 'package:ketoclub/widgets/failure_copy.dart';
import 'package:ketoclub/widgets/offline_banner.dart';
import 'package:ketoclub/widgets/skeletons.dart';
import 'package:ketoclub/widgets/venue_card.dart';
import 'package:ketoclub/widgets/venue_grid.dart';
import 'package:provider/provider.dart';

/// The launcher icon the logo mark shows (declared in `pubspec.yaml`).
const String _logoAsset = 'assets/icon/icon.png';

/// The logo mark's side, in logical pixels.
const double _logoSize = 28;

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
/// **Card numbers follow D13 as amended by D21**: a score and counts from
/// an analysis cached on the device, or from the quick score — the rule
/// engine over each menu, never the AI — which the controller runs on its
/// own for the first `venueAutoEstimateLimit` cards of every result list,
/// and on the user's tap ("Quick score the rest", issue #42) for the cards
/// past that cap. Nothing is fetched on scroll. The *Keto 8+* chip is
/// enabled once some card has numbers, and every number the quick score
/// adds carries the rules engine's estimate marker.
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
    required this.settingsStore,
    this.directToGoogle = false,
    this.autofocusSearch,
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

  /// Backs the first-launch AI-disclosure banner (D16, issue #167). The
  /// banner reads `disclosureSeen` and either persists an acknowledgement
  /// or turns AI off, then hides itself. Route-local, matching every
  /// other service on this screen — `SettingsController` is not
  /// provided here.
  final SettingsStore settingsStore;

  /// Whether AI analysis sends dish text straight to Google from this
  /// device (iOS and Android, D17), so the disclosure banner says so
  /// rather than naming KetoClub's server (web, D12).
  final bool directToGoogle;

  /// Whether the search field takes focus as soon as the screen opens
  /// (issue #264). Null, the default, means the web build on a desktop
  /// platform: search is the main path in a browser, where location is
  /// often unavailable, while a phone, native or in a mobile browser, must
  /// not have its keyboard pop up unasked. A test passes an explicit value
  /// to exercise either branch without `kIsWeb`.
  final bool? autofocusSearch;

  @override
  State<VenueSearchScreen> createState() => _VenueSearchScreenState();
}

class _VenueSearchScreenState extends State<VenueSearchScreen> {
  final TextEditingController _field = TextEditingController();
  final FocusNode _fieldFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    // The controller outlives this screen (issue #233), so a return to the
    // Explore tab puts back what was typed when the user left it.
    _field.text = context.read<VenueSearchController>().input;
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

  /// Whether the search field autofocuses: [VenueSearchScreen.autofocusSearch]
  /// when given, else web on a desktop platform (issue #264).
  bool get _autofocusSearch =>
      widget.autofocusSearch ??
      (kIsWeb &&
          defaultTargetPlatform != TargetPlatform.android &&
          defaultTargetPlatform != TargetPlatform.iOS &&
          defaultTargetPlatform != TargetPlatform.fuchsia);

  /// The UI language code every search is made in.
  String get _language => Localizations.localeOf(context).languageCode;

  /// Opens [ref]'s menu route. [name], when the screen already knows the
  /// venue's display name (a venue card), rides along as the route's
  /// arguments so the menu header can show it: no documented menu payload
  /// names the venue, so without it the header falls back to the slug.
  void _openVenue(VenueRef ref, {String? name}) {
    Navigator.pushNamed(context, venueRoutePath(ref), arguments: name);
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
  /// `servicesOff: true`. Nothing is shown when the page opens, whether
  /// the user then grants access or backs out again; when it could not be
  /// opened at all — always the case in a browser, which has no settings
  /// page to deep-link to — a snack bar says where to go instead, so the
  /// tap is never silently a no-op (found by the visual audit).
  Future<void> _openSettings({required bool servicesOff}) async {
    final opened = await widget.locationService.openSettings(
      servicesOff: servicesOff,
    );
    if (opened || !mounted) return;
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(l10n.discoveryOpenSettingsUnavailable)),
    );
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
      body: ContentWidth(
        maxWidth: discoveryMaxWidth,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsetsDirectional.fromSTEB(20, 16, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OfflineBanner(connectivity: widget.connectivity),
                ConsentDisclosureBanner(
                  settingsStore: widget.settingsStore,
                  directToGoogle: widget.directToGoogle,
                ),
                _header(context, l10n, controller),
                const SizedBox(height: 12),
                _logoMark(),
                const SizedBox(height: 8),
                // The artboard's 34px serif heading.
                Text(
                  l10n.discoveryTitle,
                  style: textTheme.displaySmall?.copyWith(
                    fontSize: 34,
                    height: 1.08,
                  ),
                ),
                if (lastVenue != null) ...[
                  const SizedBox(height: 16),
                  _continueRow(context, l10n, lastVenue),
                ],
                const SizedBox(height: 20),
                TextField(
                  controller: _field,
                  focusNode: _fieldFocus,
                  autofocus: _autofocusSearch,
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
                    suffixIcon: controller.isExplicitLink && resolved != null
                        ? IconButton(
                            icon: const Icon(Icons.arrow_forward),
                            tooltip: l10n.venueSearchOpenLink,
                            onPressed: () => _openVenue(resolved),
                          )
                        : null,
                  ),
                ),
                // Found before a menu is open (issue #257); hidden while a
                // locate or search is loading so it never sits between the
                // field and the skeletons.
                if (controller.phase == DiscoveryPhase.idle) ...[
                  const SizedBox(height: 12),
                  _drinksGuideCard(context, l10n),
                ],
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
      ),
    );
  }

  /// A card under the search field linking to the offline drinks guide
  /// (`/drinks`, issues #216, #257).
  Widget _drinksGuideCard(BuildContext context, AppLocalizations l10n) {
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: const Icon(Icons.local_bar),
        title: Text(l10n.discoveryDrinksGuideCard),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.pushNamed(context, drinksRoutePath),
      ),
    );
  }

  /// The header: "Looking around {place}" with the location button at its
  /// end once a position exists; before one, an invitation to tap instead
  /// of a "Location not set" that reads as an error (issue #228).
  ///
  /// The page carries one location action at a time. While the body shows
  /// a denied or unavailable card, that card owns the retry (see
  /// [_bodyOwnsLocate]), so the header steps aside rather than repeat it.
  Widget _header(
    BuildContext context,
    AppLocalizations l10n,
    VenueSearchController controller,
  ) {
    final textTheme = Theme.of(context).textTheme;
    final locating = controller.phase == DiscoveryPhase.locating;
    final invited = controller.position == null;
    if (invited && _bodyOwnsLocate(controller)) return const SizedBox.shrink();
    final button = IconButton.filled(
      tooltip: l10n.discoveryUseLocation,
      icon: const Icon(Icons.my_location),
      onPressed: locating ? null : _locate,
    );
    if (invited) {
      // The words are a second target for the same tap, hidden from
      // assistive technology so the button is the one named action.
      return Row(
        children: [
          Expanded(
            child: ExcludeSemantics(
              child: InkWell(
                onTap: locating ? null : _locate,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    l10n.discoveryLocationInvite,
                    style: textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ),
          button,
        ],
      );
    }
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
        button,
      ],
    );
  }

  /// Whether [_body] is showing a denied or unavailable card, which
  /// carries its own retry or settings action.
  bool _bodyOwnsLocate(VenueSearchController controller) {
    if (controller.phase != DiscoveryPhase.idle ||
        controller.failure != null ||
        controller.hasSearched) {
      return false;
    }
    final outcome = controller.locationOutcome;
    return outcome is LocationDenied || outcome is LocationUnavailable;
  }

  /// The header's place once a position exists: the nearest result's
  /// address, or "Your location" without one.
  String _place(AppLocalizations l10n, VenueSearchController controller) {
    for (final venue in controller.results) {
      final address = venue.address;
      if (address != null && address.trim().isNotEmpty) return address;
    }
    return l10n.discoveryAroundYou;
  }

  /// The chip row: *Keto 8+* (always there, disabled with a tooltip until a
  /// card has numbers, D13), *Open now* and the one most common cuisine,
  /// when there is one. The chips combine (issue #231); "Nearby" is the
  /// default order, so it is not one. A horizontally scrollable [Row], as
  /// `CategoryChips` is.
  Widget _chips(AppLocalizations l10n, VenueSearchController controller) {
    final cuisine = controller.topCuisine;
    final active = controller.activeChips;
    final chips = <(DiscoveryChip, String, bool)>[
      (
        DiscoveryChip.ketoEightPlus,
        l10n.discoveryChipKetoEightPlus,
        controller.hasAnyNumbers,
      ),
      (DiscoveryChip.openNow, l10n.discoveryChipOpenNow, true),
      if (cuisine != null)
        (DiscoveryChip.cuisine, VenueCard.cuisineLabel(cuisine), true),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (chip, label, enabled) in chips)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: _chipWithHint(
                l10n,
                enabled: enabled,
                chip: FilterChip(
                  label: Text(label),
                  selected: enabled && active.contains(chip),
                  onSelected: enabled
                      ? (_) => controller.toggleChip(chip)
                      : null,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// [chip] as it is when [enabled]; otherwise wrapped in the tooltip that
  /// says why *Keto 8+* cannot be used yet (the only chip ever disabled).
  Widget _chipWithHint(
    AppLocalizations l10n, {
    required bool enabled,
    required Widget chip,
  }) {
    if (enabled) return chip;
    return Tooltip(message: l10n.discoveryChipKetoEightPlusHint, child: chip);
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
        if (controller.isEstimating || controller.hasVisibleToEstimate) ...[
          _estimateRow(context, l10n, controller),
          const SizedBox(height: 16),
        ],
        VenueGrid(
          itemCount: visible.length,
          itemBuilder: (context, i, photoAspectRatio) => VenueCard(
            venue: visible[i],
            numbers: controller.cardNumbers(visible[i]),
            distanceKm: controller.distanceKmTo(visible[i]),
            photoAspectRatio: photoAspectRatio,
            onTap: () => _openVenue(visible[i].ref, name: visible[i].name),
          ),
        ),
      ],
    );
  }

  /// The app's only branding (issue #232): the launcher icon at 28px, read
  /// as [appName] by a screen reader. Decoded at four times its size, not at
  /// the asset's 1024px.
  Widget _logoMark() {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: Image.asset(
          _logoAsset,
          width: _logoSize,
          height: _logoSize,
          cacheWidth: (_logoSize * 4).round(),
          semanticLabel: appName,
        ),
      ),
    );
  }

  /// The quick-score row (issue #42, D13, D21): the "Quick score the
  /// rest" action for the cards past the automatic run's cap, and the line
  /// saying what the quick score is — rules on this device, food only, not
  /// the AI. While any run is in progress, automatic or tapped, the button
  /// is disabled and reads "Estimating {done} of {total}…"; a static icon
  /// rather than a spinner, so nothing animates forever.
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
            onPressed: () => unawaited(_openSettings(servicesOff: false)),
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
            onPressed: () => unawaited(_openSettings(servicesOff: true)),
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
  /// reader hears [label] once, not three times. Laid out in the cards'
  /// own [VenueGrid] (issue #222), so a wide window shows a row of them.
  Widget _skeletons(String label) {
    return Semantics(
      liveRegion: true,
      label: label,
      child: VenueGrid(
        itemCount: 3,
        itemBuilder: (context, i, photoAspectRatio) =>
            VenueCardSkeleton(photoAspectRatio: photoAspectRatio),
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
    // A pasted menu's id is a hash, not something to show a person.
    final name =
        context.read<VenueSearchController>().lastVenueName ??
        (lastVenue.source == MenuSource.scan
            ? l10n.sourceScanned
            : lastVenue.platformId);
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: const Icon(Icons.history),
        title: Text(l10n.venueSearchContinueWith(name)),
        onTap: () => _openVenue(lastVenue, name: name),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/classifier/menu_classifier.dart';
import 'package:ketoclub/services/location/location_service.dart';
import 'package:ketoclub/services/menu/menu_repository.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/services/storage/visit_history_store.dart';
import 'package:ketoclub/services/venue/venue_ref_resolver.dart';
import 'package:ketoclub/services/venue/venue_search_service.dart';
import 'package:ketoclub/utils/constants.dart';
import 'package:ketoclub/utils/geo.dart';
import 'package:ketoclub/utils/venue_route.dart';
import 'package:ketoclub/utils/verdict_counts.dart';

/// Which step of finding venues [VenueSearchController] is in
/// (`phase2_discovery_research.md` §6), so the Discovery screen can say
/// what it is waiting for.
enum DiscoveryPhase {
  /// Nothing is in flight: no call was made yet, or the last one
  /// finished.
  idle,

  /// Waiting for `LocationService.current` to answer.
  locating,

  /// Waiting for `VenueSearchService` to answer, nearby or by name.
  searching,
}

/// The Discovery screen's filter chips (`.design/Discovery.dc.html`).
/// They combine: a venue is shown when it passes every active one, and
/// with none active every result shows, nearest first — "Nearby" is the
/// default order, not a filter, so it has no chip (issue #231).
enum DiscoveryChip {
  /// Only venues whose analysis — cached, or the quick score's — scores at
  /// least [ketoEightPlusThreshold] (D13, D21). Always shown, but enabled
  /// only while [VenueSearchController.hasAnyNumbers] holds. While it is
  /// on, venues without numbers are hidden, so a run started by a chip
  /// change has nothing to score until it is turned off again.
  ketoEightPlus,

  /// Only venues the platform says are taking orders right now
  /// ([Venue.isOnline] is true).
  openNow,

  /// Only venues tagged with [VenueSearchController.topCuisine].
  cuisine,
}

/// What a venue card may show about a venue's keto-friendliness (D13):
/// the score and verdict counts of an analysis already in the device
/// cache, with the `engine` that produced it so rules-only numbers can
/// carry the "estimate" marker.
typedef VenueCardNumbers = ({
  double score,
  int green,
  int yellow,
  AnalysisEngine engine,
});

/// Screen state for the Discovery screen (architecture.md §6.5, §6.6,
/// D13; `phase2_discovery_research.md` §6; issue #40).
///
/// **The paste path is untouched.** [setInput] still records what the
/// user typed and resolves it through [VenueRefResolver] alone, and
/// [resolved]/[isInvalid] mean exactly what they did before search
/// existed. [search] adds a debounced search by name on top, which runs
/// only when the text is not a pasted link or id (see [isPaste]) — a
/// pasted link wins and never reaches the search service.
///
/// [locate] reads one position through [LocationService] and, when it
/// gets one, lists the venues around it. Anything other than a position
/// is kept in [locationOutcome] for the screen's copy, and the screen
/// degrades to search by name.
///
/// **D13, amended by D21: the quick score runs on its own, bounded.** A
/// card's numbers come from [MenuRepository.cached], read once per result
/// set, or from the quick score: the rule engine it was given as
/// `estimateClassifier` — never the router, never the language model —
/// over a menu fetched through [MenuRepository.load]. When a result list
/// arrives, or a chip change puts venues in view, the first
/// `autoEstimateLimit` visible venues without numbers are scored
/// automatically ([venueAutoEstimateLimit]); the rest wait for
/// [estimateVisible], the explicit "Quick score the rest" tap (issue
/// #42). Either run fetches at most [venueEstimateConcurrency] menus at a
/// time and each venue at most once per result set, and a new query,
/// locate, search result, clear or chip change cancels it. Nothing is
/// fetched on scroll, and putting the last nearby list back fetches
/// nothing: it was scored when it arrived.
///
/// It also reads [AppSettings.lastVenue] (issue #55) so the screen can
/// offer a "Continue with {venue}" row instead of opening it directly on
/// launch. The name shown for that row comes from the visit history first
/// (issue #312), then from the cached menu's own
/// `CachedMenuEntry.venueName` through [MenuRepository.savedMenus] when
/// one is on hand, falling back to the platform id otherwise — the same
/// fallback `SavedScreen` and `MenuScreen` already use for a venue Wolt
/// never named.
///
/// The UI language every search is made in is passed in by the caller
/// (`language:`) rather than read here: the screen already has the
/// resolved locale from `Localizations`, which is the one the user sees,
/// whether it came from Settings or from the device.
final class VenueSearchController extends ChangeNotifier {
  /// Creates a controller with an empty query, over [_settings] and
  /// [_repository] for [load] and card numbers, [locationService] for
  /// [locate] and [venueSearchService] for the searches. `debounce` is
  /// how long [search] waits after the last keystroke, defaulting to
  /// [venueSearchDebounce].
  ///
  /// `estimateClassifier` is the rule engine the quick score classifies
  /// with — `HeuristicMenuClassifier` in production, never the router —
  /// `estimateConcurrency` how many menus it fetches at once, defaulting
  /// to [venueEstimateConcurrency], and `autoEstimateLimit` how many
  /// visible venues the automatic run covers (D21), defaulting to
  /// [venueAutoEstimateLimit]; 0 turns the automatic run off.
  ///
  /// `visitHistory` defaults to [NoVisitHistoryStore], which remembers
  /// nothing (issue #307).
  new(
    this._settings,
    this._repository, {
    required LocationService locationService,
    required VenueSearchService venueSearchService,
    required MenuClassifier estimateClassifier,
    this._debounce = venueSearchDebounce,
    this._estimateConcurrency = venueEstimateConcurrency,
    this._autoEstimateLimit = venueAutoEstimateLimit,
    VisitHistoryStore visitHistory = const NoVisitHistoryStore(),
  }) : _location = locationService,
       _search = venueSearchService,
       _estimator = estimateClassifier,
       _history = visitHistory;

  final SettingsStore _settings;
  final MenuRepository _repository;
  final LocationService _location;
  final VenueSearchService _search;
  final MenuClassifier _estimator;
  final Duration _debounce;
  final int _estimateConcurrency;
  final int _autoEstimateLimit;

  /// The menus opened on this device (issue #307): the Continue row's
  /// name and city are read from it first (issue #312).
  final VisitHistoryStore _history;

  String _input = '';
  VenueRef? _resolved;
  VenueRef? _lastVenue;
  String? _lastVenueName;
  VenueOpenHint? _lastVenueHint;

  DiscoveryPhase _phase = DiscoveryPhase.idle;
  LocationResult? _locationOutcome;
  ({double latitude, double longitude})? _position;
  List<Venue> _results = const <Venue>[];
  List<Venue>? _nearbyResults;
  Map<VenueRef, VenueCardNumbers> _nearbyNumbers =
      const <VenueRef, VenueCardNumbers>{};
  bool _hasSearched = false;
  VenueSearchFailureReason? _failure;
  final Set<DiscoveryChip> _activeChips = <DiscoveryChip>{};
  Map<VenueRef, VenueCardNumbers> _numbers =
      const <VenueRef, VenueCardNumbers>{};
  // Venues a quick-score run has started fetching in the current result
  // set, so each is fetched at most once per list (D21); mirrored for the
  // remembered nearby list as [_nearbyNumbers] mirrors [_numbers].
  Set<VenueRef> _attempted = <VenueRef>{};
  Set<VenueRef> _nearbyAttempted = <VenueRef>{};
  Future<VenueSearchResult> Function()? _lastRequest;
  bool _lastRequestWasNearby = false;
  Timer? _debounceTimer;
  int _generation = 0;
  int _estimateRun = 0;
  int _estimateTotal = 0;
  int _estimateDone = 0;
  bool _disposed = false;

  /// What the user has typed or pasted.
  String get input => _input;

  /// The reference [input] resolves to, or null when it does not resolve.
  VenueRef? get resolved => _resolved;

  /// True when [input] is non-empty but does not resolve to anything
  /// readable.
  ///
  /// Empty input is deliberately not invalid: it is nothing typed yet, and
  /// flagging an error before the user has typed anything would be wrong.
  bool get isInvalid => _input.isNotEmpty && _resolved == null;

  /// Whether [input] is a pasted link or platform id rather than a name
  /// to search for: it holds a `/` (any URL, readable or not) or is all
  /// digits (a 10bis id).
  ///
  /// A bare word is deliberately *not* a paste, even though
  /// [VenueRefResolver] also reads it as a Wolt slug: most restaurant
  /// names are one word, and treating every one as a slug would mean
  /// search never runs. The slug reading stays available through
  /// [resolved], exactly as before.
  bool get isPaste => _isPaste(_input);

  /// Whether [input] is a link or id the screen can open: a pasted
  /// [isPaste] that also [resolved] to a venue (see
  /// [VenueRefResolver.isExplicitLink]). A bare word, hyphenated or not,
  /// is never one; the screen shows its "open link" action only while
  /// this is true (issue #229).
  bool get isExplicitLink => VenueRefResolver.isExplicitLink(_input);

  /// The most recently opened venue, from [AppSettings.lastVenue], once
  /// [load] has completed; null before that, and null when nothing has
  /// ever been opened (issue #55).
  VenueRef? get lastVenue => _lastVenue;

  /// The name to show for [lastVenue] in the "Continue with…" row: the
  /// name the visit history holds for it, else the cached menu's own venue
  /// name when one is saved for it, else its website's host, else its
  /// platform id. Null exactly when [lastVenue] is null.
  String? get lastVenueName => _lastVenueName;

  /// What is known about [lastVenue] to pass to its menu route (issue
  /// #312): the name and city its visit-history entry holds, else the
  /// cached menu's own venue name. Never a fallback: unlike
  /// [lastVenueName], a hint carries no platform id or host, so the menu
  /// screen never records one as the venue's name. Null exactly when
  /// [lastVenue] is null.
  VenueOpenHint? get lastVenueHint => _lastVenueHint;

  /// Which step of finding venues is in progress.
  DiscoveryPhase get phase => _phase;

  /// The answer of the last [locate], or null before the first one. A
  /// [LocationDenied] or [LocationUnavailable] here is what the screen
  /// explains; a [LocationFound] means [results] are nearby ones.
  LocationResult? get locationOutcome => _locationOutcome;

  /// The position the last successful [locate] read, or null.
  ({double latitude, double longitude})? get position => _position;

  /// Every venue the last successful search found, in the order the
  /// search service gave (nearest first when it had a position).
  List<Venue> get results => _results;

  /// Whether any search has answered with a list since the last clear —
  /// what tells "nothing found" apart from "nothing asked yet".
  bool get hasSearched => _hasSearched;

  /// Why the last search failed, or null when it did not.
  VenueSearchFailureReason? get failure => _failure;

  /// The chips filtering [visibleResults], all of which a venue must pass;
  /// empty when nothing is filtered. A read-only view.
  Set<DiscoveryChip> get activeChips => Set.unmodifiable(_activeChips);

  /// The most common entry of [Venue.cuisineTags] across [results] — the
  /// one cuisine chip, so it is never a wall of chips — or null when no
  /// result has a tag. A tie goes to the tag seen first.
  String? get topCuisine {
    final counts = <String, int>{};
    for (final venue in _results) {
      for (final tag in venue.cuisineTags.toSet()) {
        counts[tag] = (counts[tag] ?? 0) + 1;
      }
    }
    String? top;
    var topCount = 0;
    for (final entry in counts.entries) {
      if (entry.value > topCount) {
        top = entry.key;
        topCount = entry.value;
      }
    }
    return top;
  }

  /// Whether at least one result has card numbers — what enables the
  /// *Keto 8+* chip, which would otherwise always filter to nothing (D13).
  bool get hasAnyNumbers => _results.any((v) => _numbers.containsKey(v.ref));

  /// [results] narrowed by every chip in [activeChips], in the same order.
  List<Venue> get visibleResults {
    if (_activeChips.isEmpty) return _results;
    final cuisine = _activeChips.contains(DiscoveryChip.cuisine)
        ? topCuisine
        : null;
    return [
      for (final venue in _results)
        if (_passes(venue, cuisine)) venue,
    ];
  }

  /// Whether some venue in [visibleResults] has no card numbers and no
  /// quick-score run has fetched it yet in this result set — the condition
  /// for offering "Quick score the rest" (issue #42, D21). A venue the run
  /// fetched and could not score is not offered again: the tap would only
  /// repeat the failure.
  bool get hasVisibleToEstimate =>
      _candidates(unattemptedOnly: true).isNotEmpty;

  /// Whether an [estimateVisible] run is in progress.
  bool get isEstimating => _estimateDone < _estimateTotal;

  /// How many venues the running estimate has finished — fetched and
  /// classified, or failed — out of [estimateTotal]; 0 when none runs.
  int get estimatedCount => isEstimating ? _estimateDone : 0;

  /// How many venues the running estimate set out to cover; 0 when none
  /// runs.
  int get estimateTotal => isEstimating ? _estimateTotal : 0;

  /// The score and counts a card for [venue] may show (D13): from the
  /// analysis already cached for it when that is a [MenuAnalysed] with at
  /// least one placed dish, else null — never a placeholder zero.
  ///
  /// Read from memory: the cache is read once per result set, when the
  /// results arrive, never per frame and never through a fetch.
  VenueCardNumbers? cardNumbers(Venue venue) => _numbers[venue.ref];

  /// The distance in kilometres from [position] to [venue], or null when
  /// either is unknown.
  double? distanceKmTo(Venue venue) {
    final here = _position;
    final lat = venue.latitude;
    final lon = venue.longitude;
    if (here == null || lat == null || lon == null) return null;
    return distanceKm(here.latitude, here.longitude, lat, lon);
  }

  /// Records [value] and re-resolves. Notifies listeners.
  ///
  /// A changed query cancels a running [estimateVisible]: the list it was
  /// estimating is about to be replaced.
  void setInput(String value) {
    if (value != _input) _cancelEstimate();
    _input = value;
    _resolved = VenueRefResolver.resolve(value);
    notifyListeners();
  }

  /// Records [query] through [setInput] and, unless it is a paste (see
  /// [isPaste]), searches by name in [language] once [query] has been
  /// left alone for the debounce duration — or at once with
  /// [immediate], for a submitted field.
  ///
  /// A blank [query] cancels any pending search and puts back the last
  /// nearby list, if there is one, without another request.
  void search(
    String query, {
    required String language,
    bool immediate = false,
  }) {
    setInput(query);
    _debounceTimer?.cancel();
    _debounceTimer = null;
    if (_isPaste(query)) {
      // A paste wins: a name search still in flight must not land over
      // it.
      _generation++;
      if (_phase != DiscoveryPhase.idle) {
        _phase = DiscoveryPhase.idle;
        _notify();
      }
      return;
    }
    if (query.trim().isEmpty) {
      _generation++;
      _showNearbyAgain();
      return;
    }
    if (immediate) {
      unawaited(_searchByName(query, language));
      return;
    }
    _debounceTimer = Timer(_debounce, () {
      _debounceTimer = null;
      unawaited(_searchByName(query, language));
    });
  }

  /// Clears the query and puts back the last nearby list, if any, with no
  /// new request. Notifies listeners.
  void clearSearch() {
    _cancelEstimate();
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _generation++;
    _input = '';
    _resolved = null;
    _showNearbyAgain();
  }

  /// Reads one position and, when there is one, lists the venues around
  /// it in [language]. Anything else is kept in [locationOutcome].
  Future<void> locate({required String language}) async {
    _cancelEstimate();
    _debounceTimer?.cancel();
    _debounceTimer = null;
    final generation = ++_generation;
    _phase = DiscoveryPhase.locating;
    _failure = null;
    _notify();

    final result = await _location.current();
    if (_isStale(generation)) return;
    _locationOutcome = result;
    switch (result) {
      case LocationFound(:final latitude, :final longitude):
        _position = (latitude: latitude, longitude: longitude);
        await _run(
          () => _search.nearby(
            latitude: latitude,
            longitude: longitude,
            language: language,
          ),
          generation: generation,
          isNearby: true,
        );
      case LocationDenied() || LocationUnavailable():
        _phase = DiscoveryPhase.idle;
        _notify();
    }
  }

  /// Repeats the last search, nearby or by name. A no-op before any.
  Future<void> retry() async {
    final request = _lastRequest;
    if (request == null) return;
    await _run(
      request,
      generation: ++_generation,
      isNearby: _lastRequestWasNearby,
    );
  }

  /// Turns [chip] on, or off when it is already on, leaving the other
  /// chips as they are, so the chips combine. Notifies listeners.
  ///
  /// A running quick score is cancelled: it was estimating the list the
  /// chips no longer show. A new automatic run then covers what the chips
  /// now show (D21), fetching only venues no run has fetched in this
  /// result set, so toggling back and forth never fetches a menu twice.
  void toggleChip(DiscoveryChip chip) {
    _cancelEstimate();
    if (!_activeChips.remove(chip)) _activeChips.add(chip);
    _notify();
    unawaited(_autoEstimate());
  }

  /// Reads [AppSettings.lastVenue] and, when set, the name to show for it
  /// (see the class doc). Notifies listeners once.
  ///
  /// Safe to call on every return to the Explore tab, which is when the
  /// screen calls it now that this controller lives as long as the app
  /// (issue #233): it touches only the "Continue with…" row, never the
  /// query, the results or the chip, and starts no search.
  Future<void> load() async {
    final lastVenue = (await _settings.read()).lastVenue;
    _lastVenue = lastVenue;
    final known = lastVenue == null ? null : await _knownFor(lastVenue);
    _lastVenueHint = known;
    _lastVenueName = lastVenue == null
        ? null
        : known?.name ??
              VenueRefResolver.websiteHost(lastVenue) ??
              lastVenue.platformId;
    _notify();
  }

  /// "Quick score the rest" (issue #42, D13, D21): fetches the menu of
  /// every venue in [visibleResults] that has no card numbers yet — the
  /// ones past the automatic run's cap, and any the run could not score —
  /// at most `estimateConcurrency` at a time, classifies each with the
  /// rule engine alone, saves the analysis beside its menu exactly as
  /// `MenuController` does, and shows the numbers as each one lands,
  /// marked as estimates by their [RulesEngine].
  ///
  /// Only ever called from the user's tap. A no-op while a search is in
  /// flight, while a run already goes, or when every visible card already
  /// has numbers. A venue whose menu cannot be read or classified is
  /// counted as done and left without numbers; it does not stop the
  /// others. A new query, locate, search result, clear or chip change
  /// cancels the run: no further menu is fetched, and a result still in
  /// flight is dropped rather than shown against a list it no longer
  /// belongs to.
  Future<void> estimateVisible() =>
      _runEstimate(_candidates(unattemptedOnly: false));

  /// The automatic quick score (D21): the first `autoEstimateLimit`
  /// venues in [visibleResults] that have no numbers and that no run has
  /// fetched yet in this result set. Started when a result list lands and
  /// after a chip change; a no-op under the same conditions as
  /// [estimateVisible], and when the limit is 0.
  Future<void> _autoEstimate() {
    if (_autoEstimateLimit <= 0) return Future<void>.value();
    return _runEstimate(
      _candidates(unattemptedOnly: true).take(_autoEstimateLimit).toList(),
    );
  }

  /// The venues a run may fetch: visible, without numbers, each once, and
  /// with [unattemptedOnly] not fetched by an earlier run in this result
  /// set.
  List<VenueRef> _candidates({required bool unattemptedOnly}) {
    final seen = <VenueRef>{};
    return <VenueRef>[
      for (final venue in visibleResults)
        if (!_numbers.containsKey(venue.ref) &&
            !(unattemptedOnly && _attempted.contains(venue.ref)) &&
            seen.add(venue.ref))
          venue.ref,
    ];
  }

  /// Runs one quick-score run over [pending]: the shared body of
  /// [estimateVisible] and [_autoEstimate].
  Future<void> _runEstimate(List<VenueRef> pending) async {
    if (_phase != DiscoveryPhase.idle || isEstimating) return;
    if (pending.isEmpty) return;

    final run = ++_estimateRun;
    _estimateTotal = pending.length;
    _estimateDone = 0;
    _notify();

    final settings = await _settings.read();
    if (_isEstimateStale(run)) return;
    // What shapes a verdict (issues #56, #57), as `MenuController` passes
    // it; consent stays at its default, since the rule engine never sends
    // anything anywhere.
    final options = ClassificationOptions(
      netCarbLimitGrams: settings.netCarbLimitGrams,
      dietaryConstraints: ClassificationOptions.dietaryConstraintsFor(
        seedOilFree: settings.seedOilFree,
        dairyFree: settings.dairyFree,
        carnivoreOnly: settings.carnivoreOnly,
      ),
    );

    // A small worker pool: each worker takes the next venue only once its
    // previous one is done, so no more than the bound are ever in flight,
    // and a cancelled run stops taking new ones at once.
    var next = 0;
    Future<void> worker() async {
      while (!_isEstimateStale(run) && next < pending.length) {
        final ref = pending[next++];
        await _estimateOne(ref, options, run);
        if (_isEstimateStale(run)) return;
        _estimateDone++;
        _notify();
      }
    }

    final workers = _estimateConcurrency < pending.length
        ? _estimateConcurrency
        : pending.length;
    await Future.wait([for (var i = 0; i < workers; i++) worker()]);
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelEstimate();
    _debounceTimer?.cancel();
    super.dispose();
  }

  Future<void> _searchByName(String query, String language) {
    final here = _position;
    return _run(
      () => _search.byName(
        query,
        language: language,
        latitude: here?.latitude,
        longitude: here?.longitude,
      ),
      generation: ++_generation,
      isNearby: false,
    );
  }

  /// Runs [request] as the current search: marks
  /// [DiscoveryPhase.searching], then takes its answer — and reads the
  /// card numbers for it — unless a newer search or a clear has started
  /// meanwhile.
  Future<void> _run(
    Future<VenueSearchResult> Function() request, {
    required int generation,
    required bool isNearby,
  }) async {
    _cancelEstimate();
    _lastRequest = request;
    _lastRequestWasNearby = isNearby;
    _phase = DiscoveryPhase.searching;
    _failure = null;
    _notify();

    final result = await request();
    if (_isStale(generation)) return;
    switch (result) {
      case VenuesFound(:final venues):
        final numbers = await _readNumbers(venues);
        if (_isStale(generation)) return;
        _results = venues;
        _numbers = numbers;
        _attempted = <VenueRef>{};
        _hasSearched = true;
        _activeChips.clear();
        if (isNearby) {
          _nearbyResults = venues;
          _nearbyNumbers = numbers;
          _nearbyAttempted = <VenueRef>{};
        }
      case VenueSearchFailed(:final reason):
        _failure = reason;
        _results = const <Venue>[];
        _numbers = const <VenueRef, VenueCardNumbers>{};
        _attempted = <VenueRef>{};
        _hasSearched = false;
    }
    _phase = DiscoveryPhase.idle;
    _notify();
    // A new list scores its first cards on its own (D21); a failed search
    // has no cards, and the guard inside makes this a no-op.
    if (result is VenuesFound) unawaited(_autoEstimate());
  }

  /// The card numbers for [venues] as a list arrives, read from the
  /// device cache only (D13) — [MenuRepository.cached], never
  /// [MenuRepository.load]; the quick score that follows (D21) is what
  /// fetches.
  Future<Map<VenueRef, VenueCardNumbers>> _readNumbers(
    List<Venue> venues,
  ) async {
    final entries = await Future.wait(
      venues.map((venue) async {
        final cached = await _repository.cached(venue.ref);
        if (cached == null) return null;
        final numbers = _numbersFrom(cached.menu, cached.analysis);
        if (numbers == null) return null;
        return MapEntry<VenueRef, VenueCardNumbers>(venue.ref, numbers);
      }),
    );
    return <VenueRef, VenueCardNumbers>{
      for (final entry in entries)
        if (entry != null) entry.key: entry.value,
    };
  }

  /// The card numbers [analysis] supports over [menu]: its food-only
  /// counts and score ([VerdictCounts.of], D21) when it is a
  /// [MenuAnalysed] that placed at least one food dish, else null.
  static VenueCardNumbers? _numbersFrom(Menu menu, MenuAnalysis? analysis) {
    if (analysis is! MenuAnalysed) return null;
    final counts = VerdictCounts.of(menu, analysis);
    final score = counts.score;
    if (score == null) return null;
    return (
      score: score,
      green: counts.green,
      yellow: counts.yellow,
      engine: analysis.engine,
    );
  }

  /// One venue of a quick-score run: fetch, classify with the rule engine,
  /// save beside the menu, and show — each step skipped once [run] is
  /// cancelled, so a late answer is dropped. The venue is marked attempted
  /// before the fetch, so a cancelled or failed one is not fetched again
  /// by the automatic run in this result set.
  Future<void> _estimateOne(
    VenueRef ref,
    ClassificationOptions options,
    int run,
  ) async {
    _attempted = <VenueRef>{..._attempted, ref};
    if (_nearbyResults?.any((venue) => venue.ref == ref) ?? false) {
      _nearbyAttempted = <VenueRef>{..._nearbyAttempted, ref};
    }
    final fetched = await _repository.load(ref);
    if (_isEstimateStale(run)) return;
    if (fetched is! MenuFetched) return;
    final analysis = await _estimator.classify(fetched.menu, options: options);
    if (_isEstimateStale(run)) return;
    if (analysis is! MenuAnalysed) return;
    await _repository.saveAnalysis(ref, analysis);
    if (_isEstimateStale(run)) return;
    final numbers = _numbersFrom(fetched.menu, analysis);
    if (numbers == null) return;
    _numbers = <VenueRef, VenueCardNumbers>{..._numbers, ref: numbers};
    // The same numbers stand when a cleared search puts the nearby list
    // back.
    if (_nearbyResults?.any((venue) => venue.ref == ref) ?? false) {
      _nearbyNumbers = <VenueRef, VenueCardNumbers>{
        ..._nearbyNumbers,
        ref: numbers,
      };
    }
  }

  /// Stops a running quick score, automatic or tapped: no further menu is
  /// fetched and any answer still in flight is dropped. Does not notify:
  /// every caller notifies for its own change straight afterwards.
  void _cancelEstimate() {
    _estimateRun++;
    _estimateTotal = 0;
    _estimateDone = 0;
  }

  bool _isEstimateStale(int run) => _disposed || run != _estimateRun;

  /// Whether [venue] passes every active chip; [cuisine] is
  /// [topCuisine] when that chip is on, and a null one filters nothing.
  bool _passes(Venue venue, String? cuisine) {
    for (final chip in _activeChips) {
      final passes = switch (chip) {
        DiscoveryChip.ketoEightPlus =>
          (_numbers[venue.ref]?.score ?? -1) >= ketoEightPlusThreshold,
        DiscoveryChip.openNow => venue.isOnline ?? false,
        DiscoveryChip.cuisine =>
          cuisine == null || venue.cuisineTags.contains(cuisine),
      };
      if (!passes) return false;
    }
    return true;
  }

  /// Puts the last nearby list back, or the untouched idle state when
  /// there is none, clearing any failure. Notifies listeners.
  void _showNearbyAgain() {
    final nearby = _nearbyResults;
    _phase = DiscoveryPhase.idle;
    _failure = null;
    _activeChips.clear();
    if (nearby == null) {
      _results = const <Venue>[];
      _numbers = const <VenueRef, VenueCardNumbers>{};
      _attempted = <VenueRef>{};
      _hasSearched = false;
      _notify();
      return;
    }
    _results = nearby;
    _numbers = _nearbyNumbers;
    // Its attempted set comes back with it, so no venue the nearby run
    // already fetched is fetched again (D21); no automatic run starts.
    _attempted = <VenueRef>{..._nearbyAttempted};
    _hasSearched = true;
    _notify();
  }

  bool _isStale(int generation) => _disposed || generation != _generation;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  static bool _isPaste(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return false;
    return trimmed.contains('/') || _digitsOnly.hasMatch(trimmed);
  }

  /// What is known about [ref] (issue #312): the name and city its
  /// visit-history entry holds, with the cached menu's
  /// `CachedMenuEntry.venueName` standing in for a name the history does
  /// not hold. Either field is null when nothing names it; [load] falls
  /// back to the website's host (D19), else [VenueRef.platformId], for
  /// the name it shows.
  Future<VenueOpenHint> _knownFor(VenueRef ref) async {
    final visit = await _history.read(ref);
    final city = visit?.city;
    final remembered = visit?.name;
    if (remembered != null) {
      return VenueOpenHint(name: remembered, city: city);
    }
    final saved = await _repository.savedMenus();
    for (final entry in saved) {
      if (entry.ref == ref) {
        return VenueOpenHint(name: entry.venueName, city: city);
      }
    }
    return VenueOpenHint(city: city);
  }
}

/// Bare tokens made only of ASCII digits: a pasted 10bis id, the same
/// test [VenueRefResolver] applies.
final RegExp _digitsOnly = RegExp(r'^[0-9]+$');

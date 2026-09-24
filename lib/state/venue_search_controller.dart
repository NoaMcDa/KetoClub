import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/classifier/menu_classifier.dart';
import 'package:ketoclub/services/location/location_service.dart';
import 'package:ketoclub/services/menu/menu_repository.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/services/venue/venue_ref_resolver.dart';
import 'package:ketoclub/services/venue/venue_search_service.dart';
import 'package:ketoclub/utils/constants.dart';
import 'package:ketoclub/utils/geo.dart';
import 'package:ketoclub/utils/keto_score.dart';

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

/// The Discovery screen's filter chips (`.design/Discovery.dc.html`):
/// one is active at a time, and [nearby] is the unfiltered default.
enum DiscoveryChip {
  /// Every result, nearest first — the default and "no filter".
  nearby,

  /// Only venues whose cached analysis scores at least
  /// [ketoEightPlusThreshold] (D13). Offered only while
  /// [VenueSearchController.hasAnyNumbers] holds.
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
/// **D13: no menu fetch unless the user asks.** A card's numbers come
/// from [MenuRepository.cached] alone, read once per result set in
/// [cardNumbers]. The one exception is [estimateVisible], the explicit
/// "Estimate this list" action (issue #42): only it calls
/// [MenuRepository.load], at most [venueEstimateConcurrency] at a time,
/// and only it classifies — with the rule engine it was given as
/// `estimateClassifier`, never the router and never the language model.
/// Nothing on load, locate, search, scroll or a chip change fetches a
/// menu; each of those instead cancels an estimate still running.
///
/// It also reads [AppSettings.lastVenue] (issue #55) so the screen can
/// offer a "Continue with {venue}" row instead of opening it directly on
/// launch. The name shown for that row comes from the cached menu's own
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
  /// `estimateClassifier` is the rule engine [estimateVisible] classifies
  /// with — `HeuristicMenuClassifier` in production, never the router —
  /// and `estimateConcurrency` how many menus it fetches at once,
  /// defaulting to [venueEstimateConcurrency].
  new(
    this._settings,
    this._repository, {
    required LocationService locationService,
    required VenueSearchService venueSearchService,
    required MenuClassifier estimateClassifier,
    this._debounce = venueSearchDebounce,
    this._estimateConcurrency = venueEstimateConcurrency,
  }) : _location = locationService,
       _search = venueSearchService,
       _estimator = estimateClassifier;

  final SettingsStore _settings;
  final MenuRepository _repository;
  final LocationService _location;
  final VenueSearchService _search;
  final MenuClassifier _estimator;
  final Duration _debounce;
  final int _estimateConcurrency;

  String _input = '';
  VenueRef? _resolved;
  VenueRef? _lastVenue;
  String? _lastVenueName;

  DiscoveryPhase _phase = DiscoveryPhase.idle;
  LocationResult? _locationOutcome;
  ({double latitude, double longitude})? _position;
  List<Venue> _results = const <Venue>[];
  List<Venue>? _nearbyResults;
  Map<VenueRef, VenueCardNumbers> _nearbyNumbers =
      const <VenueRef, VenueCardNumbers>{};
  bool _hasSearched = false;
  VenueSearchFailureReason? _failure;
  DiscoveryChip _activeChip = DiscoveryChip.nearby;
  Map<VenueRef, VenueCardNumbers> _numbers =
      const <VenueRef, VenueCardNumbers>{};
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
  /// [resolved] and the screen's open button, exactly as before.
  bool get isPaste => _isPaste(_input);

  /// The most recently opened venue, from [AppSettings.lastVenue], once
  /// [load] has completed; null before that, and null when nothing has
  /// ever been opened (issue #55).
  VenueRef? get lastVenue => _lastVenue;

  /// The name to show for [lastVenue] in the "Continue with…" row: the
  /// cached menu's own venue name when one is saved for it, or its
  /// platform id otherwise. Null exactly when [lastVenue] is null.
  String? get lastVenueName => _lastVenueName;

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

  /// The chip filtering [visibleResults].
  DiscoveryChip get activeChip => _activeChip;

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

  /// Whether at least one result has card numbers — the gate for the
  /// *Keto 8+* chip, which would otherwise always filter to nothing (D13).
  bool get hasAnyNumbers => _results.any((v) => _numbers.containsKey(v.ref));

  /// [results] narrowed by [activeChip].
  List<Venue> get visibleResults => switch (_activeChip) {
    DiscoveryChip.nearby => _results,
    DiscoveryChip.ketoEightPlus => [
      for (final venue in _results)
        if ((_numbers[venue.ref]?.score ?? -1) >= ketoEightPlusThreshold) venue,
    ],
    DiscoveryChip.openNow => [
      for (final venue in _results)
        if (venue.isOnline ?? false) venue,
    ],
    DiscoveryChip.cuisine => _byCuisine(topCuisine),
  };

  /// Whether some venue in [visibleResults] has no card numbers — the
  /// condition for offering "Estimate this list" (issue #42).
  bool get hasVisibleWithoutNumbers =>
      visibleResults.any((venue) => !_numbers.containsKey(venue.ref));

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

  /// Makes [chip] the active one, or goes back to [DiscoveryChip.nearby]
  /// when [chip] is already active — tap again to clear. Notifies
  /// listeners.
  ///
  /// A running [estimateVisible] is cancelled: it was estimating the list
  /// the chip no longer shows.
  void selectChip(DiscoveryChip chip) {
    _cancelEstimate();
    _activeChip = chip == _activeChip ? DiscoveryChip.nearby : chip;
    _notify();
  }

  /// Reads [AppSettings.lastVenue] and, when set, the name to show for it
  /// (see the class doc). Notifies listeners once.
  Future<void> load() async {
    final lastVenue = (await _settings.read()).lastVenue;
    _lastVenue = lastVenue;
    _lastVenueName = lastVenue == null ? null : await _nameFor(lastVenue);
    _notify();
  }

  /// "Estimate this list" (issue #42, D13): fetches the menu of every
  /// venue in [visibleResults] that has no card numbers yet, at most
  /// `estimateConcurrency` at a time, classifies each with the rule
  /// engine alone, saves the analysis beside its menu exactly as
  /// `MenuController` does, and shows the numbers as each one lands —
  /// marked as estimates by their [RulesEngine].
  ///
  /// Only ever called from the user's tap. A no-op while a search is in
  /// flight, while an estimate already runs, or when every visible card
  /// already has numbers. A venue whose menu cannot be read or classified
  /// is counted as done and left without numbers; it does not stop the
  /// others. A new query, locate, search result, clear or chip change
  /// cancels the run: no further menu is fetched, and a result still in
  /// flight is dropped rather than shown against a list it no longer
  /// belongs to.
  Future<void> estimateVisible() async {
    if (_phase != DiscoveryPhase.idle || isEstimating) return;
    final seen = <VenueRef>{};
    final pending = <VenueRef>[
      for (final venue in visibleResults)
        if (!_numbers.containsKey(venue.ref) && seen.add(venue.ref)) venue.ref,
    ];
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
        _hasSearched = true;
        _activeChip = DiscoveryChip.nearby;
        if (isNearby) {
          _nearbyResults = venues;
          _nearbyNumbers = numbers;
        }
      case VenueSearchFailed(:final reason):
        _failure = reason;
        _results = const <Venue>[];
        _numbers = const <VenueRef, VenueCardNumbers>{};
        _hasSearched = false;
    }
    _phase = DiscoveryPhase.idle;
    _notify();
  }

  /// The card numbers for [venues], read from the device cache only
  /// (D13) — [MenuRepository.cached], never [MenuRepository.load].
  Future<Map<VenueRef, VenueCardNumbers>> _readNumbers(
    List<Venue> venues,
  ) async {
    final entries = await Future.wait(
      venues.map((venue) async {
        final cached = await _repository.cached(venue.ref);
        final numbers = _numbersFrom(cached?.analysis);
        if (numbers == null) return null;
        return MapEntry<VenueRef, VenueCardNumbers>(venue.ref, numbers);
      }),
    );
    return <VenueRef, VenueCardNumbers>{
      for (final entry in entries)
        if (entry != null) entry.key: entry.value,
    };
  }

  /// The card numbers [analysis] supports: its counts and score when it
  /// is a [MenuAnalysed] that placed at least one dish, else null.
  static VenueCardNumbers? _numbersFrom(MenuAnalysis? analysis) {
    if (analysis is! MenuAnalysed) return null;
    final green = _count(analysis, DishVerdict.orderAsIs);
    final yellow = _count(analysis, DishVerdict.modifiable);
    final score = ketoScore(
      greenCount: green,
      yellowCount: yellow,
      redCount: _count(analysis, DishVerdict.nonKeto),
    );
    if (score == null) return null;
    return (
      score: score,
      green: green,
      yellow: yellow,
      engine: analysis.engine,
    );
  }

  /// One venue of an [estimateVisible] run: fetch, classify with the
  /// rule engine, save beside the menu, and show — each step skipped once
  /// [run] is cancelled, so a late answer is dropped.
  Future<void> _estimateOne(
    VenueRef ref,
    ClassificationOptions options,
    int run,
  ) async {
    final fetched = await _repository.load(ref);
    if (_isEstimateStale(run)) return;
    if (fetched is! MenuFetched) return;
    final analysis = await _estimator.classify(fetched.menu, options: options);
    if (_isEstimateStale(run)) return;
    if (analysis is! MenuAnalysed) return;
    await _repository.saveAnalysis(ref, analysis);
    if (_isEstimateStale(run)) return;
    final numbers = _numbersFrom(analysis);
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

  /// Stops a running [estimateVisible]: no further menu is fetched and
  /// any answer still in flight is dropped. Does not notify: every caller
  /// notifies for its own change straight afterwards.
  void _cancelEstimate() {
    _estimateRun++;
    _estimateTotal = 0;
    _estimateDone = 0;
  }

  bool _isEstimateStale(int run) => _disposed || run != _estimateRun;

  static int _count(MenuAnalysed analysis, DishVerdict verdict) =>
      analysis.dishes.where((dish) => dish.verdict == verdict).length;

  List<Venue> _byCuisine(String? cuisine) {
    if (cuisine == null) return _results;
    return [
      for (final venue in _results)
        if (venue.cuisineTags.contains(cuisine)) venue,
    ];
  }

  /// Puts the last nearby list back, or the untouched idle state when
  /// there is none, clearing any failure. Notifies listeners.
  void _showNearbyAgain() {
    final nearby = _nearbyResults;
    _phase = DiscoveryPhase.idle;
    _failure = null;
    _activeChip = DiscoveryChip.nearby;
    if (nearby == null) {
      _results = const <Venue>[];
      _numbers = const <VenueRef, VenueCardNumbers>{};
      _hasSearched = false;
      _notify();
      return;
    }
    _results = nearby;
    _numbers = _nearbyNumbers;
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

  /// The display name for [ref]: the cached menu's
  /// `CachedMenuEntry.venueName` when [ref] is saved, else
  /// [VenueRef.platformId].
  Future<String> _nameFor(VenueRef ref) async {
    final saved = await _repository.savedMenus();
    for (final entry in saved) {
      if (entry.ref == ref) return entry.venueName ?? ref.platformId;
    }
    return ref.platformId;
  }
}

/// Bare tokens made only of ASCII digits: a pasted 10bis id, the same
/// test [VenueRefResolver] applies.
final RegExp _digitsOnly = RegExp(r'^[0-9]+$');

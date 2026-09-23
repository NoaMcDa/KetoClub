import 'package:flutter/foundation.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/classifier/menu_classifier.dart';
import 'package:ketoclub/services/menu/menu_repository.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/services/storage/menu_cache.dart';
import 'package:ketoclub/services/storage/notes_store.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/utils/constants.dart';
import 'package:ketoclub/utils/keto_score.dart';
import 'package:ketoclub/utils/text_normaliser.dart';

/// Screen state for the classified menu screen (architecture.md §6.6).
///
/// Loads a venue's [Menu] through a [MenuRepository], classifies it
/// through a [MenuClassifier], and holds the two separately: a failed
/// [MenuAnalysis] still leaves [menu] populated, so the user sees what the
/// restaurant serves even when it could not be judged.
///
/// **Options change invalidates the cached analysis (issue #57).** Every
/// [open] builds [ClassificationOptions] from the user's settings — consent,
/// and the net-carb limit — and reuses the analysis cached beside the menu
/// only when that analysis answered the same question: see [open] for the
/// full rule. The comparison is [ClassificationOptions.matches] against the
/// [MenuAnalysed.options] every classifier records, so issue #56's dietary
/// toggles invalidate the same way once they reach [ClassificationOptions],
/// with no change here. This controller owns the rule, not the repository:
/// [MenuRepository.load] only decides whether the *menu* is fresh, and
/// only this controller knows the options the user holds now.
///
/// Never throws — both services behind it return sealed results — and does
/// no I/O, JSON parsing, price formatting or regex work of its own
/// (architecture.md §18.1); that is left to the services it wraps and to
/// the widgets above it.
final class MenuController extends ChangeNotifier {
  /// Creates a controller that loads menus through a [MenuRepository],
  /// classifies them through a [MenuClassifier], reads the user's default
  /// filter and AI-estimation consent from a [SettingsStore] on every
  /// [open], and reads and writes the open venue's personal dish notes
  /// through a [NotesStore] (issue #52).
  ///
  /// The four services are positional and private. Private, because a widget
  /// reaches a service only through a controller's own API (architecture.md
  /// §5) and public fields would hand it a way around this class; positional,
  /// because a private field cannot be a named initializing formal in Dart and
  /// the alternative was suppressing a lint on every field. The types are
  /// distinct, so a misordered call does not compile.
  ///
  /// No `Clock` is injected. Every timestamp this controller exposes comes
  /// from the result it was read from — [cachedAt] and [fetchedAt] from
  /// `Menu.fetchedAt`, `analysedAt` from the classifier — so a clock here
  /// would be a dependency nothing reads. Rendering "4 min ago" from
  /// [fetchedAt] is left to whoever displays it, against its own clock.
  new(this._repository, this._classifier, this._settings, this._notes);

  final MenuRepository _repository;
  final MenuClassifier _classifier;
  final SettingsStore _settings;
  final NotesStore _notes;

  bool _isLoading = false;
  Menu? _menu;
  MenuAnalysis? _analysis;
  MenuFetchFailureReason? _fetchFailure;
  int? _fetchStatusCode;
  bool _isFromCache = false;
  MenuFetchFailureReason? _staleReason;
  MenuFilter _filter = MenuFilter.all;
  VenueRef? _openRef;
  Map<String, String> _dishNotes = const <String, String>{};

  /// The venue [open] most recently loaded, or null before the first
  /// call — [refresh] has nothing to refetch until then.
  VenueRef? _ref;

  /// Whether [open] is currently loading or classifying a menu.
  bool get isLoading => _isLoading;

  /// The venue's menu, or null before the first successful fetch, or after
  /// a fetch that failed outright.
  Menu? get menu => _menu;

  /// The result of classifying [menu], or null before it has been
  /// analysed.
  ///
  /// A [MenuAnalysisFailed] here does not clear [menu]: the raw menu is
  /// still shown (architecture.md §6.6).
  MenuAnalysis? get analysis => _analysis;

  /// Why the most recent fetch failed outright, or null when it did not.
  MenuFetchFailureReason? get fetchFailure => _fetchFailure;

  /// The HTTP status code behind [fetchFailure], when there is one.
  int? get fetchStatusCode => _fetchStatusCode;

  /// Whether [menu] was served from cache instead of freshly fetched.
  bool get isFromCache => _isFromCache;

  /// Why a fresh fetch could not be had, when [isFromCache] is true and a
  /// stale menu was served instead of failing outright.
  MenuFetchFailureReason? get staleReason => _staleReason;

  /// When the displayed [menu] was fetched, when [isFromCache] is true;
  /// null for a freshly fetched menu, since there is nothing stale to
  /// date.
  DateTime? get cachedAt => _isFromCache ? _menu?.fetchedAt : null;

  /// When [menu] was fetched, whether that fetch was fresh or served from
  /// cache; null before any menu is loaded.
  ///
  /// This is the source for the persistent "Wolt · 4 min ago" line: unlike
  /// [cachedAt] — which is null on a fresh fetch, since there is nothing
  /// stale to report — that line is shown for every loaded menu, so it
  /// needs a timestamp regardless of [isFromCache]. There is deliberately
  /// no injected `Clock` on this class (see the constructor doc); "4 min
  /// ago" is computed by whoever renders this value, against its own
  /// clock, from the [Menu.fetchedAt] every menu already carries.
  DateTime? get fetchedAt => _menu?.fetchedAt;

  /// The restaurant name from [menu], when the source platform named it;
  /// null otherwise.
  ///
  /// **Null is the normal case here, not the exception.** No documented
  /// Wolt payload names the venue today (see `WoltMenuMapper`); only the
  /// checked-in fixture is synthetic. A header reading this value falls
  /// back to something else — the pasted venue reference, per
  /// [Menu.venueName]'s own doc comment — never to a placeholder guessed
  /// in this class.
  String? get venueName => _menu?.venueName;

  /// A rough "how keto-friendly is this menu" score out of 10, or null
  /// when [analysis] is not a [MenuAnalysed] — see [ketoScore] for the
  /// formula and the judgement calls behind it. Never render a fallback
  /// number in its place; a null here means "not computable", not zero.
  double? get ketoScoreOutOfTen => ketoScore(
    greenCount: greenCount,
    yellowCount: yellowCount,
    redCount: redCount,
  );

  /// How many dishes in [analysis] were classified [DishVerdict.orderAsIs]
  /// (green); 0 when there is no [MenuAnalysed] result.
  int get greenCount => _countOf(DishVerdict.orderAsIs);

  /// How many dishes in [analysis] were classified [DishVerdict.modifiable]
  /// (yellow); 0 when there is no [MenuAnalysed] result.
  int get yellowCount => _countOf(DishVerdict.modifiable);

  /// How many dishes in [analysis] were classified [DishVerdict.nonKeto]
  /// (red); 0 when there is no [MenuAnalysed] result.
  int get redCount => _countOf(DishVerdict.nonKeto);

  /// How many dish names [analysis] saw on the menu but could not place;
  /// 0 when there is no [MenuAnalysed] result. Same source as
  /// [unclassifiedNames]'s length, exposed as a count for a summary line
  /// that does not need the names themselves.
  int get unclassifiedCount {
    final currentAnalysis = _analysis;
    return currentAnalysis is MenuAnalysed
        ? currentAnalysis.unclassified.length
        : 0;
  }

  /// The total number of dishes on [menu], across every category; 0
  /// before a menu is loaded.
  ///
  /// This counts dishes on the raw menu, not verdicts, so it stays
  /// meaningful even when [analysis] failed: [greenCount] + [yellowCount]
  /// + [redCount] + [unclassifiedCount] equals this only once a
  /// [MenuAnalysed] result exists, since a failed analysis places no
  /// dish at all.
  int get totalDishCount {
    final currentMenu = _menu;
    if (currentMenu == null) return 0;
    return currentMenu.allDishes.length;
  }

  /// How many dishes in [analysis] carry [verdict]; 0 when there is no
  /// [MenuAnalysed] result.
  int _countOf(DishVerdict verdict) {
    final currentAnalysis = _analysis;
    if (currentAnalysis is! MenuAnalysed) return 0;
    return currentAnalysis.dishes
        .where((dish) => dish.verdict == verdict)
        .length;
  }

  /// The net-carb limit in grams [analysis] was produced under (issue #57),
  /// for the legend's green definition; [defaultNetCarbLimitGrams] when
  /// there is no [MenuAnalysed] result or it recorded no options.
  int get netCarbLimitGrams {
    final currentAnalysis = _analysis;
    if (currentAnalysis is! MenuAnalysed) return defaultNetCarbLimitGrams;
    return currentAnalysis.options?.netCarbLimitGrams ??
        defaultNetCarbLimitGrams;
  }

  /// Which engine produced [analysis], or null before a [MenuAnalysed]
  /// result exists.
  AnalysisEngine? get engine {
    final currentAnalysis = _analysis;
    return currentAnalysis is MenuAnalysed ? currentAnalysis.engine : null;
  }

  /// Which verdicts [visibleRows] keeps.
  MenuFilter get filter => _filter;

  /// The dishes to render, honouring [filter].
  ///
  /// [MenuFilter.greenOnly] keeps [DishVerdict.orderAsIs] dishes;
  /// [MenuFilter.yellowOnly] keeps [DishVerdict.modifiable] ones;
  /// [MenuFilter.redOnly] keeps [DishVerdict.nonKeto] ones;
  /// [MenuFilter.greenAndYellow] keeps the first two together (see its own
  /// doc: no longer offered by a control, but still honoured); and
  /// [MenuFilter.all] keeps every dish, judged or not.
  ///
  /// **Issue #29 replaced the menu screen's separate, always-shown
  /// "collapsed red group" with [MenuFilter.redOnly] as a tile like any
  /// other** — the artboard's three counters draw no distinction between
  /// verdicts here, so this getter no longer carves non-keto dishes out on
  /// its own the way an earlier version did (that version's counterpart
  /// getter, `redRows`, no longer exists). A screen that still wants every
  /// non-keto dish regardless of the active filter can total [redCount]
  /// instead.
  ///
  /// **When there is no successful analysis, every dish is returned with a
  /// null verdict, whatever the filter says.** A filter selects verdicts, and
  /// with no analysis there are none to select, so applying it would return an
  /// empty list and a failed analysis would cost the user the menu — which
  /// architecture.md §6.6 forbids. Keeping that rule here rather than in a
  /// screen means no screen has to reach around this controller to rebuild
  /// rows for itself.
  List<DishRow> get visibleRows {
    final currentMenu = _menu;
    if (currentMenu == null) return const <DishRow>[];
    if (analysis is! MenuAnalysed) return _allRows(currentMenu);
    final analysedById = _analysedById();
    final rows = <DishRow>[];
    for (final category in currentMenu.categories) {
      for (final dish in category.dishes) {
        final verdict = analysedById[dish.id];
        if (!_matchesFilter(verdict)) continue;
        rows.add(
          DishRow(dish: dish, category: category.name, analysis: verdict),
        );
      }
    }
    return rows;
  }

  /// Every dish in [menu] as an unjudged row, in category order.
  List<DishRow> _allRows(Menu menu) => <DishRow>[
    for (final category in menu.categories)
      for (final dish in category.dishes)
        DishRow(dish: dish, category: category.name),
  ];

  /// Dish names [analysis] saw on the menu but could not place, shown
  /// under their own heading regardless of [filter] (architecture.md
  /// §6.6, constraint 8 — unclassified is rendered, never dropped).
  List<String> get unclassifiedNames {
    final currentAnalysis = _analysis;
    return currentAnalysis is MenuAnalysed
        ? currentAnalysis.unclassified
        : const <String>[];
  }

  /// The user's personal note for the dish [dishId], on the currently
  /// open venue, or null when none has been written (issue #52). Local
  /// only: see [NotesStore]'s own doc comment for the privacy boundary
  /// this never crosses.
  String? noteFor(String dishId) => _dishNotes[dishId];

  /// Loads [ref]'s menu, then classifies it, notifying listeners after
  /// each step so a caller can render a spinner and then the result.
  ///
  /// A failed fetch leaves [menu] null and sets [fetchFailure] and
  /// [fetchStatusCode]; no classification is attempted. After a successful
  /// fetch, the analysis cached for [ref] is reused — spending no
  /// classifier call — only when all of these hold (issue #57):
  ///
  /// - it is a [MenuAnalysed] from the LLM engine ([LlmEngine]), and the
  ///   user still consents to AI analysis. A rules result is never reused:
  ///   re-running the heuristic is free, and whatever made the LLM
  ///   unavailable last time (no consent, offline, a timeout) may have
  ///   passed, so a fresh open deserves a fresh try;
  /// - the cached menu's dish text fingerprints the same as the fetched
  ///   menu's ([TextNormaliser.menuFingerprint]), so it describes these
  ///   dishes; and
  /// - its recorded [MenuAnalysed.options] match the options built from
  ///   the settings now ([ClassificationOptions.matches]). A changed
  ///   net-carb limit therefore re-analyses on the next open even when
  ///   the menu itself is unchanged.
  ///
  /// Otherwise the classifier runs, and a successful [MenuAnalysed] is
  /// persisted through the repository for the next open to reuse.
  /// [filter] is reset from the user's stored default on every call.
  /// Never throws.
  Future<void> open(VenueRef ref, {bool forceRefresh = false}) async {
    _ref = ref;
    _isLoading = true;
    notifyListeners();

    _openRef = ref;
    final appSettings = await _settings.read();
    _filter = appSettings.filter;
    _dishNotes = await _notes.readAll(ref);

    final fetchResult = await _repository.load(ref, forceRefresh: forceRefresh);
    switch (fetchResult) {
      case MenuFetched(
        menu: final fetchedMenu,
        :final fromCache,
        :final staleReason,
      ):
        _menu = fetchedMenu;
        _isFromCache = fromCache;
        _staleReason = staleReason;
        _fetchFailure = null;
        _fetchStatusCode = null;

        final options = _optionsFrom(appSettings);
        final reusable = _reusableAnalysis(
          await _repository.cached(ref),
          fetchedMenu,
          options,
        );
        if (reusable != null) {
          _analysis = reusable;
        } else {
          final analysis = await _classifier.classify(
            fetchedMenu,
            options: options,
          );
          _analysis = analysis;
          if (analysis is MenuAnalysed) {
            await _repository.saveAnalysis(ref, analysis);
          }
        }
      case MenuFetchFailed(:final reason, :final statusCode):
        _menu = null;
        _analysis = null;
        _isFromCache = false;
        _staleReason = null;
        _fetchFailure = reason;
        _fetchStatusCode = statusCode;
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Force-refetches the venue last passed to [open], skipping
  /// classification when the refetched menu's dish text is unchanged
  /// (architecture.md §6.4, §10 row 1).
  ///
  /// A no-op when [open] has never been called — there is nothing to
  /// refetch. Compares [TextNormaliser.menuFingerprint] of the menu shown
  /// before this call against the refetched one: equal fingerprints keep
  /// [analysis] exactly as it was (only [menu] — and so [fetchedAt] —
  /// moves forward), spending no classifier call; a changed fingerprint
  /// reclassifies and persists the new result exactly as [open] does. So
  /// does an unchanged fingerprint whose analysis was made under options
  /// other than the user's current ones — a net-carb limit changed since
  /// [open], say (issue #57).
  ///
  /// A refetch that fails outright (no adapter succeeded and nothing was
  /// cached to fall back to — the only way [MenuRepository.load] returns
  /// [MenuFetchFailed] once a menu is already showing) leaves [menu] and
  /// [analysis] untouched and surfaces the failure reason through
  /// [staleReason], the same "still shows the last good menu" contract
  /// [MenuRepository.load] itself upholds when a cached menu exists. It
  /// is far more common for that contract to be upheld one layer down:
  /// [MenuRepository.load] itself falls back to a cached menu on a
  /// failed fetch, returning [MenuFetched] with `fromCache: true` rather
  /// than [MenuFetchFailed] — that path is handled by the same branch
  /// [open] uses, below.
  Future<void> refresh() async {
    final currentRef = _ref;
    if (currentRef == null) return;
    final previousMenu = _menu;
    final previousAnalysis = _analysis;

    _isLoading = true;
    notifyListeners();

    final fetchResult = await _repository.load(currentRef, forceRefresh: true);
    switch (fetchResult) {
      case MenuFetched(
        menu: final fetchedMenu,
        :final fromCache,
        :final staleReason,
      ):
        final unchanged =
            previousMenu != null &&
            TextNormaliser.menuFingerprint(previousMenu) ==
                TextNormaliser.menuFingerprint(fetchedMenu);
        _menu = fetchedMenu;
        _isFromCache = fromCache;
        _staleReason = staleReason;
        _fetchFailure = null;
        _fetchStatusCode = null;
        final options = _optionsFrom(await _settings.read());
        if (unchanged &&
            previousAnalysis is MenuAnalysed &&
            options.matches(previousAnalysis.options)) {
          // The dish text did not change, and neither did the options
          // that decide what a verdict means (issue #57): keep the
          // analysis already on hand — only fetchedAt (read from _menu)
          // moves forward — and spend no classifier call
          // (architecture.md §6.4).
          _analysis = previousAnalysis;
        } else {
          final analysis = await _classifier.classify(
            fetchedMenu,
            options: options,
          );
          _analysis = analysis;
          if (analysis is MenuAnalysed) {
            await _repository.saveAnalysis(currentRef, analysis);
          }
        }
      case MenuFetchFailed(:final reason):
        // Nothing fresh, and nothing stale either: keep exactly what was
        // already shown, and say why a refresh could not improve on it.
        _staleReason = reason;
        _isFromCache = true;
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Re-runs classification on the already-loaded [menu], spending no
  /// new fetch (issue #68) — the retry action for an analysis failure
  /// shown above the dish list. Unlike [refresh], this never calls
  /// [MenuRepository.load]: the menu itself was not the problem, so
  /// there is nothing about it worth refetching, and a second Wolt
  /// request would cost a cache-freshness check the user never asked for.
  ///
  /// A no-op when [open] has not yet produced a [menu]. Persists a
  /// successful [MenuAnalysed] through the repository exactly as [open]
  /// does, so the next [open] can reuse it.
  Future<void> reanalyse() async {
    final currentMenu = _menu;
    final currentRef = _ref;
    if (currentMenu == null || currentRef == null) return;

    _isLoading = true;
    notifyListeners();

    final options = _optionsFrom(await _settings.read());
    final analysis = await _classifier.classify(currentMenu, options: options);
    _analysis = analysis;
    if (analysis is MenuAnalysed) {
      await _repository.saveAnalysis(currentRef, analysis);
    }

    _isLoading = false;
    notifyListeners();
  }

  /// The [ClassificationOptions] [settings] ask for: consent, and the
  /// net-carb limit (issue #57).
  static ClassificationOptions _optionsFrom(AppSettings settings) =>
      ClassificationOptions(
        estimationConsentGiven: settings.estimationConsentGiven,
        netCarbLimitGrams: settings.netCarbLimitGrams,
      );

  /// [cached]'s analysis when [open] may show it for [fetched] under
  /// [options] instead of classifying again, or null when it must
  /// classify. See [open] for the three conditions.
  static MenuAnalysed? _reusableAnalysis(
    CachedMenu? cached,
    Menu fetched,
    ClassificationOptions options,
  ) {
    if (cached == null) return null;
    final analysis = cached.analysis;
    if (analysis is! MenuAnalysed) return null;
    if (analysis.engine is! LlmEngine) return null;
    if (!options.estimationConsentGiven) return null;
    if (TextNormaliser.menuFingerprint(cached.menu) !=
        TextNormaliser.menuFingerprint(fetched)) {
      return null;
    }
    if (!options.matches(analysis.options)) return null;
    return analysis;
  }

  /// Changes [filter] and notifies listeners. Does not refetch or
  /// reclassify.
  void setFilter(MenuFilter filter) {
    _filter = filter;
    notifyListeners();
  }

  /// Saves [note] as the personal note for [dishId] on the open venue
  /// (issue #52), and notifies listeners once it is written.
  ///
  /// A blank [note] (empty once trimmed) clears the note instead of
  /// writing an empty string — the note editor's Save and Clear actions
  /// end up doing the same thing when the field was emptied by hand.
  /// A no-op, including no notify, when [open] has never been called:
  /// there is no venue to attribute the note to.
  Future<void> setNote(String dishId, String note) async {
    final ref = _openRef;
    if (ref == null) return;
    final trimmed = note.trim();
    if (trimmed.isEmpty) {
      await clearNote(dishId);
      return;
    }
    await _notes.write(ref, dishId, trimmed);
    _dishNotes = {..._dishNotes, dishId: trimmed};
    notifyListeners();
  }

  /// Removes the personal note for [dishId] on the open venue, and
  /// notifies listeners once it is removed. A no-op, including no
  /// notify, when [open] has never been called or when [dishId] carries
  /// no note.
  Future<void> clearNote(String dishId) async {
    final ref = _openRef;
    if (ref == null || !_dishNotes.containsKey(dishId)) return;
    await _notes.delete(ref, dishId);
    final updated = Map<String, String>.from(_dishNotes)..remove(dishId);
    _dishNotes = updated;
    notifyListeners();
  }

  /// Every [AnalysedDish] in [analysis], keyed by [AnalysedDish.dishId], or
  /// empty when [analysis] is not a [MenuAnalysed].
  Map<String, AnalysedDish> _analysedById() {
    final currentAnalysis = _analysis;
    if (currentAnalysis is! MenuAnalysed) {
      return const <String, AnalysedDish>{};
    }
    return {for (final dish in currentAnalysis.dishes) dish.dishId: dish};
  }

  /// Whether [verdict] belongs in [visibleRows] under the current
  /// [filter]. An exhaustive switch with no `default`: adding a
  /// [MenuFilter] value without updating this function is a compile error
  /// (architecture.md §10).
  bool _matchesFilter(AnalysedDish? verdict) => switch (_filter) {
    MenuFilter.greenOnly => verdict?.verdict == DishVerdict.orderAsIs,
    MenuFilter.greenAndYellow =>
      verdict?.verdict == DishVerdict.orderAsIs ||
          verdict?.verdict == DishVerdict.modifiable,
    MenuFilter.yellowOnly => verdict?.verdict == DishVerdict.modifiable,
    MenuFilter.redOnly => verdict?.verdict == DishVerdict.nonKeto,
    MenuFilter.all => true,
  };
}

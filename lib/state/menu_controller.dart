import 'package:flutter/foundation.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/classifier/menu_classifier.dart';
import 'package:ketoclub/services/menu/menu_repository.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/utils/keto_score.dart';

/// Screen state for the classified menu screen (architecture.md §6.6).
///
/// Loads a venue's [Menu] through a [MenuRepository], classifies it
/// through a [MenuClassifier], and holds the two separately: a failed
/// [MenuAnalysis] still leaves [menu] populated, so the user sees what the
/// restaurant serves even when it could not be judged.
///
/// Never throws — both services behind it return sealed results — and does
/// no I/O, JSON parsing, price formatting or regex work of its own
/// (architecture.md §18.1); that is left to the services it wraps and to
/// the widgets above it.
final class MenuController extends ChangeNotifier {
  /// Creates a controller that loads menus through a [MenuRepository],
  /// classifies them through a [MenuClassifier], and reads the user's default
  /// filter and AI-estimation consent from a [SettingsStore] on every [open].
  ///
  /// The three services are positional and private. Private, because a widget
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
  new(this._repository, this._classifier, this._settings);

  final MenuRepository _repository;
  final MenuClassifier _classifier;
  final SettingsStore _settings;

  bool _isLoading = false;
  Menu? _menu;
  MenuAnalysis? _analysis;
  MenuFetchFailureReason? _fetchFailure;
  int? _fetchStatusCode;
  bool _isFromCache = false;
  MenuFetchFailureReason? _staleReason;
  MenuFilter _filter = MenuFilter.greenAndYellow;

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

  /// Which engine produced [analysis], or null before a [MenuAnalysed]
  /// result exists.
  AnalysisEngine? get engine {
    final currentAnalysis = _analysis;
    return currentAnalysis is MenuAnalysed ? currentAnalysis.engine : null;
  }

  /// Which verdicts [visibleRows] keeps.
  MenuFilter get filter => _filter;

  /// Non-red dishes to render, honouring [filter].
  ///
  /// [MenuFilter.greenOnly] keeps [DishVerdict.orderAsIs] dishes;
  /// [MenuFilter.greenAndYellow] adds [DishVerdict.modifiable] ones;
  /// [MenuFilter.all] adds dishes [analysis] never placed on top of that.
  /// A dish verdict [DishVerdict.nonKeto] never appears here, under any
  /// filter — see [redRows].
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
        if (verdict?.verdict == DishVerdict.nonKeto) continue;
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

  /// The collapsed red group: every [DishVerdict.nonKeto] dish, regardless
  /// of [filter] (architecture.md §6.6, constraint 8 — red is grouped,
  /// never hidden).
  List<DishRow> get redRows {
    final currentMenu = _menu;
    if (currentMenu == null) return const <DishRow>[];
    final analysedById = _analysedById();
    final rows = <DishRow>[];
    for (final category in currentMenu.categories) {
      for (final dish in category.dishes) {
        final verdict = analysedById[dish.id];
        if (verdict?.verdict != DishVerdict.nonKeto) continue;
        rows.add(
          DishRow(dish: dish, category: category.name, analysis: verdict),
        );
      }
    }
    return rows;
  }

  /// Dish names [analysis] saw on the menu but could not place, shown
  /// under their own heading regardless of [filter] (architecture.md
  /// §6.6, constraint 8 — unclassified is rendered, never dropped).
  List<String> get unclassifiedNames {
    final currentAnalysis = _analysis;
    return currentAnalysis is MenuAnalysed
        ? currentAnalysis.unclassified
        : const <String>[];
  }

  /// Loads [ref]'s menu, then classifies it, notifying listeners after
  /// each step so a caller can render a spinner and then the result.
  ///
  /// A failed fetch leaves [menu] null and sets [fetchFailure] and
  /// [fetchStatusCode]; no classification is attempted. A successful
  /// fetch always runs the classifier, and a successful [MenuAnalysed] is
  /// persisted through the repository so a revisit costs no LLM request.
  /// [filter] is reset from the user's stored default on every call.
  /// Never throws.
  Future<void> open(VenueRef ref, {bool forceRefresh = false}) async {
    _isLoading = true;
    notifyListeners();

    final appSettings = await _settings.read();
    _filter = appSettings.filter;

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

        final options = ClassificationOptions(
          estimationConsentGiven: appSettings.estimationConsentGiven,
        );
        final analysis = await _classifier.classify(
          fetchedMenu,
          options: options,
        );
        _analysis = analysis;
        if (analysis is MenuAnalysed) {
          await _repository.saveAnalysis(ref, analysis);
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

  /// Changes [filter] and notifies listeners. Does not refetch or
  /// reclassify.
  void setFilter(MenuFilter filter) {
    _filter = filter;
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
  /// [filter].
  bool _matchesFilter(AnalysedDish? verdict) => switch (_filter) {
    MenuFilter.greenOnly => verdict?.verdict == DishVerdict.orderAsIs,
    MenuFilter.greenAndYellow =>
      verdict?.verdict == DishVerdict.orderAsIs ||
          verdict?.verdict == DishVerdict.modifiable,
    MenuFilter.all => true,
  };
}

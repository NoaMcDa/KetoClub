import 'package:flutter/foundation.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/classifier/menu_classifier.dart';
import 'package:ketoclub/services/menu/menu_repository.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/services/storage/settings_store.dart';

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
  /// from the result it was read from — [cachedAt] from `Menu.fetchedAt` and
  /// `analysedAt` from the classifier — so a clock here would be a dependency
  /// nothing reads.
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
  List<DishRow> get visibleRows {
    final currentMenu = _menu;
    if (currentMenu == null) return const <DishRow>[];
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

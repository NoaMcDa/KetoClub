import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/menu_question.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/classifier/menu_classifier.dart';
import 'package:ketoclub/services/classifier/menu_question_answerer.dart';
import 'package:ketoclub/services/classifier/menu_question_prompt.dart';
import 'package:ketoclub/services/classifier/menu_response_parser.dart';
import 'package:ketoclub/services/community/menu_store_client.dart';
import 'package:ketoclub/services/menu/menu_repository.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/services/storage/menu_cache.dart';
import 'package:ketoclub/services/storage/notes_store.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/services/storage/visit_history_store.dart';
import 'package:ketoclub/state/carb_budget_controller.dart';
import 'package:ketoclub/utils/constants.dart';
import 'package:ketoclub/utils/text_normaliser.dart';
import 'package:ketoclub/utils/venue_route.dart';
import 'package:ketoclub/utils/verdict_counts.dart';

/// The state of a user-initiated menu question (architecture.md §9.5;
/// issue #214).
///
/// Transitions: idle → loading → answered or failed; dismissed (any
/// terminal state) → idle via [MenuController.dismissQuestion].
enum QuestionState {
  /// No question has been asked, or the last one was dismissed.
  idle,

  /// A question is in flight; the sheet shows a spinner.
  loading,

  /// The model answered; the sheet shows the answer text and dish chips.
  answered,

  /// The model or transport failed; the sheet shows distinct failure copy.
  failed,
}

/// Which step of loading a menu [MenuController] is in (issue #65), so the
/// menu screen can say what it is waiting for rather than show a bare
/// spinner.
///
/// The three classifying values come from the engines themselves, never
/// from a guess in the controller: the controller enters [classifying]
/// when it calls the classifier, and moves to [classifyingLlm] or
/// [classifyingRules] only when an engine announces itself through
/// [ClassificationOptions.onEngineStarted]. A fallback after a failed AI
/// call therefore reads as [classifyingLlm] then [classifyingRules], and
/// the brief connectivity pre-check before the AI is tried stays
/// [classifying] — the controller never restates the router's rules to
/// predict which engine will run.
enum LoadPhase {
  /// Nothing is loading: no call is in flight, or the last one finished.
  idle,

  /// The menu itself is being fetched (or read from cache).
  fetching,

  /// The classifier has been called, but no engine has announced itself
  /// yet.
  classifying,

  /// The AI engine is running.
  classifyingLlm,

  /// The on-device rule engine is running — because it was the only one
  /// allowed, or because the AI call just failed and it is the fallback.
  classifyingRules;

  /// Whether this is one of the three classifying phases.
  bool get isClassifying =>
      this == classifying || this == classifyingLlm || this == classifyingRules;
}

/// Screen state for the classified menu screen (architecture.md §6.6).
///
/// Loads a venue's [Menu] through a [MenuRepository], classifies it
/// through a [MenuClassifier], and holds the two separately: a failed
/// [MenuAnalysis] still leaves [menu] populated, so the user sees what the
/// restaurant serves even when it could not be judged.
///
/// **Options change invalidates the cached analysis (issue #57).** Every
/// [open] builds [ClassificationOptions] from the user's settings —
/// consent, the net-carb limit and the dietary toggles — and reuses the
/// analysis cached beside the menu only when that analysis answered the
/// same question: see [open] for the full rule. The comparison is
/// [ClassificationOptions.matches] against the [MenuAnalysed.options] every
/// classifier records, so issue #56's dietary toggles, which reach
/// [ClassificationOptions.dietaryConstraints] through [_optionsFrom],
/// invalidate exactly as a changed limit does. This controller owns the
/// rule, not the repository: [MenuRepository.load] only decides whether
/// the *menu* is fresh, and only this controller knows the options the
/// user holds now.
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
  /// The five services are positional and private. Private, because a widget
  /// reaches a service only through a controller's own API (architecture.md
  /// §5) and public fields would hand it a way around this class; positional,
  /// because a private field cannot be a named initializing formal in Dart and
  /// the alternative was suppressing a lint on every field. The types are
  /// distinct, so a misordered call does not compile.
  ///
  /// The optional [MenuQuestionAnswerer] defaults to null: callers that never
  /// use the question feature — tests and the scan path — need not construct
  /// one. When null, [isQuestionAvailable] returns false and [askQuestion]
  /// is a no-op.
  ///
  /// The optional [VisitHistoryStore] defaults to [NoVisitHistoryStore],
  /// which remembers nothing; the app passes the device's own (issue #307).
  ///
  /// The optional [MenuStoreClient] defaults to [NoMenuStoreClient], which
  /// sends nothing; the app passes the backend's (issue #312, D24).
  ///
  /// No `Clock` is injected. Every timestamp this controller exposes comes
  /// from the result it was read from — [cachedAt] and [fetchedAt] from
  /// `Menu.fetchedAt`, `analysedAt` from the classifier — so a clock here
  /// would be a dependency nothing reads. Rendering "4 min ago" from
  /// [fetchedAt] is left to whoever displays it, against its own clock.
  new(
    this._repository,
    this._classifier,
    this._settings,
    this._notes,
    this._carbBudget, [
    this._answerer,
    this._history = const NoVisitHistoryStore(),
    this._menuStore = const NoMenuStoreClient(),
  ]) {
    _carbBudget.addListener(_onBudgetChange);
  }

  final MenuRepository _repository;
  final MenuClassifier _classifier;
  final SettingsStore _settings;
  final NotesStore _notes;
  final CarbBudgetController _carbBudget;
  final MenuQuestionAnswerer? _answerer;

  /// The menus opened on this device (issue #307): [open] reads the
  /// venue's entry for [historyName] and [historyCity], and records every
  /// successful open in it (issue #312).
  final VisitHistoryStore _history;

  /// Contributes a fetched menu to the shared menu store (issue #312,
  /// D24); see [open] for when.
  final MenuStoreClient _menuStore;

  /// The name the visit history holds for the open venue; see
  /// [historyName].
  String? _historyName;

  /// The city the visit history holds for the open venue; see
  /// [historyCity].
  String? _historyCity;

  /// The upload [open] last started, or an already-complete future when
  /// none has been; see [lastUpload].
  Future<void> _lastUpload = Future<void>.value();

  @override
  void dispose() {
    _carbBudget.removeListener(_onBudgetChange);
    super.dispose();
  }

  /// Called when the budget changes; re-filters the visible rows by
  /// notifying listeners. Never re-classifies.
  void _onBudgetChange() => notifyListeners();

  LoadPhase _phase = LoadPhase.idle;
  Menu? _menu;
  MenuAnalysis? _analysis;
  MenuFetchFailureReason? _fetchFailure;
  int? _fetchStatusCode;
  bool _isFromCache = false;
  MenuFetchFailureReason? _staleReason;
  MenuFilter _filter = MenuFilter.all;
  String _query = '';
  int? _pageFilter;
  VenueRef? _openRef;
  Map<String, String> _dishNotes = const <String, String>{};

  // Question state (architecture.md §9.5; issue #214). None of these fields
  // is ever persisted, logged, or sent to the cache — see D8.
  QuestionState _questionState = QuestionState.idle;
  MenuQuestionAnswered? _questionAnswer;
  MenuQuestionFailureReason? _questionFailure;

  /// Whether a question is currently in flight.
  bool get isQuestionLoading => _questionState == QuestionState.loading;

  /// The current question state.
  QuestionState get questionState => _questionState;

  /// The last successful answer, or null when [questionState] is not
  /// [QuestionState.answered].
  MenuQuestionAnswered? get questionAnswer => _questionAnswer;

  /// The reason the last question failed, or null when [questionState] is not
  /// [QuestionState.failed].
  MenuQuestionFailureReason? get questionFailure => _questionFailure;

  /// Whether the app-bar action that opens the question sheet is available.
  ///
  /// True only when an LLM analysis succeeded, the question answerer is
  /// wired in, and the analysis did not itself fail — mirrors the condition
  /// under which [askQuestion] can do real work.
  bool get isQuestionAvailable {
    final a = _analysis;
    return _answerer != null && a is MenuAnalysed && a.engine is LlmEngine;
  }

  /// The venue [open] most recently loaded, or null before the first
  /// call — [refresh] has nothing to refetch until then.
  VenueRef? _ref;

  /// Whether [open] or [refresh] is currently loading or classifying a
  /// menu; true exactly when [phase] is not [LoadPhase.idle].
  bool get isLoading => _phase != LoadPhase.idle;

  /// Which step of loading the menu is in progress (issue #65).
  LoadPhase get phase => _phase;

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
  /// **Null is the normal case here, not the exception.** Wolt's
  /// consumer-assortment payload does not name the venue (see
  /// `WoltMenuMapper`). A header reading this value falls back to
  /// something else — the pasted venue reference, per [Menu.venueName]'s
  /// own doc comment — never to a placeholder guessed in this class.
  String? get venueName => _menu?.venueName;

  /// The name the visit history remembers for the open venue (issue #307),
  /// for a header to fall back to when [venueName] is null.
  ///
  /// Read at the start of [open], before the menu is fetched, so a header
  /// can show it while the menu loads; refreshed once [open] has recorded
  /// the visit. Null before [open] and for a venue never named.
  String? get historyName => _historyName;

  /// The city the visit history remembers for the open venue (issue #307),
  /// read and refreshed exactly as [historyName]; null when none is known.
  String? get historyCity => _historyCity;

  /// Completes when the most recent menu upload [open] started has
  /// finished (issue #312); already complete when none has been started.
  ///
  /// The upload's result is never surfaced — the client logs its own
  /// failures — so this exists for a test to wait on, nothing else.
  Future<void> get lastUpload => _lastUpload;

  /// A rough "how keto-friendly is this menu" score out of 10, or null
  /// when [analysis] is not a [MenuAnalysed] — see `utils/keto_score.dart`
  /// for the formula and the judgement calls behind it, and
  /// [VerdictCounts] for which dishes feed it (food only, D21). Never
  /// render a fallback number in its place; a null here means "not
  /// computable", not zero.
  double? get ketoScoreOutOfTen => _counts.score;

  /// How many *food* dishes in [analysis] were classified
  /// [DishVerdict.orderAsIs] (green); 0 when there is no [MenuAnalysed]
  /// result. A drink, an extra or a notice line (D21, `dishKindOf`) is
  /// still listed under its verdict but never counted here.
  int get greenCount => _counts.green;

  /// How many food dishes in [analysis] were classified
  /// [DishVerdict.modifiable] (yellow); 0 when there is no [MenuAnalysed]
  /// result. Food only, as [greenCount].
  int get yellowCount => _counts.yellow;

  /// How many [DishVerdict.modifiable] food dishes in [analysis] were
  /// demoted from green because of a hidden-carb flag (issue #213); 0 when
  /// there is no [MenuAnalysed] result. A subset of [yellowCount].
  int get hiddenCarbYellowCount => _counts.hiddenCarbYellow;

  /// How many food dishes in [analysis] were classified
  /// [DishVerdict.nonKeto] (red); 0 when there is no [MenuAnalysed]
  /// result. Food only, as [greenCount].
  int get redCount => _counts.red;

  /// The food-only verdict counts of [analysis] over [menu]
  /// ([VerdictCounts.of], D21), computed once per (menu, analysis) pair
  /// rather than per getter: the kind of every dish is a regex pass over
  /// the whole menu, and a build reads four of these getters.
  VerdictCounts get _counts {
    final currentMenu = _menu;
    final currentAnalysis = _analysis;
    if (currentMenu == null || currentAnalysis is! MenuAnalysed) {
      return VerdictCounts.zero;
    }
    final memo = _countsMemo;
    if (memo != null &&
        identical(memo.menu, currentMenu) &&
        identical(memo.analysis, currentAnalysis)) {
      return memo.counts;
    }
    final counts = VerdictCounts.of(currentMenu, currentAnalysis);
    _countsMemo = (
      menu: currentMenu,
      analysis: currentAnalysis,
      counts: counts,
    );
    return counts;
  }

  ({Menu menu, MenuAnalysed analysis, VerdictCounts counts})? _countsMemo;

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

  /// Whether the carb budget can meaningfully filter the current analysis.
  ///
  /// True only when [analysis] is a [MenuAnalysed] produced by the LLM
  /// engine — the rule engine never sets [AnalysedDish.netCarbsEstimate],
  /// so a budget would silently pass every dish and mislead the user.
  bool get isBudgetAvailable =>
      _analysis is MenuAnalysed && engine is LlmEngine;

  /// Which verdicts [visibleRows] keeps.
  MenuFilter get filter => _filter;

  /// The user's search text over a dish's name and description (issue
  /// #51). Combines with [filter] in [visibleRows]: both must match for a
  /// dish to show. `''` (the default) matches every dish.
  String get query => _query;

  /// Which scanned page [visibleRows] keeps (issue #300): null keeps every
  /// page, [scanPageUnknown] keeps only dishes whose [Dish.page] is
  /// unknown, and any other value n keeps only dishes printed on page n.
  /// Reset to null on every [open].
  int? get pageFilter => _pageFilter;

  /// The distinct [Dish.page] values on [menu], ascending (issue #300).
  ///
  /// Empty before a menu is loaded, when no dish carries a page, and for
  /// every menu whose source is not [MenuSource.scan] — a platform menu
  /// has no pages, so no page control is ever offered for one.
  List<int> get attributedPages {
    final currentMenu = _menu;
    if (currentMenu == null) return const <int>[];
    if (currentMenu.venueRef.source != MenuSource.scan) {
      return const <int>[];
    }
    final pages = <int>{
      for (final dish in currentMenu.allDishes)
        if (dish.page case final int page) page,
    };
    return pages.toList()..sort();
  }

  /// Whether [attributedPages] is non-empty and at least one dish on
  /// [menu] has no [Dish.page] (issue #300) — when true, a page control
  /// also offers [scanPageUnknown].
  bool get hasUnattributedDishes {
    final currentMenu = _menu;
    if (currentMenu == null || attributedPages.isEmpty) return false;
    return currentMenu.allDishes.any((dish) => dish.page == null);
  }

  /// The dishes to render, honouring [filter] and, once it is non-blank,
  /// [query].
  ///
  /// [MenuFilter.greenOnly] keeps [DishVerdict.orderAsIs] dishes;
  /// [MenuFilter.yellowOnly] keeps [DishVerdict.modifiable] ones;
  /// [MenuFilter.redOnly] keeps [DishVerdict.nonKeto] ones;
  /// [MenuFilter.greenAndYellow] keeps the first two together (see its own
  /// doc: no longer offered by a control, but still honoured); and
  /// [MenuFilter.all] keeps every dish, judged or not. Independently,
  /// [query] — normalised through [TextNormaliser.normalise], so it is
  /// case- and niqqud-insensitive — must appear in the dish's normalised
  /// name or description; a blank [query] applies no such test.
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
  /// null verdict, whatever the filter says** — [query] still applies. A
  /// filter selects verdicts, and with no analysis there are none to select,
  /// so applying it would return an empty list and a failed analysis would
  /// cost the user the menu — which architecture.md §6.6 forbids. Keeping
  /// that rule here rather than in a screen means no screen has to reach
  /// around this controller to rebuild rows for itself.
  ///
  /// **Scanned pages (issue #300).** When [attributedPages] is non-empty,
  /// [pageFilter] applies last, in both cases above, and the rows are
  /// stably sorted by [Dish.page], unknown pages last, so each page's
  /// dishes sit together in their transcribed order. A one-page scan and
  /// every platform menu keep menu order exactly.
  List<DishRow> get visibleRows {
    final currentMenu = _menu;
    if (currentMenu == null) return const <DishRow>[];
    final normalisedQuery = TextNormaliser.normalise(_query);
    final List<DishRow> rows;
    if (analysis is! MenuAnalysed) {
      rows = _allRows(currentMenu)
          .where((row) => _matchesQuery(row.dish, normalisedQuery))
          .toList();
    } else {
      final analysedById = _analysedById();
      rows = <DishRow>[];
      for (final category in currentMenu.categories) {
        for (final dish in category.dishes) {
          final verdict = analysedById[dish.id];
          if (!_matchesFilter(verdict)) continue;
          if (!_matchesQuery(dish, normalisedQuery)) continue;
          if (!_matchesBudget(verdict)) continue;
          rows.add(
            DishRow(dish: dish, category: category.name, analysis: verdict),
          );
        }
      }
    }
    if (attributedPages.isEmpty) return rows;
    return _byPage(rows.where((row) => _matchesPage(row.dish)).toList());
  }

  /// Whether [dish] passes [pageFilter]: every dish when it is null, a
  /// dish with no page when it is [scanPageUnknown], and otherwise a dish
  /// printed on exactly that page. Only consulted when [attributedPages]
  /// is non-empty, so a platform menu ignores any page filter.
  bool _matchesPage(Dish dish) => switch (_pageFilter) {
    null => true,
    scanPageUnknown => dish.page == null,
    final int page => dish.page == page,
  };

  /// [rows] stably sorted by [Dish.page], unknown pages last. `List.sort`
  /// is not guaranteed stable, so the original index breaks ties.
  List<DishRow> _byPage(List<DishRow> rows) {
    final indexed = <(int, DishRow)>[
      for (var i = 0; i < rows.length; i++) (i, rows[i]),
    ];
    int pageOf(DishRow row) => row.dish.page ?? _unknownPageSortKey;
    indexed.sort((a, b) {
      final byPage = pageOf(a.$2).compareTo(pageOf(b.$2));
      return byPage != 0 ? byPage : a.$1.compareTo(b.$1);
    });
    return <DishRow>[for (final (_, row) in indexed) row];
  }

  /// The sort key a dish with no page takes in [_byPage]: after every
  /// real page.
  static const int _unknownPageSortKey = 1 << 30;

  /// The categories that still have at least one row in [visibleRows], in
  /// menu order (issue #51's category jump) — the same order
  /// [visibleRows] itself already walks categories in, so this needs no
  /// filter logic of its own beyond reading that result.
  List<String> get visibleCategories {
    final seen = <String>{};
    final ordered = <String>[];
    for (final row in visibleRows) {
      if (seen.add(row.category)) ordered.add(row.category);
    }
    return ordered;
  }

  /// Every dish in [menu] as an unjudged row, in category order.
  List<DishRow> _allRows(Menu menu) => <DishRow>[
    for (final category in menu.categories)
      for (final dish in category.dishes)
        DishRow(dish: dish, category: category.name),
  ];

  /// Whether [dish]'s name or description contains [normalisedQuery] once
  /// both are run through [TextNormaliser.normalise] — the same
  /// case-fold/niqqud-strip/whitespace-collapse pipeline the heuristic
  /// classifier and the cache fingerprint already share (issue #51). An
  /// empty [normalisedQuery] (the common case: no search typed) matches
  /// every dish, so [visibleRows] does no extra work when [query] is
  /// blank.
  bool _matchesQuery(Dish dish, String normalisedQuery) {
    if (normalisedQuery.isEmpty) return true;
    final haystack =
        '${TextNormaliser.normalise(dish.name)} '
        '${TextNormaliser.normalise(dish.description)}';
    return haystack.contains(normalisedQuery);
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

  /// [unclassifiedNames] resolved to rows, so the menu screen can draw each
  /// one as a `DishCard` (issue #244) with its description, price and photo.
  ///
  /// Each name is matched, in menu order, to a dish of that name the list
  /// has not already used, so two dishes sharing a name stay two rows. A
  /// name the menu does not contain (the model can name a dish by what it
  /// read) still gets a row, a bare one built from the name alone: an
  /// unclassified dish is never dropped (architecture.md §6.6, constraint
  /// 8). Every row has a null [DishRow.analysis].
  List<DishRow> get unclassifiedRows {
    final currentMenu = _menu;
    final names = unclassifiedNames;
    if (names.isEmpty) return const <DishRow>[];
    final unused = <DishRow>[
      if (currentMenu != null)
        for (final category in currentMenu.categories)
          for (final dish in category.dishes)
            DishRow(dish: dish, category: category.name),
    ];
    final rows = <DishRow>[];
    for (final name in names) {
      final index = unused.indexWhere((row) => row.dish.name == name);
      if (index >= 0) {
        rows.add(unused.removeAt(index));
      } else {
        rows.add(
          DishRow(
            dish: Dish(
              id: 'unclassified:${rows.length}:$name',
              name: name,
              description: '',
              price: 0,
              options: const <DishOption>[],
            ),
            category: '',
          ),
        );
      }
    }
    return rows;
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
  /// [filter] is reset from the user's stored default on every call, and
  /// [pageFilter] to null.
  ///
  /// **The visit history (issue #312).** Before fetching, the venue's
  /// history entry is read into [historyName] and [historyCity], and
  /// listeners are told when that changes either, so a header can name the
  /// venue while it loads.
  /// Every successful fetch then records exactly one visit, once the
  /// analysis is settled: the name the menu itself carries, else
  /// [hint]'s; [hint]'s city; the dish count; and, when the analysis
  /// succeeded, the score and the green and yellow counts. A failed fetch
  /// records nothing, and neither does [refresh].
  ///
  /// **The shared menu store (issue #312, D24).** Right after recording,
  /// and only when the user consents to AI analysis and the store is
  /// configured, the menu is uploaded in the background when it is news to
  /// the store from this device: the venue was never opened here before, or
  /// a language-model analysis ([LlmEngine]) was made in this open, or the
  /// cached language-model analysis is newer than the previous visit (a
  /// background fetch or a scan saved it since). A rules analysis is never
  /// news after the first visit, since it is never reused and would upload
  /// on every open: a menu only the rules judged uploads once, on its first
  /// visit, without an analysis. An analysis rides along only when the
  /// language model made it. [lastUpload] completes when that upload does;
  /// its result is never shown.
  ///
  /// Never throws.
  Future<void> open(
    VenueRef ref, {
    bool forceRefresh = false,
    VenueOpenHint? hint,
  }) async {
    _ref = ref;
    _phase = LoadPhase.fetching;
    _pageFilter = null;
    notifyListeners();

    _openRef = ref;
    final appSettings = await _settings.read();
    _filter = appSettings.lastFilter ?? appSettings.filter;
    _dishNotes = await _notes.readAll(ref);
    final previous = await _history.read(ref);
    if (previous?.name != _historyName || previous?.city != _historyCity) {
      _historyName = previous?.name;
      _historyCity = previous?.city;
      notifyListeners();
    }

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
        // A successful open is remembered so the Explore screen can offer
        // to resume it (issue #55); a failed one is not.
        await _settings.write(appSettings.copyWith(lastVenue: ref));

        final options = _optionsFrom(appSettings);
        final reusable = _reusableAnalysis(
          await _repository.cached(ref),
          fetchedMenu,
          options,
        );
        if (reusable != null) {
          _analysis = reusable;
        } else {
          await _classify(ref, fetchedMenu, options);
        }
        await _recordVisit(
          ref,
          fetchedMenu,
          hint: hint,
          previous: previous,
          classified: reusable == null,
          consentGiven: appSettings.estimationConsentGiven,
        );
      case MenuFetchFailed(:final reason, :final statusCode):
        _menu = null;
        _analysis = null;
        _isFromCache = false;
        _staleReason = null;
        _fetchFailure = reason;
        _fetchStatusCode = statusCode;
    }

    _phase = LoadPhase.idle;
    notifyListeners();
  }

  /// Records [ref]'s visit after [open] fetched [menu] and settled its
  /// analysis, refreshes [historyName] and [historyCity] from what was
  /// recorded, and starts the upload [open] describes when it is due.
  ///
  /// [previous] is the entry read before the fetch, [classified] whether
  /// this open ran the classifier rather than reusing a cached analysis,
  /// and [consentGiven] the user's AI-analysis consent.
  Future<void> _recordVisit(
    VenueRef ref,
    Menu menu, {
    required VenueOpenHint? hint,
    required VisitEntry? previous,
    required bool classified,
    required bool consentGiven,
  }) async {
    final analysis = _analysis;
    final counts = analysis is MenuAnalysed
        ? VerdictCounts.of(menu, analysis)
        : null;
    final name = menu.venueName ?? hint?.name;
    final city = hint?.city;
    await _history.recordVisit(
      ref,
      name: name,
      city: city,
      dishCount: menu.allDishes.length,
      score: counts?.score,
      greenCount: counts?.green,
      yellowCount: counts?.yellow,
    );
    // The store never lets a null erase a recorded value, so what it now
    // holds is what was written, else what it held before.
    _historyName = name ?? previous?.name;
    _historyCity = city ?? previous?.city;

    if (!consentGiven || !_menuStore.isConfigured) return;
    // Only a language-model analysis is news: a rules result is never
    // reused, so counting it would upload on every open.
    final llm = analysis is MenuAnalysed && analysis.engine is LlmEngine
        ? analysis
        : null;
    final fresh = llm != null && classified;
    final newer =
        llm != null &&
        previous != null &&
        llm.analysedAt.isAfter(previous.lastOpenedAt);
    if (previous != null && !fresh && !newer) return;
    _startUpload(ref, menu, llm);
  }

  /// Sends [menu] and [analysis] (null when the language model made none)
  /// to the shared menu store under [historyName] and [historyCity], in
  /// the background; [lastUpload] tracks it.
  void _startUpload(VenueRef ref, Menu menu, MenuAnalysed? analysis) {
    final upload = MenuUpload(
      ref: ref,
      venueName: _historyName,
      city: _historyCity,
      menu: menu,
      analysis: analysis,
    );
    final pending = _menuStore.upload(upload).then((_) {});
    _lastUpload = pending;
    unawaited(pending);
  }

  /// Whether the open menu is a scanned one, whose name and city the user
  /// may set with [renameVisit] (issue #315); a venue from a platform
  /// carries its own.
  bool get canRename => _ref?.source == MenuSource.scan;

  /// Names the open scanned menu [name] in [city] (issue #315): both are
  /// trimmed and an empty one becomes null, which clears it.
  ///
  /// Writes the visit history, updates [historyName] and [historyCity],
  /// and tells listeners. Then, when the user consents to AI analysis,
  /// the menu store is configured and a menu is loaded, uploads the menu
  /// again under the new name and city ([lastUpload] tracks it), with the
  /// analysis only when the language model made it. A no-op before
  /// [open].
  Future<void> renameVisit({
    required String? name,
    required String? city,
  }) async {
    final ref = _ref;
    if (ref == null) return;
    final cleanName = _blankToNull(name);
    final cleanCity = _blankToNull(city);
    await _history.rename(ref, name: cleanName, city: cleanCity);
    _historyName = cleanName;
    _historyCity = cleanCity;
    notifyListeners();

    final menu = _menu;
    if (menu == null || !_menuStore.isConfigured) return;
    final appSettings = await _settings.read();
    if (!appSettings.estimationConsentGiven) return;
    final analysis = _analysis;
    _startUpload(
      ref,
      menu,
      analysis is MenuAnalysed && analysis.engine is LlmEngine
          ? analysis
          : null,
    );
  }

  /// [value] trimmed, or null when nothing is left of it.
  static String? _blankToNull(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
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

    _phase = LoadPhase.fetching;
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
          await _classify(currentRef, fetchedMenu, options);
        }
      case MenuFetchFailed(:final reason):
        // Nothing fresh, and nothing stale either: keep exactly what was
        // already shown, and say why a refresh could not improve on it.
        _staleReason = reason;
        _isFromCache = true;
    }

    _phase = LoadPhase.idle;
    notifyListeners();
  }

  /// Classifies [menu] — already assigned to [menu] by the caller — and
  /// persists a successful result under [ref], moving [phase] through the
  /// classifying values on the way (issue #65).
  ///
  /// Clears [analysis] first and notifies, so the screen shows [menu]
  /// unjudged under a progress row while the engine runs, rather than
  /// the previous analysis — which may describe other dish text — or
  /// nothing at all.
  Future<void> _classify(
    VenueRef ref,
    Menu menu,
    ClassificationOptions options,
  ) async {
    _analysis = null;
    _phase = LoadPhase.classifying;
    notifyListeners();

    final analysis = await _classifier.classify(menu, options: options);
    _analysis = analysis;
    if (analysis is MenuAnalysed) {
      await _repository.saveAnalysis(ref, analysis);
    }
  }

  /// Moves [phase] to the classifying value naming [engine], notifying
  /// only when that changes it.
  ///
  /// Ignored outside the classifying phases, so a listener invoked after
  /// the load it belonged to has finished cannot put the screen back
  /// into a progress state.
  void _onEngineStarted(ClassifyingEngine engine) {
    if (!_phase.isClassifying) return;
    final next = switch (engine) {
      ClassifyingEngine.llm => LoadPhase.classifyingLlm,
      ClassifyingEngine.rules => LoadPhase.classifyingRules,
    };
    if (next == _phase) return;
    _phase = next;
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

    // Loading from the first synchronous moment, like open(); the
    // listeners hear about it once _classify notifies. Classified through
    // the same path open() and refresh() use, so [phase] names the engine
    // while the retry runs (issue #65).
    _phase = LoadPhase.classifying;
    final options = _optionsFrom(await _settings.read());
    await _classify(currentRef, currentMenu, options);

    _phase = LoadPhase.idle;
    notifyListeners();
  }

  /// The [ClassificationOptions] [settings] ask for: consent, the
  /// net-carb limit (issue #57), and the dietary constraints the three
  /// "Your keto rules" toggles switch on (issue #56), in the fixed order
  /// [ClassificationOptions.dietaryConstraintsFor] gives them.
  ClassificationOptions _optionsFrom(AppSettings settings) =>
      ClassificationOptions.fromSettings(
        settings,
        // The engine that picks up these options reports itself here, so
        // [phase] can name it (issue #65). An observer only: it takes no
        // part in [ClassificationOptions.matches] or equality.
        onEngineStarted: _onEngineStarted,
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
    // Issue #213: a cached result from a previous schema version may have
    // stale green verdicts that the new parser would demote. Re-analyse
    // rather than show a potentially wrong green.
    if (analysis.schemaVersion != MenuResponseParser.schemaVersion) {
      return null;
    }
    return analysis;
  }

  /// Sends [question] to the LLM, grounded in the current [analysis].
  ///
  /// Guards: no-ops when [_answerer] is null, when [analysis] is not a
  /// [MenuAnalysed] with an [LlmEngine], when [question] is blank after
  /// trimming, or when a question is already in flight. The question is
  /// never persisted, never logged, and never stored in the Hive cache or
  /// [SettingsStore] (architecture.md D8; issue #214).
  ///
  /// Transitions [questionState]: idle/answered/failed → loading → answered
  /// or failed.
  Future<void> askQuestion(String question) async {
    final answerer = _answerer;
    if (answerer == null) return;
    final menu = _menu;
    final analysis = _analysis;
    if (menu == null || analysis is! MenuAnalysed) return;
    if (analysis.engine is! LlmEngine) return;
    if (_questionState == QuestionState.loading) return;
    final trimmed = question.trim();
    if (trimmed.isEmpty) return;
    if (trimmed.length > menuQuestionMaxLength) return;

    _questionState = QuestionState.loading;
    _questionAnswer = null;
    _questionFailure = null;
    notifyListeners();

    // The question is in the user prompt only, never logged or persisted.
    final result = await answerer.ask(menu, analysis, trimmed);
    switch (result) {
      case MenuQuestionAnswered():
        _questionState = QuestionState.answered;
        _questionAnswer = result;
        _questionFailure = null;
      case MenuQuestionFailed():
        _questionState = QuestionState.failed;
        _questionAnswer = null;
        _questionFailure = result.reason;
    }
    notifyListeners();
  }

  /// Resets the question sheet to idle, discarding any previous answer or
  /// failure. A no-op when already idle.
  void dismissQuestion() {
    if (_questionState == QuestionState.idle) return;
    _questionState = QuestionState.idle;
    _questionAnswer = null;
    _questionFailure = null;
    notifyListeners();
  }

  /// Changes [filter], persists it as [AppSettings.lastFilter] (issue
  /// #55) so the next [open] restores it, and notifies listeners. Does
  /// not refetch or reclassify.
  Future<void> setFilter(MenuFilter filter) async {
    _filter = filter;
    notifyListeners();
    final appSettings = await _settings.read();
    await _settings.write(appSettings.copyWith(lastFilter: filter));
  }

  /// Changes [query] and notifies listeners (issue #51). Does not refetch
  /// or reclassify — matching is done on [menu]'s already-loaded text, not
  /// sent anywhere.
  void setQuery(String query) {
    _query = query;
    notifyListeners();
  }

  /// Changes [pageFilter] to [page] (issue #300): null for every page,
  /// [scanPageUnknown] for dishes whose page is unknown, or a 1-based
  /// page number. Notifies listeners only when the value actually
  /// changes. Not persisted: a page belongs to one scan, so the next
  /// [open] starts from every page again.
  void setPageFilter(int? page) {
    if (page == _pageFilter) return;
    _pageFilter = page;
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

  /// Whether [verdict] passes the current carb budget, if one is set.
  ///
  /// Null budget → always true (no budget active).
  /// Null verdict → always true (no analysis yet, so never hide).
  /// Null [AnalysedDish.netCarbsEstimate] → always true (estimate-less
  /// dishes are never filtered out: the budget only trims dishes the LLM
  /// estimated, and silently hiding estimate-less dishes would misrepresent
  /// the menu).
  /// Otherwise passes when the estimate is ≤ the budget (inclusive).
  bool _matchesBudget(AnalysedDish? verdict) {
    final budget = _carbBudget.budgetGrams;
    if (budget == null) return true;
    if (verdict == null) return true;
    final estimate = verdict.netCarbsEstimate;
    if (estimate == null) return true;
    return estimate <= budget;
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

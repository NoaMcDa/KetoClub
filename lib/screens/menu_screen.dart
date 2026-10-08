import 'dart:async';

// `MenuController` also names a widget in Flutter's own menu-anchor API;
// hidden here so this file's own `MenuController` (state/menu_controller.dart)
// resolves without ambiguity.
import 'package:flutter/material.dart' hide MenuController;
import 'package:intl/intl.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/scanned_menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/screens/waiter_card_sheet.dart';
import 'package:ketoclub/services/platform/connectivity.dart';
import 'package:ketoclub/services/platform/external_link_opener.dart';
import 'package:ketoclub/services/platform/menu_sharer.dart';
import 'package:ketoclub/services/platform/screen_brightness.dart';
import 'package:ketoclub/services/venue/venue_ref_resolver.dart';
import 'package:ketoclub/state/carb_budget_controller.dart';
import 'package:ketoclub/state/menu_controller.dart';
import 'package:ketoclub/state/scanned_pages_registry.dart';
import 'package:ketoclub/theme/app_typography.dart';
import 'package:ketoclub/utils/constants.dart';
import 'package:ketoclub/utils/menu_share_text.dart';
import 'package:ketoclub/utils/venue_route.dart';
import 'package:ketoclub/widgets/analysis_progress_row.dart';
import 'package:ketoclub/widgets/app_notice.dart';
import 'package:ketoclub/widgets/app_sheet.dart';
import 'package:ketoclub/widgets/carb_budget_field.dart';
import 'package:ketoclub/widgets/category_chips.dart';
import 'package:ketoclub/widgets/content_width.dart';
import 'package:ketoclub/widgets/dish_card.dart';
import 'package:ketoclub/widgets/engine_chip.dart';
import 'package:ketoclub/widgets/failure_copy.dart';
import 'package:ketoclub/widgets/fetch_failure_action.dart';
import 'package:ketoclub/widgets/keto_score_badge.dart';
import 'package:ketoclub/widgets/menu_filters_row.dart';
import 'package:ketoclub/widgets/menu_question_sheet.dart';
import 'package:ketoclub/widgets/menu_search_field.dart';
import 'package:ketoclub/widgets/note_editor_sheet.dart';
import 'package:ketoclub/widgets/offline_banner.dart';
import 'package:ketoclub/widgets/rename_menu_dialog.dart';
import 'package:ketoclub/widgets/rules_reason_banner.dart';
import 'package:ketoclub/widgets/scanned_page_chips.dart';
import 'package:ketoclub/widgets/scanned_page_header.dart';
import 'package:ketoclub/widgets/scanned_pages_sheet.dart';
import 'package:ketoclub/widgets/skeletons.dart';
import 'package:ketoclub/widgets/verdict_counter_tiles.dart';
import 'package:provider/provider.dart';

/// The narrowest window, in logical pixels, at which a loaded menu is laid
/// out in two panes: the header, the tiles, the Filters row and the
/// category chips pinned beside a dish list that scrolls on its own
/// (issue #225, architecture.md §6.6). The same width Discovery's grid
/// stops growing at (`discoveryMaxWidth`).
const double menuTwoPaneMinWidth = 1080;

/// The widest the two-pane menu grows (issue #225): the [ContentWidth] cap
/// the menu route passes in place of [contentMaxWidth] at
/// [menuTwoPaneMinWidth] and above.
const double menuTwoPaneMaxWidth = 1200;

/// The brand name shown for [ref]'s source inside failure copy (architecture.md
/// §10), e.g. "Wolt" in "Venue not found on Wolt. Check the link."
///
/// Not an l10n key: a platform's brand name is identical in every UI
/// language KetoClub supports, so it is not translatable prose — the ARB
/// files already embed the same names verbatim (e.g. `venueSearchHint`'s
/// "Wolt") rather than parameterising them.
///
/// The one exception is a pasted menu, which has no brand and so reads
/// [AppLocalizations.sourceScanned] ("Pasted menu").
///
/// A website has no brand either: it reads its own host (`cafe.co.il`,
/// architecture.md D19), the source chip the research asks for.
String _platformName(VenueRef ref, AppLocalizations l10n) =>
    switch (ref.source) {
      MenuSource.wolt => 'Wolt',
      MenuSource.tenbis => '10bis',
      MenuSource.tabit => 'Tabit',
      MenuSource.ontopo => 'Ontopo',
      MenuSource.scan => l10n.sourceScanned,
      MenuSource.website => VenueRefResolver.websiteHost(ref) ?? ref.platformId,
    };

/// The bucketed "time ago" phrase for [fetchedAt] relative to [now]
/// (issue #29's persistent source line): "just now" under a minute, then
/// the coarsest whole unit that fits — minutes, then hours, then days —
/// the way a person reads a timestamp rather than as raw seconds. [now] is
/// a parameter, not `DateTime.now()` read internally, purely so a caller
/// (or a test) controls it explicitly; this file still injects no `Clock`
/// dependency anywhere, matching `MenuController`'s own choice not to.
///
/// A [fetchedAt] slightly in the future — clock skew, not a real case —
/// reads as "just now" rather than a negative duration, since
/// [Duration.inMinutes] on a negative difference is itself negative and
/// so already less than 1.
String _ageLabel(DateTime fetchedAt, DateTime now, AppLocalizations l10n) {
  final elapsed = now.difference(fetchedAt);
  if (elapsed.inMinutes < 1) return l10n.ageJustNow;
  if (elapsed.inHours < 1) return l10n.ageMinutes(elapsed.inMinutes);
  if (elapsed.inDays < 1) return l10n.ageHours(elapsed.inHours);
  return l10n.ageDays(elapsed.inDays);
}

/// The definition text of one [promptVerdictDefinitionsFor] line, stripped of
/// its leading `verdictName — ` prefix. Returns the whole line, trimmed,
/// when no em dash is present, rather than failing — this is display
/// text, not a value anything downstream depends on being exact.
String _definitionTextFrom(String line) {
  final dashIndex = line.indexOf('—');
  return dashIndex == -1 ? line.trim() : line.substring(dashIndex + 1).trim();
}

/// The classified menu screen: a header naming the venue and its keto
/// score, the persistent "{platform} · {age}" source line, the three
/// verdict counter tiles that double as the filter, a collapsed Filters
/// row over the search, the carb budget and the legend (issue #234), the
/// engine chip, dish cards, and the unclassified section (architecture.md
/// §6.6, issue #29).
///
/// Reads its [MenuController] from `provider` and loads [ref] once, after
/// the first frame, so the initial build never itself triggers I/O. A
/// failed fetch leaves the raw menu unrendered and offers a retry; a
/// failed analysis never does — the raw menu is still shown, per
/// architecture.md §6.6's "a failed analysis must not cost the user the
/// menu".
///
/// The app bar carries the Settings action, as every screen does: the
/// analysis banners on this screen ("Allow AI analysis in Settings…")
/// name Settings as the way out, so it must be reachable from here
/// without first going back.
class MenuScreen extends StatefulWidget {
  /// Creates a screen that loads and classifies the menu for [ref].
  const new({
    required this.ref,
    required this.screenBrightness,
    required this.connectivity,
    required this.externalLinkOpener,
    required this.menuSharer,
    this.hint,
    this.scannedPages,
    super.key,
  });

  /// Which venue, on which platform, to load a menu for.
  final VenueRef ref;

  /// What the screen that opened this one already knew about the venue
  /// (a Discovery venue card, the Continue row, a Recent row; issue #312),
  /// or null on a deep link.
  ///
  /// Its name is shown in the header when the menu itself names no venue
  /// — which no documented Wolt payload does — ahead of the name the visit
  /// history remembers and the bare [VenueRef.platformId] slug. Its city
  /// joins the source line. [MenuController.open] records both in the
  /// visit history.
  final VenueOpenHint? hint;

  /// Raises the screen brightness while the Waiter Card is open, so the
  /// card stays readable across a restaurant table, and restores it on
  /// close. A no-op on web, chosen in `di.dart` (architecture.md §6.6).
  final ScreenBrightness screenBrightness;

  /// Backs the persistent offline banner (issue #68).
  final Connectivity connectivity;

  /// Opens the venue's own page on its platform when the "open on
  /// {platform}" action beside the source line is tapped (issue #53).
  final ExternalLinkOpener externalLinkOpener;

  /// Shares [MenuShareText.build]'s summary of the green and yellow
  /// dishes when the app bar's share action is tapped (issue #54).
  final MenuSharer menuSharer;

  /// The pages recent scans were read from, in memory only (issue #89).
  /// When it holds pages for a [MenuSource.scan] [ref], the header names
  /// the menu as read by AI from those pages and offers "View pages";
  /// otherwise — a pasted menu, a scan from an earlier run, or null — the
  /// header reads as a pasted menu, as it did before scanning existed.
  final ScannedPagesRegistry? scannedPages;

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

/// The entries of the menu app bar's overflow menu (issue #238).
enum _MenuOverflowAction {
  /// Shares the menu's green and yellow dishes as text.
  share,

  /// Names a scanned menu (issue #315).
  rename,
}

class _MenuScreenState extends State<MenuScreen> {
  /// Whether the verdict legend (issue #17, §"WHAT TO BUILD" item 5) is
  /// expanded.
  ///
  /// Local UI state, not persisted and not part of [MenuController]: it
  /// says nothing about the menu itself, only about this screen's
  /// disclosure widget — the same reasoning that kept the collapsed red
  /// group's expansion flag local before issue #29 replaced that group
  /// with [MenuFilter.redOnly].
  bool _legendExpanded = false;

  /// Whether the Filters row (issue #234) — the search field, the carb
  /// budget and the legend — is expanded. Local UI state for the same
  /// reason as [_legendExpanded]; collapsed by default so the first dish
  /// card is on screen when the menu opens.
  bool _filtersExpanded = false;

  /// Bumped on every retry action on this screen — the failed-fetch
  /// retry, the [RulesReasonBanner] retry, and pull-to-refresh — so the
  /// [OfflineBanner] above the body re-checks connectivity exactly when
  /// this screen makes a fresh attempt (issue #68). [Connectivity
  /// .isOnline] is a one-shot check, not a stream, so nothing else would
  /// tell that banner a retry just happened.
  int _recheckToken = 0;

  /// Scrolls the loaded-menu list for [_scrollToCategory] (issue #51).
  final ScrollController _scrollController = ScrollController();

  /// The loaded-menu list's top padding, above [_header].
  static const double _listTopPadding = 8;

  /// Whether the loaded-menu list has scrolled the [_header] out from
  /// under the app bar, so the bar shows the venue name as its title
  /// (issue #237). A notifier rather than a [State] field, so crossing
  /// that line rebuilds the title alone, not the whole dish list.
  final ValueNotifier<bool> _headerScrolledPast = ValueNotifier<bool>(false);

  /// Wraps [_header], so [_updateHeaderScrolledPast] can read its height.
  final GlobalKey _headerKey = GlobalKey();

  /// Whether the last build laid the loaded menu out in two panes (issue
  /// #225); kept so [_updateHeaderScrolledPast] can tell.
  bool _twoPane = false;

  /// The side pane's width in the two-pane layout (issue #225): the
  /// 390px artboard's column, so the header, the tiles and the chips keep
  /// the proportions they were drawn at.
  static const double _sidePaneWidth = 380;

  /// The stable [GlobalKey] for each category header currently or
  /// previously shown, keyed by category name — see [_categoryKeyFor]
  /// (issue #51).
  final Map<String, GlobalKey> _categoryKeys = <String, GlobalKey>{};

  @override
  void dispose() {
    _scrollController
      ..removeListener(_updateHeaderScrolledPast)
      ..dispose();
    _headerScrolledPast.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_updateHeaderScrolledPast);
    // Deferred to after the first frame, so building this screen never
    // itself starts the fetch — a widget's build method must stay free of
    // side effects.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        context.read<MenuController>().open(widget.ref, hint: widget.hint),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final controller = context.watch<MenuController>();
    // The share action needs at least one green or yellow dish to build a
    // non-empty summary from (issue #54); a failed or not-yet-run analysis
    // — where every count below reads 0 — hides it rather than sharing an
    // empty card.
    // Any green or yellow dish, drinks included: the counts are food only
    // (D21), but a card of safe drinks is still worth sharing.
    final analysis = controller.analysis;
    final canShare =
        analysis is MenuAnalysed &&
        analysis.dishes.any(
          (dish) =>
              dish.verdict == DishVerdict.orderAsIs ||
              dish.verdict == DishVerdict.modifiable,
        );
    return Scaffold(
      appBar: AppBar(
        // The venue name, once the body header has scrolled under the bar
        // (issue #237); the theme's `scrolledUnderElevation: 0` still
        // keeps the bar flat over the list (audit G2).
        title: controller.menu == null
            ? null
            : ValueListenableBuilder<bool>(
                valueListenable: _headerScrolledPast,
                builder: (context, scrolledPast, _) => scrolledPast
                    ? Text(
                        _displayName(controller, l10n),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      )
                    : const SizedBox.shrink(),
              ),
        actions: [
          if (controller.isQuestionAvailable)
            IconButton(
              icon: const Icon(Icons.question_answer),
              tooltip: l10n.actionAskAboutMenu,
              onPressed: () => _openQuestionSheet(context, controller),
            ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: l10n.actionOpenSettings,
            onPressed: () => Navigator.pushNamed(context, '/settings'),
          ),
          // The overflow holds "Share" (since the drinks guide moved to
          // Explore, issue #257) and, for a scanned menu, "Rename" (issue
          // #315), so with neither it is hidden rather than opening an
          // empty menu.
          if (canShare || controller.canRename)
            PopupMenuButton<_MenuOverflowAction>(
              tooltip: l10n.actionMoreMenuOptions,
              onSelected: (action) => switch (action) {
                _MenuOverflowAction.share => unawaited(_shareMenu(controller)),
                _MenuOverflowAction.rename => unawaited(
                  _renameMenu(context, controller),
                ),
              },
              itemBuilder: (context) => [
                if (canShare)
                  PopupMenuItem(
                    value: _MenuOverflowAction.share,
                    child: Text(l10n.actionShareMenu),
                  ),
                if (controller.canRename)
                  PopupMenuItem(
                    value: _MenuOverflowAction.rename,
                    child: Text(l10n.menuRenameAction),
                  ),
              ],
            ),
        ],
      ),
      // The window's width, not the capped column's, decides the layout:
      // the cap itself depends on it (issue #225).
      body: LayoutBuilder(
        builder: (context, constraints) {
          final twoPane =
              constraints.maxWidth >= menuTwoPaneMinWidth &&
              (controller.menu?.allDishes.isNotEmpty ?? false);
          _syncTwoPane(twoPane);
          return ContentWidth(
            maxWidth: twoPane ? menuTwoPaneMaxWidth : contentMaxWidth,
            child: Column(
              children: [
                OfflineBanner(
                  connectivity: widget.connectivity,
                  recheckToken: _recheckToken,
                ),
                Expanded(
                  child: _body(context, l10n, controller, twoPane: twoPane),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Records whether the body is laid out in two panes (issue #225) and,
  /// when that just changed, re-derives [_headerScrolledPast] after the
  /// frame: the list it was measured on is not the list now shown.
  void _syncTwoPane(bool twoPane) {
    if (twoPane == _twoPane) return;
    _twoPane = twoPane;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateHeaderScrolledPast();
    });
  }

  /// Sets [_headerScrolledPast] from the list's offset: past once the
  /// list's top padding and the whole [_header] are above the viewport.
  ///
  /// A [ListView] builds lazily, so a header scrolled far enough away has
  /// no render box left to measure; any offset above zero then means it
  /// is gone.
  ///
  /// Always false in two panes (issue #225): the header is pinned in the
  /// side pane there and never scrolls under the bar.
  void _updateHeaderScrolledPast() {
    if (_twoPane) {
      _headerScrolledPast.value = false;
      return;
    }
    if (!_scrollController.hasClients) return;
    final offset = _scrollController.offset;
    final box = _headerKey.currentContext?.findRenderObject();
    _headerScrolledPast.value = box is RenderBox && box.hasSize
        ? offset >= _listTopPadding + box.size.height
        : offset > 0;
  }

  /// Builds [MenuShareText.build]'s summary of [controller]'s current
  /// green and yellow dishes and hands it to `widget.menuSharer` (issue
  /// #54).
  ///
  /// A no-op when [MenuController.menu] or [MenuController.analysis] is
  /// not in the shape [build]'s `canShare` check already requires before
  /// this action is even shown — defensive only, since a listener could in
  /// principle rebuild between that check and a tap reaching here, but no
  /// test exercises it. The venue name follows the same fallback [_header]
  /// uses, so the shared text names the venue exactly as the header does.
  Future<void> _shareMenu(MenuController controller) async {
    final menu = controller.menu;
    final analysis = controller.analysis;
    if (menu == null || analysis is! MenuAnalysed) return;
    final text = MenuShareText.build(
      venueName: _displayName(controller, AppLocalizations.of(context)!),
      menu: menu,
      analysis: analysis,
    );
    await widget.menuSharer.shareText(text);
  }

  /// The screen body for the controller's current state: loading, a
  /// failed fetch, or a loaded menu (architecture.md §6.6).
  ///
  /// [twoPane] lays a loaded menu out in two panes (issue #225).
  Widget _body(
    BuildContext context,
    AppLocalizations l10n,
    MenuController controller, {
    required bool twoPane,
  }) {
    final menu = controller.menu;
    if (menu == null) {
      final failure = controller.fetchFailure;
      if (failure == null) return _fetchingSkeleton(l10n);
      return _fetchFailureView(context, l10n, controller, failure);
    }
    return _loadedView(context, l10n, controller, menu, twoPane: twoPane);
  }

  /// Three [DishCardSkeleton]s in place of the old "Reading the menu…"
  /// text, for [LoadPhase.fetching] (issue #63): a run of static,
  /// two-tone cards shaped like the ones about to load, wrapped in one
  /// live [Semantics] label — [l10n]'s own `menuLoading` copy — since the
  /// cards themselves exclude their own semantics.
  Widget _fetchingSkeleton(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Semantics(
        liveRegion: true,
        label: l10n.menuLoading,
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DishCardSkeleton(),
            SizedBox(height: 12),
            DishCardSkeleton(),
            SizedBox(height: 12),
            DishCardSkeleton(),
          ],
        ),
      ),
    );
  }

  /// A failed fetch: [fetchFailureMessage] plus the action
  /// [failure] calls for — a [FetchFailureAction] retries the same fetch,
  /// goes back to paste a different venue, or offers nothing at all,
  /// depending on the reason (issue #68).
  Widget _fetchFailureView(
    BuildContext context,
    AppLocalizations l10n,
    MenuController controller,
    MenuFetchFailureReason failure,
  ) {
    final message = fetchFailureMessage(
      failure,
      l10n,
      platform: _platformName(widget.ref, l10n),
      statusCode: controller.fetchStatusCode,
    );
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FetchFailureAction(
              reason: failure,
              onRetry: () => _retry(
                () => controller.open(
                  widget.ref,
                  forceRefresh: true,
                  hint: widget.hint,
                ),
              ),
              onBackToSearch: () => _backToSearch(context),
            ),
          ],
        ),
      ),
    );
  }

  /// Bumps [_recheckToken] — so the [OfflineBanner] above re-checks
  /// connectivity — then runs [attempt] (issue #68). Every retry action
  /// on this screen goes through this one place.
  void _retry(Future<void> Function() attempt) {
    setState(() => _recheckToken++);
    unawaited(attempt());
  }

  /// Returns to the venue search screen: pops this route when there is
  /// one to pop back to (the normal case — this screen is always pushed
  /// on top of it), or replaces this route with it when there is not
  /// (this screen reached directly, e.g. a restored deep link).
  void _backToSearch(BuildContext context) {
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    } else {
      Navigator.pushReplacementNamed(context, '/');
    }
  }

  /// A menu that was fetched, whether or not it was analysed
  /// successfully and whether or not it came from cache.
  ///
  /// [twoPane] (issue #225, a window at least [menuTwoPaneMinWidth] wide)
  /// pins the header, the tiles, the source line, the Filters row and the
  /// category chips in a side pane of their own, and scrolls only the
  /// notices and the dishes beside it. Otherwise everything is one list.
  Widget _loadedView(
    BuildContext context,
    AppLocalizations l10n,
    MenuController controller,
    Menu menu, {
    required bool twoPane,
  }) {
    final banners = _banners(context, l10n, controller);
    // The header and the source line name the venue and when its menu was
    // read; neither depends on a successful analysis, so both render for
    // an empty menu and for a failed analysis alike.
    final header = _header(context, l10n, controller);
    final sourceLine = _sourceLine(context, l10n, controller);

    if (menu.allDishes.isEmpty) {
      return _refreshable(
        controller,
        ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            header,
            const SizedBox(height: 4),
            ?sourceLine,
            const SizedBox(height: 12),
            ...banners,
            Center(
              child: Padding(
                padding: const EdgeInsets.only(top: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(l10n.menuEmpty, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () => _retry(controller.refresh),
                      child: Text(l10n.actionRefreshMenu),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    // The tiles, the "Showing" label, the legend and the engine chip all
    // key off a verdict that exists only once the analysis succeeded, so
    // they are hidden without one. The dish list itself is not:
    // MenuController.visibleRows already returns every dish unjudged in that
    // case, so a failed analysis never costs the user the menu (§6.6).
    final analysed = controller.analysis is MenuAnalysed;
    final localeTag = Localizations.localeOf(context).toLanguageTag();
    final rows = controller.visibleRows;
    final paging = _pagingFor(controller);

    // Header, tiles, category chips, then dishes (issue #234): the
    // search, the carb budget and the legend sit behind one collapsed
    // Filters row, so the first dish card fits on a phone screen.
    final top = <Widget>[
      KeyedSubtree(key: _headerKey, child: header),
      const SizedBox(height: 4),
      if (analysed) ...[
        const SizedBox(height: 8),
        VerdictCounterTiles(
          greenCount: controller.greenCount,
          yellowCount: controller.yellowCount,
          redCount: controller.redCount,
          filter: controller.filter,
          onFilterChanged: controller.setFilter,
        ),
        const SizedBox(height: 10),
      ],
      // A scan read from several pages is filtered by page right under
      // the tiles (issue #296), so in two panes it sits in the side pane.
      if (paging != null) ...[
        ScannedPageChips(
          pageCount: paging.pageCount,
          hasUnknown: controller.hasUnattributedDishes,
          selected: controller.pageFilter,
          onSelected: controller.setPageFilter,
          wrap: twoPane,
        ),
        const SizedBox(height: 10),
      ],
      // A Wrap, not a Row (issue #245): the source line sits at the end
      // of the label's line when both fit, and drops to a line of its
      // own with the whole width when a long website host would not.
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        spacing: 8,
        children: [
          if (analysed)
            Text(
              _showingLabel(l10n, controller),
              style: Theme.of(context).textTheme.labelMedium,
            )
          else
            const SizedBox.shrink(),
          ?sourceLine,
        ],
      ),
      _filtersRow(context, l10n, controller, analysed: analysed),
      const SizedBox(height: 4),
    ];
    final notices = <Widget>[
      AnalysisProgressRow(phase: controller.phase),
      ...banners,
      if (controller.engine != null) ...[
        RulesReasonBanner(
          engine: controller.engine!,
          onRetry: () => _retry(controller.reanalyse),
        ),
        // A rules result is explained by the banner above, so the chip
        // is shown for an AI result only (audit M14, issue #236).
        // Aligned rather than stretched: a ListView child is forced to
        // the full width, which drew this pill as a full-width bar.
        if (controller.engine is LlmEngine) ...[
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: EngineChip(engine: controller.engine!),
          ),
          const SizedBox(height: 12),
        ],
      ],
    ];
    final chips = <Widget>[
      CategoryChips(
        // A paged scan is headed by page, not by category (issue #296),
        // so there is no category heading for a chip to jump to.
        categories: paging != null
            ? const <String>[]
            : controller.visibleCategories,
        onSelected: (category) => unawaited(_scrollToCategory(category)),
        // Wrapped in the side pane, where a mouse cannot drag a
        // horizontal row to the chips past its edge (issue #225).
        wrap: twoPane,
      ),
      const SizedBox(height: 8),
    ];
    final dishes = <Widget>[
      if (rows.isEmpty)
        _noVisibleRows(l10n, controller)
      else
        ..._dishRows(context, controller, localeTag, rows, paging: paging),
      if (analysed && controller.unclassifiedRows.isNotEmpty)
        _unclassifiedSection(context, l10n, controller, localeTag),
    ];
    // The dish list keeps [_scrollController] in either layout, so the
    // chip jump scrolls the dishes wherever the chips sit.
    final dishList = _refreshable(
      controller,
      ListView(
        controller: _scrollController,
        // Always scrollable, so a menu shorter than the screen can still
        // be pulled down to refresh (RefreshIndicator's own requirement).
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, _listTopPadding, 20, 24),
        children: twoPane
            ? [...notices, ...dishes]
            : [...top, ...notices, ...chips, ...dishes],
      ),
    );
    if (!twoPane) return dishList;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: _sidePaneWidth,
          // Scrolls on its own when an open Filters row or a short window
          // makes the pane taller than the screen; not the primary scroll
          // view, which is the dish list's.
          child: ListView(
            primary: false,
            padding: const EdgeInsets.fromLTRB(20, _listTopPadding, 20, 24),
            children: [...top, ...chips],
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(child: dishList),
      ],
    );
  }

  /// The collapsible Filters row (issue #234) holding the search field,
  /// the carb budget and — once there is a verdict to explain — the
  /// legend. Collapsing it moves focus out of a field it hides, so the
  /// keyboard does not stay up for a field the user can no longer see.
  Widget _filtersRow(
    BuildContext context,
    AppLocalizations l10n,
    MenuController controller, {
    required bool analysed,
  }) {
    final hasBudget = context.watch<CarbBudgetController>().hasBudget;
    final activeCount =
        (controller.query.trim().isEmpty ? 0 : 1) + (hasBudget ? 1 : 0);
    return MenuFiltersRow(
      expanded: _filtersExpanded,
      activeCount: activeCount,
      onToggle: () {
        if (_filtersExpanded) FocusScope.of(context).unfocus();
        setState(() => _filtersExpanded = !_filtersExpanded);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MenuSearchField(onChanged: controller.setQuery),
          const SizedBox(height: 8),
          CarbBudgetField(isBudgetAvailable: controller.isBudgetAvailable),
          if (analysed) ...[
            const SizedBox(height: 4),
            _legend(context, l10n, controller.netCarbLimitGrams),
          ],
        ],
      ),
    );
  }

  /// Wraps [child] — the loaded-menu [ListView], empty or not — in a
  /// [RefreshIndicator] that pulls [MenuController.refresh] regardless of
  /// the active filter: the filter narrows [MenuController.visibleRows],
  /// never whether a refresh can be pulled (issue #49). Not offered on
  /// the failed-fetch or still-loading states in [_body], which have no
  /// scrollable list to pull down in the first place; the dedicated retry
  /// button there covers a hard failure instead.
  Widget _refreshable(MenuController controller, Widget child) {
    return RefreshIndicator(
      onRefresh: () {
        setState(() => _recheckToken++);
        return controller.refresh();
      },
      child: child,
    );
  }

  /// Asks for a name and a city for a scanned menu and hands them to
  /// [MenuController.renameVisit] (issue #315); nothing happens when the
  /// dialog is cancelled.
  Future<void> _renameMenu(
    BuildContext context,
    MenuController controller,
  ) async {
    final result = await showRenameMenuDialog(
      context,
      initialName: controller.historyName,
      initialCity: controller.historyCity,
    );
    if (result == null) return;
    await controller.renameVisit(name: result.name, city: result.city);
  }

  /// The name the header and the shared text give the venue: the menu's
  /// own, the hint the opener passed, the name the visit history
  /// remembers (issue #312), else the reference — except for a pasted
  /// menu, whose reference is a hash and reads as "Pasted menu", and a
  /// website, whose reference is a URL and reads as its host.
  String _displayName(MenuController controller, AppLocalizations l10n) {
    final fallback = switch (widget.ref.source) {
      MenuSource.scan => _scanSourceName(l10n),
      MenuSource.website => _platformName(widget.ref, l10n),
      _ => widget.ref.platformId,
    };
    return controller.venueName ??
        widget.hint?.name ??
        controller.historyName ??
        fallback;
  }

  /// The pages this menu was read from, when it is a scan whose pages are
  /// still held in memory (issue #89); null for every other menu.
  ScannedMenu? get _scannedPages => widget.ref.source == MenuSource.scan
      ? widget.scannedPages?.get(widget.ref)
      : null;

  /// What a [MenuSource.scan] menu is called: "Scanned menu" while its
  /// pages are held (issue #89), else "Pasted menu" — a scan from an
  /// earlier run reads as a paste, since nothing but the pages tells the
  /// two apart.
  String _scanSourceName(AppLocalizations l10n) =>
      _scannedPages != null ? l10n.scannedMenuTitle : l10n.sourceScanned;

  /// The name the source line gives this menu's source: the platform's
  /// brand, or for a scan [_scanSourceName].
  String _sourceName(AppLocalizations l10n) =>
      widget.ref.source == MenuSource.scan
      ? _scanSourceName(l10n)
      : _platformName(widget.ref, l10n);

  /// The venue name and keto score (issue #29's header row,
  /// `.design/Main.dc.html`).
  ///
  /// **`venueName` is null on every real fetch today** — no documented
  /// Wolt payload names the venue, so this is the normal case, not an
  /// edge case: the header falls back to [VenueRef.platformId] — the
  /// pasted slug or reference — rather than a placeholder like
  /// "Restaurant", per `Menu.venueName`'s own doc comment.
  Widget _header(
    BuildContext context,
    AppLocalizations l10n,
    MenuController controller,
  ) {
    final name = _displayName(controller, l10n);
    final theme = Theme.of(context);
    final titleRow = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            name,
            style: AppTypography.displayStyle(
              size: 28,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ),
        KetoScoreBadge(score: controller.ketoScoreOutOfTen),
      ],
    );
    final pages = _scannedPages;
    if (pages == null) return titleRow;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [titleRow, _scannedSourceRow(context, l10n, pages)],
    );
  }

  /// The scanned menu's honest source line (issue #89): the dishes were
  /// read by AI from the user's own pages, with "View pages" beside it so
  /// the transcription can be checked against them.
  Widget _scannedSourceRow(
    BuildContext context,
    AppLocalizations l10n,
    ScannedMenu pages,
  ) {
    final theme = Theme.of(context);
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 4,
      children: [
        Icon(
          Icons.auto_awesome_outlined,
          size: 14,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        Text(l10n.scannedMenuReadByAi, style: theme.textTheme.bodySmall),
        TextButton.icon(
          icon: const Icon(Icons.photo_library_outlined, size: 16),
          label: Text(l10n.scannedMenuViewPages),
          style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
          onPressed: () => unawaited(_openScannedPages(pages)),
        ),
      ],
    );
  }

  /// Opens [ScannedPagesSheet] over [pages] as a dismissible modal, at
  /// the 0-based [initialPage] when given (issue #296).
  Future<void> _openScannedPages(ScannedMenu pages, {int? initialPage}) {
    return showKetoClubSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => ScannedPagesSheet(scan: pages, initialPage: initialPage),
    );
  }

  /// The persistent source line, e.g. "Wolt · 4 min ago"
  /// (`.design/Main.dc.html`), plus the refresh action (issue #47) and the
  /// "open on {platform}" action (issue #53) beside it. Null before any
  /// menu is loaded — [MenuController.fetchedAt] is null then, and there
  /// is nothing to date, refresh or link out to yet. Otherwise shows for
  /// every loaded menu, fresh or cached, from that same getter — see its
  /// own doc comment for why it, not [MenuController.cachedAt], is the
  /// right source.
  ///
  /// The refresh action calls [MenuController.refresh] directly: the same
  /// refetch-and-reuse [_refreshable]'s [RefreshIndicator] already pulls
  /// (issue #49), so a tap and a pull-down behave identically rather than
  /// this screen duplicating that logic. The age label re-derives from
  /// [MenuController.fetchedAt] on every rebuild this widget already
  /// listens for, so a successful refresh moves it forward with no extra
  /// wiring here. The "open on {platform}" action is built by
  /// [_openOnPlatformAction], its own small method, so the two actions
  /// merge onto this Row without either PR having to rewrite the other's
  /// body.
  Widget? _sourceLine(
    BuildContext context,
    AppLocalizations l10n,
    MenuController controller,
  ) {
    final fetchedAt = controller.fetchedAt;
    if (fetchedAt == null) return null;
    final age = _ageLabel(fetchedAt, DateTime.now(), l10n);
    // The venue's city, when the opener or the visit history knows it
    // (issue #312): "Wolt · Tel Aviv · 4 min ago".
    final city = widget.hint?.city ?? controller.historyCity;
    final source = city == null
        ? _sourceName(l10n)
        : l10n.sourceWithCity(_sourceName(l10n), city);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Flexible, not capped: a website's source is its host (D19), which
        // can be far longer than a platform's brand, so the text takes
        // whatever width the row leaves beside the icons and wraps to a
        // second line before it ellipsises (issue #245).
        Flexible(
          child: Text(
            l10n.menuSourceLine(source, age),
            style: Theme.of(context).textTheme.bodySmall,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        // A pasted menu has no platform to ask again, so a refresh would
        // only re-serve the same cache entry.
        if (widget.ref.source != MenuSource.scan)
          IconButton(
            icon: const Icon(Icons.refresh, size: 16),
            tooltip: l10n.actionRefreshMenu,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            visualDensity: VisualDensity.compact,
            onPressed: () => _retry(controller.refresh),
          ),
        ?_openOnPlatformAction(l10n),
      ],
    );
  }

  /// The "open on {platform}" icon action beside the source line (issue
  /// #53): opens `VenueRefResolver.platformUrl` for `widget.ref` in an
  /// external app or browser through `widget.externalLinkOpener`, never
  /// inside KetoClub itself.
  ///
  /// Returns null — rendering nothing — when `VenueRefResolver.platformUrl`
  /// has no URL form for this source yet (Tabit, Ontopo): a missing button
  /// is a better failure than a link that goes nowhere.
  ///
  /// A small private method of its own, per the issue's own scoping note,
  /// so the concurrent PRs also touching this header (refresh, search) do
  /// not have to merge around this one's body.
  Widget? _openOnPlatformAction(AppLocalizations l10n) {
    final url = VenueRefResolver.platformUrl(widget.ref);
    if (url == null) return null;
    final label = l10n.menuOpenOnPlatform(_platformName(widget.ref, l10n));
    return IconButton(
      icon: const Icon(Icons.open_in_new, size: 18),
      tooltip: label,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      visualDensity: VisualDensity.compact,
      onPressed: () => unawaited(widget.externalLinkOpener.open(url)),
    );
  }

  /// The empty state for [MenuController.visibleRows] (issue #63): the
  /// existing `menuNoResults` copy, plus a "Clear filter" action that
  /// resets `controller.filter` to [MenuFilter.all] — shown only when a
  /// verdict tile, not the search field, is what emptied the list.
  ///
  /// The search field already carries its own clear button
  /// (`MenuSearchField`, issue #51) for the case where a typed query is
  /// what narrowed the list to nothing, so this action does not also
  /// reset [MenuController.query] — the two clears stay independent, each
  /// next to the control it undoes.
  Widget _noVisibleRows(AppLocalizations l10n, MenuController controller) {
    final canClearFilter = controller.filter != MenuFilter.all;
    final hasBudget = context.read<CarbBudgetController>().hasBudget;
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.menuNoResults, textAlign: TextAlign.center),
            if (canClearFilter || hasBudget) ...[
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () {
                  unawaited(controller.setFilter(MenuFilter.all));
                  context.read<CarbBudgetController>().clear();
                },
                child: Text(l10n.menuClearFilter),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// A short label for `controller.filter`, matching
  /// `.design/Main.dc.html`'s `showing` map. An exhaustive switch with no
  /// `default`: adding a [MenuFilter] value without updating this
  /// function is a compile error (architecture.md §10).
  String _showingLabel(AppLocalizations l10n, MenuController controller) =>
      switch (controller.filter) {
        MenuFilter.greenOnly => l10n.menuShowingGreen,
        MenuFilter.yellowOnly => l10n.menuShowingYellow,
        MenuFilter.redOnly => l10n.menuShowingRed,
        MenuFilter.greenAndYellow => l10n.menuShowingGreenAndYellow,
        MenuFilter.all => l10n.menuShowingAll(controller.totalDishCount),
      };

  /// The verdict legend (issue #17): a toggle, and — once expanded — the
  /// same three verdict definitions the system prompt sends
  /// ([promptVerdictDefinitionsFor]), so the legend the UI shows and the
  /// definitions the prompt sends can never drift apart. See this
  /// screen's final report for why this reads that constant directly
  /// rather than a re-translated copy of it.
  ///
  /// [netCarbLimitGrams] is the limit the shown analysis was made under
  /// (issue #57), so the green definition states the same figure the
  /// model was given.
  Widget _legend(
    BuildContext context,
    AppLocalizations l10n,
    int netCarbLimitGrams,
  ) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _legendExpanded = !_legendExpanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.info_outline,
                  size: 14,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  _legendExpanded ? l10n.legendHide : l10n.legendToggle,
                  style: theme.textTheme.labelMedium,
                ),
              ],
            ),
          ),
        ),
        if (_legendExpanded) _legendBody(context, l10n, netCarbLimitGrams),
      ],
    );
  }

  /// The expanded legend body: one line per verdict, parsed from
  /// [promptVerdictDefinitionsFor] — never re-typed — plus `l10n.legendNote`
  /// naming that source. Renders nothing if that constant is ever
  /// reshaped away from its documented one-line-per-verdict form, rather
  /// than guessing at a malformed split.
  Widget _legendBody(
    BuildContext context,
    AppLocalizations l10n,
    int netCarbLimitGrams,
  ) {
    final lines = promptVerdictDefinitionsFor(netCarbLimitGrams).split('\n');
    if (lines.length != 3) return const SizedBox.shrink();
    final labels = [
      l10n.verdictOrderAsIs,
      l10n.verdictModifiable,
      l10n.verdictNonKeto,
    ];
    final bodyStyle = Theme.of(context).textTheme.bodySmall;
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < labels.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: RichText(
                text: TextSpan(
                  style: bodyStyle,
                  children: [
                    TextSpan(
                      text: '${labels[i]}: ',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    TextSpan(text: _definitionTextFrom(lines[i])),
                  ],
                ),
              ),
            ),
          Text(l10n.legendNote, style: bodyStyle),
          const SizedBox(height: 6),
          Text(l10n.legendEngines, style: bodyStyle),
          const SizedBox(height: 6),
          Text(l10n.legendFoodOnly, style: bodyStyle),
          const SizedBox(height: 6),
          Text(l10n.legendBudget, style: bodyStyle),
        ],
      ),
    );
  }

  /// Lines shown above the menu: a failed analysis
  /// ([analysisFailureMessage]), then — independently, since either can
  /// occur without the other — a stale-cache note (`AppLocalizations
  /// .cachedFrom` and, when set, [MenuController.staleReason]'s own
  /// [fetchFailureMessage]).
  ///
  /// Both can apply at once (a stale menu whose fresh analysis failed),
  /// so every applicable line is composed into one column rather than
  /// one hiding the other. Each line is an [AppNotice.info] (issue #260):
  /// they explain, they ask for nothing, so each is one muted line with
  /// an icon.
  List<Widget> _banners(
    BuildContext context,
    AppLocalizations l10n,
    MenuController controller,
  ) {
    final lines = <AppNotice>[];
    final analysis = controller.analysis;
    if (analysis is MenuAnalysisFailed) {
      lines.add(
        AppNotice.info(
          message: analysisFailureMessage(
            analysis.reason,
            l10n,
            detail: analysis.detail,
          ),
        ),
      );
    }
    final cachedAt = controller.cachedAt;
    if (controller.isFromCache && cachedAt != null) {
      final localeTag = Localizations.localeOf(context).toLanguageTag();
      final formatted = DateFormat.yMMMd(localeTag)
          .add_Hm()
          .format(cachedAt.toLocal());
      lines.add(
        AppNotice.info(
          message: l10n.cachedFrom(formatted),
          icon: Icons.history,
        ),
      );
    }
    final staleReason = controller.staleReason;
    if (staleReason != null) {
      lines.add(
        AppNotice.info(
          message: fetchFailureMessage(
            staleReason,
            l10n,
            platform: _platformName(widget.ref, l10n),
          ),
          icon: Icons.sync_problem,
        ),
      );
    }
    // A scan whose dishes name their pages, opened after its photographs
    // left memory (a restart, or eviction): the page headers still number
    // the dishes, but nothing can show the pages themselves (issue #296).
    if (widget.ref.source == MenuSource.scan &&
        controller.attributedPages.isNotEmpty &&
        _scannedPages == null) {
      lines.add(
        AppNotice.info(
          message: l10n.scannedMenuPagesGone,
          icon: Icons.photo_library_outlined,
        ),
      );
    }
    if (lines.isEmpty) return const <Widget>[];
    return <Widget>[
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 6,
          children: lines,
        ),
      ),
    ];
  }

  /// How a scan read from several pages is laid out by page (issue
  /// #296), or null when the menu is not headed by page: a platform menu,
  /// a pasted one, a scan whose dishes name no page, and a one-page scan.
  ///
  /// The page count is the held scan's own; once its pages have left
  /// memory, it is the highest page a dish names.
  _Paging? _pagingFor(MenuController controller) {
    final attributed = controller.attributedPages;
    if (attributed.isEmpty) return null;
    final pages = _scannedPages;
    final pageCount = pages?.pages.length ?? attributed.last;
    if (pageCount < 2) return null;
    return _Paging(pageCount: pageCount, pages: pages);
  }

  /// One widget per row in [rows], with a keyed category header inserted
  /// before the first row of each category (issue #51) — the same
  /// [GlobalKey] [CategoryChips.onSelected] scrolls to through
  /// [_scrollToCategory].
  ///
  /// With [paging] (issue #296) a [ScannedPageHeader] heads each page's
  /// rows instead, the unknown-page header heading the rows no page was
  /// matched to; [rows] are already in page order, unknown last. A page
  /// the page filter emptied has no rows, so no header either.
  List<Widget> _dishRows(
    BuildContext context,
    MenuController controller,
    String localeTag,
    List<DishRow> rows, {
    _Paging? paging,
  }) {
    final widgets = <Widget>[];
    final perPage = <int?, int>{};
    if (paging != null) {
      for (final row in rows) {
        perPage.update(row.dish.page, (n) => n + 1, ifAbsent: () => 1);
      }
    }
    String? lastCategory;
    int? lastPage;
    var first = true;
    for (final row in rows) {
      if (paging != null) {
        final page = row.dish.page;
        if (first || page != lastPage) {
          lastPage = page;
          widgets.add(_pageHeader(paging, page, perPage[page] ?? 0));
        }
      } else if (row.category != lastCategory) {
        lastCategory = row.category;
        widgets.add(_categoryHeader(context, row.category));
      }
      first = false;
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: DishCard(
            row: row,
            localeTag: localeTag,
            onShowScript: (shown) => unawaited(_openWaiterCard(shown)),
            note: controller.noteFor(row.dish.id),
            onEditNote: (edited) => unawaited(_openNoteEditor(edited)),
            // A pasted menu has no prices, and a website's are unverified
            // (D18, D19): neither shows one.
            showPrice:
                widget.ref.source != MenuSource.scan &&
                widget.ref.source != MenuSource.website,
          ),
        ),
      );
    }
    return widgets;
  }

  /// The [ScannedPageHeader] over [page]'s [dishCount] visible dishes
  /// (issue #296), or over the dishes no page was matched to when [page]
  /// is null. While the scan's pages are held, it shows the page's
  /// thumbnail and opens the pages sheet at that page when tapped.
  Widget _pageHeader(_Paging paging, int? page, int dishCount) {
    final Widget header;
    if (page == null) {
      header = ScannedPageHeader.unknown(dishCount: dishCount);
    } else {
      final pages = paging.pages;
      final held = pages != null && page <= pages.pages.length;
      header = ScannedPageHeader(
        number: page,
        total: paging.pageCount,
        thumbnail: held ? pages.pages[page - 1] : null,
        dishCount: dishCount,
        onTap: held
            ? () => unawaited(_openScannedPages(pages, initialPage: page - 1))
            : null,
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 10),
      child: header,
    );
  }

  /// The keyed heading shown before a category's first visible row
  /// (issue #51). The [GlobalKey] comes from [_categoryKeyFor] rather than
  /// a fresh one, so it stays stable across rebuilds as the filter or the
  /// search narrows and widens what is visible — [_scrollToCategory] needs
  /// the same key to keep pointing at the same element.
  Widget _categoryHeader(BuildContext context, String category) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: KeyedSubtree(
        key: _categoryKeyFor(category),
        child: Text(category, style: Theme.of(context).textTheme.titleSmall),
      ),
    );
  }

  /// The stable [GlobalKey] for [category]'s header, created once and
  /// reused from [_categoryKeys] on every later call (issue #51).
  GlobalKey _categoryKeyFor(String category) =>
      _categoryKeys.putIfAbsent(category, GlobalKey.new);

  /// Scrolls the loaded-menu list so [category]'s header is on screen
  /// (issue #51's chip jump).
  ///
  /// The list is an ordinary [ListView], which — like every [ListView] —
  /// builds only the rows near the viewport (CLAUDE.md's own trap): a
  /// header far below the fold may not exist in the element tree yet, so
  /// [Scrollable.ensureVisible] on its [GlobalKey] would have nothing to
  /// scroll to. [ScrollPosition.maxScrollExtent] is itself only an
  /// estimate until every row is built, so jumping to it once can still
  /// land short of a header many rows further down; jumping to the
  /// *current* estimate, waiting a frame, and reading the (now larger,
  /// since more rows just got built to satisfy that jump) estimate again
  /// converges on the true end after a few rounds — each jump forces the
  /// rows between the last one and this one to be built, in the order a
  /// [ListView]'s sliver always builds to satisfy a new offset. The loop
  /// stops once the estimate stops growing (every row is now built) or
  /// the header is found, whichever comes first; a header already built —
  /// on screen, or just off it — skips the loop and goes straight to
  /// [Scrollable.ensureVisible].
  Future<void> _scrollToCategory(String category) async {
    final key = _categoryKeyFor(category);
    if (_scrollController.hasClients) {
      var knownMaxExtent = -1.0;
      while (key.currentContext == null) {
        final maxExtent = _scrollController.position.maxScrollExtent;
        if (maxExtent <= knownMaxExtent) break;
        knownMaxExtent = maxExtent;
        _scrollController.jumpTo(maxExtent);
        await WidgetsBinding.instance.endOfFrame;
      }
    }
    final target = key.currentContext;
    if (target == null || !target.mounted) return;
    await Scrollable.ensureVisible(
      target,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
    );
  }

  /// The unclassified section: a neutral heading naming the count, an
  /// explanation, a "Try again" that re-analyses, and every dish as a
  /// [DishCard] with the neutral "Not classified" badge (issue #244) —
  /// never dropped, regardless of [MenuFilter] (architecture.md §6.6,
  /// constraint 8).
  Widget _unclassifiedSection(
    BuildContext context,
    AppLocalizations l10n,
    MenuController controller,
    String localeTag,
  ) {
    final rows = controller.unclassifiedRows;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.unclassifiedTitle(rows.length),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(l10n.unclassifiedExplain),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: () => _retry(controller.reanalyse),
              child: Text(l10n.actionRetry),
            ),
          ),
          const SizedBox(height: 4),
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: DishCard(
                row: row,
                localeTag: localeTag,
                onShowScript: (shown) => unawaited(_openWaiterCard(shown)),
                unclassified: true,
                // The same price rule as the classified cards; a dish
                // the menu does not contain has no price to show.
                showPrice:
                    widget.ref.source != MenuSource.scan &&
                    widget.ref.source != MenuSource.website &&
                    row.category.isNotEmpty,
              ),
            ),
        ],
      ),
    );
  }

  /// Opens the full-screen [WaiterCardSheet] for [row] as a modal.
  Future<void> _openWaiterCard(DishRow row) {
    return showKetoClubSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) =>
          WaiterCardSheet(row: row, screenBrightness: widget.screenBrightness),
    );
  }

  /// Opens [NoteEditorSheet] for [row]'s dish as a modal, saving or
  /// clearing the note through this screen's [MenuController] (issue
  /// #52). Reads the controller once, before the sheet opens, rather than
  /// inside the builder: a bottom sheet's `builder` is not itself
  /// rebuilt by `context.watch` the way this screen's own `build` is, so
  /// the callbacks below close over the controller instance directly.
  Future<void> _openNoteEditor(DishRow row) {
    final controller = context.read<MenuController>();
    return showKetoClubSheet<void>(
      context: context,
      builder: (_) => NoteEditorSheet(
        dishName: row.dish.name,
        initialNote: controller.noteFor(row.dish.id),
        onSave: (note) => unawaited(controller.setNote(row.dish.id, note)),
        onClear: () => unawaited(controller.clearNote(row.dish.id)),
      ),
    );
  }

  /// Opens [MenuQuestionSheet] as a modal bottom sheet, bound to the
  /// current [MenuController] (architecture.md §9.5; issue #214).
  ///
  /// Reads the controller before opening — the same pattern [_openNoteEditor]
  /// follows — and passes current state values in. The sheet rebuilds via
  /// [StatefulBuilder] on every [ChangeNotifier] notification, so the spinner
  /// and answer appear without closing and reopening the sheet.
  void _openQuestionSheet(BuildContext context, MenuController controller) {
    final menu = controller.menu;
    if (menu == null) return;
    unawaited(
      showKetoClubSheet<void>(
        context: context,
        builder: (_) => AnimatedBuilder(
          animation: controller,
          builder: (_, child) => MenuQuestionSheet(
            questionState: controller.questionState,
            answer: controller.questionAnswer,
            failure: controller.questionFailure,
            allDishes: menu.allDishes.toList(),
            onAsk: (q) => unawaited(controller.askQuestion(q)),
            onDismiss: controller.dismissQuestion,
          ),
        ),
      ),
    );
  }
}

/// How a scan read from several pages is laid out by page on the menu
/// screen (issue #296).
final class _Paging {
  const new({required this.pageCount, required this.pages});

  /// How many pages the scan has: the held scan's own count, or the
  /// highest page a dish names once the pages have left memory.
  final int pageCount;

  /// The scan's pages, or null once they have left memory.
  final ScannedMenu? pages;
}

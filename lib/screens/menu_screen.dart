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
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/screens/waiter_card_sheet.dart';
import 'package:ketoclub/services/platform/connectivity.dart';
import 'package:ketoclub/services/platform/external_link_opener.dart';
import 'package:ketoclub/services/platform/menu_sharer.dart';
import 'package:ketoclub/services/platform/screen_brightness.dart';
import 'package:ketoclub/services/venue/venue_ref_resolver.dart';
import 'package:ketoclub/state/menu_controller.dart';
import 'package:ketoclub/theme/app_typography.dart';
import 'package:ketoclub/utils/constants.dart';
import 'package:ketoclub/utils/menu_share_text.dart';
import 'package:ketoclub/widgets/analysis_progress_row.dart';
import 'package:ketoclub/widgets/category_chips.dart';
import 'package:ketoclub/widgets/dish_card.dart';
import 'package:ketoclub/widgets/engine_chip.dart';
import 'package:ketoclub/widgets/failure_copy.dart';
import 'package:ketoclub/widgets/fetch_failure_action.dart';
import 'package:ketoclub/widgets/keto_score_badge.dart';
import 'package:ketoclub/widgets/menu_search_field.dart';
import 'package:ketoclub/widgets/note_editor_sheet.dart';
import 'package:ketoclub/widgets/offline_banner.dart';
import 'package:ketoclub/widgets/rules_reason_banner.dart';
import 'package:ketoclub/widgets/verdict_counter_tiles.dart';
import 'package:provider/provider.dart';

/// The brand name shown for [source] inside failure copy (architecture.md
/// §10), e.g. "Wolt" in "Venue not found on Wolt. Check the link."
///
/// Not an l10n key: a platform's brand name is identical in every UI
/// language KetoClub supports, so it is not translatable prose — the ARB
/// files already embed the same names verbatim (e.g. `venueSearchHint`'s
/// "Wolt") rather than parameterising them.
String _platformName(MenuSource source) => switch (source) {
  MenuSource.wolt => 'Wolt',
  MenuSource.tenbis => '10bis',
  MenuSource.tabit => 'Tabit',
  MenuSource.ontopo => 'Ontopo',
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
/// verdict counter tiles that double as the filter, the engine chip, dish
/// cards, and the unclassified section (architecture.md §6.6, issue #29).
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
    super.key,
  });

  /// Which venue, on which platform, to load a menu for.
  final VenueRef ref;

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

  @override
  State<MenuScreen> createState() => _MenuScreenState();
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

  /// Bumped on every retry action on this screen — the failed-fetch
  /// retry, the [RulesReasonBanner] retry, and pull-to-refresh — so the
  /// [OfflineBanner] above the body re-checks connectivity exactly when
  /// this screen makes a fresh attempt (issue #68). [Connectivity
  /// .isOnline] is a one-shot check, not a stream, so nothing else would
  /// tell that banner a retry just happened.
  int _recheckToken = 0;

  /// Scrolls the loaded-menu list for [_scrollToCategory] (issue #51).
  final ScrollController _scrollController = ScrollController();

  /// The stable [GlobalKey] for each category header currently or
  /// previously shown, keyed by category name — see [_categoryKeyFor]
  /// (issue #51).
  final Map<String, GlobalKey> _categoryKeys = <String, GlobalKey>{};

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // Deferred to after the first frame, so building this screen never
    // itself starts the fetch — a widget's build method must stay free of
    // side effects.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(context.read<MenuController>().open(widget.ref));
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
    final canShare =
        controller.analysis is MenuAnalysed &&
        (controller.greenCount > 0 || controller.yellowCount > 0);
    return Scaffold(
      appBar: AppBar(
        actions: [
          if (canShare)
            IconButton(
              icon: const Icon(Icons.share),
              tooltip: l10n.actionShareMenu,
              onPressed: () => unawaited(_shareMenu(controller)),
            ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: l10n.actionOpenSettings,
            onPressed: () => Navigator.pushNamed(context, '/settings'),
          ),
        ],
      ),
      body: Column(
        children: [
          OfflineBanner(
            connectivity: widget.connectivity,
            recheckToken: _recheckToken,
          ),
          Expanded(child: _body(context, l10n, controller)),
        ],
      ),
    );
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
      venueName: controller.venueName ?? widget.ref.platformId,
      menu: menu,
      analysis: analysis,
    );
    await widget.menuSharer.shareText(text);
  }

  /// The screen body for the controller's current state: loading, a
  /// failed fetch, or a loaded menu (architecture.md §6.6).
  Widget _body(
    BuildContext context,
    AppLocalizations l10n,
    MenuController controller,
  ) {
    final menu = controller.menu;
    if (menu == null) {
      final failure = controller.fetchFailure;
      if (failure == null) return Center(child: Text(l10n.menuLoading));
      return _fetchFailureView(context, l10n, controller, failure);
    }
    return _loadedView(context, l10n, controller, menu);
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
      platform: _platformName(widget.ref.source),
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
              onRetry: () =>
                  _retry(() => controller.open(widget.ref, forceRefresh: true)),
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
  Widget _loadedView(
    BuildContext context,
    AppLocalizations l10n,
    MenuController controller,
    Menu menu,
  ) {
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
          padding: const EdgeInsets.all(16),
          children: [
            header,
            const SizedBox(height: 4),
            ?sourceLine,
            const SizedBox(height: 12),
            ...banners,
            Center(child: Text(l10n.menuEmpty)),
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

    return _refreshable(
      controller,
      ListView(
        controller: _scrollController,
        // Always scrollable, so a menu shorter than the screen can still
        // be pulled down to refresh (RefreshIndicator's own requirement).
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          header,
          const SizedBox(height: 4),
          MenuSearchField(onChanged: controller.setQuery),
          const SizedBox(height: 8),
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (analysed)
                Expanded(
                  child: Text(
                    _showingLabel(l10n, controller),
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                )
              else
                const Spacer(),
              ?sourceLine,
            ],
          ),
          if (analysed) ...[
            const SizedBox(height: 4),
            _legend(context, l10n, controller.netCarbLimitGrams),
          ],
          const SizedBox(height: 8),
          AnalysisProgressRow(phase: controller.phase),
          ...banners,
          if (controller.engine != null) ...[
            RulesReasonBanner(
              engine: controller.engine!,
              onRetry: () => _retry(controller.reanalyse),
            ),
            EngineChip(engine: controller.engine!),
            const SizedBox(height: 12),
          ],
          CategoryChips(
            categories: controller.visibleCategories,
            onSelected: (category) => unawaited(_scrollToCategory(category)),
          ),
          const SizedBox(height: 8),
          if (rows.isEmpty)
            Center(child: Text(l10n.menuNoResults))
          else
            ..._dishRows(context, controller, localeTag, rows),
          if (analysed && controller.unclassifiedNames.isNotEmpty)
            _unclassifiedSection(context, l10n, controller),
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
    final name = controller.venueName ?? widget.ref.platformId;
    final theme = Theme.of(context);
    return Row(
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l10n.menuSourceLine(_platformName(widget.ref.source), age),
          style: Theme.of(context).textTheme.bodySmall,
        ),
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
    final label = l10n.menuOpenOnPlatform(_platformName(widget.ref.source));
    return IconButton(
      icon: const Icon(Icons.open_in_new, size: 18),
      tooltip: label,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      visualDensity: VisualDensity.compact,
      onPressed: () => unawaited(widget.externalLinkOpener.open(url)),
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
  /// one hiding the other.
  List<Widget> _banners(
    BuildContext context,
    AppLocalizations l10n,
    MenuController controller,
  ) {
    final lines = <String>[];
    final analysis = controller.analysis;
    if (analysis is MenuAnalysisFailed) {
      lines.add(
        analysisFailureMessage(analysis.reason, l10n, detail: analysis.detail),
      );
    }
    final cachedAt = controller.cachedAt;
    if (controller.isFromCache && cachedAt != null) {
      final localeTag = Localizations.localeOf(context).toLanguageTag();
      final formatted = DateFormat.yMMMd(localeTag)
          .add_Hm()
          .format(cachedAt.toLocal());
      lines.add(l10n.cachedFrom(formatted));
    }
    final staleReason = controller.staleReason;
    if (staleReason != null) {
      lines.add(
        fetchFailureMessage(
          staleReason,
          l10n,
          platform: _platformName(widget.ref.source),
        ),
      );
    }
    if (lines.isEmpty) return const <Widget>[];
    return <Widget>[
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [for (final line in lines) Text(line)],
        ),
      ),
    ];
  }

  /// One widget per row in [rows], with a keyed category header inserted
  /// before the first row of each category (issue #51) — the same
  /// [GlobalKey] [CategoryChips.onSelected] scrolls to through
  /// [_scrollToCategory].
  List<Widget> _dishRows(
    BuildContext context,
    MenuController controller,
    String localeTag,
    List<DishRow> rows,
  ) {
    final widgets = <Widget>[];
    String? lastCategory;
    for (final row in rows) {
      if (row.category != lastCategory) {
        lastCategory = row.category;
        widgets.add(_categoryHeader(context, row.category));
      }
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: DishCard(
            row: row,
            localeTag: localeTag,
            onShowScript: (shown) => unawaited(_openWaiterCard(shown)),
            note: controller.noteFor(row.dish.id),
            onEditNote: (edited) => unawaited(_openNoteEditor(edited)),
          ),
        ),
      );
    }
    return widgets;
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

  /// The unclassified section: a neutral heading naming
  /// [MenuController.unclassifiedNames]'s count, an explanation, and every
  /// name — never dropped, regardless of [MenuFilter] (architecture.md
  /// §6.6, constraint 8).
  Widget _unclassifiedSection(
    BuildContext context,
    AppLocalizations l10n,
    MenuController controller,
  ) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.unclassifiedTitle(controller.unclassifiedNames.length),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(l10n.unclassifiedExplain),
          const SizedBox(height: 8),
          for (final name in controller.unclassifiedNames) Text(name),
        ],
      ),
    );
  }

  /// Opens the full-screen [WaiterCardSheet] for [row] as a modal.
  Future<void> _openWaiterCard(DishRow row) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
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
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => NoteEditorSheet(
        dishName: row.dish.name,
        initialNote: controller.noteFor(row.dish.id),
        onSave: (note) => unawaited(controller.setNote(row.dish.id, note)),
        onClear: () => unawaited(controller.clearNote(row.dish.id)),
      ),
    );
  }
}

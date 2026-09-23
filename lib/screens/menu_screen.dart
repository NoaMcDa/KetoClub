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
import 'package:ketoclub/services/platform/screen_brightness.dart';
import 'package:ketoclub/state/menu_controller.dart';
import 'package:ketoclub/theme/app_typography.dart';
import 'package:ketoclub/utils/constants.dart';
import 'package:ketoclub/widgets/analysis_progress_row.dart';
import 'package:ketoclub/widgets/dish_card.dart';
import 'package:ketoclub/widgets/engine_chip.dart';
import 'package:ketoclub/widgets/failure_copy.dart';
import 'package:ketoclub/widgets/keto_score_badge.dart';
import 'package:ketoclub/widgets/note_editor_sheet.dart';
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
  const new({required this.ref, required this.screenBrightness, super.key});

  /// Which venue, on which platform, to load a menu for.
  final VenueRef ref;

  /// Raises the screen brightness while the Waiter Card is open, so the
  /// card stays readable across a restaurant table, and restores it on
  /// close. A no-op on web, chosen in `di.dart` (architecture.md §6.6).
  final ScreenBrightness screenBrightness;

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
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: l10n.actionOpenSettings,
            onPressed: () => Navigator.pushNamed(context, '/settings'),
          ),
        ],
      ),
      body: _body(context, l10n, controller),
    );
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
      return _fetchFailureView(l10n, controller, failure);
    }
    return _loadedView(context, l10n, controller, menu);
  }

  /// A failed fetch: [fetchFailureMessage] plus a retry affordance that
  /// re-opens this screen's venue with `forceRefresh: true`.
  Widget _fetchFailureView(
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
            ElevatedButton(
              onPressed: () =>
                  unawaited(controller.open(widget.ref, forceRefresh: true)),
              child: Text(l10n.actionRetry),
            ),
          ],
        ),
      ),
    );
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
        padding: const EdgeInsets.all(16),
        children: [
          header,
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
            RulesReasonBanner(engine: controller.engine!),
            EngineChip(engine: controller.engine!),
            const SizedBox(height: 12),
          ],
          for (final row in rows)
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
    return RefreshIndicator(onRefresh: controller.refresh, child: child);
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
  /// (`.design/Main.dc.html`), plus the refresh action beside it (issue
  /// #47). Null before any menu is loaded — [MenuController.fetchedAt] is
  /// null then, and there is nothing to date or refresh yet. Otherwise
  /// shows for every loaded menu, fresh or cached, from that same getter
  /// — see its own doc comment for why it, not [MenuController.cachedAt],
  /// is the right source.
  ///
  /// The action calls [MenuController.refresh] directly: the same
  /// refetch-and-reuse [_refreshable]'s [RefreshIndicator] already pulls
  /// (issue #49), so a tap and a pull-down behave identically rather than
  /// this screen duplicating that logic. The age label re-derives from
  /// [MenuController.fetchedAt] on every rebuild this widget already
  /// listens for, so a successful refresh moves it forward with no extra
  /// wiring here.
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
          onPressed: () => unawaited(controller.refresh()),
        ),
      ],
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

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
import 'package:ketoclub/state/menu_controller.dart';
import 'package:ketoclub/widgets/dish_card.dart';
import 'package:ketoclub/widgets/engine_chip.dart';
import 'package:ketoclub/widgets/failure_copy.dart';
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

/// The classified menu screen: filters, the engine chip, dish cards, the
/// collapsed red group and the unclassified section (architecture.md
/// §6.6).
///
/// Reads its [MenuController] from `provider` and loads [ref] once, after
/// the first frame, so the initial build never itself triggers I/O. A
/// failed fetch leaves the raw menu unrendered and offers a retry; a
/// failed analysis never does — the raw menu is still shown, per
/// architecture.md §6.6's "a failed analysis must not cost the user the
/// menu".
class MenuScreen extends StatefulWidget {
  /// Creates a screen that loads and classifies the menu for [ref].
  const new({required this.ref, super.key});

  /// Which venue, on which platform, to load a menu for.
  final VenueRef ref;

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  /// Whether the collapsed red group has been expanded by the user.
  ///
  /// Local UI state, not persisted and not part of [MenuController]: it
  /// says nothing about the menu itself, only about this screen's
  /// disclosure widget.
  bool _redExpanded = false;

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
    return Scaffold(appBar: AppBar(), body: _body(context, l10n, controller));
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
    if (menu.allDishes.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ...banners,
          Center(child: Text(l10n.menuEmpty)),
        ],
      );
    }

    // The filter control, the engine chip and the red/unclassified groups
    // all key off a verdict that exists only once the analysis succeeded, so
    // they are hidden without one. The dish list itself is not:
    // MenuController.visibleRows already returns every dish unjudged in that
    // case, so a failed analysis never costs the user the menu (§6.6).
    final analysed = controller.analysis is MenuAnalysed;
    final localeTag = Localizations.localeOf(context).toLanguageTag();
    final rows = controller.visibleRows;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ...banners,
        if (analysed) ...[
          _filterControl(l10n, controller),
          const SizedBox(height: 12),
        ],
        if (controller.engine != null) ...[
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
            ),
          ),
        if (analysed && controller.redRows.isNotEmpty)
          _redGroup(l10n, controller, localeTag),
        if (analysed && controller.unclassifiedNames.isNotEmpty)
          _unclassifiedSection(context, l10n, controller),
      ],
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

  /// The three-way [MenuFilter] control.
  Widget _filterControl(AppLocalizations l10n, MenuController controller) {
    return SegmentedButton<MenuFilter>(
      segments: [
        ButtonSegment(
          value: MenuFilter.greenOnly,
          label: Text(l10n.filterGreenOnly),
        ),
        ButtonSegment(
          value: MenuFilter.greenAndYellow,
          label: Text(l10n.filterGreenAndYellow),
        ),
        ButtonSegment(value: MenuFilter.all, label: Text(l10n.filterAll)),
      ],
      selected: <MenuFilter>{controller.filter},
      onSelectionChanged: (selection) => controller.setFilter(selection.first),
    );
  }

  /// The collapsed red group: a tap target naming [MenuFilter]-independent
  /// [MenuController.redRows] and its count, expanding on tap to show a
  /// [DishCard] per red dish (architecture.md §6.6, constraint 8).
  ///
  /// A hand-rolled disclosure rather than [ExpansionTile]: its children
  /// only enter the widget tree once expanded, so the collapsed state is
  /// verifiable with a plain `findsNothing`, not an `Offstage` that still
  /// builds (and would still be found by) its hidden children.
  Widget _redGroup(
    AppLocalizations l10n,
    MenuController controller,
    String localeTag,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _redExpanded = !_redExpanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.redGroupTitle(controller.redRows.length),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                Icon(_redExpanded ? Icons.expand_less : Icons.expand_more),
              ],
            ),
          ),
        ),
        if (_redExpanded)
          for (final row in controller.redRows)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: DishCard(
                row: row,
                localeTag: localeTag,
                onShowScript: (_) {},
              ),
            ),
      ],
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
      builder: (_) => WaiterCardSheet(row: row),
    );
  }
}

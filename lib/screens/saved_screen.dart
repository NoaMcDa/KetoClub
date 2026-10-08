import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/venue/venue_ref_resolver.dart';
import 'package:ketoclub/state/saved_controller.dart';
import 'package:ketoclub/theme/verdict_colors.dart';
import 'package:ketoclub/utils/constants.dart';
import 'package:ketoclub/utils/venue_route.dart';
import 'package:ketoclub/widgets/content_width.dart';
import 'package:ketoclub/widgets/engine_chip.dart';
import 'package:ketoclub/widgets/keto_score_badge.dart';
import 'package:ketoclub/widgets/rename_menu_dialog.dart';
import 'package:ketoclub/widgets/skeletons.dart';
import 'package:provider/provider.dart';

/// The brand name shown for [ref]'s source (architecture.md §10) — the same
/// literal names `menu_screen.dart`'s own `_platformName` uses. Kept as
/// this file's own copy rather than a shared import: not an l10n key
/// either, for the same reason as there — a platform's brand name does
/// not translate (architecture.md §18.2's "each file stays
/// self-contained").
///
/// A pasted menu has no brand, so it reads [AppLocalizations.sourceScanned].
///
/// A website reads its own host (architecture.md D19).
String _platformName(VenueRef ref, AppLocalizations l10n) =>
    switch (ref.source) {
      MenuSource.wolt => 'Wolt',
      MenuSource.tenbis => '10bis',
      MenuSource.tabit => 'Tabit',
      MenuSource.ontopo => 'Ontopo',
      MenuSource.scan => l10n.sourceScanned,
      MenuSource.website => VenueRefResolver.websiteHost(ref) ?? ref.platformId,
    };

/// The title a Recent row shows (issue #313): the venue name its visit
/// recorded, else its cached menu's own, else its reference — except for
/// a pasted menu, whose reference is a hash and reads as
/// [AppLocalizations.sourceScanned], and a website, which reads as its
/// host.
String _entryTitle(RecentEntry entry, AppLocalizations l10n) =>
    entry.venueName ??
    switch (entry.ref.source) {
      MenuSource.scan || MenuSource.website => _platformName(entry.ref, l10n),
      _ => entry.ref.platformId,
    };

/// Where a Recent row's menu came from (issue #313): its platform, with
/// the venue's city beside it when the visit recorded one.
String _sourceLabel(RecentEntry entry, AppLocalizations l10n) {
  final platform = _platformName(entry.ref, l10n);
  final city = entry.city;
  if (city == null || city.trim().isEmpty) return platform;
  return l10n.sourceWithCity(platform, city);
}

/// Whether a Recent row's menu can be opened, and for how long it opens
/// from this device (issue #313): kept, the cache countdown, expired, not
/// on this device (opens online), or — for a scan, which no platform can
/// serve again — gone.
String _availabilityLabel(
  RecentEntry entry,
  DateTime now,
  AppLocalizations l10n,
) {
  final cached = entry.cached;
  if (cached == null) {
    return entry.isGone ? l10n.savedScanGone : l10n.savedNotOnDevice;
  }
  if (cached.pinned) return l10n.savedKept;
  return cacheExpiryLabel(cached.fetchedAt, now, l10n);
}

/// The bucketed "time ago" phrase for [then] relative to [now] — this
/// file's own copy of `menu_screen.dart`'s `_ageLabel`, kept local for the
/// same self-containment reason as [_platformName].
String _ageLabel(DateTime then, DateTime now, AppLocalizations l10n) {
  final elapsed = now.difference(then);
  if (elapsed.inMinutes < 1) return l10n.ageJustNow;
  if (elapsed.inHours < 1) return l10n.ageMinutes(elapsed.inMinutes);
  if (elapsed.inDays < 1) return l10n.ageHours(elapsed.inHours);
  return l10n.ageDays(elapsed.inDays);
}

/// How long a cached menu has left, phrased like [_ageLabel] but looking
/// forward: the time from [now] to `fetchedAt + ttl`, rounded up to the
/// next minute and bucketed into minutes, hours and days. A menu already
/// past its window reads [AppLocalizations.savedExpired] — it is still
/// listed, and opening it refreshes it.
///
/// [ttl] defaults to [menuCacheTtl], the window `CachedMenuRepository`
/// serves a cached menu for.
String cacheExpiryLabel(
  DateTime fetchedAt,
  DateTime now,
  AppLocalizations l10n, {
  Duration ttl = menuCacheTtl,
}) {
  final remaining = fetchedAt.add(ttl).difference(now);
  if (remaining <= Duration.zero) return l10n.savedExpired;
  final minutes = (remaining.inMicroseconds / Duration.microsecondsPerMinute)
      .ceil();
  final rounded = Duration(minutes: minutes);
  if (rounded.inHours < 1) return l10n.savedExpiresMinutes(rounded.inMinutes);
  if (rounded.inDays < 1) return l10n.savedExpiresHours(rounded.inHours);
  return l10n.savedExpiresDays(rounded.inDays);
}

/// The Recent tab (architecture.md §6.6; issues #48, #313): every menu
/// opened on this device, most recently opened first, with swipe or a
/// trailing action to remove one.
///
/// The list is the visit history (`VisitHistoryStore`, issue #307), not
/// the cache: a menu stays listed, with the score and counts it last had,
/// after its cached copy has expired or gone. Each row joins the cache to
/// say how fresh it is — kept, a countdown, expired, or not on this device
/// — and a cached menu opens offline exactly as it did online, the
/// repository behind [SavedController] serving cache first.
///
/// Reads its [SavedController] from `provider` and loads it once, after
/// the first frame, the same way `MenuScreen` and `SettingsScreen` defer
/// their own loads: a `StatefulWidget` with an `initState` that posts a
/// callback, so building this screen never itself starts I/O.
class SavedScreen extends StatefulWidget {
  /// Creates the Saved tab.
  const new({super.key});

  @override
  State<SavedScreen> createState() => _SavedScreenState();
}

class _SavedScreenState extends State<SavedScreen> {
  @override
  void initState() {
    super.initState();
    // Deferred to after the first frame, so building this screen never
    // itself starts the load — a widget's build method must stay free of
    // side effects. See the class doc for why this must be a
    // StatefulWidget rather than provider's create.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(context.read<SavedController>().load());
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final controller = context.watch<SavedController>();

    return Scaffold(
      appBar: AppBar(title: Text(l10n.savedPlaceholderTitle)),
      body: ContentWidth(
        child: controller.isLoading
            ? _loadingList(l10n)
            : controller.entries.isEmpty
            ? _emptyState(context, l10n)
            : _list(context, l10n, controller),
      ),
    );
  }

  /// Three [SavedEntrySkeleton]s in place of a spinner while
  /// [SavedController.load] is in flight (issue #63), wrapped in one live
  /// [Semantics] label — the skeletons themselves exclude their own
  /// semantics, so a screen reader hears [l10n]'s `savedLoading` copy
  /// once, not three times.
  Widget _loadingList(AppLocalizations l10n) {
    return Semantics(
      liveRegion: true,
      label: l10n.savedLoading,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: const [
          SavedEntrySkeleton(),
          SizedBox(height: 8),
          SavedEntrySkeleton(),
          SizedBox(height: 8),
          SavedEntrySkeleton(),
        ],
      ),
    );
  }

  /// Shown when nothing is listed yet — before the first menu has ever
  /// been opened, or once every entry has been removed. The same icon and
  /// layout issue #11's original placeholder used; only the body copy
  /// changed, since this screen is no longer "coming in a later update".
  ///
  /// The "Find a restaurant" action (issue #63) switches to the Explore
  /// tab the same way `AppShell`'s own destination tap does — a
  /// [Navigator.pushReplacementNamed] to `/`, so the tab stack never
  /// grows and the bottom navigation bar picks up Explore as active on
  /// the very next frame.
  Widget _emptyState(BuildContext context, AppLocalizations l10n) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.history, size: 48),
          const SizedBox(height: 16),
          Text(l10n.savedPlaceholderBody, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: () => Navigator.of(context).pushReplacementNamed('/'),
            child: Text(l10n.venueSearchLabel),
          ),
        ],
      ),
    ),
  );

  /// The Recent list, `controller.entries` already most recently opened
  /// first.
  Widget _list(
    BuildContext context,
    AppLocalizations l10n,
    SavedController controller,
  ) {
    final entries = controller.entries;
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      itemCount: entries.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final entry = entries[index];
        return _SavedEntryTile(
          entry: entry,
          // A scan whose copy has gone cannot open: no platform can serve
          // it again (issue #313).
          onTap: entry.isGone
              ? null
              : () => Navigator.pushNamed(
                  context,
                  venueRoutePath(entry.ref),
                  // Issue #169: pass the venue's name (and, since #313,
                  // its city) through the route in a VenueOpenHint (issue
                  // #307), so the menu header shows the venue's real name
                  // rather than the raw slug — cached or not
                  // (`_generateRoute` in app.dart reads it). Null-safe: an
                  // entry with no name falls back to the slug, unchanged.
                  arguments: VenueOpenHint(
                    name: entry.venueName,
                    city: entry.city,
                  ),
                ),
          onRemove: () => _removeWithUndo(context, controller, entry),
          // Only a scanned menu is the user's to name (issue #315).
          onRename: entry.ref.source == MenuSource.scan
              ? () => unawaited(_rename(context, controller, entry))
              : null,
          onTogglePin: () => unawaited(
            controller.setPinned(entry.ref, pinned: !entry.isPinned),
          ),
        );
      },
    );
  }

  /// Asks for a new name and city for the scanned menu [entry] and hands
  /// them to [SavedController.rename] (issue #315); nothing happens when
  /// the dialog is cancelled.
  Future<void> _rename(
    BuildContext context,
    SavedController controller,
    RecentEntry entry,
  ) async {
    final result = await showRenameMenuDialog(
      context,
      initialName: entry.venueName,
      initialCity: entry.city,
    );
    if (result == null) return;
    await controller.rename(entry.ref, name: result.name, city: result.city);
  }

  /// Takes [entry] out of the visible list through [SavedController.hide]
  /// and offers an undo `SnackBar`. Undone within the `SnackBar`'s
  /// lifetime, [SavedController.restore] puts it back and nothing is ever
  /// deleted from storage; left to run out, [SavedController.commitRemoval]
  /// deletes it — from the history and the cache — once the `SnackBar`
  /// closes.
  void _removeWithUndo(
    BuildContext context,
    SavedController controller,
    RecentEntry entry,
  ) {
    final removed = controller.hide(entry.ref);
    if (removed == null) return;
    final l10n = AppLocalizations.of(context)!;
    final title = _entryTitle(removed, l10n);
    var undone = false;

    unawaited(
      ScaffoldMessenger.of(context)
          .showSnackBar(
            SnackBar(
              content: Text(l10n.savedRemovedMessage(title)),
              // A SnackBar with an action persists by default in this SDK,
              // which would leave the undo window open forever; the
              // removal must commit once the default duration runs out.
              persist: false,
              action: SnackBarAction(
                label: l10n.savedUndo,
                onPressed: () {
                  undone = true;
                  controller.restore(removed);
                },
              ),
            ),
          )
          .closed
          .then((_) {
            if (!undone) unawaited(controller.commitRemoval(removed.ref));
          }),
    );
  }
}

/// One row in the Recent list (issue #313): venue name with its keto
/// score inline; platform, city and when it was last opened; whether and
/// for how long it opens from this device; dish count, the green and
/// yellow counts the Explore venue card shows, and an [EngineChip] when
/// the cached menu was analysed; and a way to remove it by swipe or by
/// [onRemove]'s trailing button.
///
/// The numbers come from the cached menu when there is one, else from the
/// snapshot the visit took. The pin shows only while a cached copy exists
/// to keep. A scan whose copy has gone ([RecentEntry.isGone]) is listed
/// disabled — [onTap] is null — but can still be removed.
///
/// No photo: the cache holds no venue image (a `Menu` carries none, only
/// dishes do), so there is nothing honest to show in its place (#252).
class _SavedEntryTile extends StatelessWidget {
  const new({
    required this.entry,
    required this.onTap,
    required this.onRemove,
    required this.onRename,
    required this.onTogglePin,
  });

  /// The opened menu this row summarises.
  final RecentEntry entry;

  /// Called when the row itself is tapped, to open [entry]'s menu; null
  /// when it cannot open, which disables the row.
  final VoidCallback? onTap;

  /// Called on a swipe-to-dismiss or a tap on the trailing remove button.
  final VoidCallback onRemove;

  /// Called on a long-press on the row, or by the screen reader's
  /// "Rename" action, to name [entry]'s scanned menu (issue #315); null
  /// for a menu a platform names, which has neither.
  final VoidCallback? onRename;

  /// Called on a tap on the pin toggle, to keep [entry] past its expiry
  /// or stop keeping it.
  final VoidCallback onTogglePin;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final now = DateTime.now();
    final title = _entryTitle(entry, l10n);
    final opened = l10n.savedOpenedAgo(
      _ageLabel(entry.visit.lastOpenedAt, now, l10n),
    );
    final availability = _availabilityLabel(entry, now, l10n);
    final score = entry.score;
    final dishCount = entry.dishCount;
    final green = entry.greenCount;
    final yellow = entry.yellowCount;
    final engine = entry.engine;
    final openCount = entry.visit.openCount;
    final counts = <Widget>[
      if (dishCount != null) Text(l10n.savedEntryDishCount(dishCount)),
      if (score != null && green != null) Text(l10n.venueCardGreenCount(green)),
      if (score != null && yellow != null)
        Text(l10n.venueCardYellowCount(yellow)),
      if (engine != null) EngineChip(engine: engine),
    ];

    return Dismissible(
      key: ValueKey(entry.ref.cacheKey),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onRemove(),
      background: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Icon(
              Icons.delete_outline,
              color: theme.colorScheme.onErrorContainer,
            ),
          ),
        ),
      ),
      child: _renamable(
        l10n,
        title,
        Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            enabled: onTap != null,
            onTap: onTap,
            title: Row(
              children: [
                Expanded(child: Text(title)),
                if (score != null) ...[
                  const SizedBox(width: 10),
                  KetoScoreBadge(score: score, inline: true),
                ],
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 4),
                Text(l10n.menuSourceLine(_sourceLabel(entry, l10n), opened)),
                const SizedBox(height: 2),
                Text(availability, style: theme.textTheme.bodySmall),
                if (openCount > 1) ...[
                  const SizedBox(height: 2),
                  Text(
                    l10n.savedOpenCount(openCount),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
                if (counts.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 4,
                    children: counts,
                  ),
                ],
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (entry.isCached)
                  Semantics(
                    label: entry.isPinned
                        ? l10n.savedUnkeepSemanticLabel(title)
                        : l10n.savedKeepSemanticLabel(title),
                    button: true,
                    toggled: entry.isPinned,
                    excludeSemantics: true,
                    child: IconButton(
                      icon: Icon(
                        entry.isPinned
                            ? Icons.push_pin
                            : Icons.push_pin_outlined,
                      ),
                      tooltip: entry.isPinned
                          ? l10n.savedUnkeep
                          : l10n.savedKeep,
                      onPressed: onTogglePin,
                    ),
                  ),
                Semantics(
                  label: l10n.savedRemoveSemanticLabel(title),
                  button: true,
                  excludeSemantics: true,
                  child: IconButton(
                    // The one destructive look, shared with Settings' "Clear"
                    // (#254); the pin beside it stays neutral.
                    icon: Icon(
                      Icons.delete_outline,
                      color: VerdictColors.of(context).red.ink,
                    ),
                    tooltip: l10n.savedRemove,
                    onPressed: onRemove,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// [card] with the rename gestures when [onRename] is set (issue #315):
  /// a long-press, and a screen-reader action labelled for [title]. A
  /// [GestureDetector] rather than the tile's own `onLongPress`, which a
  /// disabled tile (a gone scan) ignores.
  Widget _renamable(AppLocalizations l10n, String title, Widget card) {
    final rename = onRename;
    if (rename == null) return card;
    return Semantics(
      customSemanticsActions: <CustomSemanticsAction, VoidCallback>{
        CustomSemanticsAction(label: l10n.savedRenameSemanticLabel(title)):
            rename,
      },
      child: GestureDetector(onLongPress: rename, child: card),
    );
  }
}
